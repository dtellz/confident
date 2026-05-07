import SwiftUI
import SwiftData

@main
struct confidentApp: App {
    var body: some Scene {
        WindowGroup {
            ChatView()
        }
        .modelContainer(for: [Conversation.self, Message.self, MessageImage.self])
    }
}
