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

    private let transport: MultipeerClient
    private var modelContext: ModelContext?

    /// Reference to the assistant Message currently receiving streamed tokens.
    /// Held by reference so it works correctly even if the user navigates to a
    /// different conversation while the previous one is still streaming.
    private var streamingMessage: Message?

    /// Conversation we last requested a title for (if any). When the title
    /// frame returns we apply it here, regardless of `currentConversation`.
    private var pendingTitleConversation: Conversation?

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
                self.connectionState = s
            }
        }
        Task { [weak self] in
            guard let self else { return }
            for await frame in self.transport.frames {
                self.handle(frame)
            }
        }
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

    // MARK: - Send

    func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, isConnected, let context = modelContext else { return }

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

        let assistant = Message(role: .assistant, content: "", isStreaming: true)
        assistant.conversation = conversation
        context.insert(assistant)
        streamingMessage = assistant

        conversation.updatedAt = .now
        draft = ""
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
}
