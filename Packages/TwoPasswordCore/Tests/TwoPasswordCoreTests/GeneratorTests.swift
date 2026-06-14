import Testing
import Foundation
@testable import TwoPasswordCore

@Suite("Password generator")
struct GeneratorTests {
    @Test func randomRespectsLengthAndCharsets() {
        for length in [8, 20, 50, 100] {
            let pw = PasswordGenerator.random(.init(length: length, includeNumbers: true, includeSymbols: true))
            #expect(pw.count == length)
            #expect(pw.contains { $0.isNumber })
            #expect(pw.contains { !$0.isLetter && !$0.isNumber })
        }
        let lettersOnly = PasswordGenerator.random(.init(length: 30, includeNumbers: false, includeSymbols: false))
        #expect(lettersOnly.allSatisfy { $0.isLetter })
    }

    @Test func lengthIsClamped() {
        #expect(PasswordGenerator.random(.init(length: 2)).count == 8)
        #expect(PasswordGenerator.random(.init(length: 500)).count == 100)
    }

    @Test func memorablePassphrases() {
        let pw = PasswordGenerator.memorable(.init(wordCount: 4, separator: .hyphens, capitalize: false, fullWords: true))
        let words = pw.split(separator: "-")
        #expect(words.count == 4)
        #expect(words.allSatisfy { Wordlist.words.contains(String($0)) })

        let capitalized = PasswordGenerator.memorable(.init(wordCount: 3, separator: .spaces, capitalize: true, fullWords: true))
        #expect(capitalized.split(separator: " ").allSatisfy { $0.first!.isUppercase })
    }

    @Test func wordlistLoaded() {
        #expect(Wordlist.words.count == 7776)
    }

    @Test func memorableDegradesWhenWordlistInadequate() {
        // If the bundled list ever failed to load, a passphrase must NOT fall
        // back to a tiny guessable word set — it degrades to a strong random
        // password (length 24) instead.
        let degraded = PasswordGenerator.memorable(
            .init(wordCount: 4, separator: .hyphens), wordlist: ["correct", "horse", "battery", "staple"])
        #expect(degraded.count == 24)
        // The real list still yields a proper multi-word passphrase.
        let real = PasswordGenerator.memorable(.init(wordCount: 4, separator: .hyphens))
        #expect(real.split(separator: "-").count == 4)
    }

    @Test func pinIsNumeric() {
        for length in [3, 6, 12] {
            let pin = PasswordGenerator.pin(length: length)
            #expect(pin.count == length)
            #expect(pin.allSatisfy { $0.isNumber })
        }
    }

    @Test func uniqueness() {
        let passwords = (0..<100).map { _ in PasswordGenerator.random(.init(length: 20)) }
        #expect(Set(passwords).count == 100)
    }
}

@Suite("Password strength")
struct StrengthTests {
    @Test func commonPasswordsScoreTerrible() {
        #expect(PasswordStrength.commonPasswords.count > 90_000)
        #expect(PasswordStrength.score("123456") == .terrible)
        #expect(PasswordStrength.score("password") == .terrible)
        #expect(PasswordStrength.score("qwerty") == .terrible)
    }

    @Test func generatedPasswordsScoreHighly() {
        #expect(PasswordStrength.score(PasswordGenerator.random(.init(length: 20))) == .excellent)
        #expect(PasswordStrength.score(PasswordGenerator.memorable(.init(wordCount: 5))) >= .good)
    }

    @Test func gradient() {
        #expect(PasswordStrength.score("") == .terrible)
        #expect(PasswordStrength.score("aaaaaaaaaaaa") == .terrible)
        #expect(PasswordStrength.score("zk9!Lm") < PasswordStrength.score("zk9!Lm#qR2vX$5"))
    }
}
