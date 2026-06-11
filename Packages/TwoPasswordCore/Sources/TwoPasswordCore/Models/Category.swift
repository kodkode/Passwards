import Foundation

/// The 22 item categories, mirroring 1Password 8.
public enum Category: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
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
        }
    }

    /// SF Symbol used on the colored rounded-rect category icon.
    public var symbolName: String {
        switch self {
        case .login: "globe"
        case .secureNote: "note.text"
        case .creditCard: "creditcard"
        case .identity: "person.crop.circle"
        case .password: "key.fill"
        case .document: "doc.fill"
        case .apiCredential: "curlybraces"
        case .bankAccount: "building.columns"
        case .cryptoWallet: "bitcoinsign.circle"
        case .database: "cylinder.split.1x2"
        case .driverLicense: "car.fill"
        case .emailAccount: "envelope.fill"
        case .medicalRecord: "cross.case.fill"
        case .membership: "person.2.fill"
        case .outdoorLicense: "leaf.fill"
        case .passport: "airplane"
        case .rewardProgram: "gift.fill"
        case .server: "server.rack"
        case .socialSecurityNumber: "shield.lefthalf.filled"
        case .softwareLicense: "app.badge.checkmark"
        case .sshKey: "terminal.fill"
        case .wirelessRouter: "wifi.router"
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
        }
    }
}
