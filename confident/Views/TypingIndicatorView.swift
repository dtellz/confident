import SwiftUI

struct TypingIndicatorView: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.neonCyan)
                    .frame(width: 8, height: 8)
                    .opacity(phase == i ? 1.0 : 0.25)
                    .scaleEffect(phase == i ? 1.25 : 1.0)
                    .shadow(color: Theme.neonCyan.opacity(phase == i ? 0.9 : 0), radius: phase == i ? 6 : 0)
                    .animation(.easeInOut(duration: 0.22), value: phase)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.strokeTint, lineWidth: 1))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(280))
                phase = (phase + 1) % 3
            }
        }
    }
}
