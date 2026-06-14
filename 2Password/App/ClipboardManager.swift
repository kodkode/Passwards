import AppKit

/// Copies values to the pasteboard, marking secrets as concealed (so clipboard
/// managers skip them) and auto-clearing after a timeout if nothing else was
/// copied in the meantime.
enum ClipboardManager {
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// `changeCount` of the most recent concealed (secret) copy we made. Lets
    /// `clearOnLock()` wipe a copied password/Secret Key without clobbering
    /// unrelated clipboard contents the user copied afterwards.
    private(set) static var lastConcealedChangeCount: Int?

    static var clearAfterSeconds: Int {
        UserDefaults.standard.object(forKey: SettingsKeys.clipboardClearSeconds) as? Int ?? 90
    }

    static func copy(_ value: String, concealed: Bool = false) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if concealed {
            pasteboard.setString(value, forType: concealedType)
        }
        pasteboard.setString(value, forType: .string)

        let changeCount = pasteboard.changeCount
        if concealed { lastConcealedChangeCount = changeCount }
        let seconds = clearAfterSeconds
        guard concealed, seconds > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
            if NSPasteboard.general.changeCount == changeCount {
                NSPasteboard.general.clearContents()
            }
        }
    }

    /// Clears the pasteboard on lock if it still holds the secret we last
    /// copied. Locking is the user's "make this machine safe now" action, so a
    /// copied password or Secret Key must not outlive it — independent of the
    /// auto-clear timeout (which may be set to "Never"). Unrelated clipboard
    /// contents copied since are left untouched.
    static func clearOnLock() {
        defer { lastConcealedChangeCount = nil }
        guard let changeCount = lastConcealedChangeCount,
              NSPasteboard.general.changeCount == changeCount else { return }
        NSPasteboard.general.clearContents()
    }
}
