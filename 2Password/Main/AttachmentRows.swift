import SwiftUI
import TwoPasswordCore
import UniformTypeIdentifiers

/// Read-mode row for a `.file` field: filename + size, open and save actions.
struct AttachmentDisplayRow: View {
    let field: ItemField
    let store: VaultStore

    @State private var metadata: AttachmentMetadata?
    @State private var failed = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(field.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let metadata {
                    Text(metadata.filename)
                        .font(.callout)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(metadata.size), countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if failed {
                    Text("Attachment unavailable")
                        .font(.callout)
                        .foregroundStyle(.orange)
                } else {
                    Text("Loading…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if metadata != nil {
                Button("Open") { open() }
                    .buttonStyle(.borderless)
                Button("Save…") { saveAs() }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .task(id: field.value) {
            do {
                metadata = try await store.attachments?.metadata(attachmentID: field.value)
            } catch {
                failed = true
            }
        }
    }

    /// Decrypts to the session temp dir (wiped on lock) and opens with the
    /// default app.
    private func open() {
        guard let metadata else { return }
        Task {
            guard let data = try? await store.attachments?.decrypt(attachmentID: field.value) else { return }
            let dir = AppState.previewTempDirectory
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(field.value + "-" + metadata.filename)
            try? data.write(to: url, options: .atomic)
            NSWorkspace.shared.open(url)
        }
    }

    private func saveAs() {
        guard let metadata else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = metadata.filename
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            guard let data = try? await store.attachments?.decrypt(attachmentID: field.value) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// Edit-mode row for a `.file` field: choose a file (encrypted on save).
struct AttachmentEditRow: View {
    @Binding var field: ItemField
    let store: VaultStore
    let onDelete: () -> Void

    @State private var existingMetadata: AttachmentMetadata?
    @State private var hovering = false

    private var pendingURL: URL? { store.pendingAttachments[field.id] }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.badge.plus")
                .font(.title3)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                TextField("Label", text: $field.label)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let pendingURL {
                    Text(pendingURL.lastPathComponent + " (will be encrypted on save)")
                        .font(.callout)
                } else if let existingMetadata {
                    Text(existingMetadata.filename)
                        .font(.callout)
                } else {
                    Text("No file selected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(field.value.isEmpty && pendingURL == nil ? "Choose File…" : "Replace…") {
                choose()
            }
            .buttonStyle(.borderless)
            if hovering {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onHover { hovering = $0 }
        .task(id: field.value) {
            guard !field.value.isEmpty else { return }
            existingMetadata = try? await store.attachments?.metadata(attachmentID: field.value)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > AttachmentStore.maxFileSize {
            let alert = NSAlert()
            alert.messageText = "File too large"
            alert.informativeText = "Attachments are limited to 25 MB."
            alert.runModal()
            return
        }
        store.pendingAttachments[field.id] = url
        // Clear the old attachment reference; the new file replaces it on save.
        field.value = ""
    }
}
