import SwiftUI

struct ChatView: View {
    @State private var viewModel = ChatViewModel()
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messagesList
                Divider()
                composer
            }
            .navigationTitle("Confident")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ConnectionStatusView(state: viewModel.connectionState)
                }
            }
            .task { viewModel.start() }
        }
    }

    // MARK: - Messages

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }
                    if viewModel.isAssistantTyping &&
                       (viewModel.messages.last?.content.isEmpty ?? true) {
                        HStack {
                            TypingIndicatorView()
                            Spacer(minLength: 40)
                        }
                        .id("typing-indicator")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.messages.last?.id) { _, _ in scrollToBottom(proxy) }
            .onChange(of: viewModel.messages.last?.content) { _, _ in scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = viewModel.messages.last else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $viewModel.draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit(send)
                .submitLabel(.send)
                .disabled(!isConnected)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
            }
            .disabled(!canSend)
        }
        .padding(10)
    }

    private var isConnected: Bool {
        if case .connected = viewModel.connectionState { return true }
        return false
    }

    private var canSend: Bool {
        isConnected &&
        !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        viewModel.sendDraft()
    }
}

#Preview {
    ChatView()
}
