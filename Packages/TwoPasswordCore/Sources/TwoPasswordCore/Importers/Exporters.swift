import Foundation

/// Plaintext exports. Both are gated behind account-password re-entry in the
/// UI — the caller must verify credentials before invoking these.
public enum Exporters {
    // MARK: CSV (Logins & Passwords, like 1Password's CSV export)

    public static func csv(items: [VaultItem]) -> Data {
        var lines = ["Title,Username,Password,OTPAuth,URL,Notes,Tags"]
        for item in items where item.trashedAt == nil {
            guard item.overview.category == .login || item.overview.category == .password else { continue }
            let fields = [
                item.overview.title,
                item.details.firstField(withPurpose: .username)?.value ?? "",
                item.details.firstField(withPurpose: .password)?.value ?? "",
                item.details.firstField(ofKind: .otp)?.value ?? "",
                item.overview.urls.first ?? "",
                item.details.notes,
                item.overview.tags.joined(separator: "; "),
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    static func escape(_ field: String) -> String {
        if field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    // MARK: Full JSON export (every category, full structure)

    struct ExportDocument: Codable {
        var format = "2password-export"
        var version = 1
        var exportedAt: Date
        var vaults: [ExportVault]
    }

    struct ExportVault: Codable {
        var name: String
        var items: [ExportItem]
    }

    struct ExportItem: Codable {
        var id: String
        var overview: ItemOverview
        var details: ItemDetails
        var createdAt: Date
        var updatedAt: Date
    }

    public static func json(items: [VaultItem], vaultNames: [String: String]) throws -> Data {
        var byVault: [String: [VaultItem]] = [:]
        for item in items where item.trashedAt == nil {
            byVault[item.vaultID, default: []].append(item)
        }
        let document = ExportDocument(
            exportedAt: Date(),
            vaults: byVault.map { vaultID, items in
                ExportVault(
                    name: vaultNames[vaultID] ?? "Vault",
                    items: items.map {
                        ExportItem(id: $0.id, overview: $0.overview, details: $0.details, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
                    }
                )
            }.sorted { $0.name < $1.name }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }
}
