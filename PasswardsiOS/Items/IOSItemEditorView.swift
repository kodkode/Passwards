import SwiftUI
import PasswardsCore

/// Create / edit an item. Edits a LOCAL `@State` copy (never a binding into the
/// shared store — mirrors the macOS force-unwrap-crash lesson). On save it routes
/// to `vault.create` (new) or `vault.save` (existing), then closes.
struct IOSItemEditorView: View {
    let vault: IOSVaultModel
    let original: VaultItem
    var isNew = false
    var showsCancel = true
    var onClose: () -> Void

    @State private var draft: VaultItem
    @State private var saving = false

    init(vault: IOSVaultModel, original: VaultItem, isNew: Bool = false, showsCancel: Bool = true, onClose: @escaping () -> Void) {
        self.vault = vault
        self.original = original
        self.isNew = isNew
        self.showsCancel = showsCancel
        self.onClose = onClose
        _draft = State(initialValue: original)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ItemIcon(overview: draft.overview, size: 40)
                    TextField("Title", text: $draft.overview.title)
                        .font(.headline)
                }
            }

            ForEach($draft.details.sections) { $section in
                Section(section.title) {
                    ForEach($section.fields) { $field in
                        EditorFieldRow(field: $field)
                    }
                }
            }

            Section("Notes") {
                TextField("Notes", text: $draft.details.notes, axis: .vertical)
                    .lineLimit(3...8)
            }
        }
        .navigationTitle(isNew ? "New \(draft.overview.category.displayName)" : "Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(saving)
            }
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onClose() }
                }
            }
        }
    }

    private func save() {
        saving = true
        Task {
            if isNew {
                await vault.create(draft)
            } else {
                await vault.save(draft, previous: original)
            }
            onClose()
        }
    }
}

/// One editable field: label + a kind-appropriate input (secure for secrets with
/// a reveal toggle + a generate shortcut; multiline for addresses; plain otherwise).
private struct EditorFieldRow: View {
    @Binding var field: ItemField
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.label.isEmpty ? field.kind.displayName : field.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            input
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var input: some View {
        switch field.kind {
        case .concealed, .sshKey:
            HStack(spacing: 8) {
                Group {
                    if revealed {
                        TextField(field.label, text: $field.value)
                    } else {
                        SecureField(field.label, text: $field.value)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())

                Button { revealed.toggle() } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)

                Button {
                    field.value = PasswordGenerator.random()
                    revealed = true
                } label: {
                    Image(systemName: "key.fill")
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
        case .address:
            TextField(field.label, text: $field.value, axis: .vertical).lineLimit(2...5)
        case .email:
            TextField(field.label, text: $field.value)
                .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
        case .url:
            TextField(field.label, text: $field.value)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
        case .phone:
            TextField(field.label, text: $field.value).keyboardType(.phonePad)
        default:
            TextField(field.label, text: $field.value)
        }
    }
}
