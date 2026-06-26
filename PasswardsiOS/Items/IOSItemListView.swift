import SwiftUI
import PasswardsCore
import PasswardsOrchestration

/// The Items tab: a searchable, month-sectioned list (1P8 default sort), with
/// swipe-to-favorite / swipe-to-trash, a sort menu, and a "+" that creates a new
/// item via the category picker. Taps push the item detail.
struct IOSItemListView: View {
    @Bindable var vault: IOSVaultModel
    @State private var showCategoryPicker = false

    private struct ListGroup: Identifiable {
        let id: String
        let header: String?
        let items: [ItemSummary]
    }

    private var groups: [ListGroup] {
        vault.grouped.enumerated().map { idx, g in
            ListGroup(id: g.header ?? "g\(idx)", header: g.header, items: g.items)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if vault.visibleSummaries.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Items")
            .searchable(text: $vault.searchText, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { sortMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCategoryPicker = true } label: { Image(systemName: "plus") }
                }
            }
            .navigationDestination(for: String.self) { id in
                IOSItemDetailView(vault: vault, itemID: id)
            }
            .sheet(isPresented: $showCategoryPicker) {
                IOSCategoryPickerView(vault: vault)
            }
        }
        .tint(Theme.accent)
    }

    private var list: some View {
        List {
            ForEach(groups) { group in
                if let header = group.header {
                    Section(header) { rows(group.items) }
                } else {
                    Section { rows(group.items) }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func rows(_ items: [ItemSummary]) -> some View {
        ForEach(items) { summary in
            NavigationLink(value: summary.id) {
                ItemRow(summary: summary)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task { await vault.moveToTrash(summary) }
                } label: { Label("Trash", systemImage: "trash") }
            }
            .swipeActions(edge: .leading) {
                Button {
                    Task { await vault.toggleFavorite(summary) }
                } label: {
                    Label(summary.overview.isFavorite ? "Unfavorite" : "Favorite",
                          systemImage: summary.overview.isFavorite ? "star.slash" : "star")
                }
                .tint(.yellow)
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $vault.sortKey) {
                Text("Title").tag(VaultSortKey.title)
                Text("Date Edited").tag(VaultSortKey.dateEdited)
                Text("Date Created").tag(VaultSortKey.dateCreated)
            }
            Toggle("Ascending", isOn: $vault.sortAscending)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(vault.searchText.isEmpty ? "No Items Yet" : "No Results", systemImage: "key.fill")
        } description: {
            Text(vault.searchText.isEmpty ? "Tap + to add your first item." : "Try a different search.")
        }
    }
}

/// A single list row: category/custom icon, title, subtitle, favorite star.
struct ItemRow: View {
    let summary: ItemSummary

    var body: some View {
        HStack(spacing: 12) {
            ItemIcon(overview: summary.overview, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(summary.overview.title.isEmpty ? "Untitled" : summary.overview.title)
                    .font(.body)
                    .lineLimit(1)
                if !summary.overview.subtitle.isEmpty {
                    Text(summary.overview.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if summary.overview.isFavorite {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 2)
    }
}
