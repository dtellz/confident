import SwiftUI
import UIKit
import PhotosUI

/// The bottom message composer. Glass background, focus-glow border, larger
/// padding and minimum height so it feels appropriate on big modern devices.
/// Supports up to `ChatViewModel.maxAttachments` image attachments via the
/// photo library or camera.
struct ComposerView: View {
    @Binding var text: String
    let isConnected: Bool
    let attachedImages: [Data]
    let onAttach: (Data) -> Void
    let onRemoveAttachment: (Int) -> Void
    let onSend: () -> Void

    @FocusState private var focused: Bool
    @State private var loggedFirstKeystroke = false

    @State private var showSourceSheet = false
    @State private var showPhotosPicker = false
    @State private var showCameraSheet = false
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        VStack(spacing: 8) {
            if !attachedImages.isEmpty {
                thumbnailRow
            }
            HStack(alignment: .bottom, spacing: 10) {
                attachButton
                field
                sendButton
            }
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
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $pickerItems,
            maxSelectionCount: max(1, ChatViewModel.maxAttachments - attachedImages.count),
            matching: .images
        )
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await ingestPickerItems(items) }
        }
        .sheet(isPresented: $showCameraSheet) {
            CameraPicker { image in
                if let compressed = ImageCompression.compress(image) {
                    onAttach(compressed)
                }
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("Add Photo",
                            isPresented: $showSourceSheet,
                            titleVisibility: .hidden) {
            Button("Photo Library") { showPhotosPicker = true }
            Button("Camera") { showCameraSheet = true }
            Button("Cancel", role: .cancel) {}
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            Log.info("Composer", "keyboardWillShow at \(Date().timeIntervalSinceReferenceDate)")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            Log.info("Composer", "keyboardDidShow at \(Date().timeIntervalSinceReferenceDate)")
        }
        .onChange(of: text) { old, new in
            if !loggedFirstKeystroke && old.isEmpty && !new.isEmpty {
                loggedFirstKeystroke = true
                Log.info("Composer", "first keystroke registered at \(Date().timeIntervalSinceReferenceDate)")
            }
        }
    }

    // MARK: - Attachments

    private var canAttachMore: Bool {
        attachedImages.count < ChatViewModel.maxAttachments
    }

    private func ingestPickerItems(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            guard let uiImage = UIImage(data: data) else { continue }
            guard let compressed = ImageCompression.compress(uiImage) else { continue }
            await MainActor.run { onAttach(compressed) }
        }
        await MainActor.run { pickerItems.removeAll() }
    }

    private var thumbnailRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(attachedImages.enumerated()), id: \.offset) { index, data in
                    thumbnail(data: data, index: index)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .frame(height: 80)
    }

    private func thumbnail(data: Data, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.strokeTint, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
            }
            Button {
                onRemoveAttachment(index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.75))
                    .font(.system(size: 20))
            }
            .offset(x: 6, y: -6)
            .accessibilityLabel("Remove attachment")
        }
        .frame(width: 70, height: 70)
    }

    private var attachButton: some View {
        Button {
            showSourceSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(canAttachMore ? .white.opacity(0.88) : .white.opacity(0.25))
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Theme.strokeTint, lineWidth: 1))
        }
        .disabled(!canAttachMore)
        .accessibilityLabel("Attach photo")
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
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.sentences)
            .keyboardType(.default)
            .textContentType(.none)
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
            .onChange(of: focused) { _, newValue in
                Log.info("Composer", "focus → \(newValue) at \(Date().timeIntervalSinceReferenceDate)")
            }
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
        guard isConnected else { return false }
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || !attachedImages.isEmpty
    }

    private func trySend() {
        guard canSend else { return }
        onSend()
    }
}
