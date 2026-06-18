import Foundation
import CryptoKit

/// Have I Been Pwned "Pwned Passwords" range client (k-anonymity model):
/// SHA-1 the password locally, send only the first 5 hex characters, and
/// compare the returned suffix list on-device. `Add-Padding` hides even the
/// response size.
public struct HIBPClient: Sendable {
    let session: URLSession
    let baseURL: String

    public init(session: URLSession = .shared, baseURL: String = "https://api.pwnedpasswords.com/range/") {
        self.session = session
        self.baseURL = baseURL
    }

    /// Returns the number of breaches the password appears in (0 = not found).
    public func breachCount(password: String) async throws -> Int {
        let digest = Insecure.SHA1.hash(data: Data(password.utf8))
        let hex = digest.map { String(format: "%02X", $0) }.joined()
        let prefix = String(hex.prefix(5))
        let suffix = String(hex.dropFirst(5))

        guard let url = URL(string: baseURL + prefix) else { return 0 }
        var request = URLRequest(url: url)
        request.setValue("true", forHTTPHeaderField: "Add-Padding")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return Self.match(suffix: suffix, in: String(decoding: data, as: UTF8.self))
    }

    /// Parses "SUFFIX:COUNT" lines; padding entries have count 0.
    static func match(suffix: String, in body: String) -> Int {
        for line in body.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":")
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespaces).uppercased() == suffix {
                return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }
}
