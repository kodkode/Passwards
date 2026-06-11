import Foundation

/// Local password strength estimation (zxcvbn-style, simplified):
/// charset entropy with penalties for dictionary hits, repeats, sequences,
/// and keyboard runs. Used by the generator meter, onboarding, and Watchtower.
public enum PasswordStrength {
    public enum Score: Int, Sendable, Comparable, CaseIterable {
        case terrible = 0
        case weak = 1
        case fair = 2
        case good = 3
        case excellent = 4

        public static func < (lhs: Score, rhs: Score) -> Bool { lhs.rawValue < rhs.rawValue }

        public var label: String {
            switch self {
            case .terrible: "Terrible"
            case .weak: "Weak"
            case .fair: "Fair"
            case .good: "Good"
            case .excellent: "Excellent"
            }
        }
    }

    /// Top-100k breached password list, lowercased, loaded once.
    static let commonPasswords: Set<String> = {
        guard let url = Bundle.module.url(forResource: "top100k_passwords", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Set(content.split(separator: "\n").map { $0.lowercased() })
    }()

    public static func entropy(of password: String) -> Double {
        guard !password.isEmpty else { return 0 }
        var charsetSize = 0
        if password.contains(where: { $0.isLowercase }) { charsetSize += 26 }
        if password.contains(where: { $0.isUppercase }) { charsetSize += 26 }
        if password.contains(where: { $0.isNumber }) { charsetSize += 10 }
        if password.contains(where: { !$0.isLetter && !$0.isNumber }) { charsetSize += 25 }
        var bits = Double(password.count) * log2(Double(max(charsetSize, 2)))

        // Penalties
        bits -= repetitionPenalty(password)
        bits -= sequencePenalty(password)
        return max(bits, 0)
    }

    public static func score(_ password: String) -> Score {
        guard !password.isEmpty else { return .terrible }
        let lower = password.lowercased()
        if commonPasswords.contains(lower) { return .terrible }
        // Common password with trivial decoration (suffix digits / leading cap)
        let stripped = lower.trimmingCharacters(in: .decimalDigits)
        if stripped.count >= 4 && commonPasswords.contains(stripped) { return .weak }

        switch entropy(of: password) {
        case ..<28: return .terrible
        case ..<40: return .weak
        case ..<60: return .fair
        case ..<80: return .good
        default: return .excellent
        }
    }

    private static func repetitionPenalty(_ password: String) -> Double {
        var penalty = 0.0
        var previous: Character?
        var runLength = 1
        for char in password {
            if char == previous {
                runLength += 1
                if runLength > 2 { penalty += 4 }
            } else {
                runLength = 1
            }
            previous = char
        }
        // Distinct-character collapse: "abcabcabc" style
        let distinct = Set(password).count
        if distinct < password.count / 2 {
            penalty += Double(password.count - distinct * 2) * 2
        }
        return penalty
    }

    private static let sequences = [
        "abcdefghijklmnopqrstuvwxyz",
        "qwertyuiop", "asdfghjkl", "zxcvbnm",
        "0123456789",
    ]

    private static func sequencePenalty(_ password: String) -> Double {
        let lower = password.lowercased()
        var penalty = 0.0
        for seq in sequences {
            for length in stride(from: min(lower.count, 8), through: 3, by: -1) {
                for start in seq.indices.dropLast(length - 1) {
                    let end = seq.index(start, offsetBy: length)
                    let chunk = String(seq[start..<end])
                    if lower.contains(chunk) || lower.contains(String(chunk.reversed())) {
                        penalty += Double(length) * 3
                    }
                }
                if penalty > 0 { break }
            }
        }
        return penalty
    }
}
