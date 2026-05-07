import Foundation
import SwiftData

/// One chat thread with its full message history. Stored locally via SwiftData
/// in the app sandbox; deleted automatically when the user removes the app.
@Model
final class Conversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    /// Cascading: removing a Conversation removes its Messages.
    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]

    init(id: UUID = UUID(),
         title: String = "New Chat",
         createdAt: Date = .now,
         updatedAt: Date = .now,
         messages: [Message] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

@Model
final class Message {
    @Attribute(.unique) var id: UUID
    /// Stored as the raw String so SwiftData can persist the enum cleanly.
    var roleRaw: String
    var content: String
    var createdAt: Date
    /// True while tokens are still being appended for an assistant message.
    /// Persisted so the streaming caret reappears if the app is killed mid-stream.
    var isStreaming: Bool
    var conversation: Conversation?
    /// Attachments rendered above the bubble's text. Cascading: dropping a
    /// Message drops its images.
    @Relationship(deleteRule: .cascade, inverse: \MessageImage.message)
    var images: [MessageImage]

    var role: Role {
        get { Role(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }

    enum Role: String, Codable, Sendable {
        case user, assistant, system
    }

    init(id: UUID = UUID(),
         role: Role,
         content: String,
         createdAt: Date = .now,
         isStreaming: Bool = false,
         images: [MessageImage] = []) {
        self.id = id
        self.roleRaw = role.rawValue
        self.content = content
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.images = images
    }
}

/// Image attached to a Message. The bytes live on the file system thanks to
/// `.externalStorage`, so listing/scrolling messages doesn't load megabytes
/// of image data into memory; the data is only fetched when the bubble
/// actually renders the image.
@Model
final class MessageImage {
    @Attribute(.unique) var id: UUID
    @Attribute(.externalStorage) var data: Data
    var createdAt: Date
    var message: Message?

    init(id: UUID = UUID(), data: Data, createdAt: Date = .now) {
        self.id = id
        self.data = data
        self.createdAt = createdAt
    }
}

extension Message {
    /// Stable ordering for views — SwiftData relationships aren't ordered.
    static func sorted(_ messages: [Message]) -> [Message] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }
}

extension Conversation {
    /// Messages in display order.
    var orderedMessages: [Message] { Message.sorted(messages) }

    /// Convert this conversation's messages to wire-protocol turns for sending
    /// to the server. Filters out empty assistant messages still streaming
    /// (they haven't received any tokens yet). Carries any attached images
    /// through as raw bytes — the server converts them to OpenAI multimodal
    /// content parts before relaying to LM Studio.
    func wireHistory() -> [ChatProtocol.Turn] {
        orderedMessages.compactMap { msg in
            let trimmed = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let imageData = msg.images.map(\.data)
            // A turn is meaningful if it has text OR images (vision models
            // accept image-only prompts).
            guard !trimmed.isEmpty || !imageData.isEmpty else { return nil }
            let role: ChatProtocol.Turn.Role = switch msg.role {
            case .user: .user
            case .assistant: .assistant
            case .system: .system
            }
            return ChatProtocol.Turn(
                role: role,
                content: msg.content,
                images: imageData.isEmpty ? nil : imageData
            )
        }
    }
}
