import Foundation
import AppKit
import LocalAuthentication
import TwoPasswordCore

/// Owns the vault-backed SSH agent. When enabled it listens on a Unix socket
/// (point `SSH_AUTH_SOCK` at it) and serves the SSH Key items in the vault:
/// `ssh`/`git` can list and sign with them. Keys are only served while the
/// vault is unlocked — locking sheds them, like 1Password's SSH agent.
@MainActor
final class SSHAgentController: SSHAgentBackend {
    private unowned let appState: AppState
    private var server: SSHAgentServer?

    init(appState: AppState) {
        self.appState = appState
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.sshAgentEnabled)
    }

    /// Stable App Group container path the user exports as SSH_AUTH_SOCK.
    static func socketPath() -> String { SSHAgentServer.defaultSocketPath() }

    func startIfEnabled() {
        guard Self.isEnabled, server == nil else { return }
        let server = SSHAgentServer(socketPath: Self.socketPath(), backend: self)
        self.server = server
        Task { try? await server.start() }
    }

    func stop() {
        let server = self.server
        self.server = nil
        Task { await server?.stop() }
    }

    /// Toggle from Settings; persists the choice and starts/stops the listener.
    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: SettingsKeys.sshAgentEnabled)
        if enabled { startIfEnabled() } else { stop() }
    }

    // MARK: Approval policy

    /// Require user authorization (Touch ID / password, with an alert fallback)
    /// for each signature. Default ON: the socket is 0600 but any process
    /// running as this user could otherwise sign with the keys while unlocked,
    /// so per-use approval is the agent's real consent gate.
    static var approvalRequired: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.sshApprovalRequired) as? Bool ?? true
    }
    /// Seconds to remember an approval per key (0 = ask every time).
    static var approvalCacheSeconds: Int {
        UserDefaults.standard.object(forKey: SettingsKeys.sshApprovalCacheSeconds) as? Int ?? 0
    }

    private var lastApproved: [Data: Date] = [:]

    private func approve(keyTitle: String, fingerprint: String, keyBlob: Data) async -> Bool {
        guard Self.approvalRequired else { return true }
        let cache = Self.approvalCacheSeconds
        if cache > 0, let last = lastApproved[keyBlob], Date().timeIntervalSince(last) < Double(cache) {
            return true
        }
        let reason = "use the SSH key “\(keyTitle)” (\(fingerprint))"
        let approved = await requestAuthorization(reason: reason)
        if approved { lastApproved[keyBlob] = Date() }
        return approved
    }

    private func requestAuthorization(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        // Touch ID, falling back to the login password.
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
        }
        // No device-auth available — require an explicit click instead.
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Allow SSH key use?"
        alert.informativeText = "A program is requesting to \(reason)."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Deny")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: SSHAgentBackend

    func identities() async -> [(blob: Data, comment: String)] {
        await withSSHKeys { key, summary in
            (key.publicKeyBlob, key.comment.isEmpty ? summary.overview.title : key.comment)
        }
    }

    func sign(keyBlob: Data, data: Data) async -> Data? {
        guard appState.phase == .unlocked, let store = appState.vaultStore else { return nil }
        // Locate the requested key (and its item title for the approval prompt).
        var match: (key: SSHKey, title: String)?
        for summary in sshSummaries(in: store) {
            guard let item = await store.item(id: summary.id),
                  let pem = item.details.firstField(ofKind: .sshKey)?.value, !pem.isEmpty,
                  let key = try? SSHKey.parseOpenSSHPrivateKey(pem), key.publicKeyBlob == keyBlob else { continue }
            match = (key, summary.overview.title)
            break
        }
        guard let match else { return nil }
        guard await approve(keyTitle: match.title, fingerprint: match.key.fingerprintSHA256, keyBlob: keyBlob) else {
            return nil  // user declined → SSH_AGENT_FAILURE
        }
        return try? match.key.sign(data)
    }

    private func sshSummaries(in store: VaultStore) -> [ItemSummary] {
        store.summaries.filter {
            $0.overview.category == .sshKey && $0.trashedAt == nil && !$0.overview.isArchived
        }
    }

    /// Decrypts every SSH Key item in the unlocked vault and maps it. Returns
    /// empty while locked so the agent exposes nothing.
    private func withSSHKeys<T>(_ transform: (SSHKey, ItemSummary) -> T) async -> [T] {
        guard appState.phase == .unlocked, let store = appState.vaultStore else { return [] }
        var result: [T] = []
        for summary in sshSummaries(in: store) {
            guard let item = await store.item(id: summary.id),
                  let pem = item.details.firstField(ofKind: .sshKey)?.value, !pem.isEmpty,
                  let key = try? SSHKey.parseOpenSSHPrivateKey(pem) else { continue }
            result.append(transform(key, summary))
        }
        return result
    }
}
