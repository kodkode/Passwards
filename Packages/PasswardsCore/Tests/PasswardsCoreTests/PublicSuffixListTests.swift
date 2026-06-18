import Testing
import Foundation
@testable import PasswardsCore

@Suite("PublicSuffixList")
struct PublicSuffixListTests {

    // MARK: Algorithm (deterministic, inline rules)

    /// A minimal list exercising normal, wildcard, and exception rules.
    private let psl = PublicSuffixList(rulesText: """
    // normal multi-label suffixes
    com
    co.uk
    github.io
    // wildcard + its exception
    *.ck
    !www.ck
    """)

    @Test func ordinaryRegistrableDomain() {
        #expect(psl.registrableDomain(host: "github.com") == "github.com")
        #expect(psl.registrableDomain(host: "www.login.github.com") == "github.com")
        #expect(psl.registrableDomain(host: "a.b.c.example.com") == "example.com")
    }

    @Test func multiLabelPublicSuffixDoesNotCollapse() {
        // The whole point of the fix: siblings under a 2-label public suffix are
        // distinct registrable domains.
        #expect(psl.registrableDomain(host: "bank.co.uk") == "bank.co.uk")
        #expect(psl.registrableDomain(host: "evil.co.uk") == "evil.co.uk")
        #expect(psl.registrableDomain(host: "bank.co.uk") != psl.registrableDomain(host: "evil.co.uk"))

        #expect(psl.registrableDomain(host: "a.github.io") == "a.github.io")
        #expect(psl.registrableDomain(host: "b.github.io") == "b.github.io")
        #expect(psl.registrableDomain(host: "a.github.io") != psl.registrableDomain(host: "b.github.io"))
    }

    @Test func subdomainsStillShareRegistrableDomain() {
        // Legitimate subdomain autofill must keep working.
        #expect(psl.registrableDomain(host: "login.bank.co.uk") == "bank.co.uk")
        #expect(psl.registrableDomain(host: "www.bank.co.uk") == "bank.co.uk")
    }

    @Test func barePublicSuffixHasNoRegistrableDomain() {
        #expect(psl.registrableDomain(host: "co.uk") == nil)
        #expect(psl.registrableDomain(host: "github.io") == nil)
        #expect(psl.registrableDomain(host: "com") == nil)
    }

    @Test func wildcardRules() {
        // `*.ck` makes any `x.ck` a public suffix.
        #expect(psl.registrableDomain(host: "foo.ck") == nil)
        #expect(psl.registrableDomain(host: "bar.foo.ck") == "bar.foo.ck")
    }

    @Test func exceptionRules() {
        // `!www.ck` carves `www.ck` back out as a registrable domain.
        #expect(psl.registrableDomain(host: "www.ck") == "www.ck")
    }

    @Test func singleLabelAndEmpty() {
        // Single-label hosts have no eTLD+1 → nil (fail-closed; also stops
        // distinct single-label intranet hosts from collapsing together).
        #expect(psl.registrableDomain(host: "localhost") == nil)
        #expect(psl.registrableDomain(host: "") == nil)
        #expect(psl.registrableDomain(host: "example.com.") == "example.com")  // trailing dot tolerated
        #expect(psl.registrableDomain(host: "EXAMPLE.COM") == "example.com")   // case-insensitive
    }

    @Test func unlistedSuffixFallsBackToLastLabel() {
        // `.io` is not a listed multi-label suffix → ordinary flat TLD behaviour.
        #expect(psl.registrableDomain(host: "example.io") == "example.io")
        #expect(psl.registrableDomain(host: "a.example.io") == "example.io")
    }

    // MARK: Bundled list (the artifact that actually ships)

    @Test func bundledListCoversRealAttackCases() {
        // Goes through the public API used by the browser bridge.
        #expect(WatchtowerAuditor.registrableDomain("https://attacker.github.io/x")
                != WatchtowerAuditor.registrableDomain("https://victim.github.io/y"))
        #expect(WatchtowerAuditor.registrableDomain("https://evil.co.uk")
                != WatchtowerAuditor.registrableDomain("https://barclays.co.uk"))
        #expect(WatchtowerAuditor.registrableDomain("https://a.vercel.app")
                != WatchtowerAuditor.registrableDomain("https://b.vercel.app"))
        // ...while ordinary matching and subdomain grouping are unchanged.
        #expect(WatchtowerAuditor.registrableDomain("https://www.login.github.com/session") == "github.com")
        #expect(WatchtowerAuditor.registrableDomain("https://accounts.google.com") == "google.com")
        #expect(WatchtowerAuditor.registrableDomain("github.com") == "github.com")
        #expect(WatchtowerAuditor.registrableDomain("not a url") == nil)
    }
}
