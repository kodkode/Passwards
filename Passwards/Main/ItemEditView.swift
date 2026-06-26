import SwiftUI
import PasswardsCore
import UniformTypeIdentifiers

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
    /// The field currently being dragged for reordering (nil when not dragging).
    @State private var draggingFieldID: UUID?
    /// The section currently being dragged for reordering (nil when not dragging).
    /// Field and section drags are mutually exclusive — each delegate validates
    /// only its own kind, so the two never interfere.
    @State private var draggingSectionID: UUID?

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

                ForEach(draft.details.sections) { $section in
                    sectionEditor(draft: draft, sectionID: section.id)
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

    private func sectionEditor(draft: Binding<VaultItem>, sectionID: UUID) -> some View {
        // Resolve by identity each render so reordering can't desync the index.
        let sectionIndex = draftItem.details.sections.firstIndex { $0.id == sectionID } ?? 0
        let sectionCount = draftItem.details.sections.count
        let sectionFields = draftItem.details.sections[sectionIndex].fields
        // Custom sections (index > 0) drag, but only when there's more than one
        // to reorder among. `enabled` must match `visible` or the grip would be
        // an invisible-yet-draggable hit target.
        let sectionDraggable = sectionIndex > 0 && sectionCount > 2
        return VStack(alignment: .leading, spacing: 0) {
            // The grip sits flush at x=0 (like field grips); the title/trash
            // carry the 14pt inset, so both gutters line up in one column.
            HStack(spacing: 2) {
                gutterGrip(
                    visible: sectionDraggable,
                    enabled: sectionDraggable,
                    help: "Drag to reorder section"
                ) {
                    draggingSectionID = sectionID
                    draggingFieldID = nil
                    return reorderProvider(sectionID, type: .passwardsSectionReorder)
                }
                HStack(spacing: 0) {
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
                            draft.wrappedValue.details.sections.removeAll { $0.id == sectionID }
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
            }
            .padding(.top, 12)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onDrop(
                of: [.passwardsSectionReorder],
                delegate: SectionReorderDropDelegate(
                    targetID: sectionID,
                    sections: draft.details.sections,
                    dragging: $draggingSectionID
                )
            )

            // Iterate by stable field identity (not position) so a drag reorder
            // animates the rows rather than re-binding by index mid-move.
            ForEach(draft.details.sections[sectionIndex].fields) { $field in
                let fieldID = field.id
                // Custom fields drag; username/password (purpose fields) are
                // pinned, matching 1P8. A grip shows only when there's somewhere
                // to drag — another field here, or another section to move into.
                let draggable = field.purpose == nil && (sectionFields.count > 1 || sectionCount > 1)
                if sectionFields.first?.id != fieldID { Divider().padding(.leading, 32) }
                HStack(spacing: 2) {
                    gutterGrip(visible: draggable, enabled: draggable, help: "Drag to reorder") {
                        draggingFieldID = fieldID
                        draggingSectionID = nil
                        return reorderProvider(fieldID, type: .passwardsFieldReorder)
                    }
                    if field.kind == .file {
                        AttachmentEditRow(
                            field: $field,
                            store: store,
                            onDelete: {
                                draft.wrappedValue.details.sections[sectionIndex].fields.removeAll { $0.id == fieldID }
                            }
                        )
                    } else {
                        FieldEditRow(
                            field: $field,
                            generatorShown: Binding(
                                get: { generatorField == fieldID },
                                set: { generatorField = $0 ? fieldID : nil }
                            ),
                            onDelete: {
                                draft.wrappedValue.details.sections[sectionIndex].fields.removeAll { $0.id == fieldID }
                            }
                        )
                    }
                }
                .onDrop(
                    of: [.passwardsFieldReorder],
                    delegate: FieldReorderDropDelegate(
                        targetID: fieldID,
                        sections: draft.details.sections,
                        dragging: $draggingFieldID
                    )
                )
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // Only an EMPTY section exposes a drop zone here (it has no field rows
            // to target). A non-empty section is served entirely by its row drop
            // targets — registering an adjacent append zone there would let a
            // cross-section drag ping-pong between the two.
            .modifier(ConditionalFieldDrop(
                active: sectionFields.isEmpty,
                delegate: SectionAppendDropDelegate(
                    sectionID: sectionID,
                    sections: draft.details.sections,
                    dragging: $draggingFieldID
                )
            ))
        }
        .background(Theme.fieldCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.fieldCardBorder, lineWidth: 1)
        }
    }

    /// A drag handle that sits in a fixed 16pt leading gutter so rows align
    /// whether or not the handle is shown. `visible` controls the glyph;
    /// `enabled` controls whether it can start a drag.
    @ViewBuilder
    private func gutterGrip(
        visible: Bool,
        enabled: Bool,
        help: String,
        provider: @escaping () -> NSItemProvider
    ) -> some View {
        if enabled {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 16)
                .opacity(visible ? 1 : 0)
                .contentShape(Rectangle())
                .help(help)
                .onDrag(provider)
        } else {
            Color.clear.frame(width: 16, height: 1)
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

/// Private drag types for editor reordering. Using app-owned types (rather than
/// `.text`) means foreign drags — text dragged out of a TextField, content from
/// another app — cannot match these drop targets, so they can never trigger a
/// reorder. This also makes a stale `dragging` id (left by a cancelled drag)
/// inert: only an actual grip drag, which resets the id first, can reach a
/// delegate.
private extension UTType {
    static let passwardsFieldReorder = UTType(exportedAs: "com.michael.passwards.field-reorder")
    static let passwardsSectionReorder = UTType(exportedAs: "com.michael.passwards.section-reorder")
}

/// An in-process-only drag payload tagged with one of the private reorder types.
private func reorderProvider(_ id: UUID, type: UTType) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { completion in
        completion(Data(id.uuidString.utf8), nil)
        return nil
    }
    return provider
}

/// Applies the field-append drop target only when `active` (an empty section).
/// A non-empty section is served entirely by its row drop targets.
private struct ConditionalFieldDrop: ViewModifier {
    let active: Bool
    let delegate: SectionAppendDropDelegate

    func body(content: Content) -> some View {
        if active {
            content.onDrop(of: [.passwardsFieldReorder], delegate: delegate)
        } else {
            content
        }
    }
}

/// Locates a field by id within a sections array. Shared by the field drop
/// delegates so within- and cross-section moves use one lookup.
private func locateField(_ id: UUID, in sections: [ItemSection]) -> (section: Int, field: Int)? {
    for (s, section) in sections.enumerated() {
        if let f = section.fields.firstIndex(where: { $0.id == id }) { return (s, f) }
    }
    return nil
}

/// Count of leading pinned (purpose) fields — username/password that 1P8 keeps
/// fixed at the top. A custom field can't initiate a drag from above them
/// (they have no grip) and must not be dropped above them either, so reorder
/// destinations are floored to this index.
private func pinnedPrefix(_ fields: [ItemField]) -> Int {
    var n = 0
    for f in fields {
        if f.purpose != nil { n += 1 } else { break }
    }
    return n
}

/// Live field reorder across all sections: as the dragged field's pointer
/// enters another row, the list reflows under the cursor (1P8 grip behavior).
/// Within a section it swaps; across sections it moves the field over.
///
/// Strict-end placement note: dropping onto a row in a *different* non-empty
/// section inserts *before* that row, so a single cross-section drag can't land
/// a field at the very end of a foreign section (drop on the last row, then
/// nudge down within the section). This is deliberate — the alternative (an
/// always-on append zone) makes a cross-section drag ping-pong at the boundary.
private struct FieldReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var sections: [ItemSection]
    @Binding var dragging: UUID?

    // Only engage while a field drag is active, so a section drag passes through.
    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        dragging == nil ? nil : DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != targetID,
              let from = locateField(dragging, in: sections),
              let to = locateField(targetID, in: sections) else { return }
        let floor = pinnedPrefix(sections[to.section].fields)
        withAnimation(.easeInOut(duration: 0.18)) {
            if from.section == to.section {
                let dest = max(to.field > from.field ? to.field + 1 : to.field, floor)
                sections[from.section].fields.move(
                    fromOffsets: IndexSet(integer: from.field),
                    toOffset: dest
                )
            } else {
                let element = sections[from.section].fields.remove(at: from.field)
                let insertAt = min(max(to.field, floor), sections[to.section].fields.count)
                sections[to.section].fields.insert(element, at: insertAt)
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Drop target on a section's "Add Field" area: moves the dragged field to the
/// end of that section. The only way to reach a section that has no fields yet.
private struct SectionAppendDropDelegate: DropDelegate {
    let sectionID: UUID
    @Binding var sections: [ItemSection]
    @Binding var dragging: UUID?

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        dragging == nil ? nil : DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let dragging,
              let to = sections.firstIndex(where: { $0.id == sectionID }),
              let from = locateField(dragging, in: sections) else { return }
        // Already the last field in this section — nothing to do (avoids churn).
        if from.section == to, from.field == sections[to].fields.count - 1 { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            let element = sections[from.section].fields.remove(at: from.field)
            sections[to].fields.append(element)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Live reorder of custom sections (the first/main section stays pinned).
private struct SectionReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var sections: [ItemSection]
    @Binding var dragging: UUID?

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        dragging == nil ? nil : DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != targetID,
              let from = sections.firstIndex(where: { $0.id == dragging }),
              let to = sections.firstIndex(where: { $0.id == targetID }),
              from >= 1, to >= 1 else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            sections.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
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
