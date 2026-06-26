import Foundation
import Testing
import PasswardsCore
@testable import PasswardsOrchestration

/// Locks the behavior of the shared list/derivation logic that both apps depend
/// on. These ran inside the macOS VaultStore before the extraction; pinning them
/// here guarantees macOS and iOS stay identical.
@Suite struct VaultQueryTests {

    private func summary(
        id: String,
        title: String,
        subtitle: String = "",
        tags: [String] = [],
        urls: [String] = [],
        category: PasswardsCore.Category = .login,
        archived: Bool = false,
        favorite: Bool = false,
        trashed: Bool = false,
        created: Date = Date(timeIntervalSince1970: 0),
        updated: Date = Date(timeIntervalSince1970: 0)
    ) -> ItemSummary {
        ItemSummary(
            id: id, vaultID: "v",
            overview: ItemOverview(
                title: title, subtitle: subtitle, urls: urls, tags: tags,
                isFavorite: favorite, isArchived: archived, category: category
            ),
            createdAt: created, updatedAt: updated,
            trashedAt: trashed ? Date(timeIntervalSince1970: 0) : nil
        )
    }

    // MARK: filteredSorted

    @Test func allItemsExcludesArchivedAndTrashed() {
        let items = [
            summary(id: "1", title: "Active"),
            summary(id: "2", title: "Archived", archived: true),
            summary(id: "3", title: "Trashed", trashed: true),
        ]
        let result = VaultQuery.filteredSorted(items, filter: .allItems, search: "", categoryFilter: nil, sortKey: .title, ascending: true)
        #expect(result.map(\.id) == ["1"])
    }

    @Test func trashShowsOnlyTrashed() {
        let items = [summary(id: "1", title: "Active"), summary(id: "2", title: "Gone", trashed: true)]
        let result = VaultQuery.filteredSorted(items, filter: .trash, search: "", categoryFilter: nil, sortKey: .title, ascending: true)
        #expect(result.map(\.id) == ["2"])
    }

    @Test func archiveShowsOnlyArchivedNotTrashed() {
        let items = [
            summary(id: "1", title: "Active"),
            summary(id: "2", title: "Archived", archived: true),
            summary(id: "3", title: "ArchivedTrashed", archived: true, trashed: true),
        ]
        let result = VaultQuery.filteredSorted(items, filter: .archive, search: "", categoryFilter: nil, sortKey: .title, ascending: true)
        #expect(result.map(\.id) == ["2"])
    }

    @Test func favoritesFilter() {
        let items = [summary(id: "1", title: "A", favorite: true), summary(id: "2", title: "B")]
        let result = VaultQuery.filteredSorted(items, filter: .favorites, search: "", categoryFilter: nil, sortKey: .title, ascending: true)
        #expect(result.map(\.id) == ["1"])
    }

    @Test func flaggedFilterKeepsOnlyTheFlaggedSet() {
        let items = [summary(id: "1", title: "A"), summary(id: "2", title: "B"), summary(id: "3", title: "C")]
        let result = VaultQuery.filteredSorted(items, filter: .flagged(["1", "3"]), search: "", categoryFilter: nil, sortKey: .title, ascending: true)
        #expect(result.map(\.id) == ["1", "3"])
    }

    @Test func tagFilterMatchesExactAndNestedTags() {
        let items = [
            summary(id: "1", title: "A", tags: ["work"]),
            summary(id: "2", title: "B", tags: ["work/clients"]),
            summary(id: "3", title: "C", tags: ["personal"]),
        ]
        let result = VaultQuery.filteredSorted(items, filter: .tag("work"), search: "", categoryFilter: nil, sortKey: .title, ascending: true)
        #expect(Set(result.map(\.id)) == ["1", "2"])
    }

    @Test func searchMatchesTitleSubtitleURLAndTag() {
        let items = [
            summary(id: "1", title: "GitHub"),
            summary(id: "2", title: "Email", subtitle: "me@github.com"),
            summary(id: "3", title: "Site", urls: ["https://github.com"]),
            summary(id: "4", title: "Tagged", tags: ["github"]),
            summary(id: "5", title: "Unrelated"),
        ]
        let result = VaultQuery.filteredSorted(items, filter: .allItems, search: "github", categoryFilter: nil, sortKey: .title, ascending: true)
        #expect(Set(result.map(\.id)) == ["1", "2", "3", "4"])
    }

    @Test func categoryFilterNarrowsResults() {
        let items = [
            summary(id: "1", title: "Login", category: .login),
            summary(id: "2", title: "Card", category: .creditCard),
        ]
        let result = VaultQuery.filteredSorted(items, filter: .allItems, search: "", categoryFilter: .creditCard, sortKey: .title, ascending: true)
        #expect(result.map(\.id) == ["2"])
    }

    @Test func titleSortIsCaseInsensitive() {
        let items = [summary(id: "1", title: "Bravo"), summary(id: "2", title: "alpha")]
        let asc = VaultQuery.filteredSorted(items, filter: .allItems, search: "", categoryFilter: nil, sortKey: .title, ascending: true)
        #expect(asc.map(\.id) == ["2", "1"])
        let desc = VaultQuery.filteredSorted(items, filter: .allItems, search: "", categoryFilter: nil, sortKey: .title, ascending: false)
        #expect(desc.map(\.id) == ["1", "2"])
    }

    @Test func dateEditedSortIsNewestFirstWhenAscending() {
        // 1P8 default: sortKey=.dateEdited, ascending=true → newest at top.
        let items = [
            summary(id: "old", title: "Old", updated: Date(timeIntervalSince1970: 100)),
            summary(id: "new", title: "New", updated: Date(timeIntervalSince1970: 200)),
        ]
        let result = VaultQuery.filteredSorted(items, filter: .allItems, search: "", categoryFilter: nil, sortKey: .dateEdited, ascending: true)
        #expect(result.map(\.id) == ["new", "old"])
    }

    // MARK: grouped

    @Test func groupedIsFlatForTitleSort() {
        let groups = VaultQuery.grouped([summary(id: "1", title: "A")], sortKey: .title)
        #expect(groups.count == 1)
        #expect(groups[0].header == nil)
    }

    @Test func groupedBucketsByMonthForDateSort() {
        let jan = Date(timeIntervalSince1970: 0)            // 1970-01
        let feb = Date(timeIntervalSince1970: 60 * 86_400)  // ~1970-03 — different month
        let items = [
            summary(id: "1", title: "A", updated: feb),
            summary(id: "2", title: "B", updated: jan),
        ]
        // already sorted newest-first by the caller in practice; grouped preserves order
        let visible = VaultQuery.filteredSorted(items, filter: .allItems, search: "", categoryFilter: nil, sortKey: .dateEdited, ascending: true)
        let groups = VaultQuery.grouped(visible, sortKey: .dateEdited)
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.header != nil })
    }

    // MARK: reconcileOverview

    @Test func reconcileDerivesSubtitleURLsOTPAndStrength() {
        var item = VaultItem(vaultID: "v", details: ItemDetails(sections: [
            ItemSection(fields: [
                ItemField(label: "username", kind: .text, value: "michael", purpose: .username),
                ItemField(label: "password", kind: .concealed, value: "Tr0ub4dour&3xtra!", purpose: .password),
                ItemField(label: "website", kind: .url, value: "https://example.com"),
                ItemField(label: "totp", kind: .otp, value: "otpauth://totp/x?secret=ABCDEF"),
            ])
        ]))
        VaultQuery.reconcileOverview(&item)
        #expect(item.overview.subtitle == "michael")
        #expect(item.overview.urls == ["https://example.com"])
        #expect(item.overview.hasOTP == true)
        #expect(item.overview.strengthBucket != nil)
    }

    @Test func reconcileMasksCreditCardNumberAsSubtitle() {
        var item = VaultItem(
            vaultID: "v",
            overview: ItemOverview(category: .creditCard),
            details: ItemDetails(sections: [ItemSection(fields: [
                ItemField(label: "number", kind: .concealed, value: "4111111111111234", purpose: .password)
            ])])
        )
        VaultQuery.reconcileOverview(&item)
        #expect(item.overview.subtitle == "•••• 1234")
    }

    @Test func reconcileClearsDerivedFieldsWhenEmpty() {
        var item = VaultItem(vaultID: "v", details: ItemDetails(sections: [ItemSection(fields: [])]))
        VaultQuery.reconcileOverview(&item)
        #expect(item.overview.subtitle == "")
        #expect(item.overview.urls.isEmpty)
        #expect(item.overview.hasOTP == false)
        #expect(item.overview.strengthBucket == nil)
    }
}
