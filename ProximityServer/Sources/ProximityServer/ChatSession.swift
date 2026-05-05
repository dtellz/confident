import Foundation
@preconcurrency import MultipeerConnectivity

/// Orchestrates the AI side: per-peer conversation history, dispatches user
/// messages to LM Studio, and forwards streamed tokens back over Multipeer.
actor ChatSession {

    private let transport: MultipeerServer
    private let llm: LMStudioClient
    private let systemPrompt: String

    private var histories: [MCPeerID: [LMStudioClient.ChatTurn]] = [:]
    private var inFlight: [MCPeerID: Task<Void, Never>] = [:]

    init(transport: MultipeerServer,
         llm: LMStudioClient,
         systemPrompt: String = "You are a helpful assistant running locally on the user's MacBook. Keep responses concise unless asked otherwise.") {
        self.transport = transport
        self.llm = llm
        self.systemPrompt = systemPrompt
    }

    /// Drives the event loop. Returns when `transport.events` finishes.
    func run() async {
        for await event in transport.events {
            switch event {
            case .connected(let peer):
                histories[peer] = [.init(role: .system, content: systemPrompt)]
                Log.info("Session", "Initialized history for \(peer.displayName)")
            case .disconnected(let peer):
                inFlight[peer]?.cancel()
                inFlight[peer] = nil
                histories[peer] = nil
                Log.info("Session", "Cleared state for \(peer.displayName)")
            case .frame(let peer, .message(let content)):
                handleUserMessage(content, from: peer)
            }
        }
    }

    private func handleUserMessage(_ content: String, from peer: MCPeerID) {
        if inFlight[peer] != nil {
            Log.warn("Session", "Cancelling in-flight turn for \(peer.displayName) (new message arrived)")
            inFlight[peer]?.cancel()
        }

        var history = histories[peer] ?? [.init(role: .system, content: systemPrompt)]
        history.append(.init(role: .user, content: content))
        histories[peer] = history

        Log.info("Session", "Dispatching to LM Studio for \(peer.displayName) (history=\(history.count) turns)")

        let task = Task { [llm, transport] in
            var assistantBuffer = ""
            var tokenCount = 0
            do {
                for try await token in llm.stream(messages: history) {
                    try Task.checkCancellation()
                    tokenCount += 1
                    assistantBuffer += token
                    do {
                        try transport.send(.token(content: token), to: peer)
                    } catch {
                        Log.warn("Session", "Peer \(peer.displayName) dropped mid-stream after \(tokenCount) tokens; abandoning")
                        return
                    }
                }
                try? transport.send(.done, to: peer)
                Log.info("Session", "Stream complete for \(peer.displayName) — \(tokenCount) tokens, \(assistantBuffer.count) chars")
                self.recordAssistant(assistantBuffer, for: peer)
            } catch is CancellationError {
                Log.info("Session", "Stream cancelled for \(peer.displayName)")
                return
            } catch {
                Log.error("Session", "LM stream failed for \(peer.displayName): \(error)")
                try? transport.send(.error(message: "\(error)"), to: peer)
            }
        }
        inFlight[peer] = task
    }

    private func recordAssistant(_ content: String, for peer: MCPeerID) {
        guard !content.isEmpty, var history = histories[peer] else { return }
        history.append(.init(role: .assistant, content: content))
        histories[peer] = history
    }
}
