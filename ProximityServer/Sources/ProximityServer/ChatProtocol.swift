import Foundation

/// Wire format mirror of the iOS-side `ChatProtocol`. Both sides must change
/// together.
enum ChatProtocol {

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

    /// A known local LLM backend the server can probe and route to. All run an
    /// OpenAI-compatible HTTP API on localhost; they differ only by default port.
    struct KnownBackend: Sendable, Equatable {
        let name: String
        let port: Int
    }

    /// The backends the server auto-detects, in display order.
    static let knownBackends: [KnownBackend] = [
        KnownBackend(name: "LM Studio", port: 1234),
        KnownBackend(name: "llama.cpp", port: 8080),
        KnownBackend(name: "MLX", port: 8000),
    ]

    /// Result of probing a single local port. `online` is true when the port
    /// answered `/v1/models` with a 2xx; `model` is the first model id it
    /// reported, if any.
    struct BackendStatus: Codable, Sendable, Equatable {
        let name: String
        let port: Int
        let online: Bool
        let model: String?
    }

    enum ClientFrame: Codable, Sendable {
        case chat(history: [Turn])
        case generateTitle(history: [Turn])
        case detectBackends
        case setBackend(port: Int)

        private enum Kind: String, Codable { case chat, generateTitle, detectBackends, setBackend }
        private enum Keys: String, CodingKey { case type, history, port }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            switch try c.decode(Kind.self, forKey: .type) {
            case .chat:
                self = .chat(history: try c.decode([Turn].self, forKey: .history))
            case .generateTitle:
                self = .generateTitle(history: try c.decode([Turn].self, forKey: .history))
            case .detectBackends:
                self = .detectBackends
            case .setBackend:
                self = .setBackend(port: try c.decode(Int.self, forKey: .port))
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
            case .detectBackends:
                try c.encode(Kind.detectBackends, forKey: .type)
            case .setBackend(let port):
                try c.encode(Kind.setBackend, forKey: .type)
                try c.encode(port, forKey: .port)
            }
        }
    }

    enum ServerFrame: Codable, Sendable {
        case token(content: String)
        case done
        case title(content: String)
        case error(message: String)
        case backends(statuses: [BackendStatus], activePort: Int)

        private enum Kind: String, Codable { case token, done, title, error, backends }
        private enum Keys: String, CodingKey { case type, content, message, statuses, activePort }

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
            case .backends:
                self = .backends(statuses: try c.decode([BackendStatus].self, forKey: .statuses),
                                 activePort: try c.decode(Int.self, forKey: .activePort))
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
            case .backends(let statuses, let activePort):
                try c.encode(Kind.backends, forKey: .type)
                try c.encode(statuses, forKey: .statuses)
                try c.encode(activePort, forKey: .activePort)
            }
        }
    }

    static let serviceType = "prox-chat"
}
