import Foundation

/// Seams for the deferred big-ticket features. Each protocol is the contract
/// a future implementation target will fulfill; nothing in the app may assume
/// more than these surfaces.
///
/// Deferred by decision (2026-06-11): browser extension/autofill, passkeys,
/// SSH agent + CLI, item sharing links.

/// Future ASCredentialProviderExtension (Safari/system autofill) will consume
/// this to resolve credentials for a service identifier.
public protocol AutoFillCredentialSource: Sendable {
    func credentials(forServiceIdentifier domain: String) async throws -> [(username: String, password: String, itemID: String)]
}

/// Future SSH agent target: serves SSH Key items over a local agent socket.
public protocol SSHAgentService: Sendable {
    func availableKeys() async throws -> [(itemID: String, publicKey: String, label: String)]
    func sign(itemID: String, challenge: Data) async throws -> Data
}

/// Future item-sharing service ("psst!"-style links) — requires a server.
public protocol ItemSharingService: Sendable {
    func createShareLink(itemID: String, expiry: TimeInterval, recipientEmails: [String]?) async throws -> URL
}

// Forward compatibility notes:
// - `FieldKind.unknown(String)` already round-trips unrecognized field kinds,
//   so a future `passkey` kind can be introduced without breaking old builds.
// - CloudKit zone layout keeps one custom zone; vault sharing can move vaults
//   into per-vault zones + CKShare in a future migration.
