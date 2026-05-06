import SwiftUI
import SwiftData

/// Sheet presenting all stored conversations. Tap a row to load it; swipe to
/// delete a single one; the trash button at the top opens a confirmation
/// alert before wiping every conversation.
struct ConversationListView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Conversation.updatedAt, order: .reverse)
    private var conversations: [Conversation]

    let onSelect: (Conversation) -> Void
    let onDelete: (Conversation) -> Void
    let onDeleteAll: () -> Void

    @State private var showDeleteAllAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackground()
                content
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.neonCyan)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showDeleteAllAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Theme.neonMagenta)
                    }
                    .disabled(conversations.isEmpty)
                }
            }
            .alert("Delete all conversations?", isPresented: $showDeleteAllAlert) {
                Button("Delete All", role: .destructive) {
                    onDeleteAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes every conversation and message stored on this device. This cannot be undone.")
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if conversations.isEmpty {
            emptyState
        } else {
            list
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(conversations) { conv in
                row(conv)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            onDelete(conv)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ conv: Conversation) -> some View {
        Button {
            onSelect(conv)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(conv.title)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let preview = previewText(for: conv) {
                        Text(preview)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                Text(relativeDate(conv.updatedAt))
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.strokeTint, lineWidth: 1)
            )
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func previewText(for conv: Conversation) -> String? {
        let last = Message.sorted(conv.messages)
            .last(where: { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        return last?.content.replacingOccurrences(of: "\n", with: " ")
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.brand)
            Text("No conversations yet")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("Your saved chats will appear here.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
