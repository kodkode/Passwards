import SwiftUI
import UIKit
import PasswardsCore
import PasswardsOrchestration

/// The Vault tab (Stitch "Vault Home"): a dashboard — Pinned (favorites) + Recent
/// sections, a Watchtower score card, and a New Item button. Searching swaps the
/// dashboard for a full filtered item list. Taps push the item detail.
struct IOSVaultHomeView: View {
    @Bindable var vault: IOSVaultModel
    let watchtower: IOSWatchtowerModel
    @Binding var selectedTab: IOSTab

    @State private var path = NavigationPath()
    @State private var showCategoryPicker = false

    private var active: [ItemSummary] {
        vault.summaries.filter { $0.trashedAt == nil && !$0.overview.isArchived }
    }
    private var pinned: [ItemSummary] { active.filter { $0.overview.isFavorite } }
    private var recent: [ItemSummary] {
        Array(active.sorted { $0.updatedAt > $1.updatedAt }.prefix(6))
    }
    private var searchResults: [ItemSummary] {
        VaultQuery.filteredSorted(vault.summaries, filter: .allItems, search: vault.searchText,
                                  categoryFilter: nil, sortKey: .title, ascending: true)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if vault.searchText.isEmpty {
                    dashboard
                } else {
                    IOSItemList(vault: vault, source: { _ in searchResults }, emptyText: "No results")
                }
            }
            .background(Theme.background)
            .navigationTitle("Vault")
            .searchable(text: $vault.searchText, prompt: "Search Vault")
            .navigationDestination(for: String.self) { id in
                IOSItemDetailView(vault: vault, itemID: id, watchtower: watchtower)
            }
            .navigationDestination(for: BrowseRoute.self) { route in browseDestination(route) }
            .sheet(isPresented: $showCategoryPicker) { IOSCategoryPickerView(vault: vault) }
            .refreshable { await vault.refresh(); await watchtower.run() }
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !pinned.isEmpty {
                    sectionHeader("Pinned", systemImage: "pin.fill")
                    VStack(spacing: 16) { ForEach(pinned) { pinnedCard($0) } }
                }
                if !recent.isEmpty {
                    sectionHeader("Recent", systemImage: "clock.arrow.circlepath")
                    recentCard
                }
                sectionHeader("Browse", systemImage: "rectangle.stack.fill")
                browseCard
                watchtowerCard
                newItemButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 18)).foregroundStyle(Theme.labelDim)
            Text(title).font(Theme.title(22, .bold)).foregroundStyle(Theme.primaryLabel)
        }
    }

    private func pinnedCard(_ s: ItemSummary) -> some View {
        HStack(spacing: 16) {
            ItemIcon(overview: s.overview, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.overview.title.isEmpty ? "Untitled" : s.overview.title)
                    .font(Theme.text(15, .semibold)).foregroundStyle(Theme.primaryLabel).lineLimit(1)
                if !s.overview.subtitle.isEmpty {
                    Text(s.overview.subtitle).font(Theme.text(15)).foregroundStyle(Theme.label).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if !s.overview.subtitle.isEmpty {
                Button {
                    UIPasteboard.general.string = s.overview.subtitle
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 18)).foregroundStyle(Theme.labelDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { path.append(s.id) }
    }

    private var recentCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(recent.enumerated()), id: \.element.id) { idx, s in
                Button { path.append(s.id) } label: {
                    HStack(spacing: 16) {
                        ItemIcon(overview: s.overview, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.overview.title.isEmpty ? "Untitled" : s.overview.title)
                                .font(Theme.text(15, .semibold)).foregroundStyle(Theme.primaryLabel).lineLimit(1)
                            Text(subtitle(s)).font(Theme.text(14)).foregroundStyle(Theme.label).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.callout).foregroundStyle(Theme.labelDim)
                    }
                    .padding(16)
                }
                .buttonStyle(.plain)
                if idx < recent.count - 1 {
                    Divider().overlay(Theme.cardBorder).padding(.leading, 16)
                }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }

    private func subtitle(_ s: ItemSummary) -> String {
        s.overview.subtitle.isEmpty ? s.overview.category.displayName : s.overview.subtitle
    }

    private var watchtowerCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                Text("Watchtower").font(Theme.title(22, .bold)).foregroundStyle(Theme.primaryLabel)
                Spacer()
                Image(systemName: "checkmark.shield.fill").font(.system(size: 22)).foregroundStyle(Theme.accent)
            }
            CircularGauge(fraction: Double(watchtower.score) / 100, value: "\(watchtower.score)",
                          label: watchtower.scoreLabel, color: watchtower.scoreColor, size: 116,
                          valueFont: 30, labelColor: watchtower.scoreColor)
                .padding(.vertical, 4)
            VStack(spacing: 8) {
                statRow("Reused Passwords", value: "\(watchtower.reused)",
                        color: watchtower.reused > 0 ? Theme.warn : Theme.primaryLabel)
                statRow("Weak Passwords", value: "\(watchtower.weak)",
                        color: watchtower.weak > 0 ? Theme.warn : Theme.primaryLabel)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.accent.opacity(0.06), .clear],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { selectedTab = .security }
    }

    private func statRow(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).font(Theme.text(15)).foregroundStyle(Theme.label)
            Spacer()
            Text(value).font(Theme.text(15, .bold)).foregroundStyle(color)
        }
    }

    // MARK: Browse

    private var browseCard: some View {
        VStack(spacing: 0) {
            browseRow("All Items", icon: "tray.full.fill", tint: Theme.link,
                      count: vault.activeSummaries.count, route: .allItems, divider: true)
            browseRow("Categories", icon: "square.grid.2x2.fill", tint: Theme.accent,
                      count: vault.categoryCounts.count, route: .categories, divider: true)
            browseRow("Tags", icon: "tag.fill", tint: .orange,
                      count: vault.tagCounts.count, route: .tags, divider: true)
            browseRow("Archive", icon: "archivebox.fill", tint: .gray,
                      count: vault.archiveCount, route: .archive, divider: true)
            browseRow("Trash", icon: "trash.fill", tint: Theme.danger,
                      count: vault.trashCount, route: .trash, divider: false)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }

    private func browseRow(_ label: String, icon: String, tint: Color, count: Int,
                           route: BrowseRoute, divider: Bool) -> some View {
        VStack(spacing: 0) {
            Button { path.append(route) } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon).font(.system(size: 15)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Text(label).font(Theme.text(16)).foregroundStyle(Theme.primaryLabel)
                    Spacer()
                    Text("\(count)").font(Theme.text(15)).foregroundStyle(Theme.labelDim)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.labelDim)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            if divider { Divider().overlay(Theme.cardBorder).padding(.leading, 58) }
        }
    }

    @ViewBuilder private func browseDestination(_ route: BrowseRoute) -> some View {
        switch route {
        case .allItems:
            IOSItemList(vault: vault, source: { $0.activeSummaries }, title: "All Items", mode: .active)
        case .archive:
            IOSItemList(vault: vault, source: { $0.archivedSummaries }, title: "Archive",
                        emptyText: "No archived items", mode: .archive)
        case .trash:
            IOSItemList(vault: vault, source: { $0.trashedSummaries }, title: "Trash",
                        emptyText: "Trash is empty", mode: .trash)
        case .categories:
            IOSCategoriesView(vault: vault)
        case .tags:
            IOSTagsView(vault: vault)
        case .category(let c):
            IOSItemList(vault: vault, source: { $0.items(in: c) }, title: c.displayName, mode: .active)
        case .tag(let t):
            IOSItemList(vault: vault, source: { $0.items(taggedWith: t) }, title: t, mode: .active)
        }
    }

    private var newItemButton: some View {
        Button {
            showCategoryPicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                Text("New Item").font(Theme.text(16, .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Theme.accent.opacity(0.3), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}
