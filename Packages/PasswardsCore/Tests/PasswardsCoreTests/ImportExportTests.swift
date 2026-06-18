import Testing
import Foundation
import ZIPFoundation
@testable import PasswardsCore

@Suite("1PUX import")
struct OnePuxTests {

    /// Builds a real .1pux (ZIP) at a temp URL with the given entries.
    private func makeOnePux(exportData: Data, files: [(name: String, data: Data)] = []) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).1pux")
        let archive = try Archive(url: url, accessMode: .create)
        func add(_ path: String, _ payload: Data) throws {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count)) { position, size in
                let start = Int(position)
                return payload.subdata(in: start..<min(start + size, payload.count))
            }
        }
        try add("export.data", exportData)
        for file in files { try add("files/\(file.name)", file.data) }
        return url
    }

    @Test func importArchiveRoundTrip() throws {
        let url = try makeOnePux(exportData: Data(Self.fixture.utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let summary = try OnePuxImporter().importArchive(at: url)
        #expect(summary.vaults.first?.items.count == 3)
    }

    @Test func oversizedExportDataIsRejected() throws {
        // A decompression bomb: export.data far larger than the cap must throw
        // rather than allocate unbounded memory.
        let url = try makeOnePux(exportData: Data(count: 4096))
        defer { try? FileManager.default.removeItem(at: url) }
        let importer = OnePuxImporter(maxExportDataSize: 1024)
        #expect(throws: OnePuxImporter.ImportError.self) {
            _ = try importer.importArchive(at: url)
        }
    }

    @Test func oversizedAttachmentIsSkippedNotFatal() throws {
        // An over-cap file entry is skipped (best-effort), import still succeeds.
        let url = try makeOnePux(exportData: Data(Self.fixture.utf8),
                                 files: [(name: "doc__big.bin", data: Data(count: 8192))])
        defer { try? FileManager.default.removeItem(at: url) }
        let summary = try OnePuxImporter(maxAttachmentSize: 1024).importArchive(at: url)
        #expect(summary.vaults.first?.items.count == 3)
    }

    @Test func tooManyFileEntriesIsRejected() throws {
        let files = (0..<5).map { (name: "doc\($0)__f.bin", data: Data([0x01])) }
        let url = try makeOnePux(exportData: Data(Self.fixture.utf8), files: files)
        defer { try? FileManager.default.removeItem(at: url) }
        let importer = OnePuxImporter(maxFileEntries: 2)
        #expect(throws: OnePuxImporter.ImportError.self) {
            _ = try importer.importArchive(at: url)
        }
    }
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

    @Test func csvNeutralizesFormulaInjection() {
        #expect(Exporters.neutralizeFormula("=1+1") == "'=1+1")
        #expect(Exporters.neutralizeFormula("+44") == "'+44")
        #expect(Exporters.neutralizeFormula("-2") == "'-2")
        #expect(Exporters.neutralizeFormula("@SUM(A1)") == "'@SUM(A1)")
        #expect(Exporters.neutralizeFormula("\tx") == "'\tx")
        #expect(Exporters.neutralizeFormula("normal") == "normal")
        #expect(Exporters.neutralizeFormula("a=b") == "a=b")   // only a leading trigger counts

        // End to end: a malicious title is neutralized in the exported CSV.
        var item = VaultItem(vaultID: "v")
        item.overview = ItemOverview(title: "=HYPERLINK(\"http://evil\")", category: .login)
        item.details = ItemDetails(sections: [ItemSection(fields: [
            ItemField(label: "password", kind: .concealed, value: "@cmd|'/c calc'", purpose: .password),
        ])])
        let csv = String(decoding: Exporters.csv(items: [item]), as: UTF8.self)
        #expect(csv.contains("'=HYPERLINK"))
        #expect(csv.contains("'@cmd"))
    }

    @Test func jsonExportStructure() throws {
        var item = VaultItem(vaultID: "v")
        item.overview = ItemOverview(title: "Anything", category: .passport)
        item.details = ItemDetails(sections: CategoryTemplates.template(for: .passport))
        let data = try Exporters.json(items: [item], vaultNames: ["v": "Personal"])
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["format"] as? String == "passwards-export")
        let vaults = decoded?["vaults"] as? [[String: Any]]
        #expect(vaults?.first?["name"] as? String == "Personal")
        #expect((vaults?.first?["items"] as? [[String: Any]])?.count == 1)
    }
}
