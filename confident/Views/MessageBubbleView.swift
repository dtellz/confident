import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.role == .user { Spacer(minLength: 60) }

            if message.role == .assistant { assistantAvatar }

            bubble

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    // MARK: - Components

    private var assistantAvatar: some View {
        ZStack {
            Circle()
                .fill(Theme.brand)
                .frame(width: 32, height: 32)
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .shadow(color: Theme.neonViolet.opacity(0.55), radius: 10, y: 2)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(displayContent)
                .textSelection(.enabled)
                .font(font)
                .foregroundStyle(textColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(strokeStyle, lineWidth: 1)
        )
        .shadow(color: shadowColor, radius: 14, y: 6)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        switch message.role {
        case .user:
            Theme.brand
        case .assistant:
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Theme.bgElevated.opacity(0.55)
            }
        }
    }

    // MARK: - Style

    private var font: Font {
        message.role == .user
            ? .system(.body, design: .rounded, weight: .medium)
            : .system(.body, design: .rounded)
    }

    private var displayContent: String {
        if message.isStreaming && message.content.isEmpty { return "▍" }
        if message.isStreaming { return message.content + " ▍" }
        return message.content
    }

    private var textColor: Color {
        message.role == .user ? .white : .white.opacity(0.94)
    }

    private var strokeStyle: AnyShapeStyle {
        switch message.role {
        case .user: AnyShapeStyle(Color.white.opacity(0.30))
        case .assistant: AnyShapeStyle(Theme.strokeTint)
        }
    }

    private var shadowColor: Color {
        switch message.role {
        case .user: Theme.neonViolet.opacity(0.45)
        case .assistant: .black.opacity(0.5)
        }
    }
}
