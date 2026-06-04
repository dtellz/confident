import Foundation

/// Streams completion tokens from a local LM Studio server.
/// LM Studio exposes an OpenAI-compatible HTTP API; we use the streaming
/// chat completions endpoint and parse Server-Sent Events line-by-line.
struct LMStudioClient {

    struct ChatTurn: Sendable {
        enum Role: String, Codable, Sendable { case system, user, assistant }
        let role: Role
        let content: String
        /// Raw image bytes (assumed JPEG by the iOS client). If non-empty,
        /// this turn is serialized as an OpenAI multimodal `content` array.
        let images: [Data]

        init(role: Role, content: String, images: [Data] = []) {
            self.role = role
            self.content = content
            self.images = images
        }
    }

    struct Configuration: Sendable {
        var baseURL: URL = URL(string: "http://localhost:1234")!
        /// LM Studio ignores `model` when only one is loaded; "local-model" is fine.
        var model: String = "local-model"
        var temperature: Double = 0.7
        /// Sent as a Bearer token. Required by omlx; ignored by LM Studio/llama.cpp.
        var apiKey: String = BackendDetector.apiKey
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
        if !configuration.apiKey.isEmpty {
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 600

        let body = RequestBody(
            model: configuration.model,
            messages: messages.map(Self.encodeMessage),
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

    /// Convert a ChatTurn into the request DTO. Text-only turns serialize
    /// `content` as a plain string (most compatible with non-vision models).
    /// Turns with images serialize `content` as an array of OpenAI-style
    /// content parts: a single text part (if any text), followed by one
    /// `image_url` part per image, encoded as a base64 data URI.
    private static func encodeMessage(_ turn: ChatTurn) -> RequestBody.Message {
        if turn.images.isEmpty {
            return RequestBody.Message(role: turn.role.rawValue, content: .text(turn.content))
        }
        var parts: [RequestBody.Message.Part] = []
        if !turn.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(.init(type: "text", text: turn.content, image_url: nil))
        }
        for data in turn.images {
            let dataURL = "data:image/jpeg;base64,\(data.base64EncodedString())"
            parts.append(.init(type: "image_url", text: nil, image_url: .init(url: dataURL)))
        }
        return RequestBody.Message(role: turn.role.rawValue, content: .parts(parts))
    }

    private struct RequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: Content

            enum Content: Encodable {
                case text(String)
                case parts([Part])

                func encode(to encoder: Encoder) throws {
                    var c = encoder.singleValueContainer()
                    switch self {
                    case .text(let s): try c.encode(s)
                    case .parts(let p): try c.encode(p)
                    }
                }
            }

            struct Part: Encodable {
                let type: String        // "text" or "image_url"
                let text: String?
                let image_url: ImageURL?

                struct ImageURL: Encodable {
                    let url: String
                }
            }
        }

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
