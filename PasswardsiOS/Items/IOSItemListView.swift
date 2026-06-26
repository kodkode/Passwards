import SwiftUI
import PasswardsCore
import PasswardsOrchestration

/// The Vault tab (Stitch "Vault Home"): dark surface, category filter chips, dark
/// item cards (icon · title · subtitle · chevron), swipe favorite/trash, a green
/// FAB to add, and a sort menu. Taps push the item detail.
struct IOSItemListView: View {
    @Bindable var vault: IOSVaultModel
    @State private var showCategoryPicker = false

    private struct Chip: Identifiable {
        let id: String
        let title: String
        let filter: VaultFilter
    }
    private let chips: [Chip] = [
        .init(id: "all", title: "All", filter: .allItems),
        .init(id: "login", title: "Logins", filter: .category(.login)),
        .init(id: "card", title: "Cards", filter: .category(.creditCard)),
        .init(id: "note", title: "Notes", filter: .category(.secureNote)),
        .init(id: "fav", title: "Favorites", filter: .favorites),
    ]

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
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    chipsRow
                    list.overlay {
                        if vault.visibleSummaries.isEmpty { emptyState }
                    }
                }
                fab
            }
            .background(Theme.background)
            .navigationTitle("Vault")
            .searchable(text: $vault.searchText, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { sortMenu }
            }
            .navigationDestination(for: String.self) { id in
                IOSItemDetailView(vault: vault, itemID: id)
            }
            .sheet(isPresented: $showCategoryPicker) {
                IOSCategoryPickerView(vault: vault)
            }
        }
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    let selected = vault.filter == chip.filter
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { vault.filter = chip.filter }
                    } label: {
                        Text(chip.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? Theme.navy : Theme.label)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selected ? Theme.accent : Theme.surfaceHigh, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Theme.background)
    }

    private var list: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.items) { summary in rowLink(summary) }
                } header: {
                    if let header = group.header {
                        Text(header).foregroundStyle(Theme.labelDim)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .refreshable { await vault.refresh() }
    }

    private func rowLink(_ summary: ItemSummary) -> some View {
        NavigationLink(value: summary.id) {
            ItemRow(summary: summary)
        }
        .listRowBackground(Theme.surface)
        .listRowSeparatorTint(Theme.cardBorder)
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
            .tint(Theme.accent)
        }
    }

    private var fab: some View {
        Button {
            showCategoryPicker = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.navy)
                .frame(width: 56, height: 56)
                .background(Theme.accent, in: Circle())
                .shadow(color: Theme.accent.opacity(0.4), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .padding(20)
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
        .tint(Theme.accent)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(vault.searchText.isEmpty ? "No Items Yet" : "No Results", systemImage: "key.fill")
        } description: {
            Text(vault.searchText.isEmpty ? "Tap + to add your first item." : "Try a different search.")
        }
    }
}

/// A single list row (Stitch Vault Home): monochrome glyph tile, title, and a
/// masked password preview for items that have a password (subtitle otherwise).
struct ItemRow: View {
    let summary: ItemSummary

    var body: some View {
        HStack(spacing: 12) {
            MonoIcon(overview: summary.overview, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.overview.title.isEmpty ? "Untitled" : summary.overview.title)
                    .font(Theme.text(16, .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                secondaryLine
            }
            Spacer()
            if summary.overview.isFavorite {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var secondaryLine: some View {
        if summary.overview.strengthBucket != nil {
            // Has a password → masked preview, like the Stitch mock.
            Text("••••••••••").font(Theme.mono(13)).foregroundStyle(Theme.labelDim)
        } else if !summary.overview.subtitle.isEmpty {
            Text(summary.overview.subtitle).font(Theme.text(14)).foregroundStyle(Theme.labelDim).lineLimit(1)
        }
    }
}
