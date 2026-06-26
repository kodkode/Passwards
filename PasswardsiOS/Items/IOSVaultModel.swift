import Foundation
import os
import PasswardsCore
import PasswardsOrchestration

/// iOS vault view-model: the unlock-time summary cache + CRUD + list navigation
/// state. The genuinely-shared, complex bits (filter/sort, overview derivation)
/// come from `VaultQuery`; the repositories come from the shared `AccountController`.
/// This is the iOS analog of the macOS `VaultStore` (navigation is platform-shaped).
@MainActor
@Observable
final class IOSVaultModel {
    let core: AccountController

    private(set) var vaults: [Vault] = []
    private(set) var summaries: [ItemSummary] = []

    var searchText = ""
    var sortKey: VaultSortKey = .dateEdited
    var sortAscending = true
    var filter: VaultFilter = .allItems

    #if DEBUG
    /// Sample items for screenshot/design previews (no live repository).
    var seededItems: [String: VaultItem] = [:]

    /// Populates the model with sample data for `-uiPreview` screenshots.
    func seedPreview() {
        let samples: [(id: String, title: String, sub: String, cat: PasswardsCore.Category, fav: Bool, day: Double)] = [
            ("1", "GitHub", "octocat", .login, true, 0),
            ("2", "Personal Email", "me@example.com", .emailAccount, false, 1),
            ("3", "Visa", "•••• 4242", .creditCard, false, 2),
            ("4", "AWS Production", "AKIA…", .apiCredential, false, 9),
            ("5", "Home Wi-Fi", "Living room", .wirelessRouter, false, 12),
        ]
        let base = Date(timeIntervalSince1970: 1_717_200_000) // 2024-06
        summaries = samples.map { s in
            ItemSummary(
                id: s.id, vaultID: "v",
                overview: ItemOverview(title: s.title, subtitle: s.sub, isFavorite: s.fav, category: s.cat),
                createdAt: base, updatedAt: base.addingTimeInterval(-s.day * 86_400), trashedAt: nil
            )
        }
        var gh = VaultItem(id: "1", vaultID: "v")
        gh.overview = ItemOverview(title: "GitHub", subtitle: "octocat", isFavorite: true, category: .login)
        gh.details = ItemDetails(sections: [
            ItemSection(fields: [
                ItemField(label: "username", kind: .text, value: "octocat", purpose: .username),
                ItemField(label: "password", kind: .concealed, value: "h0rse-Battery-9!", purpose: .password),
                ItemField(label: "one-time password", kind: .otp, value: "otpauth://totp/GitHub:octocat?secret=JBSWY3DPEHPK3PXP&issuer=GitHub"),
                ItemField(label: "website", kind: .url, value: "https://github.com"),
            ])
        ], notes: "Personal account.")
        seededItems["1"] = gh
    }

    /// The seeded detail item (call `seedPreview()` first). For editor previews.
    var seededDetailItem: VaultItem { seededItems["1"] ?? newItem(category: .login) }
    #endif

    init(core: AccountController) { self.core = core }

    private var items: ItemRepository? { core.itemRepository }
    private var vaultRepo: VaultRepository? { core.vaultRepository }
    var attachments: AttachmentStore? { core.attachmentStore }

    func load() async {
        guard core.phase == .unlocked else { return }
        do {
            vaults = try await vaultRepo?.allVaults() ?? []
            summaries = try await items?.allSummaries() ?? []
        } catch {
            // A lock/unlock race or a single undecryptable record must never crash
            // a password manager — keep prior state.
            Logger(subsystem: "com.michael.passwards", category: "ios-vault")
                .error("load failed: \(String(describing: error), privacy: .public)")
        }
    }

    func refresh() async {
        await load()
        core.sync.kick()
    }

    func clearSecrets() {
        vaults = []
        summaries = []
        searchText = ""
        filter = .allItems
    }

    // MARK: Derived

    var visibleSummaries: [ItemSummary] {
        VaultQuery.filteredSorted(
            summaries, filter: filter, search: searchText,
            categoryFilter: nil, sortKey: sortKey, ascending: sortAscending
        )
    }

    var grouped: [(header: String?, items: [ItemSummary])] {
        VaultQuery.grouped(visibleSummaries, sortKey: sortKey)
    }

    var trashCount: Int { summaries.lazy.filter { $0.trashedAt != nil }.count }

    // MARK: CRUD

    func item(id: String) async -> VaultItem? {
        #if DEBUG
        if let seeded = seededItems[id] { return seeded }
        #endif
        return try? await items?.item(id: id)
    }

    func newItem(category: PasswardsCore.Category) -> VaultItem {
        var item = VaultItem(vaultID: vaults.first?.id ?? "")
        item.overview.category = category
        item.details = ItemDetails(sections: CategoryTemplates.template(for: category))
        return item
    }

    func create(_ item: VaultItem) async {
        var item = item
        VaultQuery.reconcileOverview(&item)
        do {
            _ = try await items?.create(item)
            await refresh()
        } catch {
            assertionFailure("create failed: \(error)")
        }
    }

    func save(_ item: VaultItem, previous: VaultItem?) async {
        var item = item
        if let oldPassword = previous?.details.firstField(withPurpose: .password)?.value,
           let newPassword = item.details.firstField(withPurpose: .password)?.value,
           !oldPassword.isEmpty, oldPassword != newPassword {
            item.details.passwordHistory.append(PasswordHistoryEntry(value: oldPassword, replacedAt: Date()))
            if item.details.passwordHistory.count > 50 {
                item.details.passwordHistory.removeFirst(item.details.passwordHistory.count - 50)
            }
        }
        VaultQuery.reconcileOverview(&item)
        do {
            try await items?.update(item)
            await refresh()
        } catch {
            assertionFailure("save failed: \(error)")
        }
    }

    func toggleFavorite(_ summary: ItemSummary) async {
        var overview = summary.overview
        overview.isFavorite.toggle()
        try? await items?.updateOverview(overview, itemID: summary.id)
        await refresh()
    }

    func moveToTrash(_ summary: ItemSummary) async {
        try? await items?.moveToTrash(itemID: summary.id)
        await refresh()
    }

    func restoreFromTrash(_ summary: ItemSummary) async {
        try? await items?.restoreFromTrash(itemID: summary.id)
        await refresh()
    }

    func deletePermanently(_ summary: ItemSummary) async {
        try? await items?.deletePermanently(itemID: summary.id)
        await refresh()
    }
}
