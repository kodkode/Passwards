import Foundation

/// Wire protocol between the browser extension and the app.
///
/// Transport: Chrome native-messaging framing (4-byte little-endian length +
/// UTF-8 JSON) end to end — the native messaging host is a dumb pipe between
/// the extension port and the app's Unix socket, so the same codec works on
/// both hops and the JS side never re-frames.
///
/// Every message carries a `cid` (connection id) the extension mints once per
/// `connectNative` port. The app keys all session/sequence state by `cid`, not
/// by socket-connection identity — so a relay (Safari's app-extension) that
/// silently drops and reopens the underlying socket mid-session resumes the
/// same `cid` and the sequence counters never reset. See `BrowserBridgeServer`.
///
/// Lifecycle (strictly one reply per inbound message, so it works over Safari's
/// per-message `beginRequest`/`completeRequest` as well as a streaming socket):
///   1. Pairing (once): `pairRequest` → `pairResponse` (the app's public key);
///      the user approves a verification code shown in both the app and the
///      extension; the extension then polls `pairPoll` → `pairPending` until
///      the app answers `pairConfirmed` / `pairRejected`. (The verdict is a
///      *pulled* reply, never an unsolicited push — Safari forbids pushes.)
///   2. Session (every connect): `sessionStart` ⇄ `sessionAccept` derive fresh
///      AES-GCM keys (see `BrowserChannelCrypto`); `sessionEnd` drops it.
///   3. RPC: `enc` envelopes carrying `BrowserRequest`/`BrowserResponse` JSON.
public struct BrowserWireMessage: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case pairRequest = "pair-request"
        case pairResponse = "pair-response"
        case pairPoll = "pair-poll"
        case pairPending = "pair-pending"
        case pairConfirmed = "pair-confirmed"
        case pairRejected = "pair-rejected"
        case sessionStart = "session-start"
        case sessionAccept = "session-accept"
        case sessionEnd = "session-end"
        case enc
        case error
    }

    public var type: Kind
    /// Connection id minted per extension port; routes every message to its
    /// session/pairing state in the app, independent of socket identity.
    public var cid: String?
    /// Base64 X25519 static public key (pairing identity).
    public var publicKey: String?
    /// Base64 X25519 ephemeral public key (session handshake).
    public var ephemeralKey: String?
    /// Monotonic per-direction counter for `enc` payloads.
    public var seq: UInt64?
    /// Base64 AES-GCM `combined` ciphertext of a request/response JSON.
    public var payload: String?
    /// Human-readable detail for `error`.
    public var message: String?

    public init(type: Kind, cid: String? = nil, publicKey: String? = nil, ephemeralKey: String? = nil,
                seq: UInt64? = nil, payload: String? = nil, message: String? = nil) {
        self.type = type
        self.cid = cid
        self.publicKey = publicKey
        self.ephemeralKey = ephemeralKey
        self.seq = seq
        self.payload = payload
        self.message = message
    }
}

/// Decrypted RPC request. Flat shape: `method` decides which fields matter.
public struct BrowserRequest: Codable, Sendable, Equatable {
    public enum Method: String, Codable, Sendable {
        /// → `matches` for the page URL. No secrets in the response.
        case credentialsQuery = "credentials.query"
        /// → `username` + `password` for one item; requires prior query.
        case credentialsFill = "credentials.fill"
        /// Create (or offer to update) a Login item from a submitted form.
        case loginSave = "login.save"
        /// Open & Fill: asked by the content script on page load — returns
        /// credentials (+ submit flag) only if the app staged a pending fill
        /// for this domain moments ago.
        case fillPending = "fill.pending"
        /// → app lock state + version.
        case status
    }

    public var id: UInt64
    public var method: Method
    public var url: String?
    public var itemID: String?
    public var username: String?
    public var password: String?
    public var title: String?

    public init(id: UInt64, method: Method, url: String? = nil, itemID: String? = nil,
                username: String? = nil, password: String? = nil, title: String? = nil) {
        self.id = id
        self.method = method
        self.url = url
        self.itemID = itemID
        self.username = username
        self.password = password
        self.title = title
    }
}

public struct BrowserResponse: Codable, Sendable, Equatable {
    public struct Match: Codable, Sendable, Equatable {
        public var itemID: String
        public var title: String
        public var username: String

        public init(itemID: String, title: String, username: String) {
            self.itemID = itemID
            self.title = title
            self.username = username
        }
    }

    public var id: UInt64
    public var error: String?
    public var locked: Bool?
    public var matches: [Match]?
    public var username: String?
    public var password: String?
    public var savedItemID: String?
    /// Open & Fill: also submit the form after filling.
    public var submit: Bool?

    public init(id: UInt64, error: String? = nil, locked: Bool? = nil, matches: [Match]? = nil,
                username: String? = nil, password: String? = nil, savedItemID: String? = nil,
                submit: Bool? = nil) {
        self.id = id
        self.error = error
        self.locked = locked
        self.matches = matches
        self.username = username
        self.password = password
        self.savedItemID = savedItemID
        self.submit = submit
    }
}

/// Chrome native-messaging framing: 4-byte little-endian length + JSON bytes.
public enum NativeMessageFraming {
    /// 1 MiB — Chrome's own limit for messages to the browser.
    public static let maxFrameLength = 1024 * 1024

    public enum FramingError: Error, Equatable {
        case frameTooLarge(Int)
    }

    public static func encode(_ body: Data) throws -> Data {
        guard body.count <= maxFrameLength else { throw FramingError.frameTooLarge(body.count) }
        var length = UInt32(body.count).littleEndian
        return withUnsafeBytes(of: &length) { Data($0) } + body
    }

    /// Extracts complete frames from an accumulating buffer, leaving any
    /// partial frame in place. Call again as more bytes arrive.
    public static func drainFrames(from buffer: inout Data) throws -> [Data] {
        var frames: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
            guard Int(length) <= maxFrameLength else { throw FramingError.frameTooLarge(Int(length)) }
            guard buffer.count >= 4 + Int(length) else { break }
            frames.append(buffer.subdata(in: (buffer.startIndex + 4)..<(buffer.startIndex + 4 + Int(length))))
            buffer.removeFirst(4 + Int(length))
        }
        return frames
    }

    public static func encodeMessage(_ message: BrowserWireMessage) throws -> Data {
        try encode(JSONEncoder().encode(message))
    }

    public static func decodeMessage(_ frame: Data) throws -> BrowserWireMessage {
        try JSONDecoder().decode(BrowserWireMessage.self, from: frame)
    }
}
