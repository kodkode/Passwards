import Foundation

/// Platform-service seams that let the shared orchestration drive OS-specific
/// behavior without importing AppKit/UIKit. Each app provides concrete
/// implementations (macOS: NSPasteboard/NSWorkspace/NSApp/NSSavePanel; iOS:
/// UIPasteboard/scenePhase/fileExporter) and injects them into the controllers.
///
/// All four are `@MainActor`: pasteboard, auto-lock, activation, and file export
/// are main-thread UI concerns, and the shared `AccountController` (also
/// `@MainActor`) drives them. Marking the protocols keeps the concrete witnesses
/// main-actor-isolated so they can touch AppKit/UIKit safely.

/// Copies secrets to the system pasteboard and clears them on lock.
@MainActor
public protocol PasteboardService {
    /// Copies `value`. When `concealed`, marks it so clipboard managers and
    /// Universal Clipboard don't persist/sync it (macOS concealed type / iOS
    /// `localOnly` + expiry).
    func copy(_ value: String, concealed: Bool)
    /// Clears any secret this service placed on the pasteboard (called on lock).
    func clearSecret()
}

/// Drives the inactivity / system-event auto-lock. The app implements the
/// platform triggers and calls `onShouldLock`; the controller wires `lock()`.
@MainActor
public protocol AutoLockService: AnyObject {
    var onShouldLock: (() -> Void)? { get set }
    func start()
    func stop()
}

/// Reports app foreground state so the lock screen can auto-prompt biometrics on
/// activation (macOS: NSApplication.didBecomeActive; iOS: scenePhase == .active).
@MainActor
public protocol AppActivationService: AnyObject {
    var isActive: Bool { get }
    /// Registers a handler invoked each time the app becomes active.
    func onDidBecomeActive(_ handler: @escaping () -> Void)
}

/// Exports/imports a file (backups, emergency kit). macOS uses NSSave/OpenPanel;
/// iOS uses `.fileExporter`/`.fileImporter`/`ShareLink`.
@MainActor
public protocol FileExportService {
    /// Presents a save UI for `data`; returns true if the user completed the export.
    func exportData(_ data: Data, suggestedName: String) async -> Bool
    /// Presents a picker and returns the chosen file's URL, or nil if cancelled.
    func importFile() async -> URL?
}
