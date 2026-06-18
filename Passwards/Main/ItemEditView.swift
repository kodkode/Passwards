import SwiftUI
import PasswardsCore

/// In-place editor for new and existing items: title, vault, every field
/// editable, add/remove fields and sections, tags, notes.
///
/// Edits happen on a local `@State` copy of the item — never through a binding
/// into `store.editorDraft` — so clearing the draft on save/cancel can't race
/// SwiftUI re-evaluation (force-unwrap crash).
struct ItemEditView: View {
    @Bindable var store: VaultStore
    @State private var draftItem: VaultItem

    @State private var generatorField: UUID?
    @State private var tagsText = ""
    @State private var isSaving = false
    @State private var iconPickerShown = false

    init(store: VaultStore, draft: VaultItem) {
        self.store = store
        _draftItem = State(initialValue: draft)
    }

    private var isNew: Bool { store.editorPrevious == nil }

    var body: some View {
        content
    }

    private var content: some View {
        let draft = $draftItem
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title + vault
                HStack(spacing: 14) {
                    Button {
                        iconPickerShown = true
                    } label: {
                        editorIcon(size: 48)
                    }
                    .buttonStyle(.plain)
                    .help("Change icon")
                    .popover(isPresented: $iconPickerShown, arrowEdge: .bottom) {
                        ItemIconPicker(
                            symbol: draft.overview.iconSymbol,
                            colorToken: draft.overview.iconColor,
                            categoryColorToken: draft.wrappedValue.overview.category.colorToken
                        )
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Title", text: draft.overview.title, prompt: Text("Title"))
                            .font(.title2.bold())
                            .textFieldStyle(.plain)
                        if isNew && store.vaults.count > 1 {
                            Picker("Vault:", selection: draft.vaultID) {
                                ForEach(store.vaults) { vault in
                                    Text(vault.attributes.name).tag(vault.id)
                                }
                            }
                            .fixedSize()
                            .font(.caption)
                        }
                    }
                }

                ForEach(draft.details.sections.indices, id: \.self) { sectionIndex in
                    sectionEditor(draft: draft, sectionIndex: sectionIndex)
                }

                Button {
                    draft.wrappedValue.details.sections.append(ItemSection(title: "New Section"))
                } label: {
                    Label("Add Section", systemImage: "plus.rectangle.on.rectangle")
                }
                .buttonStyle(.borderless)

                // Tags
                VStack(alignment: .leading, spacing: 6) {
                    Text("TAGS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Tags", text: $tagsText, prompt: Text("comma, separated, tags (use / for nesting)"))
                        .textFieldStyle(.roundedBorder)
                }

                // Notes
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTES")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: draft.details.notes)
                        .font(.body)
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        // The window is non-opaque (frosted sidebar); keep this pane solid.
        .background(Theme.detailBackground)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { close() }
                    .keyboardShortcut(.cancelAction)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(isSaving)
            }
        }
        .onAppear {
            tagsText = draftItem.overview.tags.joined(separator: ", ")
        }
    }

    private func sectionEditor(draft: Binding<VaultItem>, sectionIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField(
                    "Section",
                    text: draft.details.sections[sectionIndex].title,
                    prompt: Text(sectionIndex == 0 ? "" : "Section title")
                )
                .textFieldStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                Spacer()
                if sectionIndex > 0 {
                    Button {
                        draft.wrappedValue.details.sections.remove(at: sectionIndex)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove section")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)

            let fields = draft.wrappedValue.details.sections[sectionIndex].fields
            ForEach(fields.indices, id: \.self) { fieldIndex in
                if fieldIndex > 0 { Divider().padding(.leading, 14) }
                if fields[fieldIndex].kind == .file {
                    AttachmentEditRow(
                        field: draft.details.sections[sectionIndex].fields[fieldIndex],
                        store: store,
                        onDelete: {
                            draft.wrappedValue.details.sections[sectionIndex].fields.remove(at: fieldIndex)
                        }
                    )
                } else {
                    FieldEditRow(
                        field: draft.details.sections[sectionIndex].fields[fieldIndex],
                        generatorShown: Binding(
                            get: { generatorField == fields[fieldIndex].id },
                            set: { generatorField = $0 ? fields[fieldIndex].id : nil }
                        ),
                        onDelete: {
                            draft.wrappedValue.details.sections[sectionIndex].fields.remove(at: fieldIndex)
                        }
                    )
                }
            }

            Menu {
                ForEach(addableKinds, id: \.self) { kind in
                    Button(kind.displayName) {
                        draft.wrappedValue.details.sections[sectionIndex].fields.append(
                            ItemField(label: kind.displayName.lowercased(), kind: kind)
                        )
                    }
                }
            } label: {
                Label("Add Field", systemImage: "plus.circle")
                    .font(.callout)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(14)
        }
        .background(Theme.fieldCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.fieldCardBorder, lineWidth: 1)
        }
    }

    private func firstURL(in item: VaultItem) -> String? {
        for section in item.details.sections {
            if let field = section.fields.first(where: { $0.kind == .url && !$0.value.isEmpty }) {
                return field.value
            }
        }
        return nil
    }

    /// The editor's header icon: custom icon if chosen, else the live URL's
    /// favicon, else the category tile.
    @ViewBuilder
    private func editorIcon(size: CGFloat) -> some View {
        if let symbol = draftItem.overview.iconSymbol, !symbol.isEmpty {
            CustomIconView(symbol: symbol, colorToken: draftItem.overview.iconColor ?? draftItem.overview.category.colorToken, size: size)
        } else if let url = firstURL(in: draftItem), !url.isEmpty {
            FaviconView(urlString: url, fallback: draftItem.overview.category, size: size)
        } else {
            CategoryIconView(category: draftItem.overview.category, size: size)
        }
    }

    private var addableKinds: [FieldKind] {
        [.text, .concealed, .email, .url, .phone, .otp, .date, .monthYear, .address, .file]
    }

    private func save() {
        var item = draftItem
        isSaving = true
        item.overview.tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let previous = store.editorPrevious
        Task {
            if isNew {
                await store.create(item)
            } else {
                await store.save(item, previous: previous)
            }
            isSaving = false
            close()
        }
    }

    private func close() {
        store.editorDraft = nil
        store.editorPrevious = nil
    }
}

/// One editable field row: label (editable), value input matched to kind,
/// generator popover for passwords, delete button.
struct FieldEditRow: View {
    @Binding var field: ItemField
    @Binding var generatorShown: Bool
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var revealed = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Label", text: $field.label)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                valueEditor
            }
            Spacer()
            if field.kind == .concealed || field.kind == .otp {
                Button {
                    generatorShown = true
                } label: {
                    Image(systemName: "dice")
                }
                .buttonStyle(.plain)
                .help("Generate password")
                .popover(isPresented: $generatorShown, arrowEdge: .trailing) {
                    GeneratorPopover(context: .filling { newValue in
                        field.value = newValue
                        // A freshly generated password should be visible.
                        revealed = true
                    })
                }
            }
            if hovering && field.purpose == nil {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Remove field")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch field.kind {
        case .sshKey:
            // A private key is multi-line — a single-line field would strip the
            // pasted newlines. Monospaced TextEditor, paste the whole key here.
            TextEditor(text: $field.value)
                .font(.body.monospaced())
                .frame(minHeight: 96)
                .scrollContentBackground(.hidden)
                .textContentType(nil)
        case .concealed:
            HStack(spacing: 6) {
                Group {
                    if revealed {
                        TextField("Value", text: $field.value, prompt: Text(field.kind.displayName))
                    } else {
                        SecureField("Value", text: $field.value, prompt: Text(field.kind.displayName))
                    }
                }
                .textFieldStyle(.plain)
                .font(.body.monospaced())
                Button {
                    revealed.toggle()
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(revealed ? "Conceal" : "Reveal")
                if !field.value.isEmpty {
                    StrengthBar(score: PasswordStrength.score(field.value), showLabel: false)
                        .frame(width: 70)
                }
            }
        case .address:
            TextEditor(text: $field.value)
                .font(.body)
                .frame(minHeight: 52)
                .scrollContentBackground(.hidden)
        case .date:
            DateValueEditor(value: $field.value)
        case .monthYear:
            TextField("Value", text: $field.value, prompt: Text("YYYY-MM"))
                .textFieldStyle(.plain)
        default:
            TextField("Value", text: $field.value, prompt: Text(field.kind.displayName))
                .textFieldStyle(.plain)
        }
    }
}

/// Date fields store "YYYY-MM-DD" strings; edit via DatePicker.
struct DateValueEditor: View {
    @Binding var value: String

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    var body: some View {
        HStack {
            DatePicker(
                "",
                selection: Binding(
                    get: { Self.formatter.date(from: value) ?? Date() },
                    set: { value = Self.formatter.string(from: $0) }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.field)
            if !value.isEmpty {
                Button {
                    value = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear date")
            }
        }
    }
}

/// Popover for choosing a custom item icon (SF Symbol + color), with a reset to
/// the default favicon/category icon.
struct ItemIconPicker: View {
    @Binding var symbol: String?
    @Binding var colorToken: String?
    let categoryColorToken: String
    @Environment(\.dismiss) private var dismiss

    private let symbols = [
        "globe", "person.fill", "envelope.fill", "creditcard.fill",
        "key.fill", "lock.fill", "wifi", "house.fill",
        "briefcase.fill", "cart.fill", "gamecontroller.fill", "banknote.fill",
        "heart.fill", "star.fill", "bolt.fill", "cloud.fill",
    ]
    private let colors = ["blue", "teal", "green", "orange", "red", "purple", "pink", "steel"]

    private var selectedColor: String { colorToken ?? categoryColorToken }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Item Icon").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 8), spacing: 6) {
                ForEach(symbols, id: \.self) { name in
                    Button {
                        symbol = name
                        if colorToken == nil { colorToken = categoryColorToken }
                    } label: {
                        Image(systemName: name)
                            .frame(width: 30, height: 30)
                            .background(
                                symbol == name ? Theme.accent.opacity(0.2) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                ForEach(colors, id: \.self) { token in
                    Button {
                        colorToken = token
                        if symbol == nil { symbol = symbols.first }
                    } label: {
                        Circle()
                            .fill(Theme.color(token: token))
                            .frame(width: 20, height: 20)
                            .overlay {
                                if selectedColor == token {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            Button("Use Default Icon") {
                symbol = nil
                colorToken = nil
                dismiss()
            }
            .disabled(symbol == nil && colorToken == nil)
        }
        .padding(16)
        .frame(width: 320)
    }
}
