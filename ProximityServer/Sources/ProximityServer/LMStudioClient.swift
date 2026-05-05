import Foundation

/// Streams completion tokens from a local LM Studio server.
/// LM Studio exposes an OpenAI-compatible HTTP API; we use the streaming
/// chat completions endpoint and parse Server-Sent Events line-by-line.
struct LMStudioClient {

    struct ChatTurn: Sendable {
        enum Role: String, Codable, Sendable { case system, user, assistant }
        let role: Role
        let content: String
    }

    struct Configuration: Sendable {
        var baseURL: URL = URL(string: "http://localhost:1234")!
        /// LM Studio ignores `model` when only one is loaded; "local-model" is fine.
        var model: String = "local-model"
        var temperature: Double = 0.7
    }

    let configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Streams assistant token deltas. The returned stream finishes when LM Studio
    /// emits `[DONE]`, the connection ends, or an error occurs (delivered via throw).
    func stream(messages: [ChatTurn]) -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let task = Task {
            do {
                try await self.run(messages: messages) { continuation.yield($0) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private func run(messages: [ChatTurn],
                     yield: @Sendable (String) -> Void) async throws {
        let url = configuration.baseURL.appendingPathComponent("v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 600

        let body = RequestBody(
            model: configuration.model,
            messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            stream: true,
            temperature: configuration.temperature
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LMError.transport("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LMError.transport("LM Studio returned HTTP \(http.statusCode)")
        }

        let decoder = JSONDecoder()
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line
                .dropFirst("data:".count)
                .trimmingCharacters(in: .whitespaces)
            if payload.isEmpty { continue }
            if payload == "[DONE]" { return }

            guard let data = payload.data(using: .utf8) else { continue }
            do {
                let chunk = try decoder.decode(ChunkResponse.self, from: data)
                if let token = chunk.choices.first?.delta.content, !token.isEmpty {
                    yield(token)
                }
            } catch {
                // Tolerate occasional non-chunk frames (keep-alives, role-only deltas, etc.)
                Log.debug("LMStudio", "Skipping unparseable SSE payload: \(payload)")
            }
        }
    }

    // MARK: - DTOs

    private struct RequestBody: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let messages: [Message]
        let stream: Bool
        let temperature: Double
    }

    private struct ChunkResponse: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }
            let delta: Delta
        }
        let choices: [Choice]
    }

    enum LMError: Error, CustomStringConvertible {
        case transport(String)
        var description: String {
            switch self {
            case .transport(let m): return m
            }
        }
    }
}
