import SwiftUI
import TwoPasswordCore

/// Runs the Watchtower audit and holds the latest report for the dashboard,
/// sidebar badge, and per-item banners.
@Observable
final class WatchtowerState {
    private(set) var report = WatchtowerReport()
    private(set) var isRunning = false
    var focus: WatchtowerCheck?

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    var hibpEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.watchtowerHIBPEnabled) as? Bool ?? true
    }

    func run() async {
        guard !isRunning, let items = appState.itemRepository else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let decrypted = try await items.allItems()
            let auditor = WatchtowerAuditor(hibp: hibpEnabled ? HIBPClient() : nil)
            report = await auditor.audit(items: decrypted)
        } catch {
            // Locked mid-run or decryption failure: keep the previous report.
        }
    }

    func runIfStale() async {
        if Date().timeIntervalSince(report.generatedAt) > 300 {
            await run()
        }
    }

    /// Discards the audit report (which item IDs are weak/breached/reused) on
    /// lock, so the locked app holds no derived view of the vault's contents.
    func clear() {
        report = WatchtowerReport()
        focus = nil
    }

    /// Dismiss a specific check for an item ("not an issue").
    func exclude(check: WatchtowerCheck, summary: ItemSummary, store: VaultStore) async {
        var overview = summary.overview
        overview.watchtowerExclusions.insert(check.rawValue)
        try? await appState.itemRepository?.updateOverview(overview, itemID: summary.id)
        await store.refresh()
        await run()
    }
}
