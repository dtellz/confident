import Foundation
@preconcurrency import MultipeerConnectivity

/// Stateless dispatcher between Multipeer frames and LM Studio. The client now
/// sends the full transcript with each request, so the server keeps no
/// per-peer state — every chat or title request is a one-shot.
actor ChatSession {

    private let transport: MultipeerServer
    private let llm: LMStudioClient
    private let systemPrompt: String

    /// Latest in-flight task per peer. New requests cancel the previous one so
    /// token streams don't interleave on the wire.
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
                Log.info("Session", "Peer connected: \(peer.displayName)")
            case .disconnected(let peer):
                inFlight[peer]?.cancel()
                inFlight[peer] = nil
                Log.info("Session", "Peer disconnected: \(peer.displayName)")
            case .frame(let peer, .chat(let history)):
                handleChat(history: history, from: peer)
            case .frame(let peer, .generateTitle(let history)):
                handleGenerateTitle(history: history, from: peer)
            }
        }
    }

    // MARK: - Chat

    private func handleChat(history: [ChatProtocol.Turn], from peer: MCPeerID) {
        cancelInFlight(for: peer, reason: "new chat request")

        let messages = injectSystemPromptIfMissing(into: history, system: systemPrompt)
        Log.info("Session", "Chat ← \(peer.displayName) (history=\(messages.count) turns)")

        let task = Task { [llm, transport] in
            var assistantBuffer = ""
            var tokenCount = 0
            do {
                for try await token in llm.stream(messages: messages) {
                    try Task.checkCancellation()
                    tokenCount += 1
                    assistantBuffer += token
                    do {
                        try transport.send(.token(content: token), to: peer)
                    } catch {
                        Log.warn("Session", "Peer \(peer.displayName) dropped after \(tokenCount) tokens; abandoning")
                        return
                    }
                }
                try? transport.send(.done, to: peer)
                Log.info("Session", "Chat → \(peer.displayName) complete (\(tokenCount) tokens, \(assistantBuffer.count) chars)")
            } catch is CancellationError {
                return
            } catch {
                Log.error("Session", "LM stream failed: \(error)")
                try? transport.send(.error(message: "\(error)"), to: peer)
            }
        }
        inFlight[peer] = task
    }

    // MARK: - Title

    private func handleGenerateTitle(history: [ChatProtocol.Turn], from peer: MCPeerID) {
        cancelInFlight(for: peer, reason: "new title request")

        let messages = buildTitleMessages(from: history)
        Log.info("Session", "Title ← \(peer.displayName) (summarizing \(history.count) turns)")

        let task = Task { [llm, transport] in
            var buffer = ""
            do {
                for try await token in llm.stream(messages: messages) {
                    try Task.checkCancellation()
                    buffer += token
                }
                let title = Self.cleanTitle(buffer)
                Log.info("Session", "Title → \(peer.displayName): \"\(title)\"")
                try? transport.send(.title(content: title), to: peer)
            } catch is CancellationError {
                return
            } catch {
                Log.error("Session", "Title generation failed: \(error)")
                // Title is best-effort — don't escalate to the client as an error frame.
            }
        }
        inFlight[peer] = task
    }

    // MARK: - Helpers

    private func cancelInFlight(for peer: MCPeerID, reason: String) {
        if let task = inFlight[peer] {
            Log.warn("Session", "Cancelling in-flight task for \(peer.displayName) (\(reason))")
            task.cancel()
        }
    }

    /// Some clients send a system turn first; if not, prepend the default.
    private func injectSystemPromptIfMissing(into history: [ChatProtocol.Turn],
                                             system: String) -> [LMStudioClient.ChatTurn] {
        var out: [LMStudioClient.ChatTurn] = []
        if history.first?.role != .system {
            out.append(.init(role: .system, content: system))
        }
        out.append(contentsOf: history.map { .init(role: .init(wireRole: $0.role), content: $0.content) })
        return out
    }

    private func buildTitleMessages(from history: [ChatProtocol.Turn]) -> [LMStudioClient.ChatTurn] {
        // Render the conversation as plain text the model can summarize. Skip
        // any system turns so the title is grounded in the actual exchange.
        let transcript = history
            .filter { $0.role != .system }
            .map { turn in
                let label = turn.role == .user ? "User" : "Assistant"
                return "\(label): \(turn.content)"
            }
            .joined(separator: "\n\n")

        return [
            .init(role: .system, content:
                "You generate concise titles for chat conversations. " +
                "Output a 2 to 5 word title that captures the main topic. " +
                "Output ONLY the title — no quotes, no punctuation, no preamble, no explanation."
            ),
            .init(role: .user, content: "Generate a title for this conversation:\n\n\(transcript)")
        ]
    }

    /// Best-effort cleanup of the model's title output: trim, drop quotes/
    /// punctuation, keep first line, cap length.
    private static func cleanTitle(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = t.split(separator: "\n").first {
            t = String(first).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Strip surrounding quotes (straight or curly)
        let quoteOpens: Set<Character> = ["\"", "'", "“", "‘"]
        let quoteCloses: Set<Character> = ["\"", "'", "”", "’"]
        if let f = t.first, let l = t.last, quoteOpens.contains(f), quoteCloses.contains(l), t.count >= 2 {
            t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Strip trailing punctuation
        while let last = t.last, ".!?,;:".contains(last) { t.removeLast() }
        if t.count > 60 { t = String(t.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines) }
        return t.isEmpty ? "New Chat" : t
    }
}

private extension LMStudioClient.ChatTurn.Role {
    init(wireRole: ChatProtocol.Turn.Role) {
        switch wireRole {
        case .system: self = .system
        case .user: self = .user
        case .assistant: self = .assistant
        }
    }
}
