import AppKit

/// Copies values to the pasteboard, marking secrets as concealed (so clipboard
/// managers skip them) and auto-clearing after a timeout if nothing else was
/// copied in the meantime.
enum ClipboardManager {
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

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
        let seconds = clearAfterSeconds
        guard concealed, seconds > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
            if NSPasteboard.general.changeCount == changeCount {
                NSPasteboard.general.clearContents()
            }
        }
    }
}
