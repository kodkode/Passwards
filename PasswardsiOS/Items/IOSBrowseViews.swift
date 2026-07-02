import SwiftUI
import PasswardsCore
import PasswardsOrchestration

/// Navigation routes for the Vault tab's "Browse" section. Resolved by the Vault
/// stack's `.navigationDestination(for: BrowseRoute.self)`.
enum BrowseRoute: Hashable {
    case allItems, archive, trash, categories, tags
    case category(PasswardsCore.Category)
    case tag(String)
}

/// Browse-by-category: every category that has active items, with counts, 1P-style.
struct IOSCategoriesView: View {
    let vault: IOSVaultModel

    var body: some View {
        List {
            ForEach(vault.categoryCounts, id: \.category) { entry in
                NavigationLink(value: BrowseRoute.category(entry.category)) {
                    HStack(spacing: 12) {
                        CategoryIcon(category: entry.category, size: 30)
                        Text(entry.category.displayName).font(Theme.text(16)).foregroundStyle(.primary)
                        Spacer()
                        Text("\(entry.count)").font(Theme.text(15)).foregroundStyle(Theme.labelDim)
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Categories")
        .overlay {
            if vault.categoryCounts.isEmpty {
                ContentUnavailableView("No items", systemImage: "square.grid.2x2")
            }
        }
    }
}

/// Browse-by-tag: every tag across active items, with counts.
struct IOSTagsView: View {
    let vault: IOSVaultModel

    var body: some View {
        List {
            ForEach(vault.tagCounts, id: \.tag) { entry in
                NavigationLink(value: BrowseRoute.tag(entry.tag)) {
                    HStack(spacing: 12) {
                        Image(systemName: "tag.fill").font(.system(size: 14)).foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Text(entry.tag).font(Theme.text(16)).foregroundStyle(.primary)
                        Spacer()
                        Text("\(entry.count)").font(Theme.text(15)).foregroundStyle(Theme.labelDim)
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Tags")
        .overlay {
            if vault.tagCounts.isEmpty {
                ContentUnavailableView("No tags", systemImage: "tag",
                                       description: Text("Add tags to an item when you edit it."))
            }
        }
    }
}
