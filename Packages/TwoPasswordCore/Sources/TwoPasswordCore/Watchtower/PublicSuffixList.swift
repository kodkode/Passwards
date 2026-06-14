import Foundation

/// A real Public Suffix List (https://publicsuffix.org) matcher used to compute
/// the registrable domain (eTLD+1) of a host.
///
/// This is a SECURITY boundary, not a heuristic. The browser bridge releases a
/// saved credential to a page only when the page's registrable domain equals the
/// stored item's. A correct eTLD+1 is what keeps `evil.co.uk` from being treated
/// as the same site as `bank.co.uk`, and one tenant's `a.github.io` from being
/// treated as another tenant's `b.github.io`. The previous last-two-labels guess
/// collapsed all of those onto a single "domain" and leaked credentials across
/// unrelated sites that merely share a multi-label public suffix.
///
/// Rules come from the bundled `public_suffix_list.dat`. A small set of the most
/// security-relevant suffixes is also compiled in (`fallbackRules`) so a missing
/// or unreadable resource can never silently degrade matching back to the
/// vulnerable behaviour. Refresh the bundled list with `scripts/update-psl.sh`.
public struct PublicSuffixList: Sendable {
    public static let shared = PublicSuffixList()

    private let normalRules: Set<String>
    private let wildcardRules: Set<String>   // the `parent` of a `*.parent` rule
    private let exceptionRules: Set<String>  // a `!rule`, stored without the `!`

    /// - Parameter rulesText: PSL-format rules; defaults to the bundled list.
    ///   Exposed for deterministic unit tests.
    init(rulesText: String? = nil) {
        let text = rulesText ?? Self.bundledRulesText() ?? ""
        var normal: Set<String> = []
        var wildcard: Set<String> = []
        var exception: Set<String> = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // Blank lines and `//` comments (incl. the ICANN/PRIVATE section
            // markers) are not rules.
            if line.isEmpty || line.hasPrefix("//") { continue }
            // PSL rules are punycode/ASCII; lowercase for case-insensitive match.
            let rule = line.lowercased()
            if rule.hasPrefix("!") {
                exception.insert(String(rule.dropFirst()))
            } else if rule.hasPrefix("*.") {
                wildcard.insert(String(rule.dropFirst(2)))
            } else {
                normal.insert(rule)
            }
        }
        // Never trust an empty/partial load: fold in the compiled-in safety net
        // so the highest-risk suffixes are always enforced.
        normal.formUnion(Self.fallbackRules)
        self.normalRules = normal
        self.wildcardRules = wildcard
        self.exceptionRules = exception
    }

    private static func bundledRulesText() -> String? {
        guard let url = Bundle.module.url(forResource: "public_suffix_list", withExtension: "dat"),
              let data = try? Data(contentsOf: url) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// The registrable domain (eTLD+1) of `host`, or nil when `host` has none —
    /// a bare public suffix like `co.uk`/`github.io`/`com`, or a single-label
    /// host such as `localhost` or an intranet name. Returning nil there is
    /// deliberately fail-closed: a host with no eTLD+1 yields no credential
    /// match rather than collapsing distinct single-label hosts together.
    public func registrableDomain(host: String) -> String? {
        var normalized = host.lowercased()
        while normalized.hasSuffix(".") { normalized.removeLast() }
        while normalized.hasPrefix(".") { normalized.removeFirst() }
        guard !normalized.isEmpty else { return nil }

        let labels = normalized.split(separator: ".").map(String.init)
        guard !labels.isEmpty else { return nil }

        let suffixLabelCount = publicSuffixLabelCount(labels)
        // The host must have at least one label MORE than its public suffix to
        // have a registrable domain; otherwise it *is* a public suffix.
        guard labels.count > suffixLabelCount else { return nil }
        return labels.suffix(suffixLabelCount + 1).joined(separator: ".")
    }

    /// Number of labels in the public suffix of `labels`, per the PSL algorithm:
    /// exception rules prevail, otherwise the longest matching normal/wildcard
    /// rule wins, otherwise the implicit `*` rule (the rightmost single label).
    private func publicSuffixLabelCount(_ labels: [String]) -> Int {
        let n = labels.count
        // Exception rules take priority. The public suffix of a matched
        // exception rule is the rule with its leftmost label removed.
        for i in 0..<n {
            let candidate = labels[i...].joined(separator: ".")
            if exceptionRules.contains(candidate) { return (n - i) - 1 }
        }
        // Longest match wins; i == 0 is the longest candidate, so the first hit
        // is the longest matching rule.
        for i in 0..<n {
            let candidate = labels[i...].joined(separator: ".")
            if normalRules.contains(candidate) { return n - i }
            if i + 1 < n {
                let parent = labels[(i + 1)...].joined(separator: ".")
                if wildcardRules.contains(parent) { return n - i }
            }
        }
        return 1  // implicit `*` rule
    }

    /// Compiled-in safety net (see `init`). Intentionally small — the bundled
    /// `.dat` is the source of truth; this only prevents a silent regression to
    /// last-two-labels if that resource is ever unavailable at runtime.
    private static let fallbackRules: Set<String> = [
        // ICANN ccTLD second levels (high-density shared-suffix registrations).
        "co.uk", "org.uk", "me.uk", "gov.uk", "ac.uk", "net.uk", "sch.uk", "nhs.uk",
        "com.au", "net.au", "org.au", "edu.au", "gov.au", "id.au",
        "co.jp", "or.jp", "ne.jp", "ac.jp", "go.jp", "gr.jp",
        "co.nz", "net.nz", "org.nz", "govt.nz", "ac.nz",
        "co.za", "org.za", "gov.za", "ac.za", "web.za",
        "com.br", "net.br", "org.br", "gov.br", "edu.br",
        "co.in", "net.in", "org.in", "gov.in", "ac.in", "edu.in",
        "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn",
        "co.kr", "or.kr", "go.kr", "ne.kr",
        "com.mx", "org.mx", "gob.mx", "edu.mx",
        "co.il", "org.il", "gov.il", "ac.il",
        "com.sg", "edu.sg", "gov.sg", "org.sg",
        "com.hk", "org.hk", "gov.hk", "edu.hk",
        "com.tw", "org.tw", "gov.tw", "edu.tw",
        "com.tr", "net.tr", "org.tr", "gov.tr", "edu.tr",
        "com.ua", "net.ua", "org.ua", "gov.ua", "in.ua",
        "com.ar", "net.ar", "org.ar", "gob.ar", "edu.ar",
        "com.my", "net.my", "org.my", "gov.my", "edu.my",
        "com.ph", "net.ph", "org.ph", "gov.ph", "edu.ph",
        "co.th", "or.th", "go.th", "ac.th", "in.th",
        "co.id", "or.id", "web.id", "go.id", "ac.id",
        // Private suffixes / PaaS where unrelated tenants share a base domain.
        "github.io", "gitlab.io", "bitbucket.io", "readthedocs.io",
        "vercel.app", "netlify.app", "web.app", "firebaseapp.com",
        "pages.dev", "workers.dev", "herokuapp.com", "herokussl.com",
        "appspot.com", "r.appspot.com", "azurewebsites.net", "cloudapp.net",
        "azurestaticapps.net", "cloudfront.net", "s3.amazonaws.com",
        "now.sh", "surge.sh", "glitch.me", "fly.dev", "onrender.com",
        "blogspot.com", "wordpress.com", "ngrok.io", "ngrok-free.app",
        "repl.co", "replit.dev", "github.dev", "pythonanywhere.com",
    ]
}
