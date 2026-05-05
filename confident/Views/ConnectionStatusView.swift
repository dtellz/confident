import SwiftUI

struct ConnectionStatusView: View {
    let state: MultipeerClient.ConnectionState

    @State private var pulse: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if isPulsing {
                    Circle()
                        .stroke(color, lineWidth: 1)
                        .frame(width: 16, height: 16)
                        .opacity(2.0 - pulse)
                        .scaleEffect(pulse)
                }
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.9), radius: 5)
            }
            .frame(width: 16, height: 16)

            Text(label)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.strokeTint, lineWidth: 1))
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulse = 1.6
            }
        }
    }

    private var isPulsing: Bool {
        switch state {
        case .browsing, .connecting: true
        default: false
        }
    }

    private var color: Color {
        switch state {
        case .idle: .gray
        case .browsing: Theme.neonAmber
        case .connecting: Theme.neonMagenta
        case .connected: Theme.neonGreen
        }
    }

    private var label: String {
        switch state {
        case .idle: "Offline"
        case .browsing: "Searching"
        case .connecting(let n): "Connecting · \(n)"
        case .connected(let n): "Online · \(n)"
        }
    }
}
