import SwiftUI
import PasswardsCore

/// Detail column: editor when a draft is active, otherwise the selected item.
struct ItemDetailContainer: View {
    @Bindable var store: VaultStore

    var body: some View {
        if let draft = store.editorDraft {
            ItemEditView(store: store, draft: draft)
                .id(draft.id)
        } else if let selectedID = store.selectedItemID {
            ItemDetailView(store: store, itemID: selectedID)
                .id(selectedID)
        } else if store.sidebarSelection == .watchtower {
            WatchtowerDashboardView(store: store)
        } else {
            // Empty detail pane: the security-themed illustration.
            LogoEmptyIllustration()
        }
    }
}

/// The empty-pane illustration: a hand-authored, security-themed artwork
/// (central shield + key ringed by locks, biometrics, cards, 2FA…), shown small
/// and centered on the standard pane background.
struct LogoEmptyIllustration: View {
    var body: some View {
        Image("EmptyVaultIllustration")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 200, height: 200)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.detailBackground)
            .accessibilityHidden(true)
    }
}

struct ItemDetailView: View {
    @Bindable var store: VaultStore
    let itemID: String

    @State private var item: VaultItem?
    @State private var revealedFields: Set<UUID> = []
    @State private var copiedFieldID: UUID?
    @State private var largeTypeValue: String?
    @State private var historyShown = false

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(store.watchtower.report.checks(for: item.id)) { check in
                            WatchtowerBanner(check: check) {
                                if let summary = store.summaries.first(where: { $0.id == item.id }) {
                                    Task {
                                        await store.watchtower.exclude(check: check, summary: summary, store: store)
                                        self.item = await store.item(id: itemID)
                                    }
                                }
                            }
                        }
                        header(item)
                        ForEach(item.details.sections) { section in
                            if section.fields.contains(where: { !$0.value.isEmpty }) {
                                sectionCard(section)
                            }
                        }
                        if !item.details.notes.isEmpty {
                            notesCard(item.details.notes)
                        }
                        if !item.overview.tags.isEmpty {
                            tagsRow(item.overview.tags)
                        }
                        if !item.details.passwordHistory.isEmpty {
                            passwordHistoryCard(item.details.passwordHistory)
                        }
                        footer(item)
                    }
                    .padding(20)
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .background(Theme.detailBackground)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.detailBackground)
            }
        }
        .task(id: itemID) {
            item = await store.item(id: itemID)
        }
        .toolbar {
            if let item, item.trashedAt == nil {
                ToolbarItem {
                    Button {
                        store.editorPrevious = item
                        store.editorDraft = item
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .keyboardShortcut("e", modifiers: .command)
                    .help("Edit (⌘E)")
                }
                ToolbarItem {
                    Button {
                        Task { await store.duplicate(itemID: itemID) }
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .keyboardShortcut("d", modifiers: .command)
                    .help("Duplicate item (⌘D)")
                }
            }
        }
        .sheet(item: $largeTypeValue) { value in
            LargeTypeView(value: value)
        }
        .sheet(isPresented: $historyShown) {
            if let item {
                HistorySheet(store: store, item: item) {
                    Task { self.item = await store.item(id: itemID) }
                }
            }
        }
        .onKeyPress(.init("r"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            toggleRevealAll()
            return .handled
        }
        // Match both "c" and "C": SwiftUI folds Shift into the key equivalent,
        // so ⇧⌘C arrives as key "C". Plain ⌘C falls through to text-copy.
        .onKeyPress(keys: ["c", "C"], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if press.modifiers.contains(.shift) { copyPrimary(.password); return .handled }
            if press.modifiers.contains(.option) { copyOTP(); return .handled }
            return .ignored
        }
        .onKeyPress(.delete, phases: .down) { press in
            guard press.modifiers.contains(.command), let item, item.trashedAt == nil else { return .ignored }
            Task { await store.moveToTrash(itemID: item.id) }
            return .handled
        }
    }

    private func copyPrimary(_ purpose: FieldPurpose) {
        guard let item, let field = item.details.firstField(withPurpose: purpose), !field.value.isEmpty else { return }
        ClipboardManager.copy(field.value, concealed: field.kind.isSecret)
    }

    private func copyOTP() {
        guard let item, let field = item.details.firstField(ofKind: .otp),
              let generator = TOTPGenerator(userInput: field.value) else { return }
        ClipboardManager.copy(generator.code(), concealed: true)
    }

    private func toggleRevealAll() {
        guard let item else { return }
        let secretIDs = item.details.sections.flatMap(\.fields).filter { $0.kind.isSecret }.map(\.id)
        if revealedFields.isEmpty {
            revealedFields = Set(secretIDs)
        } else {
            revealedFields = []
        }
    }

    private func header(_ item: VaultItem) -> some View {
        HStack(spacing: 14) {
            if let symbol = item.overview.iconSymbol, !symbol.isEmpty {
                CustomIconView(symbol: symbol, colorToken: item.overview.iconColor ?? item.overview.category.colorToken, size: 54)
            } else if let url = item.overview.urls.first, !url.isEmpty {
                FaviconView(urlString: url, fallback: item.overview.category, size: 54)
            } else {
                CategoryIconView(category: item.overview.category, size: 54)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.overview.title.isEmpty ? "Untitled" : item.overview.title)
                    .font(.system(size: 22, weight: .bold))
            }
            Spacer()
            if let summary = store.summaries.first(where: { $0.id == item.id }) {
                Button {
                    Task { await store.toggleFavorite(summary) }
                } label: {
                    Image(systemName: item.overview.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(item.overview.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help(item.overview.isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }
        }
    }

    private func sectionCard(_ section: ItemSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !section.title.isEmpty {
                Text(section.title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }
            ForEach(Array(section.fields.filter { !$0.value.isEmpty }.enumerated()), id: \.element.id) { index, field in
                if index > 0 { Divider().padding(.leading, 14) }
                if field.kind == .file {
                    AttachmentDisplayRow(field: field, store: store)
                } else {
                FieldDisplayRow(
                    field: field,
                    revealed: revealedFields.contains(field.id),
                    copied: copiedFieldID == field.id,
                    onCopy: { copy(field) },
                    onToggleReveal: {
                        if revealedFields.contains(field.id) {
                            revealedFields.remove(field.id)
                        } else {
                            revealedFields.insert(field.id)
                        }
                    },
                    onLargeType: { largeTypeValue = field.value },
                    onOpenAndFill: field.kind == .url && item?.overview.category == .login
                        ? { [itemID = item?.id] in
                            if let itemID { store.openAndFill(itemID: itemID, urlString: field.value) }
                        }
                        : nil
                )
                }
            }
        }
        .background(Theme.fieldCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.fieldCardBorder, lineWidth: 1)
        }
    }

    private func copy(_ field: ItemField) {
        // OTP fields copy the current 6-digit code, not the secret.
        if field.kind == .otp, let generator = TOTPGenerator(userInput: field.value) {
            ClipboardManager.copy(generator.code(), concealed: true)
        } else {
            ClipboardManager.copy(field.value, concealed: field.kind.isSecret)
        }
        copiedFieldID = field.id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedFieldID == field.id { copiedFieldID = nil }
        }
    }

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(LocalizedStringKey(notes)) // renders basic Markdown
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.fieldCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.fieldCardBorder, lineWidth: 1)
        }
    }

    private func tagsRow(_ tags: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private func passwordHistoryCard(_ history: [PasswordHistoryEntry]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(history.reversed(), id: \.replacedAt) { entry in
                    HStack {
                        Text(Theme.coloredPassword(entry.value, font: .caption.monospaced()))
                            .lineLimit(1)
                        Spacer()
                        Text(entry.replacedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button {
                            ClipboardManager.copy(entry.value, concealed: true)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Label("Password history (\(history.count))", systemImage: "clock.arrow.circlepath")
                .font(.callout)
        }
        .padding(14)
        .background(Theme.fieldCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.fieldCardBorder, lineWidth: 1)
        }
    }

    private func footer(_ item: VaultItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                historyShown = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Last edited \(item.updatedAt.formatted(date: .complete, time: .standard))")
                        .font(.system(size: 13))
                }
            }
            .buttonStyle(.plain)
            .help("View previous versions")

            HStack(spacing: 4) {
                Image(systemName: "lock.fill").font(.caption2)
                Text(store.vaultName(item.vaultID))
                Text("·")
                Text("Created \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 10)
    }
}

/// One read-mode field row: gray label above value, click-to-copy, hover
/// affordances, reveal/conceal for secrets.
struct FieldDisplayRow: View {
    let field: ItemField
    let revealed: Bool
    let copied: Bool
    let onCopy: () -> Void
    let onToggleReveal: () -> Void
    let onLargeType: () -> Void
    /// Present on website fields when the browser extension can auto-login.
    var onOpenAndFill: (() -> Void)? = nil

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(field.label)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.fieldLabel)
                valueView
            }
            Spacer()
            if copied {
                Label("Copied", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            } else if !hovering, field.purpose == .password, !field.value.isEmpty {
                // 1P8 shows the strength verdict at the right of the password row.
                let score = PasswordStrength.score(field.value)
                HStack(spacing: 6) {
                    Text(Theme.strengthDisplayName(score))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.strengthColor(score))
                    Circle()
                        .strokeBorder(Theme.strengthColor(score), lineWidth: 2)
                        .frame(width: 12, height: 12)
                }
            } else if hovering {
                HStack(spacing: 8) {
                    if let onOpenAndFill {
                        Button(action: onOpenAndFill) {
                            Image(systemName: "bolt.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        .help("Open & Fill")
                    }
                    if field.kind.isSecret {
                        Button(action: onToggleReveal) {
                            Image(systemName: revealed ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .help(revealed ? "Conceal" : "Reveal")
                        Button(action: onLargeType) {
                            Image(systemName: "textformat.size")
                        }
                        .buttonStyle(.plain)
                        .help("Show in Large Type")
                    }
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onCopy)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: copied)
        .contextMenu {
            Button("Copy") { onCopy() }
            if field.kind.isSecret {
                Button(revealed ? "Conceal" : "Reveal") { onToggleReveal() }
                Button("Show in Large Type") { onLargeType() }
            }
            if field.kind == .url, let url = URL(string: field.value.hasPrefix("http") ? field.value : "https://\(field.value)") {
                if let onOpenAndFill {
                    Button("Open & Fill") { onOpenAndFill() }
                }
                Button("Open in Browser") { NSWorkspace.shared.open(url) }
            }
        }
    }

    @ViewBuilder
    private var valueView: some View {
        switch field.kind {
        case .concealed, .sshKey:
            if revealed {
                Text(Theme.coloredPassword(field.value))
                    .textSelection(.enabled)
                    .lineLimit(field.kind == .sshKey ? 10 : 1)
            } else {
                Text(String(repeating: "•", count: min(max(field.value.count, 6), 12)))
                    .font(.body.monospaced())
            }
        case .otp:
            TOTPCodeView(secretInput: field.value)
        case .url:
            urlText(field.value)
                .lineLimit(1)
        default:
            Text(field.value)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    /// 1P8 styles URLs with the scheme/path dimmed and the host highlighted.
    private func urlText(_ urlString: String) -> Text {
        let candidate = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
        guard let url = URL(string: candidate), let host = url.host() else {
            return Text(urlString).foregroundStyle(Theme.accent)
        }
        let scheme = (url.scheme ?? "https") + "://"
        let path = url.path.isEmpty || url.path == "/" ? "" : url.path
        return Text(scheme).foregroundStyle(.secondary)
            + Text(host).foregroundStyle(Theme.accent).underline()
            + Text(path).foregroundStyle(.secondary)
    }
}

/// Full-window large type: big monospaced characters with position indices,
/// digits/symbols colored.
struct LargeTypeView: View {
    let value: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            FlowLayout(spacing: 6) {
                ForEach(Array(value.enumerated()), id: \.offset) { index, char in
                    VStack(spacing: 2) {
                        Text(String(char))
                            .font(.system(size: 36, weight: .semibold, design: .monospaced))
                            .foregroundStyle(charColor(char))
                        Text("\(index + 1)")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minWidth: 30)
                }
            }
            .padding(30)
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(minWidth: 460, maxWidth: 700)
    }

    private func charColor(_ char: Character) -> Color {
        if char.isNumber { return Theme.accent }
        if !char.isLetter { return Color(.sRGB, red: 0.90, green: 0.24, blue: 0.24) }
        return .primary
    }
}

/// Simple wrapping layout for large type characters.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Item edit history list with restore.
struct HistorySheet: View {
    let store: VaultStore
    let item: VaultItem
    let onRestore: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var versions: [ItemRepository.DecryptedVersion] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Item History")
                .font(.title3.bold())
            if versions.isEmpty {
                Text("No previous versions.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List(versions) { version in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(version.overview.title.isEmpty ? "Untitled" : version.overview.title)
                                .font(.callout.weight(.medium))
                            Text("Version \(version.versionNumber) — \(version.editedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") {
                            Task {
                                await store.restoreVersion(version, itemID: item.id)
                                onRestore()
                                dismiss()
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 220)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            versions = await store.versions(itemID: item.id)
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
