import Foundation

/// Field type. Unknown raw values are preserved round-trip so newer payloads
/// (e.g. a future `passkey` kind) survive being opened by this version.
public enum FieldKind: Codable, Sendable, Equatable, Hashable {
    case text
    case concealed
    case email
    case url
    case phone
    case otp
    case date        // value: "YYYY-MM-DD"
    case monthYear   // value: "YYYY-MM"
    case address     // value: multi-line string
    case file        // value: attachment UUID string
    case linkedItem  // value: item UUID string
    case sshKey      // value: PEM private key (concealed, monospaced)
    case unknown(String)

    private var rawString: String {
        switch self {
        case .text: "text"
        case .concealed: "concealed"
        case .email: "email"
        case .url: "url"
        case .phone: "phone"
        case .otp: "otp"
        case .date: "date"
        case .monthYear: "monthYear"
        case .address: "address"
        case .file: "file"
        case .linkedItem: "linkedItem"
        case .sshKey: "sshKey"
        case .unknown(let raw): raw
        }
    }

    public init(rawString: String) {
        switch rawString {
        case "text": self = .text
        case "concealed": self = .concealed
        case "email": self = .email
        case "url": self = .url
        case "phone": self = .phone
        case "otp": self = .otp
        case "date": self = .date
        case "monthYear": self = .monthYear
        case "address": self = .address
        case "file": self = .file
        case "linkedItem": self = .linkedItem
        case "sshKey": self = .sshKey
        default: self = .unknown(rawString)
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(rawString: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawString)
    }

    /// Whether the value is hidden behind dots until revealed.
    public var isSecret: Bool {
        switch self {
        case .concealed, .otp, .sshKey: true
        default: false
        }
    }

    public var displayName: String {
        switch self {
        case .text: "Text"
        case .concealed: "Password"
        case .email: "Email"
        case .url: "URL"
        case .phone: "Phone"
        case .otp: "One-Time Password"
        case .date: "Date"
        case .monthYear: "Month/Year"
        case .address: "Address"
        case .file: "File"
        case .linkedItem: "Linked Item"
        case .sshKey: "SSH Private Key"
        case .unknown: "Unknown"
        }
    }
}

/// Marks the well-known fields so generic code (copy shortcuts, Watchtower,
/// autofill later) can find them regardless of label or position.
public enum FieldPurpose: String, Codable, Sendable, Hashable {
    case username
    case password
    case notes
}

public struct ItemField: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var label: String
    public var kind: FieldKind
    public var value: String
    public var purpose: FieldPurpose?

    public init(id: UUID = UUID(), label: String, kind: FieldKind, value: String = "", purpose: FieldPurpose? = nil) {
        self.id = id
        self.label = label
        self.kind = kind
        self.value = value
        self.purpose = purpose
    }
}

public struct ItemSection: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var title: String
    public var fields: [ItemField]

    public init(id: UUID = UUID(), title: String = "", fields: [ItemField] = []) {
        self.id = id
        self.title = title
        self.fields = fields
    }
}
