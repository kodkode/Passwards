import Testing
import Foundation
@testable import PasswardsCore

@Suite("Watchtower")
struct WatchtowerTests {
    func login(_ title: String, password: String, urls: [String] = [], username: String = "user", otp: String = "", vaultID: String = "v") -> VaultItem {
        var item = VaultItem(vaultID: vaultID)
        var fields = [
            ItemField(label: "username", kind: .text, value: username, purpose: .username),
            ItemField(label: "password", kind: .concealed, value: password, purpose: .password),
        ]
        if !otp.isEmpty {
            fields.append(ItemField(label: "one-time password", kind: .otp, value: otp))
        }
        fields.append(contentsOf: urls.map { ItemField(label: "website", kind: .url, value: $0) })
        item.details = ItemDetails(sections: [ItemSection(fields: fields)])
        item.overview = ItemOverview(title: title, subtitle: username, urls: urls, category: .login, hasOTP: !otp.isEmpty)
        return item
    }

    @Test func weakAndReused() async {
        let auditor = WatchtowerAuditor(hibp: nil)
        let strong1 = PasswordGenerator.random(.init(length: 24))
        let strong2 = PasswordGenerator.random(.init(length: 24))
        let items = [
            login("A", password: "abc123", urls: ["https://a.com"]),
            login("B", password: strong1, urls: ["https://b.com"]),
            login("C", password: strong1, urls: ["https://c.com"]),
            login("D", password: strong2, urls: ["https://d.com"]),
        ]
        let report = await auditor.audit(items: items)
        #expect(report.items(for: .weakPasswords) == [items[0].id])
        #expect(report.items(for: .reusedPasswords) == [items[1].id, items[2].id])
        #expect(report.items(for: .duplicateItems).isEmpty)
    }

    @Test func unsecuredAndDuplicates() async {
        let auditor = WatchtowerAuditor(hibp: nil)
        let pw1 = PasswordGenerator.random(.init(length: 24))
        let pw2 = PasswordGenerator.random(.init(length: 24))
        let items = [
            login("Old Site", password: pw1, urls: ["http://insecure.example.com"]),
            login("GitHub", password: pw2, urls: ["https://github.com"], username: "michael"),
            login("GitHub copy", password: pw2, urls: ["https://www.github.com/login"], username: "michael"),
        ]
        let report = await auditor.audit(items: items)
        #expect(report.items(for: .unsecuredWebsites) == [items[0].id])
        #expect(report.items(for: .duplicateItems) == [items[1].id, items[2].id])
    }

    @Test func twoFactorAvailable() async {
        let auditor = WatchtowerAuditor(hibp: nil)
        #expect(TwoFADirectory.totpDomains.count > 1000)
        #expect(TwoFADirectory.supportsTOTP(domain: "github.com"))

        let strong = { PasswordGenerator.random(.init(length: 24)) }
        let items = [
            login("GitHub", password: strong(), urls: ["https://github.com"]),
            login("GitHub with OTP", password: strong(), urls: ["https://github.com"], username: "other", otp: "JBSWY3DPEHPK3PXP"),
            login("No 2FA site", password: strong(), urls: ["https://definitely-not-in-directory-xyz.example"]),
        ]
        let report = await auditor.audit(items: items)
        #expect(report.items(for: .twoFactorAvailable) == [items[0].id])
    }

    @Test func expiringItems() async {
        let auditor = WatchtowerAuditor(hibp: nil)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let soon = formatter.string(from: Date().addingTimeInterval(20 * 86_400))
        let far = formatter.string(from: Date().addingTimeInterval(200 * 86_400))

        var passport = VaultItem(vaultID: "v")
        passport.overview = ItemOverview(title: "Passport", category: .passport)
        passport.details = ItemDetails(sections: [ItemSection(fields: [
            ItemField(label: "expiry date", kind: .date, value: soon)
        ])])
        var passport2 = VaultItem(vaultID: "v")
        passport2.overview = ItemOverview(title: "Passport 2", category: .passport)
        passport2.details = ItemDetails(sections: [ItemSection(fields: [
            ItemField(label: "expiry date", kind: .date, value: far)
        ])])

        let report = await auditor.audit(items: [passport, passport2])
        #expect(report.items(for: .expiringItems) == [passport.id])
    }

    @Test func exclusionsAreRespected() async {
        let auditor = WatchtowerAuditor(hibp: nil)
        var item = login("A", password: "abc123", urls: ["http://a.com"])
        item.overview.watchtowerExclusions = [WatchtowerCheck.weakPasswords.rawValue]
        let report = await auditor.audit(items: [item])
        #expect(report.items(for: .weakPasswords).isEmpty)
        #expect(report.items(for: .unsecuredWebsites) == [item.id])
    }

    @Test func archivedAndTrashedSkipped() async {
        let auditor = WatchtowerAuditor(hibp: nil)
        var archived = login("A", password: "abc123")
        archived.overview.isArchived = true
        var trashed = login("B", password: "abc123")
        trashed.trashedAt = Date()
        let report = await auditor.audit(items: [archived, trashed])
        #expect(report.totalIssues == 0)
    }

    @Test func hibpResponseParsing() {
        // Recorded-style fixture: suffix list for some prefix.
        let body = """
        0018A45C4D1DEF81644B54AB7F969B88D65:1
        00D4F6E8FA6EECAD2A3AA415EEC418D38EC:2
        011053FD0102E94D6AE2F8B83D76FAF94F6:9999
        """
        #expect(HIBPClient.match(suffix: "011053FD0102E94D6AE2F8B83D76FAF94F6", in: body) == 9999)
        #expect(HIBPClient.match(suffix: "0018A45C4D1DEF81644B54AB7F969B88D65", in: body) == 1)
        #expect(HIBPClient.match(suffix: "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF", in: body) == 0)
    }

    @Test func registrableDomain() {
        #expect(WatchtowerAuditor.registrableDomain("https://www.login.github.com/session") == "github.com")
        #expect(WatchtowerAuditor.registrableDomain("github.com") == "github.com")
        #expect(WatchtowerAuditor.registrableDomain("not a url") == nil)
    }
}
