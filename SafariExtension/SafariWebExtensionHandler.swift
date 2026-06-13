import SafariServices

/// Principal class of the Safari Web Extension app-extension.
///
/// Safari delivers each `browser.runtime.connectNative` / `sendNativeMessage`
/// payload to a FRESH instance of this handler, one `beginRequest` per message,
/// answered exactly once via `completeRequest`. The appex is short-lived and may
/// be reaped between messages, so it holds NO session or crypto state: it is a
/// dumb pipe that forwards each message to the running app over the shared
/// App Group Unix socket and returns the single reply. All end-to-end crypto
/// (X25519 / HKDF / AES-GCM) and the sequence-counted session live in the
/// extension's background.js and the app — never here. See `AppGroupRelay`.
class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let raw = (context.inputItems.first as? NSExtensionItem)?.userInfo?[SFExtensionMessageKey]
        // The context is touched only here and in the completion below, on one
        // logical flow; it isn't Sendable but is used single-threaded. We pass
        // the message across the relay actor as opaque JSON bytes (Data), so no
        // non-Sendable dictionary crosses the isolation boundary.
        nonisolated(unsafe) let ctx = context
        guard let raw, let payload = try? JSONSerialization.data(withJSONObject: raw) else {
            Self.reply(to: ctx, ["type": "error", "message": "malformed message"])
            return
        }
        Task {
            let replyData = await AppGroupRelay.shared.roundTrip(payload)
            let reply = ((try? JSONSerialization.jsonObject(with: replyData)) as? [String: Any])
                ?? ["type": "error", "message": "bad reply"]
            Self.reply(to: ctx, reply)
        }
    }

    private static func reply(to context: NSExtensionContext, _ reply: [String: Any]) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
