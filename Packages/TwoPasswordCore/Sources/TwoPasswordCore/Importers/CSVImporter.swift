import Foundation

/// Generic CSV login import with header auto-detection for the common
/// exporters (1Password CSV, Chrome/Edge, Bitwarden, LastPass, Safari).
public struct CSVImporter: Sendable {
    public init() {}

    public struct Result: Sendable {
        public var items: [VaultItem]
        public var skippedRows: Int
    }

    public enum ImportError: Error {
        case empty
        case noUsableColumns
    }

    public func importCSV(data: Data) throws -> Result {
        let text = String(decoding: data, as: UTF8.self)
        var rows = Self.parse(text)
        guard rows.count > 1 else { throw ImportError.empty }

        let header = rows.removeFirst().map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        func column(_ names: [String]) -> Int? {
            for name in names {
                if let index = header.firstIndex(of: name) { return index }
            }
            return nil
        }

        let titleCol = column(["title", "name", "account"])
        let userCol = column(["username", "user name", "login_username", "user", "login"])
        let passCol = column(["password", "login_password", "pass"])
        let urlCol = column(["url", "website", "login_uri", "web site", "urls"])
        let notesCol = column(["notes", "note", "extra", "comments"])
        let otpCol = column(["otpauth", "totp", "login_totp", "one-time password", "otp"])

        guard passCol != nil || userCol != nil || titleCol != nil else {
            throw ImportError.noUsableColumns
        }

        var items: [VaultItem] = []
        var skipped = 0

        for row in rows {
            func cell(_ index: Int?) -> String {
                guard let index, index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let title = cell(titleCol)
            let username = cell(userCol)
            let password = cell(passCol)
            let url = cell(urlCol)
            let notes = cell(notesCol)
            let otp = cell(otpCol)

            guard !(title.isEmpty && username.isEmpty && password.isEmpty && url.isEmpty) else {
                skipped += 1
                continue
            }

            var fields: [ItemField] = []
            if !username.isEmpty { fields.append(ItemField(label: "username", kind: .text, value: username, purpose: .username)) }
            if !password.isEmpty { fields.append(ItemField(label: "password", kind: .concealed, value: password, purpose: .password)) }
            if !otp.isEmpty { fields.append(ItemField(label: "one-time password", kind: .otp, value: otp)) }
            if !url.isEmpty { fields.append(ItemField(label: "website", kind: .url, value: url)) }

            var item = VaultItem(vaultID: "")
            item.overview = ItemOverview(
                title: title.isEmpty ? (WatchtowerAuditor.registrableDomain(url) ?? username) : title,
                subtitle: username,
                urls: url.isEmpty ? [] : [url],
                category: .login
            )
            item.details = ItemDetails(sections: [ItemSection(fields: fields)], notes: notes)
            items.append(item)
        }
        return Result(items: items, skippedRows: skipped)
    }

    /// RFC 4180-ish CSV parser: quoted fields, escaped quotes, CRLF.
    static func parse(_ text: String) -> [[String]] {
        // "\r\n" is a single Character in Swift; normalize before scanning.
        let text = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) {
                rows.append(row)
            }
            row = []
        }

        while let char = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else {
                switch char {
                case "\"" where field.isEmpty:
                    inQuotes = true
                case ",":
                    endField()
                case "\r":
                    break
                case "\n":
                    endRow()
                default:
                    field.append(char)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty {
            endRow()
        }
        return rows
    }
}
