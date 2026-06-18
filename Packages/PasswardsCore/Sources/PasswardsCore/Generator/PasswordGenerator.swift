import Foundation

/// The three generator modes of 1Password: random characters, memorable
/// word-based passphrases, and numeric PINs.
public enum PasswordGenerator {
    public static let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    public static let digits = Array("0123456789")
    public static let symbols = Array("!@#$%^&*()_+-=[]{};:,.<>?")

    // MARK: Random

    public struct RandomOptions: Sendable, Equatable {
        public var length: Int
        public var includeNumbers: Bool
        public var includeSymbols: Bool

        public init(length: Int = 20, includeNumbers: Bool = true, includeSymbols: Bool = true) {
            self.length = length.clamped(to: 8...100)
            self.includeNumbers = includeNumbers
            self.includeSymbols = includeSymbols
        }
    }

    public static func random(_ options: RandomOptions = RandomOptions()) -> String {
        var pool = letters
        var required: [Character] = []
        if options.includeNumbers {
            pool += digits
            required.append(SecureRandom.element(of: digits))
        }
        if options.includeSymbols {
            pool += symbols
            required.append(SecureRandom.element(of: symbols))
        }
        var chars = required
        while chars.count < options.length {
            chars.append(SecureRandom.element(of: pool))
        }
        SecureRandom.shuffle(&chars)
        return String(chars.prefix(options.length))
    }

    // MARK: Memorable

    public enum Separator: String, Sendable, CaseIterable, Identifiable {
        case hyphens, spaces, periods, commas, underscores, numbers, numbersAndSymbols

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .hyphens: "Hyphens"
            case .spaces: "Spaces"
            case .periods: "Periods"
            case .commas: "Commas"
            case .underscores: "Underscores"
            case .numbers: "Numbers"
            case .numbersAndSymbols: "Numbers and Symbols"
            }
        }

        func next() -> String {
            switch self {
            case .hyphens: "-"
            case .spaces: " "
            case .periods: "."
            case .commas: ","
            case .underscores: "_"
            case .numbers: String(SecureRandom.element(of: PasswordGenerator.digits))
            case .numbersAndSymbols: String(SecureRandom.element(of: PasswordGenerator.digits + PasswordGenerator.symbols))
            }
        }
    }

    public struct MemorableOptions: Sendable {
        public var wordCount: Int
        public var separator: Separator
        public var capitalize: Bool
        public var fullWords: Bool

        public init(wordCount: Int = 4, separator: Separator = .hyphens, capitalize: Bool = false, fullWords: Bool = true) {
            self.wordCount = wordCount.clamped(to: 3...15)
            self.separator = separator
            self.capitalize = capitalize
            self.fullWords = fullWords
        }
    }

    public static func memorable(_ options: MemorableOptions = MemorableOptions()) -> String {
        memorable(options, wordlist: Wordlist.words)
    }

    static func memorable(_ options: MemorableOptions, wordlist: [String]) -> String {
        // If the bundled EFF list (7,776 words) somehow failed to load, NEVER
        // emit a low-entropy passphrase from a tiny fallback list — fall back to
        // a strong random password instead. 2^128 needs ~10 words; require a
        // list large enough that the requested word count is actually secure.
        guard wordlist.count >= 2048 else {
            return random(RandomOptions(length: 24))
        }
        let words = (0..<options.wordCount).map { _ -> String in
            var word = SecureRandom.element(of: wordlist)
            if !options.fullWords {
                // Truncated mode: random 3-4 character syllable-ish chunks.
                word = String(word.prefix(3 + SecureRandom.int(below: 2)))
            }
            if options.capitalize {
                word = word.capitalized
            }
            return word
        }
        var result = ""
        for (index, word) in words.enumerated() {
            result += word
            if index < words.count - 1 {
                result += options.separator.next()
            }
        }
        return result
    }

    // MARK: PIN

    public static func pin(length: Int = 6) -> String {
        let count = length.clamped(to: 3...12)
        return String((0..<count).map { _ in SecureRandom.element(of: digits) })
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

/// EFF large wordlist (7,776 words), bundled.
public enum Wordlist {
    public static let words: [String] = {
        guard let url = Bundle.module.url(forResource: "eff_large_wordlist", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            // Empty, not a tiny stub: `memorable` detects this and degrades to a
            // strong random password rather than a guessable 4-word passphrase.
            return []
        }
        return content.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t")
            return parts.count == 2 ? String(parts[1]) : nil
        }
    }()
}
