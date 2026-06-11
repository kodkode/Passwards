import Foundation

/// Lightweight, always-decrypted-at-unlock projection of an item. Drives the
/// sidebar, list, search, and most Watchtower checks without touching details.
public struct ItemOverview: Codable, Sendable, Equatable, Hashable {
    public var title: String
    public var subtitle: String
    public var urls: [String]
    public var tags: [String]
    public var isFavorite: Bool
    public var isArchived: Bool
    public var category: Category
    public var hasOTP: Bool
    /// 0–4 strength bucket of the primary password, precomputed on save.
    public var strengthBucket: Int?
    /// Watchtower checks the user dismissed for this item.
    public var watchtowerExclusions: Set<String>

    public init(
        title: String = "",
        subtitle: String = "",
        urls: [String] = [],
        tags: [String] = [],
        isFavorite: Bool = false,
        isArchived: Bool = false,
        category: Category = .login,
        hasOTP: Bool = false,
        strengthBucket: Int? = nil,
        watchtowerExclusions: Set<String> = []
    ) {
        self.title = title
        self.subtitle = subtitle
        self.urls = urls
        self.tags = tags
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.category = category
        self.hasOTP = hasOTP
        self.strengthBucket = strengthBucket
        self.watchtowerExclusions = watchtowerExclusions
    }
}

public struct PasswordHistoryEntry: Codable, Sendable, Equatable, Hashable {
    public var value: String
    public var replacedAt: Date

    public init(value: String, replacedAt: Date) {
        self.value = value
        self.replacedAt = replacedAt
    }
}

/// Full decrypted payload, loaded on demand when an item is opened.
public struct ItemDetails: Codable, Sendable, Equatable, Hashable {
    public var sections: [ItemSection]
    public var notes: String
    public var passwordHistory: [PasswordHistoryEntry]

    public init(sections: [ItemSection] = [], notes: String = "", passwordHistory: [PasswordHistoryEntry] = []) {
        self.sections = sections
        self.notes = notes
        self.passwordHistory = passwordHistory
    }

    public func firstField(withPurpose purpose: FieldPurpose) -> ItemField? {
        for section in sections {
            if let field = section.fields.first(where: { $0.purpose == purpose }) {
                return field
            }
        }
        return nil
    }

    public func firstField(ofKind kind: FieldKind) -> ItemField? {
        for section in sections {
            if let field = section.fields.first(where: { $0.kind == kind }) {
                return field
            }
        }
        return nil
    }
}

/// A fully decrypted item as used by the UI.
public struct VaultItem: Identifiable, Sendable, Equatable {
    public var id: String
    public var vaultID: String
    public var overview: ItemOverview
    public var details: ItemDetails
    public var createdAt: Date
    public var updatedAt: Date
    public var trashedAt: Date?

    public init(
        id: String = UUID().uuidString,
        vaultID: String,
        overview: ItemOverview = ItemOverview(),
        details: ItemDetails = ItemDetails(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        trashedAt: Date? = nil
    ) {
        self.id = id
        self.vaultID = vaultID
        self.overview = overview
        self.details = details
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.trashedAt = trashedAt
    }
}

/// List-row projection: overview plus identity/timestamps, no details.
public struct ItemSummary: Identifiable, Sendable, Equatable, Hashable {
    public var id: String
    public var vaultID: String
    public var overview: ItemOverview
    public var createdAt: Date
    public var updatedAt: Date
    public var trashedAt: Date?

    public init(id: String, vaultID: String, overview: ItemOverview, createdAt: Date, updatedAt: Date, trashedAt: Date?) {
        self.id = id
        self.vaultID = vaultID
        self.overview = overview
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.trashedAt = trashedAt
    }
}

public struct VaultAttributes: Codable, Sendable, Equatable {
    public var name: String
    public var symbolName: String
    public var colorToken: String

    public init(name: String, symbolName: String = "lock.fill", colorToken: String = "blue") {
        self.name = name
        self.symbolName = symbolName
        self.colorToken = colorToken
    }
}

public struct Vault: Identifiable, Sendable, Equatable {
    public var id: String
    public var attributes: VaultAttributes
    public var createdAt: Date

    public init(id: String = UUID().uuidString, attributes: VaultAttributes, createdAt: Date = Date()) {
        self.id = id
        self.attributes = attributes
        self.createdAt = createdAt
    }
}
