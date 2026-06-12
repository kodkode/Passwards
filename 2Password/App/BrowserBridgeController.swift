import AppKit
import SwiftUI
import TwoPasswordCore

/// Owns the Unix-socket bridge the browser extension connects through.
/// Pairings are approved by the user (verification code alert) and stored
/// in the Keychain; RPCs are served only while the vault is unlocked.
@MainActor
final class BrowserBridgeController: BrowserBridgeDelegate, BrowserPairingStore {
    private unowned let appState: AppState
    private var server: BrowserBridgeServer?

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        guard server == nil else { return }
        let server = BrowserBridgeServer(
            socketPath: BrowserBridgeServer.defaultSocketPath(),
            delegate: self,
            pairings: self
        )
        self.server = server
        Task {
            do {
                try await server.start()
            } catch {
                assertionFailure("browser bridge failed to start: \(error)")
            }
        }
    }

    // MARK: BrowserPairingStore (Keychain-backed)

    private static let pairingService = "com.michael.twopassword.browser-pairings"

    private func loadPairings() -> [String: String] {
        guard let blob = KeychainStore.loadBlob(service: Self.pairingService, account: "all"),
              let dict = try? JSONDecoder().decode([String: String].self, from: blob) else { return [:] }
        return dict
    }

    func pairingSecret(forExtensionKey key: Data) async -> Data? {
        loadPairings()[key.base64EncodedString()].flatMap { Data(base64Encoded: $0) }
    }

    func savePairing(extensionKey: Data, secret: Data) async {
        var pairings = loadPairings()
        pairings[extensionKey.base64EncodedString()] = secret.base64EncodedString()
        if let blob = try? JSONEncoder().encode(pairings) {
            try? KeychainStore.saveBlob(blob, service: Self.pairingService, account: "all")
        }
    }

    // MARK: BrowserBridgeDelegate

    func approveBrowserPairing(verificationCode: String) async -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Connect Browser Extension?"
        alert.informativeText = """
        A browser extension is asking to connect to 2Password.

        Approve only if you just installed or re-paired the 2Password \
        extension, and the code below matches the one in your browser.
        """
        let codeLabel = NSTextField(labelWithString: verificationCode)
        codeLabel.font = .monospacedSystemFont(ofSize: 28, weight: .bold)
        codeLabel.alignment = .center
        codeLabel.frame = NSRect(x: 0, y: 0, width: 220, height: 36)
        alert.accessoryView = codeLabel
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func handleBrowserRequest(_ request: BrowserRequest) async -> BrowserResponse {
        guard appState.phase == .unlocked, let store = appState.vaultStore else {
            return BrowserResponse(id: request.id, locked: true)
        }
        switch request.method {
        case .status:
            return BrowserResponse(id: request.id, locked: false)
        case .credentialsQuery:
            return query(request, store: store)
        case .credentialsFill:
            return await fill(request, store: store)
        case .loginSave:
            return await save(request, store: store)
        }
    }

    // MARK: Handlers

    private func loginSummaries(matching url: String?, in store: VaultStore) -> [ItemSummary] {
        guard let url, let domain = WatchtowerAuditor.registrableDomain(url) else { return [] }
        return store.summaries.filter { summary in
            summary.trashedAt == nil
                && !summary.overview.isArchived
                && summary.overview.category == .login
                && summary.overview.urls.contains { WatchtowerAuditor.registrableDomain($0) == domain }
        }
    }

    private func query(_ request: BrowserRequest, store: VaultStore) -> BrowserResponse {
        let matches = loginSummaries(matching: request.url, in: store).map {
            BrowserResponse.Match(itemID: $0.id, title: $0.overview.title, username: $0.overview.subtitle)
        }
        return BrowserResponse(id: request.id, matches: matches)
    }

    private func fill(_ request: BrowserRequest, store: VaultStore) async -> BrowserResponse {
        guard let itemID = request.itemID,
              // The page URL must actually match the item — a hostile page
              // can't ask for some other site's credentials by ID.
              loginSummaries(matching: request.url, in: store).contains(where: { $0.id == itemID }),
              let item = await store.item(id: itemID) else {
            return BrowserResponse(id: request.id, error: "no such credential")
        }
        return BrowserResponse(
            id: request.id,
            username: item.details.firstField(withPurpose: .username)?.value ?? "",
            password: item.details.firstField(withPurpose: .password)?.value ?? ""
        )
    }

    private func save(_ request: BrowserRequest, store: VaultStore) async -> BrowserResponse {
        guard let url = request.url, let username = request.username, let password = request.password else {
            return BrowserResponse(id: request.id, error: "missing fields")
        }
        // Same site + same username → update the password (history kept by save).
        if let existing = loginSummaries(matching: url, in: store).first(where: { $0.overview.subtitle == username }),
           var item = await store.item(id: existing.id) {
            let previous = item
            if let index = item.details.indexOfFirstField(withPurpose: .password) {
                item.details.sections[index.section].fields[index.field].value = password
            }
            await store.save(item, previous: previous)
            return BrowserResponse(id: request.id, savedItemID: item.id)
        }

        var item = store.newItem(category: .login)
        let domain = WatchtowerAuditor.registrableDomain(url)
        item.overview.title = request.title?.isEmpty == false ? request.title! : (domain ?? url)
        for (s, section) in item.details.sections.enumerated() {
            for (f, field) in section.fields.enumerated() {
                switch field.purpose {
                case .username: item.details.sections[s].fields[f].value = username
                case .password: item.details.sections[s].fields[f].value = password
                default:
                    if field.kind == .url { item.details.sections[s].fields[f].value = url }
                }
            }
        }
        await store.create(item)
        return BrowserResponse(id: request.id, savedItemID: item.id)
    }
}

extension ItemDetails {
    /// Section/field index of the first field with the given purpose.
    func indexOfFirstField(withPurpose purpose: FieldPurpose) -> (section: Int, field: Int)? {
        for (s, section) in sections.enumerated() {
            for (f, field) in section.fields.enumerated() where field.purpose == purpose {
                return (s, f)
            }
        }
        return nil
    }
}
