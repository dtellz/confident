import Foundation

/// Wire format mirror of the iOS-side `ChatProtocol`. Kept locally so the macOS
/// server compiles standalone — both sides must change together.
enum ChatProtocol {

    enum ClientFrame: Codable, Sendable {
        case message(content: String)

        private enum Kind: String, Codable { case message }
        private enum Keys: String, CodingKey { case type, content }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            switch try c.decode(Kind.self, forKey: .type) {
            case .message:
                self = .message(content: try c.decode(String.self, forKey: .content))
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            switch self {
            case .message(let content):
                try c.encode(Kind.message, forKey: .type)
                try c.encode(content, forKey: .content)
            }
        }
    }

    enum ServerFrame: Codable, Sendable {
        case token(content: String)
        case done
        case error(message: String)

        private enum Kind: String, Codable { case token, done, error }
        private enum Keys: String, CodingKey { case type, content, message }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            switch try c.decode(Kind.self, forKey: .type) {
            case .token:
                self = .token(content: try c.decode(String.self, forKey: .content))
            case .done:
                self = .done
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
            case .error(let message):
                try c.encode(Kind.error, forKey: .type)
                try c.encode(message, forKey: .message)
            }
        }
    }

    static let serviceType = "prox-chat"
}
