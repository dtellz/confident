import SwiftUI

struct ConnectionStatusView: View {
    let state: MultipeerClient.ConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
    }

    private var color: Color {
        switch state {
        case .idle: .gray
        case .browsing: .orange
        case .connecting: .yellow
        case .connected: .green
        }
    }

    private var label: String {
        switch state {
        case .idle: "Offline"
        case .browsing: "Searching for Mac…"
        case .connecting(let name): "Connecting to \(name)…"
        case .connected(let name): "Connected · \(name)"
        }
    }
}
