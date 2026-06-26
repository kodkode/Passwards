import Foundation
import PasswardsOrchestration
import PasswardsCore

/// Serves the `passwards` CLI's control channel: lists items and reads one
/// field on request. Opt-in (Settings → Advanced → Command-Line Access); only
/// works while unlocked; and every secret read (`get`) is gated behind a Touch
/// ID prompt, so a program can't quietly read your vault even with the socket.
@MainActor
final class CLIControlController: CLIControlBackend {
    private unowned let appState: AppState
    private var server: CLIControlServer?

    init(appState: AppState) {
        self.appState = appState
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.cliAccessEnabled)
    }

    func startIfEnabled() {
        guard Self.isEnabled, server == nil else { return }
        let server = CLIControlServer(socketPath: CLIControlServer.defaultSocketPath(), backend: self)
        self.server = server
        Task { try? await server.start() }
    }

    func stop() {
        let server = self.server
        self.server = nil
        Task { await server?.stop() }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: SettingsKeys.cliAccessEnabled)
        if enabled { startIfEnabled() } else { stop() }
    }

    // MARK: CLIControlBackend

    func handle(_ request: CLIRequest) async -> CLIResponse {
        guard appState.phase == .unlocked, let store = appState.vaultStore else {
            return CLIResponse(error: "Passwards is locked")
        }
        switch request.command {
        case .list:
            let items = store.summaries
                .filter { $0.trashedAt == nil && !$0.overview.isArchived }
                .sorted { $0.overview.title.localizedCaseInsensitiveCompare($1.overview.title) == .orderedAscending }
                .map { CLIItemSummary(id: $0.id, title: $0.overview.title,
                                      username: $0.overview.subtitle, category: $0.overview.category.rawValue) }
            return CLIResponse(items: items)

        case .get:
            guard let query = request.query, !query.isEmpty else { return CLIResponse(error: "missing item") }
            guard let summary = matchItem(query, in: store) else {
                return CLIResponse(error: "no item matching “\(query)”")
            }
            // Secret read → require Touch ID, naming the item + field up front.
            let fieldName = request.field ?? "password"
            guard await LocalAuthorization.request(
                reason: "read the \(fieldName) for “\(summary.overview.title)”") else {
                return CLIResponse(error: "denied")
            }
            guard let item = await store.item(id: summary.id) else {
                return CLIResponse(error: "couldn't read item")
            }
            guard let resolved = fieldValue(item.details, field: request.field) else {
                return CLIResponse(error: "no “\(fieldName)” field on “\(summary.overview.title)”")
            }
            return CLIResponse(value: resolved.value, itemTitle: summary.overview.title, fieldLabel: resolved.label)
        }
    }

    /// Match by exact id, else exact title (case-insensitive), else title prefix.
    private func matchItem(_ query: String, in store: VaultStore) -> ItemSummary? {
        let active = store.summaries.filter { $0.trashedAt == nil && !$0.overview.isArchived }
        if let byID = active.first(where: { $0.id == query }) { return byID }
        if let exact = active.first(where: { $0.overview.title.caseInsensitiveCompare(query) == .orderedSame }) {
            return exact
        }
        return active.first { $0.overview.title.range(of: query, options: .caseInsensitive) != nil }
    }

    /// Resolve a field by purpose keyword (password/username/notes) or by label.
    private func fieldValue(_ details: ItemDetails, field: String?) -> (label: String, value: String)? {
        switch field?.lowercased() {
        case nil, "password":
            if let f = details.firstField(withPurpose: .password) { return (f.label, f.value) }
        case "username":
            if let f = details.firstField(withPurpose: .username) { return (f.label, f.value) }
        case "notes":
            return ("notes", details.notes)
        default:
            for section in details.sections {
                for f in section.fields where f.label.caseInsensitiveCompare(field!) == .orderedSame {
                    return (f.label, f.value)
                }
            }
        }
        return nil
    }
}
