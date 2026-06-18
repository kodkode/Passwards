import Foundation

/// Bundled snapshot of 2fa.directory: which domains support TOTP two-factor
/// authentication. Matching is fully local.
public enum TwoFADirectory {
    /// Domains (registrable, lowercased) that support TOTP.
    public static let totpDomains: Set<String> = {
        guard let url = Bundle.module.url(forResource: "2fa_directory", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else {
            return []
        }
        var domains: Set<String> = []
        for entry in entries {
            guard entry.count == 2, let info = entry[1] as? [String: Any],
                  let methods = info["tfa"] as? [String],
                  methods.contains("totp") else { continue }
            if let domain = info["domain"] as? String {
                domains.insert(domain.lowercased())
            }
            if let additional = info["additional-domains"] as? [String] {
                for domain in additional { domains.insert(domain.lowercased()) }
            }
        }
        return domains
    }()

    public static func supportsTOTP(domain: String) -> Bool {
        totpDomains.contains(domain.lowercased())
    }
}
