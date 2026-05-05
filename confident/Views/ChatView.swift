import SwiftUI

struct ChatView: View {
    @State private var viewModel = ChatViewModel()

    var body: some View {
        ZStack {
            AnimatedBackground()

            VStack(spacing: 0) {
                header
                messagesList
                ComposerView(
                    text: $viewModel.draft,
                    isConnected: isConnected,
                    onSend: viewModel.sendDraft
                )
            }
        }
        .preferredColorScheme(.dark)
        .task { viewModel.start() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CONFIDENT")
                    .font(.system(.caption2, design: .rounded, weight: .heavy))
                    .tracking(3)
                    .foregroundStyle(Theme.brand)
                Text("Local AI · Proximity")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
            }

            Spacer()

            HStack(spacing: 8) {
                ConnectionStatusView(state: viewModel.connectionState)
                reconnectButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var reconnectButton: some View {
        Button {
            viewModel.reconnect()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Theme.strokeTint, lineWidth: 1))
        }
        .accessibilityLabel("Rebuild connection")
    }

    // MARK: - Messages list

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if viewModel.messages.isEmpty {
                        emptyState
                            .padding(.top, 60)
                    }
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                            .transition(
                                .scale(scale: 0.92, anchor: anchor(for: message))
                                .combined(with: .opacity)
                            )
                    }
                    if viewModel.isAssistantTyping &&
                       (viewModel.messages.last?.content.isEmpty ?? true) {
                        HStack {
                            TypingIndicatorView()
                                .padding(.leading, 42) // align after assistant avatar
                            Spacer(minLength: 60)
                        }
                        .id("typing-indicator")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.messages.count)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.last?.id) { _, _ in
                guard let id = viewModel.messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
            .task(id: viewModel.messages.last?.id) {
                while !Task.isCancelled, viewModel.isAssistantTyping {
                    if let id = viewModel.messages.last?.id {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                    try? await Task.sleep(for: .milliseconds(80))
                }
            }
        }
    }

    private func anchor(for message: ChatMessage) -> UnitPoint {
        message.role == .user ? .bottomTrailing : .bottomLeading
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Theme.brand)
                    .frame(width: 130, height: 130)
                    .opacity(0.18)
                    .blur(radius: 30)
                Image(systemName: "sparkles")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Theme.brand)
            }
            VStack(spacing: 6) {
                Text("Ask anything")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text(emptyStateSubtitle)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyStateSubtitle: String {
        switch viewModel.connectionState {
        case .connected: "Your local model is ready.\nStart the conversation."
        case .browsing: "Looking for your Mac nearby…"
        case .connecting: "Establishing secure session…"
        case .idle: "Tap reload to begin searching."
        }
    }

    // MARK: - Helpers

    private var isConnected: Bool {
        if case .connected = viewModel.connectionState { return true }
        return false
    }
}

#Preview {
    ChatView()
}
