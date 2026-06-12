import Foundation
import CryptoKit

/// The Watchtower security audit, mirroring 1Password's checks. All checks run
/// locally except `vulnerablePasswords`, which uses the HIBP k-anonymity range
/// API (only the first 5 SHA-1 hex chars ever leave the device).
public enum WatchtowerCheck: String, Sendable, CaseIterable, Identifiable, Codable {
    case vulnerablePasswords
    case reusedPasswords
    case weakPasswords
    case unsecuredWebsites
    case twoFactorAvailable
    case expiringItems
    case duplicateItems

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vulnerablePasswords: "Vulnerable Passwords"
        case .reusedPasswords: "Reused Passwords"
        case .weakPasswords: "Weak Passwords"
        case .unsecuredWebsites: "Unsecured Websites"
        case .twoFactorAvailable: "Two-Factor Authentication"
        case .expiringItems: "Expiring Items"
        case .duplicateItems: "Duplicate Items"
        }
    }

    public var explanation: String {
        switch self {
        case .vulnerablePasswords: "These passwords appeared in known data breaches. Change them now."
        case .reusedPasswords: "The same password is used by more than one item."
        case .weakPasswords: "These passwords are easy to guess."
        case .unsecuredWebsites: "These websites use http:// — change to https:// if the site supports it."
        case .twoFactorAvailable: "These sites support two-factor authentication, but no one-time password is saved."
        case .expiringItems: "These items have expired or expire within 60 days."
        case .duplicateItems: "These items appear to be duplicates of each other."
        }
    }

    /// Severity bucket for card coloring: 0 red, 1 orange, 2 yellow, 3 info.
    public var severity: Int {
        switch self {
        case .vulnerablePasswords: 0
        case .reusedPasswords: 1
        case .weakPasswords: 2
        case .unsecuredWebsites: 2
        case .twoFactorAvailable: 3
        case .expiringItems: 3
        case .duplicateItems: 3
        }
    }
}

public struct WatchtowerReport: Sendable, Equatable {
    public var flagged: [WatchtowerCheck: Set<String>] = [:]
    public var generatedAt: Date = .distantPast

    public init() {}

    public func items(for check: WatchtowerCheck) -> Set<String> {
        flagged[check] ?? []
    }

    public func checks(for itemID: String) -> [WatchtowerCheck] {
        WatchtowerCheck.allCases.filter { flagged[$0]?.contains(itemID) ?? false }
    }

    public var totalIssues: Int {
        flagged.values.reduce(0) { $0 + $1.count }
    }
}

public struct WatchtowerAuditor: Sendable {
    public var hibp: HIBPClient?

    public init(hibp: HIBPClient? = nil) {
        self.hibp = hibp
    }

    /// Runs all checks over decrypted items (archived and trashed items are
    /// the caller's responsibility to exclude).
    public func audit(items: [VaultItem]) async -> WatchtowerReport {
        var report = WatchtowerReport()
        let active = items.filter { $0.trashedAt == nil && !$0.overview.isArchived }

        struct PasswordInfo {
            let itemID: String
            let password: String
            let exclusions: Set<String>
        }
        let passwords: [PasswordInfo] = active.compactMap { item in
            guard let password = item.details.firstField(withPurpose: .password)?.value,
                  !password.isEmpty, item.overview.category != .sshKey else { return nil }
            return PasswordInfo(itemID: item.id, password: password, exclusions: item.overview.watchtowerExclusions)
        }

        func flag(_ check: WatchtowerCheck, _ itemID: String, exclusions: Set<String>) {
            guard !exclusions.contains(check.rawValue) else { return }
            report.flagged[check, default: []].insert(itemID)
        }

        // Weak
        for info in passwords where PasswordStrength.score(info.password) <= .weak {
            flag(.weakPasswords, info.itemID, exclusions: info.exclusions)
        }

        // Reused
        let grouped = Dictionary(grouping: passwords, by: \.password)
        for (_, group) in grouped where group.count > 1 {
            for info in group {
                flag(.reusedPasswords, info.itemID, exclusions: info.exclusions)
            }
        }

        // Vulnerable (HIBP) — dedupe identical passwords before hitting the API.
        if let hibp {
            var verdictCache: [String: Bool] = [:]
            for info in passwords {
                let pwned: Bool
                if let cached = verdictCache[info.password] {
                    pwned = cached
                } else {
                    pwned = ((try? await hibp.breachCount(password: info.password)) ?? 0) > 0
                    verdictCache[info.password] = pwned
                }
                if pwned {
                    flag(.vulnerablePasswords, info.itemID, exclusions: info.exclusions)
                }
            }
        }

        for item in active {
            let exclusions = item.overview.watchtowerExclusions

            // Unsecured websites
            if item.overview.urls.contains(where: { $0.lowercased().hasPrefix("http://") }) {
                flag(.unsecuredWebsites, item.id, exclusions: exclusions)
            }

            // 2FA available
            if item.overview.category == .login, !item.overview.hasOTP,
               item.overview.urls.contains(where: { url in
                   guard let domain = Self.registrableDomain(url) else { return false }
                   return TwoFADirectory.supportsTOTP(domain: domain)
               }) {
                flag(.twoFactorAvailable, item.id, exclusions: exclusions)
            }

            // Expiring items
            if let expiry = Self.earliestExpiry(item.details), expiry < Date().addingTimeInterval(60 * 86_400) {
                flag(.expiringItems, item.id, exclusions: exclusions)
            }
        }

        // Duplicates: same category + domain + username (or same title for
        // items without URLs).
        var signatures: [String: [VaultItem]] = [:]
        for item in active {
            let domain = item.overview.urls.compactMap(Self.registrableDomain).first ?? item.overview.title.lowercased()
            guard !domain.isEmpty else { continue }
            let signature = "\(item.overview.category.rawValue)|\(domain)|\(item.overview.subtitle.lowercased())"
            signatures[signature, default: []].append(item)
        }
        for (_, group) in signatures where group.count > 1 {
            for item in group {
                flag(.duplicateItems, item.id, exclusions: item.overview.watchtowerExclusions)
            }
        }

        report.generatedAt = Date()
        return report
    }

    /// "https://www.login.github.com/x" → "github.com" (public-suffix-naive).
    public static func registrableDomain(_ urlString: String) -> String? {
        let candidate = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
        guard let host = URL(string: candidate)?.host()?.lowercased() else { return nil }
        let parts = host.split(separator: ".")
        // Single-label hosts (localhost, intranet names) are their own domain.
        guard parts.count >= 2 else { return host.isEmpty ? nil : host }
        return parts.suffix(2).joined(separator: ".")
    }

    /// Earliest date among fields whose label suggests expiry.
    static func earliestExpiry(_ details: ItemDetails) -> Date? {
        var dates: [Date] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        monthFormatter.timeZone = TimeZone(identifier: "UTC")

        for section in details.sections {
            for field in section.fields {
                let label = field.label.lowercased()
                guard label.contains("expir") || label.contains("expires") else { continue }
                guard !field.value.isEmpty else { continue }
                switch field.kind {
                case .date:
                    if let date = dateFormatter.date(from: field.value) { dates.append(date) }
                case .monthYear:
                    // Expires at the END of the stated month.
                    if let start = monthFormatter.date(from: field.value) {
                        let end = Calendar.current.date(byAdding: DateComponents(month: 1), to: start) ?? start
                        dates.append(end)
                    }
                default:
                    break
                }
            }
        }
        return dates.min()
    }
}
