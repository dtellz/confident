import SwiftUI

/// The bottom message composer. Glass background, focus-glow border, larger
/// padding and minimum height so it feels appropriate on big modern devices.
struct ComposerView: View {
    @Binding var text: String
    let isConnected: Bool
    let onSend: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            field
            sendButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [Color.clear, Theme.bgBase.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Field

    private var field: some View {
        TextField("", text: $text, prompt: prompt, axis: .vertical)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(.white)
            .tint(Theme.neonCyan)
            .lineLimit(1...8)
            .focused($focused)
            .submitLabel(.send)
            .onSubmit { trySend() }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(minHeight: 56)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(focused ? Theme.neonCyan.opacity(0.75) : Theme.strokeTint, lineWidth: 1)
            )
            .shadow(color: focused ? Theme.neonCyan.opacity(0.30) : .clear, radius: 14)
            .animation(.easeInOut(duration: 0.2), value: focused)
            .disabled(!isConnected)
    }

    private var prompt: Text {
        Text(isConnected ? "Ask anything…" : "Waiting for connection…")
            .foregroundStyle(.white.opacity(0.45))
    }

    // MARK: - Send button

    private var sendButton: some View {
        Button(action: trySend) {
            ZStack {
                Circle()
                    .fill(canSend ? AnyShapeStyle(Theme.brandReversed) : AnyShapeStyle(Color.white.opacity(0.10)))
                    .frame(width: 52, height: 52)
                    .shadow(color: canSend ? Theme.neonCyan.opacity(0.55) : .clear, radius: 14, y: 4)

                Image(systemName: "arrow.up")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(canSend ? .white : .white.opacity(0.35))
            }
        }
        .disabled(!canSend)
        .scaleEffect(canSend ? 1.0 : 0.92)
        .animation(.spring(response: 0.32, dampingFraction: 0.65), value: canSend)
    }

    private var canSend: Bool {
        isConnected && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func trySend() {
        guard canSend else { return }
        onSend()
    }
}
