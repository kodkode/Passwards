import Foundation

/// Wire types for the local CLI control channel: the `passwards` CLI connects
/// to the running app and asks it to list items or read a field. Plaintext JSON
/// over a 0600 Unix socket (same-user only); secret reads are additionally
/// gated by the app behind a Touch ID prompt, which is the real authorization.
public struct CLIRequest: Codable, Sendable, Equatable {
    public enum Command: String, Codable, Sendable {
        case list   // non-secret overview of every item
        case get    // read one field's value (secret) — app prompts for approval
    }
    public var command: Command
    /// `get`: item id or a title to match (case-insensitive exact, else prefix).
    public var query: String?
    /// `get`: field label/purpose to read; nil means the primary password.
    public var field: String?

    public init(command: Command, query: String? = nil, field: String? = nil) {
        self.command = command
        self.query = query
        self.field = field
    }
}

public struct CLIItemSummary: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var username: String
    public var category: String

    public init(id: String, title: String, username: String, category: String) {
        self.id = id
        self.title = title
        self.username = username
        self.category = category
    }
}

public struct CLIResponse: Codable, Sendable, Equatable {
    public var error: String?
    public var items: [CLIItemSummary]?
    public var value: String?
    public var itemTitle: String?
    public var fieldLabel: String?

    public init(error: String? = nil, items: [CLIItemSummary]? = nil,
                value: String? = nil, itemTitle: String? = nil, fieldLabel: String? = nil) {
        self.error = error
        self.items = items
        self.value = value
        self.itemTitle = itemTitle
        self.fieldLabel = fieldLabel
    }
}

/// Resolves CLI control requests against the unlocked vault. Implemented by the
/// app; abstract here so the protocol/server are testable headless.
public protocol CLIControlBackend: Sendable {
    func handle(_ request: CLIRequest) async -> CLIResponse
}

/// A 1Password-style secret reference: `op://[vault/]item/field`.
public struct SecretReference: Equatable, Sendable {
    public var vault: String?
    public var item: String
    public var field: String

    public init(vault: String? = nil, item: String, field: String) {
        self.vault = vault
        self.item = item
        self.field = field
    }

    public static func parse(_ string: String) -> SecretReference? {
        guard string.hasPrefix("op://") else { return nil }
        let parts = string.dropFirst("op://".count)
            .split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        switch parts.count {
        case 3: return SecretReference(vault: parts[0], item: parts[1], field: parts[2])
        case 2: return SecretReference(vault: nil, item: parts[0], field: parts[1])
        default: return nil
        }
    }
}
