import SwiftUI
import PasswardsCore
import PasswardsOrchestration

/// A reusable dark item list (rows → detail) with mode-aware swipe actions. Used
/// by Vault Home search results, the Security per-check drill-down, and the
/// Categories / Tags / Archive / Trash browse screens. Reads its rows from `vault`
/// via `source` so favorite/archive/trash swipes update the list live. Expects an
/// ambient NavigationStack whose root declares `.navigationDestination(for: String.self)`.
struct IOSItemList: View {
    enum Mode { case active, archive, trash }

    let vault: IOSVaultModel
    let source: (IOSVaultModel) -> [ItemSummary]
    var title: String?
    var emptyText: String = "Nothing here"
    var mode: Mode = .active

    private var summaries: [ItemSummary] { source(vault) }

    var body: some View {
        List {
            ForEach(summaries) { summary in
                NavigationLink(value: summary.id) { ItemRow(summary: summary) }
                    .listRowBackground(Theme.surface)
                    .listRowSeparatorTint(Theme.cardBorder)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) { leadingActions(summary) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) { trailingActions(summary) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if summaries.isEmpty {
                ContentUnavailableView(emptyText, systemImage: mode == .trash ? "trash" : "checkmark.shield")
            }
        }
        .modifier(OptionalTitle(title: title))
    }

    @ViewBuilder private func leadingActions(_ s: ItemSummary) -> some View {
        if mode == .active {
            Button { Task { await vault.toggleFavorite(s) } } label: {
                Label(s.overview.isFavorite ? "Unfavorite" : "Favorite",
                      systemImage: s.overview.isFavorite ? "star.slash.fill" : "star.fill")
            }
            .tint(.yellow)
        }
    }

    @ViewBuilder private func trailingActions(_ s: ItemSummary) -> some View {
        switch mode {
        case .active:
            Button(role: .destructive) { Task { await vault.moveToTrash(s) } } label: {
                Label("Trash", systemImage: "trash")
            }
            Button { Task { await vault.setArchived(s, true) } } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.gray)
        case .archive:
            Button(role: .destructive) { Task { await vault.moveToTrash(s) } } label: {
                Label("Trash", systemImage: "trash")
            }
            Button { Task { await vault.setArchived(s, false) } } label: {
                Label("Unarchive", systemImage: "tray.and.arrow.up")
            }
            .tint(Theme.accent)
        case .trash:
            Button(role: .destructive) { Task { await vault.deletePermanently(s) } } label: {
                Label("Delete", systemImage: "trash.fill")
            }
            Button { Task { await vault.restoreFromTrash(s) } } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(Theme.accent)
        }
    }
}

private struct OptionalTitle: ViewModifier {
    let title: String?
    func body(content: Content) -> some View {
        if let title { content.navigationTitle(title) } else { content }
    }
}

/// A single list row: favicon icon, title, and a username/subtitle line.
struct ItemRow: View {
    let summary: ItemSummary

    var body: some View {
        HStack(spacing: 12) {
            ItemIcon(overview: summary.overview, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.overview.title.isEmpty ? "Untitled" : summary.overview.title)
                    .font(Theme.text(16, .medium)).foregroundStyle(.primary).lineLimit(1)
                if !summary.overview.subtitle.isEmpty {
                    Text(summary.overview.subtitle).font(Theme.text(14)).foregroundStyle(Theme.labelDim).lineLimit(1)
                }
            }
            Spacer()
            if summary.overview.isFavorite {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 4)
    }
}
