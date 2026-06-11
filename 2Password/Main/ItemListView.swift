import SwiftUI
import TwoPasswordCore

struct ItemListView: View {
    @Bindable var store: VaultStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.visibleSummaries.isEmpty {
                emptyState
            } else {
                List(selection: $store.selectedItemID) {
                    ForEach(Array(store.groupedSummaries.enumerated()), id: \.offset) { _, group in
                        if let header = group.header {
                            Section {
                                rows(group.items)
                            } header: {
                                Text(header)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            }
                        } else {
                            rows(group.items)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.listBackground)
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search items")
        .navigationTitle(store.listTitle)
    }

    private func rows(_ items: [ItemSummary]) -> some View {
        ForEach(items) { summary in
            ItemListRow(summary: summary, store: store)
                .tag(summary.id)
        }
    }

    private var header: some View {
        HStack {
            Menu {
                Button("All Categories") { store.categoryFilter = nil }
                Divider()
                ForEach(TwoPasswordCore.Category.allCases) { category in
                    Button(category.displayName) { store.categoryFilter = category }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(store.categoryFilter?.displayName ?? "All Categories")
                        .font(.callout)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            Text("\(store.visibleSummaries.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                Picker("Sort by", selection: $store.sortKey) {
                    ForEach(SortKey.allCases) { key in
                        Text(key.rawValue).tag(key)
                    }
                }
                Divider()
                Toggle(store.sortKey == .title ? "A → Z" : "Newest First", isOn: $store.sortAscending)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.callout)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: emptyStateSymbol)
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(emptyStateText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var emptyStateSymbol: String {
        switch store.sidebarSelection {
        case .trash: "trash"
        case .archive: "archivebox"
        case .favorites: "star"
        default: "square.grid.2x2"
        }
    }

    private var emptyStateText: String {
        if !store.searchText.isEmpty { return "No items match “\(store.searchText)”" }
        switch store.sidebarSelection {
        case .trash: return "Recently deleted items appear here for 30 days."
        case .archive: return "Archived items are hidden from lists and search."
        case .favorites: return "Mark items as favorites to pin them here."
        default: return "No items yet.\nPress ⌘N to add your first item."
        }
    }
}

struct ItemListRow: View {
    let summary: ItemSummary
    let store: VaultStore

    var body: some View {
        HStack(spacing: 9) {
            ItemIconView(summary: summary, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(summary.overview.title.isEmpty ? "Untitled" : summary.overview.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if summary.overview.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                    }
                }
                if !summary.overview.subtitle.isEmpty {
                    Text(summary.overview.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contextMenu {
            contextMenu
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if summary.trashedAt != nil {
            Button("Restore") {
                Task { await store.restoreFromTrash(summary) }
            }
            Button("Delete Permanently", role: .destructive) {
                Task { await store.deletePermanently(summary) }
            }
        } else {
            Button(summary.overview.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                Task { await store.toggleFavorite(summary) }
            }
            if store.vaults.count > 1 {
                Menu("Move to Vault") {
                    ForEach(store.vaults.filter { $0.id != summary.vaultID }) { vault in
                        Button(vault.attributes.name) {
                            Task { await store.move(itemID: summary.id, toVault: vault.id) }
                        }
                    }
                }
            }
            Button(summary.overview.isArchived ? "Unarchive" : "Archive") {
                Task { await store.setArchived(!summary.overview.isArchived, summary: summary) }
            }
            Divider()
            Button("Move to Recently Deleted", role: .destructive) {
                Task { await store.moveToTrash(summary) }
            }
        }
    }
}

/// Rich icon: website favicon when the item has a URL, category icon otherwise.
struct ItemIconView: View {
    let summary: ItemSummary
    var size: CGFloat = 32

    var body: some View {
        if let url = summary.overview.urls.first, !url.isEmpty {
            FaviconView(urlString: url, fallback: summary.overview.category, size: size)
        } else {
            CategoryIconView(category: summary.overview.category, size: size)
        }
    }
}
