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

    enum ClientFrame: Codable, Sendable {
        case chat(history: [Turn])
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
