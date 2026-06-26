import Foundation
import Observation
import PasswardsCore
import Security

/// App-side wrapper around the core SyncEngine: entitlement detection,
/// status for the sidebar, and change kicks after local mutations.
///
/// Lives in PasswardsOrchestration so both the macOS and iOS apps share one
/// sync wrapper. Explicitly `@MainActor` because this package target has no
/// default actor isolation (the app targets set `SWIFT_DEFAULT_ACTOR_ISOLATION
/// = MainActor`, which doesn't apply here).
@MainActor
@Observable
public final class SyncController {
    public static let containerIdentifier = "iCloud.com.michael.twopassword"

    public enum DisplayStatus: Equatable {
        case disabled        // no entitlement or user turned sync off
        case idle
        case syncing
        case error(String)
        case accountUnavailable
    }

    public private(set) var status: DisplayStatus = .disabled
    private var engine: SyncEngine?
    public var onRemoteChanges: (() -> Void)?

    public init() {}

    /// True when the running binary actually has the iCloud entitlement —
    /// CloudKit APIs crash (uncatchably) without it, so never touch them unless
    /// this returns true.
    public static var hasCloudKitEntitlement: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        guard let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) else {
            return false
        }
        if let services = value as? [String] {
            return services.contains("CloudKit")
        }
        return false
        #else
        // iOS builds always carry their declared entitlements, and CloudKit APIs
        // don't fault without one the way they do on macOS — so no runtime probe
        // is needed (and SecTaskCreateFromSelf is macOS-only). An unavailable
        // iCloud account is reported by CKSyncEngine as `.accountUnavailable`.
        return true
        #endif
    }

    public var syncEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "cloudSyncEnabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "cloudSyncEnabled")
            Task { if newValue { await start(database: lastDatabase) } else { await stop() } }
        }
    }

    private var lastDatabase: AppDatabase?

    public func start(database: AppDatabase?) async {
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

    public func stop() async {
        // Capture the engine BEFORE niling: `engine = nil` runs synchronously on
        // the MainActor, so a detached `Task { await engine?.stop() }` would read
        // a nil `self.engine` and never actually tear the engine down — leaving
        // the old CKSyncEngine alive (it retains us as its delegate) to keep
        // handling push events and re-persisting its state token. Awaiting the
        // captured engine's stop() releases it and breaks that retain cycle.
        let old = engine
        engine = nil
        status = .disabled
        await old?.stop()
    }

    /// Call after local mutations so pending rows get queued and pushed.
    public func kick() {
        guard let engine else { return }
        Task {
            await engine.enqueuePendingChanges()
            await engine.manualSync()
        }
    }

    /// Like `kick()` but awaits the push, so a caller can sequence on it — e.g.
    /// disabling recovery awaits this so the overwritten (un-openable) account
    /// record reaches iCloud before reporting done. A no-op when no engine is
    /// running: if sync was previously on (so a recovery blob already reached
    /// iCloud) and was then turned OFF, the stale cloud copy isn't overwritten
    /// here — it's replaced on the next sync, because the account record is
    /// always re-enqueued (see `SyncEngine.enqueuePendingChanges`).
    public func pushChangesAndWait() async {
        guard let engine else { return }
        await engine.enqueuePendingChanges()
        await engine.manualSync()
    }

    /// Fetch the remote account for the new-device sign-in flow.
    public static func fetchRemoteAccount() async throws -> AccountCrypto.AccountKeyRecord? {
        guard hasCloudKitEntitlement else { return nil }
        return try await SyncEngine.fetchRemoteAccount(containerIdentifier: containerIdentifier)
    }
}
