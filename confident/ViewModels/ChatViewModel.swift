import Foundation
import Observation
import SwiftData
import UIKit

@Observable
@MainActor
final class ChatViewModel {

    private(set) var connectionState: MultipeerClient.ConnectionState = .idle
    var draft: String = ""
    /// The conversation currently displayed in `ChatView`. `nil` means the
    /// empty-state landing screen — a Conversation is created lazily on first
    /// send, so we don't pollute the list with empty "New Chat" entries.
    var currentConversation: Conversation?

    /// Pending image attachments for the next message. Already compressed
    /// (JPEG, ~1024px) so sendDraft can write them straight to SwiftData
    /// and the wire without any per-send work.
    private(set) var attachedImages: [Data] = []
    static let maxAttachments = 4

    private let transport: MultipeerClient
    private var modelContext: ModelContext?

    /// Reference to the assistant Message currently receiving streamed tokens.
    /// Held by reference so it works correctly even if the user navigates to a
    /// different conversation while the previous one is still streaming.
    private var streamingMessage: Message?

    /// Conversation we last requested a title for (if any). When the title
    /// frame returns we apply it here, regardless of `currentConversation`.
    private var pendingTitleConversation: Conversation?

    /// Last state we observed on the transport, used to detect transitions
    /// into `.connected` so we can resume any orphan streams from a session
    /// that ended mid-response (app closed, or rebuild after a failed connect).
    private var previousConnectionState: MultipeerClient.ConnectionState = .idle

    init(transport: MultipeerClient? = nil) {
        self.transport = transport ?? MultipeerClient(displayName: UIDevice.current.name)
    }

    func bind(to context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Derived

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    var isAssistantTyping: Bool {
        currentConversation?.messages.contains { $0.isStreaming } ?? false
    }

    // MARK: - Lifecycle

    func start() {
        Log.info("ViewModel", "start() — kicking off transport on \(UIDevice.current.name)")
        transport.start()
        Task { [weak self] in
            guard let self else { return }
            for await s in self.transport.state {
                let wasConnected = Self.isConnected(self.previousConnectionState)
                let nowConnected = Self.isConnected(s)
                self.connectionState = s
                if !wasConnected && nowConnected {
                    self.resumeOrphanStreamsIfNeeded()
                }
                self.previousConnectionState = s
            }
        }
        Task { [weak self] in
            guard let self else { return }
            for await frame in self.transport.frames {
                self.handle(frame)
            }
        }
    }

    private static func isConnected(_ state: MultipeerClient.ConnectionState) -> Bool {
        if case .connected = state { return true }
        return false
    }

    func reconnect() {
        Log.info("ViewModel", "Manual reconnect requested")
        transport.restart()
    }

    // MARK: - Conversation navigation

    func open(_ conversation: Conversation) {
        // Don't delete the in-flight stream — let it finish in the background.
        finalizeStreamingMessage(deleteIfEmpty: false)
        currentConversation = conversation
    }

    /// Reset to the empty-state landing screen. The next `sendDraft` will
    /// lazily create a fresh conversation.
    func startNew() {
        finalizeStreamingMessage(deleteIfEmpty: false)
        currentConversation = nil
    }

    func delete(_ conversation: Conversation) {
        if currentConversation?.id == conversation.id {
            currentConversation = nil
            streamingMessage = nil
        }
        if pendingTitleConversation?.id == conversation.id {
            pendingTitleConversation = nil
        }
        modelContext?.delete(conversation)
        try? modelContext?.save()
    }

    func deleteAll() {
        currentConversation = nil
        streamingMessage = nil
        pendingTitleConversation = nil
        try? modelContext?.delete(model: Conversation.self)
        try? modelContext?.save()
    }

    // MARK: - Attachments

    /// Append a compressed image to the next outgoing message. Silently
    /// drops if we're already at the cap.
    func attach(image data: Data) {
        guard attachedImages.count < Self.maxAttachments else { return }
        attachedImages.append(data)
    }

    func removeAttachment(at index: Int) {
        guard attachedImages.indices.contains(index) else { return }
        attachedImages.remove(at: index)
    }

    func clearAttachments() {
        attachedImages.removeAll()
    }

    // MARK: - Send

    func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasText = !text.isEmpty
        let hasImages = !attachedImages.isEmpty
        // Vision models can take an image with no text, so allow image-only
        // turns. Block only when the user has nothing at all.
        guard (hasText || hasImages), isConnected, let context = modelContext else { return }

        // Lazy-create the conversation on the first message of a new thread.
        let conversation: Conversation
        if let existing = currentConversation {
            conversation = existing
        } else {
            conversation = Conversation()
            context.insert(conversation)
            currentConversation = conversation
        }

        let user = Message(role: .user, content: text)
        user.conversation = conversation
        context.insert(user)

        // Persist the image attachments alongside the user message. Cascading
        // delete on Message will sweep them when the conversation is purged.
        for imgData in attachedImages {
            let img = MessageImage(data: imgData)
            img.message = user
            context.insert(img)
        }

        let assistant = Message(role: .assistant, content: "", isStreaming: true)
        assistant.conversation = conversation
        context.insert(assistant)
        streamingMessage = assistant

        conversation.updatedAt = .now
        draft = ""
        attachedImages.removeAll()
        try? context.save()

        do {
            try transport.send(.chat(history: conversation.wireHistory()))
        } catch {
            replaceStreamingMessage(withError: "Failed to send: \(error.localizedDescription)")
        }
    }

    // MARK: - Inbound frame handling

    private func handle(_ frame: ChatProtocol.ServerFrame) {
        switch frame {
        case .token(let chunk):
            appendTokenToStreamingMessage(chunk)
        case .done:
            finalizeStreamingMessage(deleteIfEmpty: true)
            requestTitleIfNeeded()
        case .title(let content):
            applyTitle(content)
        case .error(let message):
            replaceStreamingMessage(withError: message)
        }
    }

    private func appendTokenToStreamingMessage(_ chunk: String) {
        guard let msg = streamingMessage else { return }
        if msg.content.isEmpty {
            let trimmed = chunk.drop(while: { $0.isWhitespace })
            if !trimmed.isEmpty {
                msg.content = String(trimmed)
            }
        } else {
            msg.content.append(chunk)
        }
        msg.conversation?.updatedAt = .now
    }

    private func finalizeStreamingMessage(deleteIfEmpty: Bool) {
        if let msg = streamingMessage {
            msg.isStreaming = false
            if deleteIfEmpty && msg.content.isEmpty {
                modelContext?.delete(msg)
            }
            try? modelContext?.save()
        }
        streamingMessage = nil
    }

    private func replaceStreamingMessage(withError text: String) {
        if let msg = streamingMessage {
            msg.content = "⚠︎ \(text)"
            msg.isStreaming = false
            try? modelContext?.save()
        }
        streamingMessage = nil
    }

    // MARK: - Title

    /// Ask the server to summarize the current conversation into a short title,
    /// once we have at least one full user/assistant exchange and the
    /// conversation hasn't already been titled.
    private func requestTitleIfNeeded() {
        guard let conv = currentConversation else { return }
        guard conv.title == "New Chat" else { return }
        let real = conv.messages.filter { !$0.isStreaming && !$0.content.isEmpty }
        guard real.count >= 2 else { return }

        pendingTitleConversation = conv
        do {
            try transport.send(.generateTitle(history: conv.wireHistory()))
            Log.info("ViewModel", "Title requested for conversation \(conv.id)")
        } catch {
            Log.warn("ViewModel", "Title request failed: \(error)")
            pendingTitleConversation = nil
        }
    }

    private func applyTitle(_ title: String) {
        guard let conv = pendingTitleConversation else { return }
        pendingTitleConversation = nil
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        conv.title = trimmed
        try? modelContext?.save()
        Log.info("ViewModel", "Title applied: \"\(trimmed)\"")
    }

    // MARK: - Orphan stream resumption

    /// Called every time the transport transitions into `.connected`.
    ///
    /// If a previous session ended mid-response (the user closed the app while
    /// streaming, or the connection dropped and was rebuilt), we'll find
    /// assistant Messages persisted with `isStreaming == true` and a
    /// conversation whose last entry is a user prompt with no reply. Those
    /// would otherwise sit forever as stuck bubbles. We delete the orphan
    /// streaming bubble(s) and re-issue the chat request for the most recent
    /// affected conversation, so the user gets a fresh complete response.
    private func resumeOrphanStreamsIfNeeded() {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate { $0.isStreaming == true }
        )
        guard let orphans = try? context.fetch(descriptor), !orphans.isEmpty else { return }

        Log.info("ViewModel", "Cleaning up \(orphans.count) orphan streaming message(s) on (re)connect")

        for msg in orphans {
            if msg.id == streamingMessage?.id {
                streamingMessage = nil
            }
            context.delete(msg)
        }
        try? context.save()

        // Find the most recent conversation whose last message is a user prompt
        // (i.e. the assistant's reply was lost). Re-issue exactly one — Multipeer
        // can only handle one in-flight stream per peer anyway.
        let convDescriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\Conversation.updatedAt, order: .reverse)]
        )
        guard let conversations = try? context.fetch(convDescriptor) else { return }

        for conv in conversations {
            guard let last = conv.orderedMessages.last, last.role == .user else { continue }
            Log.info("ViewModel", "Re-issuing chat in conversation \(conv.id) (dangling user message)")
            reissueChat(in: conv)
            return
        }
    }

    private func reissueChat(in conversation: Conversation) {
        guard let context = modelContext else { return }

        let assistant = Message(role: .assistant, content: "", isStreaming: true)
        assistant.conversation = conversation
        context.insert(assistant)
        streamingMessage = assistant
        conversation.updatedAt = .now
        try? context.save()

        do {
            try transport.send(.chat(history: conversation.wireHistory()))
        } catch {
            Log.warn("ViewModel", "Failed to re-issue chat: \(error)")
            context.delete(assistant)
            streamingMessage = nil
            try? context.save()
        }
    }
}
