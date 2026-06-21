import Foundation

/// The 22 item categories, mirroring 1Password 8.
///
/// Unknown raw values are preserved round-trip (the same treatment `FieldKind`
/// gets) so an item created by a newer build with a category this version
/// doesn't recognize survives being opened and re-saved — instead of failing to
/// decode and silently vanishing from the list. The on-the-wire encoding is a
/// bare category string, identical to the previous `String`-raw representation,
/// so existing encrypted blobs and synced records decode unchanged.
public enum Category: Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case login
    case secureNote
    case creditCard
    case identity
    case password
    case document
    case apiCredential
    case bankAccount
    case cryptoWallet
    case database
    case driverLicense
    case emailAccount
    case medicalRecord
    case membership
    case outdoorLicense
    case passport
    case rewardProgram
    case server
    case socialSecurityNumber
    case softwareLicense
    case sshKey
    case wirelessRouter
    /// A category raw value this build doesn't know (forward compatibility).
    case unknown(String)

    /// The 22 known categories, in canonical order. Excludes `.unknown`, so
    /// pickers and the sidebar only ever offer the real categories.
    public static let allCases: [Category] = [
        .login, .secureNote, .creditCard, .identity, .password, .document,
        .apiCredential, .bankAccount, .cryptoWallet, .database, .driverLicense,
        .emailAccount, .medicalRecord, .membership, .outdoorLicense, .passport,
        .rewardProgram, .server, .socialSecurityNumber, .softwareLicense,
        .sshKey, .wirelessRouter,
    ]

    public var rawValue: String {
        switch self {
        case .login: "login"
        case .secureNote: "secureNote"
        case .creditCard: "creditCard"
        case .identity: "identity"
        case .password: "password"
        case .document: "document"
        case .apiCredential: "apiCredential"
        case .bankAccount: "bankAccount"
        case .cryptoWallet: "cryptoWallet"
        case .database: "database"
        case .driverLicense: "driverLicense"
        case .emailAccount: "emailAccount"
        case .medicalRecord: "medicalRecord"
        case .membership: "membership"
        case .outdoorLicense: "outdoorLicense"
        case .passport: "passport"
        case .rewardProgram: "rewardProgram"
        case .server: "server"
        case .socialSecurityNumber: "socialSecurityNumber"
        case .softwareLicense: "softwareLicense"
        case .sshKey: "sshKey"
        case .wirelessRouter: "wirelessRouter"
        case .unknown(let raw): raw
        }
    }

    public init(rawValue raw: String) {
        switch raw {
        case "login": self = .login
        case "secureNote": self = .secureNote
        case "creditCard": self = .creditCard
        case "identity": self = .identity
        case "password": self = .password
        case "document": self = .document
        case "apiCredential": self = .apiCredential
        case "bankAccount": self = .bankAccount
        case "cryptoWallet": self = .cryptoWallet
        case "database": self = .database
        case "driverLicense": self = .driverLicense
        case "emailAccount": self = .emailAccount
        case "medicalRecord": self = .medicalRecord
        case "membership": self = .membership
        case "outdoorLicense": self = .outdoorLicense
        case "passport": self = .passport
        case "rewardProgram": self = .rewardProgram
        case "server": self = .server
        case "socialSecurityNumber": self = .socialSecurityNumber
        case "softwareLicense": self = .softwareLicense
        case "sshKey": self = .sshKey
        case "wirelessRouter": self = .wirelessRouter
        default: self = .unknown(raw)
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .login: "Login"
        case .secureNote: "Secure Note"
        case .creditCard: "Credit Card"
        case .identity: "Identity"
        case .password: "Password"
        case .document: "Document"
        case .apiCredential: "API Credential"
        case .bankAccount: "Bank Account"
        case .cryptoWallet: "Crypto Wallet"
        case .database: "Database"
        case .driverLicense: "Driver License"
        case .emailAccount: "Email Account"
        case .medicalRecord: "Medical Record"
        case .membership: "Membership"
        case .outdoorLicense: "Outdoor License"
        case .passport: "Passport"
        case .rewardProgram: "Reward Program"
        case .server: "Server"
        case .socialSecurityNumber: "Social Security Number"
        case .softwareLicense: "Software License"
        case .sshKey: "SSH Key"
        case .wirelessRouter: "Wireless Router"
        case .unknown: "Item"
        }
    }

    /// SF Symbol used on the colored rounded-rect category icon (chosen to
    /// approximate 1Password 8's glyphs).
    public var symbolName: String {
        switch self {
        case .login: "person.badge.key.fill"
        case .secureNote: "note.text"
        case .creditCard: "creditcard.fill"
        case .identity: "person.crop.rectangle.fill"
        case .password: "key.fill"
        case .document: "doc.fill"
        case .apiCredential: "chevron.left.forwardslash.chevron.right"
        case .bankAccount: "dollarsign.circle.fill"
        case .cryptoWallet: "wallet.pass.fill"
        case .database: "cylinder.split.1x2.fill"
        case .driverLicense: "car.fill"
        case .emailAccount: "envelope.fill"
        case .medicalRecord: "heart.text.square.fill"
        case .membership: "star.square.fill"
        case .outdoorLicense: "tree.fill"
        case .passport: "globe.americas.fill"
        case .rewardProgram: "gift.fill"
        case .server: "server.rack"
        case .socialSecurityNumber: "person.text.rectangle.fill"
        case .softwareLicense: "checkmark.seal.fill"
        case .sshKey: "terminal.fill"
        case .wirelessRouter: "wifi.router"
        case .unknown: "questionmark.square.dashed"
        }
    }

    /// Stable color token; the UI layer maps these to actual colors.
    public var colorToken: String {
        switch self {
        case .login: "blue"
        case .secureNote: "yellow"
        case .creditCard: "teal"
        case .identity: "green"
        case .password: "slate"
        case .document: "gray"
        case .apiCredential: "indigo"
        case .bankAccount: "mint"
        case .cryptoWallet: "orange"
        case .database: "purple"
        case .driverLicense: "cyan"
        case .emailAccount: "sky"
        case .medicalRecord: "red"
        case .membership: "pink"
        case .outdoorLicense: "forest"
        case .passport: "navy"
        case .rewardProgram: "magenta"
        case .server: "steel"
        case .socialSecurityNumber: "maroon"
        case .softwareLicense: "violet"
        case .sshKey: "terminalGreen"
        case .wirelessRouter: "aqua"
        case .unknown: "gray"
        }
    }
}
