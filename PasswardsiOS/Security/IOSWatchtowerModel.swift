import SwiftUI
import os
import PasswardsCore
import PasswardsOrchestration

/// iOS Watchtower model — mirrors the macOS `WatchtowerState`: decrypts all items
/// and runs the shared `WatchtowerAuditor`, then exposes a 0–100 health score +
/// per-category counts for the Security dashboard and item-detail warnings.
@MainActor
@Observable
final class IOSWatchtowerModel {
    let core: AccountController
    private(set) var report = WatchtowerReport()
    private(set) var totalPasswordItems = 0
    private(set) var isRunning = false

    init(core: AccountController) { self.core = core }

    private var hibpEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.watchtowerHIBPEnabled) as? Bool ?? true
    }

    func run() async {
        guard !isRunning, core.phase == .unlocked, let items = core.itemRepository else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let decrypted = try await items.allItems()
            totalPasswordItems = decrypted.filter {
                $0.trashedAt == nil && !$0.overview.isArchived
                    && !($0.details.firstField(withPurpose: .password)?.value.isEmpty ?? true)
            }.count
            let auditor = WatchtowerAuditor(hibp: hibpEnabled ? HIBPClient() : nil)
            report = await auditor.audit(items: decrypted)
        } catch {
            Logger(subsystem: "com.michael.passwards", category: "ios-watchtower")
                .error("audit failed: \(String(describing: error), privacy: .public)")
        }
    }

    func runIfStale() async {
        if Date().timeIntervalSince(report.generatedAt) > 300 { await run() }
    }

    func clear() { report = WatchtowerReport() }

    // MARK: Counts

    var compromised: Int { report.items(for: .vulnerablePasswords).count }
    var reused: Int { report.items(for: .reusedPasswords).count }
    var weak: Int { report.items(for: .weakPasswords).count }
    var unsecured: Int { report.items(for: .unsecuredWebsites).count }

    /// The checks flagged for a given item (for the detail-screen warning card).
    func checks(for itemID: String) -> [WatchtowerCheck] { report.checks(for: itemID) }

    // MARK: Score (the core has no score; derive a "% of healthy password items")

    var score: Int {
        let flaggedUnique = report.items(for: .vulnerablePasswords)
            .union(report.items(for: .reusedPasswords))
            .union(report.items(for: .weakPasswords)).count
        guard totalPasswordItems > 0 else { return 100 }
        let healthy = max(0, totalPasswordItems - flaggedUnique)
        return Int((Double(healthy) / Double(totalPasswordItems) * 100).rounded())
    }

    #if DEBUG
    /// Sample data for `-uiPreview` screenshots.
    func seedPreview() {
        var r = WatchtowerReport()
        r.flagged[.vulnerablePasswords] = ["a", "b", "c"]
        r.flagged[.reusedPasswords] = Set((1...12).map { "r\($0)" }).union(["1"])  // flag sample item "1"
        r.flagged[.weakPasswords] = Set((1...5).map { "w\($0)" })
        report = r
        totalPasswordItems = 50
    }
    #endif

    var scoreLabel: String {
        switch score {
        case 90...: "Excellent"
        case 75..<90: "Good"
        case 50..<75: "Fair"
        default: "Weak"
        }
    }

    /// Longer explanatory copy for the Sentinel screen body.
    var scoreBody: String {
        "Think of this as your password fitness score — squash the issues below to level up."
    }

    var scoreStatus: String {
        switch score {
        case 90...: "Status: Excellent. You're well protected."
        case 75..<90: "Status: Good. A few things to improve."
        case 50..<75: "Status: Fair. Improvements needed."
        default: "Status: Weak. Address the issues below."
        }
    }

    var scoreColor: Color {
        switch score {
        case 75...: Theme.accent
        case 50..<75: Theme.warn
        default: Theme.danger
        }
    }
}
