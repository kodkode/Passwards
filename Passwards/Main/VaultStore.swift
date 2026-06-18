import SwiftUI
import PasswardsCore
import os

enum SidebarFilter: Hashable {
    case allItems
    case favorites
    case watchtower
    case category(PasswardsCore.Category)
    case tag(String)
    case vault(String)
    case archive
    case trash
}

enum SortKey: String, CaseIterable, Identifiable {
    case title = "Title"
    case dateEdited = "Date Edited"
    case dateCreated = "Date Created"
    var id: String { rawValue }
}

/// Unlock-time cache of decrypted overviews plus all item mutations.
/// Every mutation goes through the repository (encrypting) and then refreshes
/// the in-memory summaries.
@Observable
final class VaultStore {
    private(set) var vaults: [Vault] = []
    private(set) var summaries: [ItemSummary] = []

    var sidebarSelection: SidebarFilter = .allItems
    var selectedItemID: String?
    var searchText = ""
    var categoryFilter: PasswardsCore.Category?
    var sortKey: SortKey = .dateEdited   // 1P8 default: newest first, month groups
    var sortAscending = true

    /// When set, the detail pane shows the editor. `editorPrevious` is the
    /// pre-edit snapshot (nil = creating a new item), used for password history.
    var editorDraft: VaultItem?
    var editorPrevious: VaultItem?

    /// Files picked in the editor for `.file` fields, keyed by field ID.
    /// Encrypted and attached when the item is saved (the item row must exist
    /// before attachments can reference it).
    var pendingAttachments: [UUID: URL] = [:]

    var attachments: AttachmentStore? { appState.attachmentStore }

    private let appState: AppState
    let watchtower: WatchtowerState

    init(appState: AppState) {
        self.appState = appState
        self.watchtower = WatchtowerState(appState: appState)
    }

    private var items: ItemRepository? { appState.itemRepository }
    private var vaultRepo: VaultRepository? { appState.vaultRepository }

    func load() async {
        // Decryption requires the unlocked key store. Sync delivers remote
        // changes (onRemoteChanges → reloadFromRemote → load) that can arrive
        // while the vault is locked — decrypting then fails, and a locked vault
        // simply has nothing to load.
        guard appState.phase == .unlocked else { return }
        do {
            vaults = try await vaultRepo?.allVaults() ?? []
            summaries = try await items?.allSummaries() ?? []
        } catch {
            // A lock/unlock race or a single undecryptable record (e.g. a
            // foreign/corrupt CloudKit record) must never crash a password
            // manager. Log and keep whatever state we already had.
            Logger(subsystem: "com.michael.passwards", category: "vault-store")
                .error("VaultStore.load failed: \(String(describing: error), privacy: .public)")
        }
    }

    func refresh() async {
        await load()
        appState.sync.kick()
    }

    /// Drops every piece of decrypted/sensitive state so locking the vault
    /// actually sheds secrets from memory. Called from `AppState.lock()`; the
    /// next unlock re-runs `load()`. Without this the shared store keeps
    /// decrypted overviews (titles, usernames, URLs) — and, if locked mid-edit,
    /// a full plaintext item including its password — resident after lock.
    func clearSecrets() {
        vaults = []
        summaries = []
        editorDraft = nil
        editorPrevious = nil
        pendingAttachments = [:]
        selectedItemID = nil
        searchText = ""
        categoryFilter = nil
        sidebarSelection = .allItems
        watchtower.clear()
    }

    /// Reload from disk without pushing (used when remote changes arrive).
    func reloadFromRemote() async {
        await load()
    }

    // MARK: Derived collections

    var allTags: [String] {
        Array(Set(summaries.filter { $0.trashedAt == nil && !$0.overview.isArchived }.flatMap(\.overview.tags))).sorted()
    }

    var trashCount: Int { summaries.lazy.filter { $0.trashedAt != nil }.count }

    func vaultName(_ id: String) -> String {
        vaults.first(where: { $0.id == id })?.attributes.name ?? "Vault"
    }

    /// Items shown for the current sidebar selection + search + filter + sort.
    var visibleSummaries: [ItemSummary] {
        var result = summaries

        switch sidebarSelection {
        case .allItems:
            result = result.filter { $0.trashedAt == nil && !$0.overview.isArchived }
        case .watchtower:
            let flagged: Set<String>
            if let focus = watchtower.focus {
                flagged = watchtower.report.items(for: focus)
            } else {
                flagged = WatchtowerCheck.allCases.reduce(into: Set<String>()) {
                    $0.formUnion(watchtower.report.items(for: $1))
                }
            }
            result = result.filter { $0.trashedAt == nil && !$0.overview.isArchived && flagged.contains($0.id) }
        case .favorites:
            result = result.filter { $0.trashedAt == nil && !$0.overview.isArchived && $0.overview.isFavorite }
        case .category(let category):
            result = result.filter { $0.trashedAt == nil && !$0.overview.isArchived && $0.overview.category == category }
        case .tag(let tag):
            result = result.filter {
                $0.trashedAt == nil && !$0.overview.isArchived &&
                $0.overview.tags.contains(where: { $0 == tag || $0.hasPrefix(tag + "/") })
            }
        case .vault(let vaultID):
            result = result.filter { $0.trashedAt == nil && !$0.overview.isArchived && $0.vaultID == vaultID }
        case .archive:
            result = result.filter { $0.trashedAt == nil && $0.overview.isArchived }
        case .trash:
            result = result.filter { $0.trashedAt != nil }
        }

        if let categoryFilter {
            result = result.filter { $0.overview.category == categoryFilter }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.overview.title.lowercased().contains(query)
                || $0.overview.subtitle.lowercased().contains(query)
                || $0.overview.urls.contains(where: { $0.lowercased().contains(query) })
                || $0.overview.tags.contains(where: { $0.lowercased().contains(query) })
            }
        }

        switch sortKey {
        case .title:
            result.sort {
                let l = $0.overview.title.localizedCaseInsensitiveCompare($1.overview.title)
                return sortAscending ? l == .orderedAscending : l == .orderedDescending
            }
        case .dateEdited:
            result.sort { sortAscending ? $0.updatedAt > $1.updatedAt : $0.updatedAt < $1.updatedAt }
        case .dateCreated:
            result.sort { sortAscending ? $0.createdAt > $1.createdAt : $0.createdAt < $1.createdAt }
        }
        return result
    }

    /// List sections: grouped by month for date sorts (like 1P8), flat for title sort.
    var groupedSummaries: [(header: String?, items: [ItemSummary])] {
        let visible = visibleSummaries
        guard sortKey != .title else {
            return visible.isEmpty ? [] : [(nil, visible)]
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var groups: [(header: String?, items: [ItemSummary])] = []
        for summary in visible {
            let date = sortKey == .dateEdited ? summary.updatedAt : summary.createdAt
            let header = formatter.string(from: date).uppercased()
            if let last = groups.indices.last, groups[last].header == header {
                groups[last].items.append(summary)
            } else {
                groups.append((header, [summary]))
            }
        }
        return groups
    }

    var listTitle: String {
        switch sidebarSelection {
        case .allItems: "All Items"
        case .favorites: "Favorites"
        case .watchtower: "Watchtower"
        case .category(let c): c.displayName
        case .tag(let t): t
        case .vault(let id): vaultName(id)
        case .archive: "Archive"
        case .trash: "Recently Deleted"
        }
    }

    // MARK: Item CRUD

    /// Computes the derived overview bits (subtitle, strength, OTP flag) that
    /// keep list and Watchtower fast without decrypting details.
    static func reconcileOverview(_ item: inout VaultItem) {
        if let username = item.details.firstField(withPurpose: .username)?.value, !username.isEmpty {
            item.overview.subtitle = username
        } else if item.overview.category == .creditCard,
                  let number = item.details.firstField(withPurpose: .password)?.value, number.count >= 4 {
            item.overview.subtitle = "•••• " + number.suffix(4)
        } else {
            item.overview.subtitle = ""
        }
        item.overview.urls = item.details.sections
            .flatMap(\.fields)
            .filter { $0.kind == .url && !$0.value.isEmpty }
            .map(\.value)
        item.overview.hasOTP = item.details.sections
            .flatMap(\.fields)
            .contains { $0.kind == .otp && !$0.value.isEmpty }
        if let password = item.details.firstField(withPurpose: .password)?.value, !password.isEmpty {
            item.overview.strengthBucket = PasswordStrength.score(password).rawValue
        } else {
            item.overview.strengthBucket = nil
        }
    }

    func newItem(category: PasswardsCore.Category, vaultID: String? = nil) -> VaultItem {
        let targetVault = vaultID
            ?? { if case .vault(let id) = sidebarSelection { return id } else { return nil } }()
            ?? vaults.first?.id
            ?? ""
        var item = VaultItem(vaultID: targetVault)
        item.overview.category = category
        item.details = ItemDetails(sections: CategoryTemplates.template(for: category))
        if case .tag(let tag) = sidebarSelection {
            item.overview.tags = [tag]
        }
        return item
    }

    func create(_ item: VaultItem) async {
        var item = item
        Self.reconcileOverview(&item)
        do {
            try await items?.create(item)
            if try await attachPendingFiles(to: &item) {
                try await items?.update(item)
            }
            await refresh()
            selectedItemID = item.id
        } catch {
            assertionFailure("create failed: \(error)")
        }
    }

    /// Clones an item into the same vault: new ID, "(copy)" title, not a
    /// favorite, fresh timestamps. Attachment references are dropped (files are
    /// stored per originating item), and the new item is selected.
    func duplicate(itemID: String) async {
        guard let original = await item(id: itemID) else { return }
        var overview = original.overview
        overview.title = (overview.title.isEmpty ? "Untitled" : overview.title) + " (copy)"
        overview.isFavorite = false
        var details = original.details
        for s in details.sections.indices {
            for f in details.sections[s].fields.indices where details.sections[s].fields[f].kind == .file {
                details.sections[s].fields[f].value = ""
            }
        }
        await create(VaultItem(vaultID: original.vaultID, overview: overview, details: details))
    }

    /// Encrypts files picked in the editor and writes their attachment IDs
    /// into the corresponding `.file` fields. Returns true if anything changed.
    private func attachPendingFiles(to item: inout VaultItem) async throws -> Bool {
        guard !pendingAttachments.isEmpty, let attachments else { return false }
        var changed = false
        for (sectionIndex, section) in item.details.sections.enumerated() {
            for (fieldIndex, field) in section.fields.enumerated() {
                guard field.kind == .file, let url = pendingAttachments[field.id] else { continue }
                let data = try Data(contentsOf: url)
                let attachmentID = try await attachments.add(data: data, filename: url.lastPathComponent, itemID: item.id)
                item.details.sections[sectionIndex].fields[fieldIndex].value = attachmentID
                changed = true
            }
        }
        pendingAttachments.removeAll()
        return changed
    }

    /// Saves an edit; appends password history when the primary password changed.
    func save(_ item: VaultItem, previous: VaultItem?) async {
        var item = item
        _ = try? await attachPendingFiles(to: &item)
        if let oldPassword = previous?.details.firstField(withPurpose: .password)?.value,
           let newPassword = item.details.firstField(withPurpose: .password)?.value,
           !oldPassword.isEmpty, oldPassword != newPassword {
            item.details.passwordHistory.append(PasswordHistoryEntry(value: oldPassword, replacedAt: Date()))
            if item.details.passwordHistory.count > 50 {
                item.details.passwordHistory.removeFirst(item.details.passwordHistory.count - 50)
            }
        }
        Self.reconcileOverview(&item)
        do {
            try await items?.update(item)
            await refresh()
        } catch {
            assertionFailure("save failed: \(error)")
        }
    }

    func item(id: String) async -> VaultItem? {
        try? await items?.item(id: id)
    }

    /// 1P8's "Open & Fill": open the site and let the browser extension
    /// fill + submit the login automatically.
    func openAndFill(itemID: String, urlString: String) {
        appState.browserBridge?.openAndFill(itemID: itemID, urlString: urlString)
    }

    func toggleFavorite(_ summary: ItemSummary) async {
        var overview = summary.overview
        overview.isFavorite.toggle()
        try? await items?.updateOverview(overview, itemID: summary.id)
        await refresh()
    }

    func setArchived(_ archived: Bool, summary: ItemSummary) async {
        var overview = summary.overview
        overview.isArchived = archived
        try? await items?.updateOverview(overview, itemID: summary.id)
        await refresh()
    }

    func moveToTrash(_ summary: ItemSummary) async {
        try? await items?.moveToTrash(itemID: summary.id)
        if selectedItemID == summary.id { selectedItemID = nil }
        await refresh()
    }

    func restoreFromTrash(_ summary: ItemSummary) async {
        try? await items?.restoreFromTrash(itemID: summary.id)
        await refresh()
    }

    func deletePermanently(_ summary: ItemSummary) async {
        try? await items?.deletePermanently(itemID: summary.id)
        if selectedItemID == summary.id { selectedItemID = nil }
        await refresh()
    }

    func emptyTrash() async {
        try? await items?.emptyTrash()
        if case .trash = sidebarSelection { selectedItemID = nil }
        await refresh()
    }

    func move(itemID: String, toVault vaultID: String) async {
        try? await items?.move(itemID: itemID, toVault: vaultID)
        await refresh()
    }

    // MARK: Vaults

    func createVault(name: String, symbolName: String, colorToken: String) async {
        _ = try? await vaultRepo?.createVault(attributes: VaultAttributes(name: name, symbolName: symbolName, colorToken: colorToken))
        await refresh()
    }

    // MARK: History

    func versions(itemID: String) async -> [ItemRepository.DecryptedVersion] {
        (try? await items?.versions(itemID: itemID)) ?? []
    }

    func restoreVersion(_ version: ItemRepository.DecryptedVersion, itemID: String) async {
        try? await items?.restoreVersion(version, itemID: itemID)
        await refresh()
    }
}
