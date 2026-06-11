import Testing
import Foundation
@testable import TwoPasswordCore

@Suite("1PUX import")
struct OnePuxTests {
    static let fixture = """
    {
      "accounts": [{
        "attrs": {"name": "Michael"},
        "vaults": [{
          "attrs": {"uuid": "v1", "name": "Personal"},
          "items": [
            {
              "uuid": "item1",
              "categoryUuid": "001",
              "favIndex": 1,
              "createdAt": 1600000000,
              "updatedAt": 1700000000,
              "state": "active",
              "overview": {
                "title": "GitHub",
                "subtitle": "michael",
                "url": "https://github.com",
                "urls": [{"label": "site", "url": "https://github.com"}],
                "tags": ["dev", "work/code"]
              },
              "details": {
                "loginFields": [
                  {"value": "michael", "designation": "username", "name": "username", "fieldType": "T"},
                  {"value": "hunter2", "designation": "password", "name": "password", "fieldType": "P"}
                ],
                "notesPlain": "my github note",
                "sections": [{
                  "title": "Extra",
                  "fields": [
                    {"title": "one-time password", "id": "totp", "value": {"totp": "JBSWY3DPEHPK3PXP"}},
                    {"title": "recovery email", "id": "em", "value": {"email": {"email_address": "m@x.com"}}},
                    {"title": "member since", "id": "my", "value": {"monthYear": 202103}},
                    {"title": "birth date", "id": "bd", "value": {"date": 631152000}},
                    {"title": "home", "id": "addr", "value": {"address": {"street": "1 Main St", "city": "Tel Aviv", "country": "IL"}}}
                  ]
                }],
                "passwordHistory": [{"value": "oldpass", "time": 1500000000}]
              }
            },
            {
              "uuid": "item2",
              "categoryUuid": "002",
              "overview": {"title": "Visa", "subtitle": ""},
              "details": {
                "sections": [{
                  "title": "",
                  "fields": [
                    {"title": "number", "id": "ccnum", "value": {"creditCardNumber": "4111111111111111"}},
                    {"title": "expiry date", "id": "expiry", "value": {"monthYear": 202712}}
                  ]
                }]
              }
            },
            {
              "uuid": "item3",
              "categoryUuid": "003",
              "state": "archived",
              "overview": {"title": "Note"},
              "details": {"notesPlain": "secret note body"}
            }
          ]
        }]
      }]
    }
    """

    @Test func parsesFixture() throws {
        let summary = try OnePuxImporter().parse(jsonData: Data(Self.fixture.utf8))
        #expect(summary.vaults.count == 1)
        let vault = summary.vaults[0]
        #expect(vault.name == "Personal")
        #expect(vault.items.count == 3)
        #expect(summary.skippedItems == 0)

        let github = vault.items[0]
        #expect(github.overview.title == "GitHub")
        #expect(github.overview.category == .login)
        #expect(github.overview.isFavorite)
        #expect(github.overview.tags == ["dev", "work/code"])
        #expect(github.overview.urls == ["https://github.com"])
        #expect(github.details.firstField(withPurpose: .username)?.value == "michael")
        #expect(github.details.firstField(withPurpose: .password)?.value == "hunter2")
        #expect(github.details.firstField(ofKind: .otp)?.value == "JBSWY3DPEHPK3PXP")
        #expect(github.details.firstField(ofKind: .email)?.value == "m@x.com")
        #expect(github.details.firstField(ofKind: .monthYear)?.value == "2021-03")
        #expect(github.details.firstField(ofKind: .date)?.value == "1990-01-01")
        #expect(github.details.firstField(ofKind: .address)?.value.contains("Tel Aviv") == true)
        #expect(github.details.notes == "my github note")
        #expect(github.details.passwordHistory.first?.value == "oldpass")
        #expect(github.createdAt == Date(timeIntervalSince1970: 1_600_000_000))

        let visa = vault.items[1]
        #expect(visa.overview.category == .creditCard)
        #expect(visa.details.firstField(withPurpose: .password)?.value == "4111111111111111")

        let note = vault.items[2]
        #expect(note.overview.category == .secureNote)
        #expect(note.overview.isArchived)
        #expect(note.details.notes == "secret note body")
    }

    @Test func importsIntoEncryptedStore() async throws {
        let env = try await TestEnvironment.make()
        let summary = try OnePuxImporter().parse(jsonData: Data(Self.fixture.utf8))
        for var item in summary.vaults[0].items {
            item.vaultID = env.vault.id
            try await env.items.create(item)
        }
        let all = try await env.items.allItems()
        #expect(all.count == 3)
        let github = try #require(all.first { $0.overview.title == "GitHub" })
        #expect(github.details.firstField(withPurpose: .password)?.value == "hunter2")
    }
}

@Suite("CSV import/export")
struct CSVTests {
    @Test func chromeStyle() throws {
        let csv = """
        name,url,username,password
        GitHub,https://github.com,michael,hunter2
        "Comma, Site",https://x.com,user,"pa""ss,word"
        """
        let result = try CSVImporter().importCSV(data: Data(csv.utf8))
        #expect(result.items.count == 2)
        #expect(result.items[0].overview.title == "GitHub")
        #expect(result.items[0].details.firstField(withPurpose: .password)?.value == "hunter2")
        #expect(result.items[1].overview.title == "Comma, Site")
        #expect(result.items[1].details.firstField(withPurpose: .password)?.value == "pa\"ss,word")
    }

    @Test func bitwardenStyle() throws {
        let csv = """
        folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp
        ,,login,Example,some note,,0,https://example.com,user@x.com,secretpw,JBSWY3DP
        """
        let result = try CSVImporter().importCSV(data: Data(csv.utf8))
        #expect(result.items.count == 1)
        let item = result.items[0]
        #expect(item.overview.title == "Example")
        #expect(item.details.firstField(withPurpose: .username)?.value == "user@x.com")
        #expect(item.details.firstField(ofKind: .otp)?.value == "JBSWY3DP")
        #expect(item.details.notes == "some note")
    }

    @Test func unusableHeaderThrows() {
        #expect(throws: CSVImporter.ImportError.self) {
            _ = try CSVImporter().importCSV(data: Data("a,b,c\n1,2,3".utf8))
        }
    }

    @Test func exportImportRoundTrip() throws {
        var item = VaultItem(vaultID: "v")
        item.overview = ItemOverview(title: "Site, with comma", subtitle: "u", urls: ["https://s.com"], tags: ["t1"], category: .login)
        item.details = ItemDetails(sections: [ItemSection(fields: [
            ItemField(label: "username", kind: .text, value: "u", purpose: .username),
            ItemField(label: "password", kind: .concealed, value: "p\"w,x", purpose: .password),
        ])], notes: "line1\nline2")

        let csv = Exporters.csv(items: [item])
        let reimported = try CSVImporter().importCSV(data: csv)
        #expect(reimported.items.count == 1)
        #expect(reimported.items[0].overview.title == "Site, with comma")
        #expect(reimported.items[0].details.firstField(withPurpose: .password)?.value == "p\"w,x")
        #expect(reimported.items[0].details.notes == "line1\nline2")
    }

    @Test func jsonExportStructure() throws {
        var item = VaultItem(vaultID: "v")
        item.overview = ItemOverview(title: "Anything", category: .passport)
        item.details = ItemDetails(sections: CategoryTemplates.template(for: .passport))
        let data = try Exporters.json(items: [item], vaultNames: ["v": "Personal"])
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["format"] as? String == "2password-export")
        let vaults = decoded?["vaults"] as? [[String: Any]]
        #expect(vaults?.first?["name"] as? String == "Personal")
        #expect((vaults?.first?["items"] as? [[String: Any]])?.count == 1)
    }
}
