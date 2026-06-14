import Foundation
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

    // MARK: SSHAgentBackend

    func identities() async -> [(blob: Data, comment: String)] {
        await withSSHKeys { key, summary in
            (key.publicKeyBlob, key.comment.isEmpty ? summary.overview.title : key.comment)
        }
    }

    func sign(keyBlob: Data, data: Data) async -> Data? {
        let matches = await withSSHKeys { key, _ -> Data? in
            key.publicKeyBlob == keyBlob ? try? key.sign(data) : nil
        }
        return matches.compactMap { $0 }.first
    }

    /// Decrypts every SSH Key item in the unlocked vault and maps it. Returns
    /// empty while locked so the agent exposes nothing.
    private func withSSHKeys<T>(_ transform: (SSHKey, ItemSummary) -> T) async -> [T] {
        guard appState.phase == .unlocked, let store = appState.vaultStore else { return [] }
        let sshItems = store.summaries.filter {
            $0.overview.category == .sshKey && $0.trashedAt == nil && !$0.overview.isArchived
        }
        var result: [T] = []
        for summary in sshItems {
            guard let item = await store.item(id: summary.id),
                  let pem = item.details.firstField(ofKind: .sshKey)?.value, !pem.isEmpty,
                  let key = try? SSHKey.parseOpenSSHPrivateKey(pem) else { continue }
            result.append(transform(key, summary))
        }
        return result
    }
}
