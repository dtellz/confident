import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class ChatViewModel {

    private(set) var messages: [ChatMessage] = []
    private(set) var connectionState: MultipeerClient.ConnectionState = .idle
    private(set) var isAssistantTyping: Bool = false
    var draft: String = ""

    private let transport: MultipeerClient
    private var streamingMessageID: UUID?

    init(transport: MultipeerClient? = nil) {
        self.transport = transport ?? MultipeerClient(displayName: UIDevice.current.name)
    }

    /// Begin browsing and start consuming inbound state + frame streams.
    func start() {
        Log.info("ViewModel", "start() — kicking off transport on \(UIDevice.current.name)")
        transport.start()

        Task { [weak self] in
            guard let self else { return }
            for await state in self.transport.state {
                self.connectionState = state
                // If we drop the peer mid-stream, finalize the in-flight assistant turn.
                if case .browsing = state, self.isAssistantTyping {
                    self.finalizeStreamingMessage()
                }
            }
        }

        Task { [weak self] in
            guard let self else { return }
            for await frame in self.transport.frames {
                self.handle(frame)
            }
        }
    }

    /// Manually rebuild the Multipeer session — exposed in the UI as a refresh
    /// button. Useful when a connection attempt has stalled in `connecting`.
    func reconnect() {
        Log.info("ViewModel", "Manual reconnect requested")
        transport.restart()
    }

    func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard case .connected = connectionState else { return }

        messages.append(ChatMessage(role: .user, content: text))
        draft = ""

        // Pre-allocate the assistant's streaming bubble so tokens can append in place.
        let assistant = ChatMessage(role: .assistant, content: "", isStreaming: true)
        streamingMessageID = assistant.id
        messages.append(assistant)
        isAssistantTyping = true

        do {
            try transport.send(.message(content: text))
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
            finalizeStreamingMessage()
        case .error(let message):
            replaceStreamingMessage(withError: message)
        }
    }

    private func appendTokenToStreamingMessage(_ chunk: String) {
        guard let id = streamingMessageID,
              let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].content.append(chunk)
    }

    private func finalizeStreamingMessage() {
        if let id = streamingMessageID,
           let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx].isStreaming = false
            // Drop empty turns rather than leaving a blank bubble.
            if messages[idx].content.isEmpty {
                messages.remove(at: idx)
            }
        }
        streamingMessageID = nil
        isAssistantTyping = false
    }

    private func replaceStreamingMessage(withError text: String) {
        if let id = streamingMessageID,
           let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx].content = "⚠︎ \(text)"
            messages[idx].isStreaming = false
        }
        streamingMessageID = nil
        isAssistantTyping = false
    }
}
