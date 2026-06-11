import SwiftUI
import TwoPasswordCore
import Security

/// App-side wrapper around the core SyncEngine: entitlement detection,
/// status for the sidebar, and change kicks after local mutations.
@Observable
final class SyncController {
    static let containerIdentifier = "iCloud.com.michael.twopassword"

    enum DisplayStatus: Equatable {
        case disabled        // no entitlement or user turned sync off
        case idle
        case syncing
        case error(String)
        case accountUnavailable
    }

    private(set) var status: DisplayStatus = .disabled
    private var engine: SyncEngine?
    var onRemoteChanges: (() -> Void)?

    /// True when the running binary actually has the iCloud entitlement —
    /// CloudKit APIs crash (uncatchably) without it, so never touch them unless
    /// this returns true.
    static var hasCloudKitEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        guard let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) else {
            return false
        }
        if let services = value as? [String] {
            return services.contains("CloudKit")
        }
        return false
    }

    var syncEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "cloudSyncEnabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "cloudSyncEnabled")
            Task { newValue ? await start(database: lastDatabase) : stop() }
        }
    }

    private var lastDatabase: AppDatabase?

    func start(database: AppDatabase?) async {
        guard let database else { return }
        lastDatabase = database
        guard Self.hasCloudKitEntitlement, syncEnabled else {
            status = .disabled
            return
        }
        if engine == nil {
            let engine = SyncEngine(database: database, containerIdentifier: Self.containerIdentifier)
            self.engine = engine
            await engine.setStatusHandler { [weak self] engineStatus in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let wasSyncing = self.status == .syncing
                    switch engineStatus {
                    case .idle: self.status = .idle
                    case .syncing: self.status = .syncing
                    case .error(let message): self.status = .error(message)
                    case .accountUnavailable: self.status = .accountUnavailable
                    }
                    if wasSyncing && self.status == .idle {
                        self.onRemoteChanges?()
                    }
                }
            }
            await engine.start()
            status = .idle
        }
        await engine?.manualSync()
    }

    func stop() {
        Task { await engine?.stop() }
        engine = nil
        status = .disabled
    }

    /// Call after local mutations so pending rows get queued and pushed.
    func kick() {
        guard let engine else { return }
        Task {
            await engine.enqueuePendingChanges()
            await engine.manualSync()
        }
    }

    /// Fetch the remote account for the new-device sign-in flow.
    static func fetchRemoteAccount() async throws -> AccountCrypto.AccountKeyRecord? {
        guard hasCloudKitEntitlement else { return nil }
        return try await SyncEngine.fetchRemoteAccount(containerIdentifier: containerIdentifier)
    }
}
