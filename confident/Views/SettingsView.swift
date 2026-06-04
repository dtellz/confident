import SwiftUI

/// Lets the user pick which local LLM server on the Mac to talk to. Detection
/// runs on the Mac (only it can reach `localhost`) and the results stream back
/// over Multipeer, so this screen needs a live connection to probe. Known ports
/// — LM Studio (1234), llama.cpp (8080), MLX (8000) — show a live online
/// indicator; a custom port can be entered for anything else.
struct SettingsView: View {
    let viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var customPort: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if !viewModel.isConnected {
                            offlineNote
                        }
                        backendsSection
                        customPortSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Model Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.neonCyan)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.detectBackends()
                    } label: {
                        if viewModel.isDetectingBackends {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(!viewModel.isConnected || viewModel.isDetectingBackends)
                    .foregroundStyle(.white.opacity(0.9))
                }
            }
            .preferredColorScheme(.dark)
        }
        .onAppear {
            if viewModel.isConnected { viewModel.detectBackends() }
        }
    }

    // MARK: - Offline note

    private var offlineNote: some View {
        Label("Connect to your Mac to detect running models.",
              systemImage: "wifi.slash")
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(Theme.neonAmber)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceTint, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Known backends

    private var backendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("DETECTED PORTS")
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.port) { index, row in
                    backendRow(row)
                    if index < rows.count - 1 {
                        Divider().overlay(Theme.strokeTint).padding(.leading, 16)
                    }
                }
            }
            .background(Theme.surfaceTint, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.strokeTint, lineWidth: 1))
        }
    }

    private func backendRow(_ row: BackendRow) -> some View {
        Button {
            viewModel.selectBackend(port: row.port)
        } label: {
            HStack(spacing: 12) {
                statusDot(online: row.online, detecting: viewModel.isDetectingBackends && row.status == nil)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.name)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(verbatim: ":\(row.port)")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Text(row.subtitle)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(row.online ? Theme.neonGreen.opacity(0.9) : .white.opacity(0.4))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if row.isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.neonCyan)
                        .font(.system(size: 18, weight: .bold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusDot(online: Bool, detecting: Bool) -> some View {
        ZStack {
            Circle()
                .fill(online ? Theme.neonGreen : Color.white.opacity(0.22))
                .frame(width: 10, height: 10)
            if online {
                Circle()
                    .fill(Theme.neonGreen)
                    .frame(width: 10, height: 10)
                    .blur(radius: 5)
                    .opacity(0.8)
            }
        }
        .frame(width: 14, height: 14)
        .opacity(detecting ? 0.4 : 1)
    }

    // MARK: - Custom port

    private var customPortSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("CUSTOM PORT")
            HStack(spacing: 10) {
                TextField("Custom port", text: $customPort, prompt: Text(verbatim: "e.g. 5000"))
                    .keyboardType(.numberPad)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.surfaceTint, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.strokeTint, lineWidth: 1))

                Button("Use") {
                    if let port = parsedCustomPort {
                        viewModel.selectBackend(port: port)
                        customPort = ""
                    }
                }
                .font(.system(.body, design: .rounded, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(parsedCustomPort == nil ? AnyShapeStyle(Color.white.opacity(0.18))
                                                    : AnyShapeStyle(Theme.brandReversed),
                            in: RoundedRectangle(cornerRadius: 12))
                .disabled(parsedCustomPort == nil)
            }
            Text("Any OpenAI-compatible server on your Mac's localhost.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var parsedCustomPort: Int? {
        guard let port = Int(customPort.trimmingCharacters(in: .whitespaces)),
              (1...65535).contains(port) else { return nil }
        return port
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .rounded, weight: .heavy))
            .tracking(2)
            .foregroundStyle(.white.opacity(0.45))
    }

    // MARK: - Row model

    /// One row merges a known/active backend with its latest probe status.
    private struct BackendRow {
        let name: String
        let port: Int
        let status: ChatProtocol.BackendStatus?
        let isActive: Bool

        var online: Bool { status?.online ?? false }
        var subtitle: String {
            if let status, status.online {
                return status.model ?? "Online"
            }
            return status == nil ? "Not checked" : "Offline"
        }
    }

    /// Known ports plus any extra port the server reported (e.g. a custom active
    /// port), each annotated with its latest status and active flag.
    private var rows: [BackendRow] {
        let statusByPort = Dictionary(uniqueKeysWithValues: viewModel.backendStatuses.map { ($0.port, $0) })
        var ports = ChatProtocol.knownBackends.map { ($0.name, $0.port) }
        for status in viewModel.backendStatuses where !ports.contains(where: { $0.1 == status.port }) {
            ports.append((status.name, status.port))
        }
        // Surface a persisted custom selection even before the server replies.
        if viewModel.activeBackendPort > 0,
           !ports.contains(where: { $0.1 == viewModel.activeBackendPort }) {
            ports.append(("Custom", viewModel.activeBackendPort))
        }
        return ports
            .sorted { $0.1 < $1.1 }
            .map { name, port in
                let status = statusByPort[port]
                return BackendRow(
                    name: status?.name ?? name,
                    port: port,
                    status: status,
                    isActive: viewModel.activeBackendPort == port
                )
            }
    }
}
