import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 0) {
                Text(displayContent)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(textColor)
                    .background(bubbleColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    /// While streaming, surface a caret so the user sees the response is in flight
    /// even before the first token arrives.
    private var displayContent: String {
        if message.isStreaming && message.content.isEmpty { return "▍" }
        if message.isStreaming { return message.content + "▍" }
        return message.content
    }

    private var bubbleColor: Color {
        switch message.role {
        case .user: .accentColor
        case .assistant: .gray.opacity(0.18)
        }
    }

    private var textColor: Color {
        switch message.role {
        case .user: .white
        case .assistant: .primary
        }
    }
}
