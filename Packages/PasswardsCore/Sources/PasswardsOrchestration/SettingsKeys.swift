import CryptoKit
import Foundation

/// UserDefaults keys shared across the app + the orchestration layer. The values
/// are the on-disk contract, so both platforms read/write the same keys.
public enum SettingsKeys {
    public static let lastPasswordUnlock = "lastPasswordUnlock"
    public static let requirePasswordAfterHours = "requirePasswordAfterHours"
    public static let lockOnSleep = "lockOnSleep"
    public static let lockOnScreensaver = "lockOnScreensaver"
    public static let idleLockMinutes = "idleLockMinutes"
    public static let lockWhenBackgroundMinutes = "lockWhenBackgroundMinutes"
    public static let clipboardClearSeconds = "clipboardClearSeconds"
    public static let concealPasswords = "concealPasswords"
    public static let richIconsEnabled = "richIconsEnabled"
    public static let watchtowerHIBPEnabled = "watchtowerHIBPEnabled"
    public static let watchtowerEnabled = "watchtowerEnabled"
    public static let theme = "appTheme"
    public static let sshAgentEnabled = "sshAgentEnabled"
    public static let sshApprovalRequired = "sshApprovalRequired"
    public static let sshApprovalCacheSeconds = "sshApprovalCacheSeconds"
    public static let cliAccessEnabled = "cliAccessEnabled"
}

/// Sendable wrapper to move a SymmetricKey across a `Task.detached` boundary.
public struct SymmetricKeyBox: @unchecked Sendable {
    public let key: SymmetricKey
    public init(key: SymmetricKey) { self.key = key }
}
