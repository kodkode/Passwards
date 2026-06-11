import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Block screen capture of vault windows, like 1Password.
        for window in NSApp.windows {
            window.sharingType = .none
        }
        // CKSyncEngine listens for CloudKit pushes once the app registers.
        if SyncController.hasCloudKitEntitlement {
            NSApplication.shared.registerForRemoteNotifications()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
