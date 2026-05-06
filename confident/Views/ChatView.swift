import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    @State private var viewModel = ChatViewModel()
    @State private var didStart = false
    @State private var showHistory = false

    var body: some View {
        ZStack {
            AnimatedBackground()

            VStack(spacing: 0) {
                header
                messagesList
                ComposerView(
                    text: $viewModel.draft,
                    isConnected: viewModel.isConnected,
                    onSend: viewModel.sendDraft
                )
            }
        }
        .preferredColorScheme(.dark)
        .task { startOnce() }
        .sheet(isPresented: $showHistory) {
            ConversationListView(
                onSelect: { viewModel.open($0) },
                onDelete: { viewModel.delete($0) },
                onDeleteAll: { viewModel.deleteAll() }
            )
        }
    }

    private func startOnce() {
        guard !didStart else { return }
        didStart = true
        viewModel.bind(to: modelContext)
        // Resume the most recent conversation on a cold start, so launching
        // the app doesn't always feel like wiping context.
        if viewModel.currentConversation == nil, let recent = conversations.first {
            viewModel.open(recent)
        }
        viewModel.start()
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CONFIDENT")
                        .font(.system(.caption2, design: .rounded, weight: .heavy))
                        .tracking(3)
                        .foregroundStyle(Theme.brand)
                    Text(headerTitle)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                iconButton(systemName: "clock.arrow.circlepath", help: "History") {
                    showHistory = true
                }
                iconButton(systemName: "square.and.pencil", help: "New chat") {
                    viewModel.startNew()
                }
            }

            HStack {
                Spacer()
                ConnectionStatusView(state: viewModel.connectionState)
                    .onTapGesture { viewModel.reconnect() }
                    .accessibilityHint("Tap to rebuild the connection")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private var headerTitle: String {
        if let conv = viewModel.currentConversation {
            return conv.title.isEmpty ? "New Conversation" : conv.title
        }
        return "Local AI · Proximity"
    }

    private func iconButton(systemName: String,
                            help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Theme.strokeTint, lineWidth: 1))
        }
        .accessibilityLabel(help)
    }

    // MARK: - Messages list

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if currentMessages.isEmpty {
                        emptyState
                            .padding(.top, 60)
                    }
                    ForEach(currentMessages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                            .transition(
                                .scale(scale: 0.92, anchor: anchor(for: message))
                                .combined(with: .opacity)
                            )
                    }
                    if viewModel.isAssistantTyping &&
                       (currentMessages.last?.content.isEmpty ?? true) {
                        HStack {
                            TypingIndicatorView()
                                .padding(.leading, 42)
                            Spacer(minLength: 60)
                        }
                        .id("typing-indicator")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: currentMessages.count)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: currentMessages.last?.id) { _, _ in
                guard let id = currentMessages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
            .task(id: currentMessages.last?.id) {
                while !Task.isCancelled, viewModel.isAssistantTyping {
                    if let id = currentMessages.last?.id {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                    try? await Task.sleep(for: .milliseconds(80))
                }
            }
        }
    }

    private var currentMessages: [Message] {
        let all = viewModel.currentConversation?.orderedMessages ?? []
        return all.filter { $0.role != .system }
    }

    private func anchor(for message: Message) -> UnitPoint {
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
        case .idle: "Tap the status pill to begin searching."
        }
    }
}

#Preview {
    ChatView()
        .modelContainer(for: [Conversation.self, Message.self], inMemory: true)
}
