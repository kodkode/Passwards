import AppKit
import SwiftUI
import TwoPasswordCore
import UniformTypeIdentifiers

/// File-menu import/export flows. Exports are plaintext, so they re-verify
/// the account password (full key re-derivation, not just a UI check).
enum ImportExport {
    // MARK: Import

    static func importOnePux(appState: AppState, store: VaultStore) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "1pux") ?? .zip, .zip]
        panel.message = "Choose a 1Password .1pux export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let summary = try OnePuxImporter().importArchive(at: url)
                var importedItems = 0
                for importedVault in summary.vaults {
                    guard !importedVault.items.isEmpty else { continue }
                    let vault = try await appState.vaultRepository?.createVault(
                        attributes: VaultAttributes(name: uniqueVaultName(importedVault.name, store: store), symbolName: "tray.and.arrow.down.fill", colorToken: "purple")
                    )
                    guard let vaultID = vault?.id else { continue }
                    for var item in importedVault.items {
                        item.vaultID = vaultID
                        var reconciled = item
                        VaultStore.reconcileOverview(&reconciled)
                        try await appState.itemRepository?.create(reconciled)
                        // Attach any files carried in the archive.
                        for section in reconciled.details.sections {
                            for field in section.fields where field.kind == .file {
                                if let data = importedVault.attachmentFiles[field.id.uuidString] {
                                    let attachmentID = try await appState.attachmentStore?.add(data: data, filename: field.label, itemID: reconciled.id)
                                    if let attachmentID {
                                        var updated = reconciled
                                        for (si, s) in updated.details.sections.enumerated() {
                                            for (fi, f) in s.fields.enumerated() where f.id == field.id {
                                                updated.details.sections[si].fields[fi].value = attachmentID
                                            }
                                        }
                                        try await appState.itemRepository?.update(updated)
                                        reconciled = updated
                                    }
                                }
                            }
                        }
                        importedItems += 1
                    }
                }
                await store.refresh()
                await store.watchtower.run()
                notify("Import complete", "\(importedItems) items imported into \(summary.vaults.count) vault(s)."
                       + (summary.skippedItems > 0 ? " \(summary.skippedItems) items skipped." : ""))
            } catch {
                notify("Import failed", error.localizedDescription)
            }
        }
    }

    static func importCSV(appState: AppState, store: VaultStore) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.message = "Choose a CSV file (1Password, Chrome, Bitwarden, LastPass…)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let data = try Data(contentsOf: url)
                let result = try CSVImporter().importCSV(data: data)
                guard let vaultID = currentVaultID(store: store) else { return }
                for var item in result.items {
                    item.vaultID = vaultID
                    var reconciled = item
                    VaultStore.reconcileOverview(&reconciled)
                    try await appState.itemRepository?.create(reconciled)
                }
                await store.refresh()
                await store.watchtower.run()
                notify("Import complete", "\(result.items.count) logins imported."
                       + (result.skippedRows > 0 ? " \(result.skippedRows) rows skipped." : ""))
            } catch {
                notify("Import failed", "Could not read that CSV: \(error.localizedDescription)")
            }
        }
    }

    private static func currentVaultID(store: VaultStore) -> String? {
        if case .vault(let id) = store.sidebarSelection { return id }
        return store.vaults.first?.id
    }

    private static func uniqueVaultName(_ name: String, store: VaultStore) -> String {
        let existing = Set(store.vaults.map(\.attributes.name))
        if !existing.contains(name) { return name }
        var counter = 2
        while existing.contains("\(name) \(counter)") { counter += 1 }
        return "\(name) \(counter)"
    }

    // MARK: Export

    static func exportCSV(appState: AppState, store: VaultStore) {
        export(appState: appState, store: store, fileName: "2Password Logins.csv", contentType: .commaSeparatedText) { items, _ in
            Exporters.csv(items: items)
        }
    }

    static func exportJSON(appState: AppState, store: VaultStore) {
        export(appState: appState, store: store, fileName: "2Password Export.json", contentType: .json) { items, vaultNames in
            (try? Exporters.json(items: items, vaultNames: vaultNames)) ?? Data()
        }
    }

    private static func export(
        appState: AppState,
        store: VaultStore,
        fileName: String,
        contentType: UTType,
        encode: @escaping ([VaultItem], [String: String]) -> Data
    ) {
        Task {
            guard await confirmPassword(appState: appState) else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [contentType]
            panel.nameFieldStringValue = fileName
            panel.message = "This export is NOT encrypted. Store it safely and delete it when done."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                let items = try await appState.itemRepository?.allItems() ?? []
                let vaultNames = Dictionary(uniqueKeysWithValues: store.vaults.map { ($0.id, $0.attributes.name) })
                try encode(items, vaultNames).write(to: url, options: .atomic)
                notify("Export complete", "Saved to \(url.lastPathComponent). Remember: the file is unencrypted.")
            } catch {
                notify("Export failed", error.localizedDescription)
            }
        }
    }

    /// Gate: re-derive the account unlock key from the typed password.
    static func confirmPassword(appState: AppState) async -> Bool {
        guard let account = appState.account,
              let secretKey = KeychainStore.loadSecretKey(accountID: account.id) else { return false }

        let alert = NSAlert()
        alert.messageText = "Confirm your account password"
        alert.informativeText = "Exporting creates an unencrypted copy of your data. Enter your account password to continue."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        let password = field.stringValue

        let record = account.keyRecord
        return await Task.detached(priority: .userInitiated) {
            (try? AccountCrypto.unlock(record: record, password: password, secretKey: secretKey)) != nil
        }.value
    }

    private static func notify(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
