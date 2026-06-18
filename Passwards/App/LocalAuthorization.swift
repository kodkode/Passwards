import AppKit
import LocalAuthentication

/// User authorization for sensitive local actions (SSH signatures, CLI secret
/// reads). Touch ID with login-password fallback; an explicit Allow/Deny alert
/// if neither device-auth is available. Shared so every consent prompt looks
/// and behaves the same.
@MainActor
enum LocalAuthorization {
    static func request(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
        }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Authorize Passwards access?"
        alert.informativeText = "A program is requesting to \(reason)."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Deny")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
