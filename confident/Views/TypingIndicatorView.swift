import SwiftUI

struct TypingIndicatorView: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(phase == i ? 1.0 : 0.3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.gray.opacity(0.18), in: Capsule())
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(280))
                phase = (phase + 1) % 3
            }
        }
    }
}
