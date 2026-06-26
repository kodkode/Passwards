import Foundation
import PasswardsCore

/// Platform-neutral list filter. Mirrors the macOS sidebar selection but with no
/// UI naming, so both apps share the same filtering. The Watchtower case carries
/// the already-resolved set of flagged item IDs (the app resolves it from its
/// Watchtower report) so this layer has no Watchtower dependency.
public enum VaultFilter: Equatable, Sendable {
    case allItems
    case favorites
    case flagged(Set<String>)
    case category(PasswardsCore.Category)
    case tag(String)
    case vault(String)
    case archive
    case trash
}

public enum VaultSortKey: Sendable {
    case title
    case dateEdited
    case dateCreated
}

/// Pure, shared vault list/derivation logic — the complex, easy-to-get-wrong part
/// both apps need. No navigation state, no repositories: just data in → data out,
/// so it's unit-testable and identical on macOS and iOS.
public enum VaultQuery {
    /// Items shown for the given filter + search + category + sort. Pure.
    public static func filteredSorted(
        _ summaries: [ItemSummary],
        filter: VaultFilter,
        search: String,
        categoryFilter: PasswardsCore.Category?,
        sortKey: VaultSortKey,
        ascending: Bool
    ) -> [ItemSummary] {
        var result = summaries

        switch filter {
        case .allItems:
            result = result.filter { $0.trashedAt == nil && !$0.overview.isArchived }
        case .flagged(let flagged):
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

        if !search.isEmpty {
            let query = search.lowercased()
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
                return ascending ? l == .orderedAscending : l == .orderedDescending
            }
        case .dateEdited:
            result.sort { ascending ? $0.updatedAt > $1.updatedAt : $0.updatedAt < $1.updatedAt }
        case .dateCreated:
            result.sort { ascending ? $0.createdAt > $1.createdAt : $0.createdAt < $1.createdAt }
        }
        return result
    }

    /// List sections: grouped by month for date sorts (like 1P8), flat for title sort.
    public static func grouped(
        _ visible: [ItemSummary],
        sortKey: VaultSortKey
    ) -> [(header: String?, items: [ItemSummary])] {
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

    /// Computes the derived overview bits (subtitle, URLs, OTP flag, password
    /// strength bucket) that keep the list and Watchtower fast without decrypting
    /// details. Pure; called on every create/save.
    public static func reconcileOverview(_ item: inout VaultItem) {
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
}
