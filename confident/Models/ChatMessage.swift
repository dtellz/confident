import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role: Equatable { case user, assistant }

    let id: UUID
    let role: Role
    var content: String
    /// True while tokens are still being appended for an assistant message.
    var isStreaming: Bool

    init(id: UUID = UUID(), role: Role, content: String, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
    }
}
