import Foundation
import ZIPFoundation

/// Imports 1Password's .1pux export format (a ZIP containing `export.data`
/// JSON). Maps 1Password categories, fields, tags, favorites, and password
/// history onto the native model. File attachments inside the archive are
/// imported when present.
public struct OnePuxImporter: Sendable {
    public struct ImportedVault: Sendable {
        public var name: String
        public var items: [VaultItem]   // vaultID left empty; assigned on insert
        public var attachmentFiles: [String: Data] = [:]  // attachment field UUID → file data
    }

    public struct Summary: Sendable {
        public var vaults: [ImportedVault]
        public var itemCount: Int { vaults.reduce(0) { $0 + $1.items.count } }
        public var skippedItems: Int
    }

    public init() {}

    public func importArchive(at url: URL) throws -> Summary {
        let archive = try Archive(url: url, accessMode: .read)
        guard let entry = archive["export.data"] else {
            throw ImportError.missingExportData
        }
        var jsonData = Data()
        _ = try archive.extract(entry) { jsonData.append($0) }

        // Stash archived files for attachment import: files/<documentId>__<name>
        var files: [String: Data] = [:]
        for entry in archive where entry.path.hasPrefix("files/") {
            var data = Data()
            _ = try? archive.extract(entry) { data.append($0) }
            files[String(entry.path.dropFirst("files/".count))] = data
        }
        return try parse(jsonData: jsonData, files: files)
    }

    public enum ImportError: Error {
        case missingExportData
        case malformed
    }

    func parse(jsonData: Data, files: [String: Data] = [:]) throws -> Summary {
        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let accounts = root["accounts"] as? [[String: Any]] else {
            throw ImportError.malformed
        }
        var vaults: [ImportedVault] = []
        var skipped = 0

        for account in accounts {
            for vaultDict in account["vaults"] as? [[String: Any]] ?? [] {
                let attrs = vaultDict["attrs"] as? [String: Any]
                var vault = ImportedVault(name: attrs?["name"] as? String ?? "Imported", items: [])
                for itemDict in vaultDict["items"] as? [[String: Any]] ?? [] {
                    // Some 1pux exports nest under "item".
                    let item = (itemDict["item"] as? [String: Any]) ?? itemDict
                    if let converted = convertItem(item, files: files, into: &vault) {
                        vault.items.append(converted)
                    } else {
                        skipped += 1
                    }
                }
                vaults.append(vault)
            }
        }
        return Summary(vaults: vaults, skippedItems: skipped)
    }

    static let categoryMap: [String: Category] = [
        "001": .login, "002": .creditCard, "003": .secureNote, "004": .identity,
        "005": .password, "006": .document, "100": .softwareLicense,
        "101": .bankAccount, "102": .database, "103": .driverLicense,
        "104": .outdoorLicense, "105": .membership, "106": .passport,
        "107": .rewardProgram, "108": .socialSecurityNumber, "109": .wirelessRouter,
        "110": .server, "111": .emailAccount, "112": .apiCredential,
        "113": .medicalRecord, "114": .sshKey, "115": .cryptoWallet,
    ]

    private func convertItem(_ dict: [String: Any], files: [String: Data], into vault: inout ImportedVault) -> VaultItem? {
        guard let overviewDict = dict["overview"] as? [String: Any] else { return nil }
        let detailsDict = dict["details"] as? [String: Any] ?? [:]
        let categoryUuid = dict["categoryUuid"] as? String ?? "001"
        let category = Self.categoryMap[categoryUuid] ?? .login
        let state = dict["state"] as? String

        var overview = ItemOverview(category: category)
        overview.title = overviewDict["title"] as? String ?? "Untitled"
        overview.subtitle = overviewDict["subtitle"] as? String ?? ""
        var urls: [String] = []
        if let url = overviewDict["url"] as? String, !url.isEmpty { urls.append(url) }
        for entry in overviewDict["urls"] as? [[String: Any]] ?? [] {
            if let url = entry["url"] as? String, !urls.contains(url) { urls.append(url) }
        }
        overview.urls = urls
        overview.tags = overviewDict["tags"] as? [String] ?? []
        overview.isFavorite = (dict["favIndex"] as? Int ?? 0) > 0
        overview.isArchived = state == "archived"

        var sections: [ItemSection] = []

        // Login fields (username/password/otp on Login & Password categories)
        var loginSection = ItemSection()
        for field in detailsDict["loginFields"] as? [[String: Any]] ?? [] {
            guard let value = field["value"] as? String, !value.isEmpty else { continue }
            let designation = field["designation"] as? String
            let name = field["name"] as? String ?? designation ?? "field"
            switch designation {
            case "username":
                loginSection.fields.append(ItemField(label: "username", kind: .text, value: value, purpose: .username))
            case "password":
                loginSection.fields.append(ItemField(label: "password", kind: .concealed, value: value, purpose: .password))
            default:
                let type = field["fieldType"] as? String
                loginSection.fields.append(ItemField(label: name, kind: type == "P" ? .concealed : .text, value: value))
            }
        }
        if !urls.isEmpty && category == .login {
            for url in urls {
                loginSection.fields.append(ItemField(label: "website", kind: .url, value: url))
            }
        }
        if !loginSection.fields.isEmpty {
            sections.append(loginSection)
        }

        // Generic sections
        for sectionDict in detailsDict["sections"] as? [[String: Any]] ?? [] {
            var section = ItemSection(title: sectionDict["title"] as? String ?? "")
            for fieldDict in sectionDict["fields"] as? [[String: Any]] ?? [] {
                if let field = convertField(fieldDict, files: files, into: &vault) {
                    section.fields.append(field)
                }
            }
            if !section.fields.isEmpty {
                sections.append(section)
            }
        }

        // Standalone password category value
        if category == .password, let password = detailsDict["password"] as? String, !password.isEmpty {
            sections.insert(ItemSection(fields: [
                ItemField(label: "password", kind: .concealed, value: password, purpose: .password)
            ]), at: 0)
        }

        var details = ItemDetails(sections: sections)
        details.notes = detailsDict["notesPlain"] as? String ?? ""
        for entry in detailsDict["passwordHistory"] as? [[String: Any]] ?? [] {
            guard let value = entry["value"] as? String else { continue }
            let time = entry["time"] as? TimeInterval ?? 0
            details.passwordHistory.append(PasswordHistoryEntry(value: value, replacedAt: Date(timeIntervalSince1970: time)))
        }

        var item = VaultItem(vaultID: "")
        item.overview = overview
        item.details = details
        if let created = dict["createdAt"] as? TimeInterval, created > 0 {
            item.createdAt = Date(timeIntervalSince1970: created)
        }
        if let updated = dict["updatedAt"] as? TimeInterval, updated > 0 {
            item.updatedAt = Date(timeIntervalSince1970: updated)
        }
        if state == "trashed" {
            item.trashedAt = Date()
        }
        return item
    }

    private func convertField(_ dict: [String: Any], files: [String: Data], into vault: inout ImportedVault) -> ItemField? {
        let title = dict["title"] as? String ?? ""
        guard let value = dict["value"] as? [String: Any], let valueKey = value.keys.first else { return nil }
        let raw = value[valueKey]

        func stringValue() -> String {
            (raw as? String) ?? (raw as? NSNumber)?.stringValue ?? ""
        }

        switch valueKey {
        case "string":
            let v = stringValue()
            return v.isEmpty ? nil : ItemField(label: title.isEmpty ? "text" : title, kind: .text, value: v)
        case "concealed":
            let v = stringValue()
            return v.isEmpty ? nil : ItemField(label: title.isEmpty ? "password" : title, kind: .concealed, value: v)
        case "totp":
            let v = stringValue()
            return v.isEmpty ? nil : ItemField(label: title.isEmpty ? "one-time password" : title, kind: .otp, value: v)
        case "url":
            let v = stringValue()
            return v.isEmpty ? nil : ItemField(label: title.isEmpty ? "website" : title, kind: .url, value: v)
        case "phone":
            let v = stringValue()
            return v.isEmpty ? nil : ItemField(label: title.isEmpty ? "phone" : title, kind: .phone, value: v)
        case "email":
            var v = stringValue()
            if let obj = raw as? [String: Any] {
                v = obj["email_address"] as? String ?? ""
            }
            return v.isEmpty ? nil : ItemField(label: title.isEmpty ? "email" : title, kind: .email, value: v)
        case "date":
            guard let timestamp = raw as? TimeInterval else { return nil }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            return ItemField(label: title.isEmpty ? "date" : title, kind: .date,
                             value: formatter.string(from: Date(timeIntervalSince1970: timestamp)))
        case "monthYear":
            guard let number = raw as? Int, number > 0 else { return nil }
            let year = number / 100
            let month = number % 100
            return ItemField(label: title.isEmpty ? "month/year" : title, kind: .monthYear,
                             value: String(format: "%04d-%02d", year, month))
        case "address":
            guard let obj = raw as? [String: Any] else { return nil }
            let parts = ["street", "city", "state", "zip", "country"]
                .compactMap { obj[$0] as? String }
                .filter { !$0.isEmpty }
            return parts.isEmpty ? nil : ItemField(label: title.isEmpty ? "address" : title, kind: .address, value: parts.joined(separator: "\n"))
        case "file":
            guard let obj = raw as? [String: Any],
                  let documentId = obj["documentId"] as? String,
                  let fileName = obj["fileName"] as? String else { return nil }
            // Archive stores files as files/<documentId>__<fileName>
            let fieldID = UUID()
            if let data = files["\(documentId)__\(fileName)"] ?? files.first(where: { $0.key.hasPrefix(documentId) })?.value {
                vault.attachmentFiles[fieldID.uuidString] = data
            }
            return ItemField(id: fieldID, label: fileName, kind: .file, value: "")
        case "sshKey":
            guard let obj = raw as? [String: Any], let privateKey = obj["privateKey"] as? String else { return nil }
            return ItemField(label: title.isEmpty ? "private key" : title, kind: .sshKey, value: privateKey, purpose: .password)
        case "menu", "gender", "cctype":
            let v = stringValue()
            return v.isEmpty ? nil : ItemField(label: title, kind: .text, value: v)
        case "creditCardNumber":
            let v = stringValue()
            return v.isEmpty ? nil : ItemField(label: title.isEmpty ? "number" : title, kind: .concealed, value: v, purpose: .password)
        case "reference":
            let v = stringValue()
            return v.isEmpty ? nil : ItemField(label: title.isEmpty ? "linked item" : title, kind: .linkedItem, value: v)
        default:
            let v = stringValue()
            return v.isEmpty ? nil : ItemField(label: title.isEmpty ? valueKey : title, kind: .text, value: v)
        }
    }
}
