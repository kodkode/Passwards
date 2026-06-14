import Foundation

/// Seams for the deferred big-ticket features. Each protocol is the contract
/// a future implementation target will fulfill; nothing in the app may assume
/// more than these surfaces.
///
/// Deferred by decision: passkeys, item sharing links. (Browser extension and
/// the SSH agent + CLI are now implemented — see BrowserBridge/ and SSH/.)

/// Future ASCredentialProviderExtension (Safari/system autofill) will consume
/// this to resolve credentials for a service identifier.
public protocol AutoFillCredentialSource: Sendable {
    func credentials(forServiceIdentifier domain: String) async throws -> [(username: String, password: String, itemID: String)]
}

// The SSH agent is implemented in SSH/ (`SSHAgentBackend`/`SSHAgentServer`),
// superseding the original `SSHAgentService` sketch.

/// Future item-sharing service ("psst!"-style links) — requires a server.
public protocol ItemSharingService: Sendable {
    func createShareLink(itemID: String, expiry: TimeInterval, recipientEmails: [String]?) async throws -> URL
}

// Forward compatibility notes:
// - `FieldKind.unknown(String)` already round-trips unrecognized field kinds,
//   so a future `passkey` kind can be introduced without breaking old builds.
// - CloudKit zone layout keeps one custom zone; vault sharing can move vaults
//   into per-vault zones + CKShare in a future migration.
