import Foundation
import CryptoKit

/// RFC 6238 TOTP on top of CryptoKit HMAC.
public struct TOTPGenerator: Sendable, Equatable {
    public enum Algorithm: String, Sendable, Equatable {
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
    }

    public let secret: Data
    public let digits: Int
    public let period: Int
    public let algorithm: Algorithm

    public init(secret: Data, digits: Int = 6, period: Int = 30, algorithm: Algorithm = .sha1) {
        self.secret = secret
        self.digits = max(min(digits, 10), 4)
        self.period = max(period, 1)
        self.algorithm = algorithm
    }

    /// Builds a generator from either an otpauth:// URI or a bare Base32 secret.
    public init?(userInput: String) {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("otpauth://") {
            guard let parsed = OTPAuthURI.parse(trimmed) else { return nil }
            self = parsed.generator
        } else {
            guard let secret = Base32.decode(trimmed) else { return nil }
            self.init(secret: secret)
        }
    }

    public func code(at date: Date = Date()) -> String {
        let counter = UInt64(floor(date.timeIntervalSince1970 / Double(period)))
        return hotp(counter: counter)
    }

    /// Seconds until the current code rolls over.
    public func secondsRemaining(at date: Date = Date()) -> Int {
        let interval = Int(date.timeIntervalSince1970)
        return period - (interval % period)
    }

    func hotp(counter: UInt64) -> String {
        var bigEndian = counter.bigEndian
        let message = Data(bytes: &bigEndian, count: 8)
        let key = SymmetricKey(data: secret)
        let mac: Data
        switch algorithm {
        case .sha1: mac = Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256: mac = Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512: mac = Data(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }
        let offset = Int(mac[mac.count - 1] & 0x0F)
        let truncated = (UInt32(mac[offset] & 0x7F) << 24)
            | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8)
            | UInt32(mac[offset + 3])
        let modulo = UInt32(pow(10, Double(digits)))
        return String(format: "%0\(digits)d", truncated % modulo)
    }
}

/// otpauth://totp/Label?secret=...&issuer=...&digits=6&period=30&algorithm=SHA1
public enum OTPAuthURI {
    public struct Parsed: Sendable {
        public let generator: TOTPGenerator
        public let label: String
        public let issuer: String?
    }

    public static func parse(_ uri: String) -> Parsed? {
        guard let components = URLComponents(string: uri),
              components.scheme?.lowercased() == "otpauth",
              components.host?.lowercased() == "totp" else { return nil }
        let queryItems = components.queryItems ?? []
        func query(_ name: String) -> String? {
            queryItems.first { $0.name.lowercased() == name }?.value
        }
        guard let secretParam = query("secret"), let secret = Base32.decode(secretParam) else { return nil }
        let algorithm = TOTPGenerator.Algorithm(rawValue: (query("algorithm") ?? "SHA1").uppercased()) ?? .sha1
        let generator = TOTPGenerator(
            secret: secret,
            digits: Int(query("digits") ?? "") ?? 6,
            period: Int(query("period") ?? "") ?? 30,
            algorithm: algorithm
        )
        let label = components.path.dropFirst().removingPercentEncoding ?? ""
        return Parsed(generator: generator, label: String(label), issuer: query("issuer"))
    }
}

/// RFC 4648 Base32 decoding (tolerant: case-insensitive, ignores spaces/padding).
public enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    private static let lookup: [Character: UInt8] = {
        var map: [Character: UInt8] = [:]
        for (index, char) in alphabet.enumerated() {
            map[char] = UInt8(index)
            map[Character(char.lowercased())] = UInt8(index)
        }
        return map
    }()

    public static func decode(_ string: String) -> Data? {
        let cleaned = string.filter { $0 != "=" && $0 != " " && $0 != "-" }
        guard !cleaned.isEmpty else { return nil }
        var bits = 0
        var buffer: UInt32 = 0
        var output = Data()
        for char in cleaned {
            guard let value = lookup[char] else { return nil }
            buffer = (buffer << 5) | UInt32(value)
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((buffer >> UInt32(bits)) & 0xFF))
            }
        }
        return output
    }
}
