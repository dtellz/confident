import SwiftUI
import UIKit

struct MessageBubbleView: View {
    let message: Message

    @ViewBuilder
    var body: some View {
        // While the assistant message is empty and still streaming, the typing
        // indicator is already shown — don't render an empty bubble next to it.
        // A user message with images but no text still renders.
        let hasImages = !message.images.isEmpty
        let hasText = !message.content.isEmpty
        if !(message.isStreaming && !hasText) || hasImages {
            HStack(alignment: .bottom, spacing: 10) {
                if message.role == .user { Spacer(minLength: 60) }

                if message.role == .assistant { assistantAvatar }

                bubble

                if message.role == .assistant { Spacer(minLength: 60) }
            }
        }
    }

    /// User turns render as plain text (they typed it). Assistant/system turns
    /// render Markdown, since that's what the models emit.
    @ViewBuilder
    private var messageText: some View {
        switch message.role {
        case .user:
            Text(displayContent)
                .textSelection(.enabled)
                .font(font)
                .foregroundStyle(textColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        case .assistant, .system:
            MarkdownText(text: displayContent, baseFont: font, textColor: textColor)
                .textSelection(.enabled)
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
        VStack(alignment: .leading, spacing: 8) {
            if !message.images.isEmpty {
                imageStack
            }
            if !message.content.isEmpty || message.isStreaming {
                messageText
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(strokeStyle, lineWidth: 1)
        )
        .shadow(color: shadowColor, radius: 14, y: 6)
    }

    /// Stack of attached images. Each rendered at its native aspect ratio,
    /// capped at 240pt wide. Vertical layout — multi-image messages produce
    /// a tall bubble, which the parent ScrollView handles fine.
    private var imageStack: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(message.images) { img in
                if let uiImage = UIImage(data: img.data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        switch message.role {
        case .user:
            Theme.brand
        case .assistant, .system:
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
        if message.isStreaming { return message.content + " ▍" }
        return message.content
    }

    private var textColor: Color {
        message.role == .user ? .white : .white.opacity(0.94)
    }

    private var strokeStyle: AnyShapeStyle {
        switch message.role {
        case .user: AnyShapeStyle(Color.white.opacity(0.30))
        case .assistant, .system: AnyShapeStyle(Theme.strokeTint)
        }
    }

    private var shadowColor: Color {
        switch message.role {
        case .user: Theme.neonViolet.opacity(0.45)
        case .assistant, .system: .black.opacity(0.5)
        }
    }
}
