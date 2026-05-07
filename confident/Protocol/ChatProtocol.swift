import Foundation

/// Wire format spoken between iOS client and macOS server over Multipeer.
/// Each frame is a single JSON object sent as one Multipeer payload.
///
/// The server is stateless: every chat or title request includes the full
/// transcript needed for the model. This lets conversations survive a server
/// restart and lets the client resume any prior conversation at will.
nonisolated enum ChatProtocol {

    /// One turn in a conversation, in OpenAI-style role/content shape.
    /// `images` carries raw image bytes (typically JPEG/PNG, downscaled to
    /// ~1024px on the longest edge before sending). The server translates
    /// these into OpenAI multimodal `image_url` parts when relaying to LM
    /// Studio. `nil` or empty array means a text-only turn.
    struct Turn: Codable, Sendable, Equatable {
        enum Role: String, Codable, Sendable { case system, user, assistant }
        let role: Role
        let content: String
        var images: [Data]?

        init(role: Role, content: String, images: [Data]? = nil) {
            self.role = role
            self.content = content
            self.images = images
        }
    }

    enum ClientFrame: Codable, Sendable {
        /// Send a chat turn: include the full conversation up to and including
        /// the latest user message. The server forwards this to LM Studio
        /// without keeping any history of its own.
        case chat(history: [Turn])
        /// Ask the server to produce a short title for the supplied conversation.
        case generateTitle(history: [Turn])

        private enum Kind: String, Codable { case chat, generateTitle }
        private enum Keys: String, CodingKey { case type, history }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            switch try c.decode(Kind.self, forKey: .type) {
            case .chat:
                self = .chat(history: try c.decode([Turn].self, forKey: .history))
            case .generateTitle:
                self = .generateTitle(history: try c.decode([Turn].self, forKey: .history))
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            switch self {
            case .chat(let h):
                try c.encode(Kind.chat, forKey: .type)
                try c.encode(h, forKey: .history)
            case .generateTitle(let h):
                try c.encode(Kind.generateTitle, forKey: .type)
                try c.encode(h, forKey: .history)
            }
        }
    }

    enum ServerFrame: Codable, Sendable {
        case token(content: String)
        case done
        case title(content: String)
        case error(message: String)

        private enum Kind: String, Codable { case token, done, title, error }
        private enum Keys: String, CodingKey { case type, content, message }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            switch try c.decode(Kind.self, forKey: .type) {
            case .token:
                self = .token(content: try c.decode(String.self, forKey: .content))
            case .done:
                self = .done
            case .title:
                self = .title(content: try c.decode(String.self, forKey: .content))
            case .error:
                self = .error(message: try c.decode(String.self, forKey: .message))
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            switch self {
            case .token(let content):
                try c.encode(Kind.token, forKey: .type)
                try c.encode(content, forKey: .content)
            case .done:
                try c.encode(Kind.done, forKey: .type)
            case .title(let content):
                try c.encode(Kind.title, forKey: .type)
                try c.encode(content, forKey: .content)
            case .error(let message):
                try c.encode(Kind.error, forKey: .type)
                try c.encode(message, forKey: .message)
            }
        }
    }

    static let serviceType = "prox-chat"
}
