import Testing
import Foundation
@testable import PasswardsCore

@Suite("TOTP")
struct TOTPTests {
    /// RFC 6238 Appendix B vectors (8 digits). Seeds per algorithm.
    @Test func rfc6238Vectors() {
        let sha1Seed = Data("12345678901234567890".utf8)
        let sha256Seed = Data("12345678901234567890123456789012".utf8)
        let sha512Seed = Data("1234567890123456789012345678901234567890123456789012345678901234".utf8)

        let cases: [(time: TimeInterval, algorithm: TOTPGenerator.Algorithm, seed: Data, expected: String)] = [
            (59, .sha1, sha1Seed, "94287082"),
            (59, .sha256, sha256Seed, "46119246"),
            (59, .sha512, sha512Seed, "90693936"),
            (1111111109, .sha1, sha1Seed, "07081804"),
            (1111111109, .sha256, sha256Seed, "68084774"),
            (1111111111, .sha256, sha256Seed, "67062674"),
            (1111111111, .sha512, sha512Seed, "99943326"),
            (1234567890, .sha512, sha512Seed, "93441116"),
            (2000000000, .sha1, sha1Seed, "69279037"),
            (20000000000, .sha512, sha512Seed, "47863826"),
        ]
        for c in cases {
            let generator = TOTPGenerator(secret: c.seed, digits: 8, period: 30, algorithm: c.algorithm)
            #expect(generator.code(at: Date(timeIntervalSince1970: c.time)) == c.expected)
        }
    }

    @Test func base32Decoding() {
        // RFC 4648 vectors
        #expect(Base32.decode("MZXW6YTBOI======") == Data("foobar".utf8))
        #expect(Base32.decode("MZXW6YTB") == Data("fooba".utf8))
        #expect(Base32.decode("mzxw6ytboi") == Data("foobar".utf8)) // lowercase + no padding
        #expect(Base32.decode("MZXW 6YTB OI") == Data("foobar".utf8)) // spaces
        #expect(Base32.decode("1nvalid!") == nil)
    }

    @Test func otpauthURIParsing() throws {
        let uri = "otpauth://totp/GitHub:michael?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&digits=6&period=30&algorithm=SHA1"
        let parsed = try #require(OTPAuthURI.parse(uri))
        #expect(parsed.issuer == "GitHub")
        #expect(parsed.label == "GitHub:michael")
        #expect(parsed.generator.digits == 6)
        #expect(parsed.generator.period == 30)
        let code = parsed.generator.code()
        #expect(code.count == 6)
        #expect(code.allSatisfy { $0.isNumber })
    }

    @Test func userInputAcceptsBareSecretAndURI() throws {
        let fromSecret = try #require(TOTPGenerator(userInput: "JBSWY3DPEHPK3PXP"))
        let fromURI = try #require(TOTPGenerator(userInput: "otpauth://totp/x?secret=JBSWY3DPEHPK3PXP"))
        let now = Date()
        #expect(fromSecret.code(at: now) == fromURI.code(at: now))
        #expect(TOTPGenerator(userInput: "not a secret!!") == nil)
    }

    @Test func largeDigitsClampInsteadOfCrashing() throws {
        // Regression: digits >= 10 previously trapped — UInt32(pow(10,10))
        // overflows — at code-generation time, so a single malformed otpauth
        // URI crashed the app whenever that item was viewed.
        let seed = Data("12345678901234567890".utf8)
        for d in [10, 99, 1_000_000] {
            let gen = TOTPGenerator(secret: seed, digits: d, period: 30, algorithm: .sha1)
            #expect(gen.digits == 9)
            let code = gen.code(at: Date(timeIntervalSince1970: 59))
            #expect(code.count == 9)
            #expect(code.allSatisfy { $0.isNumber })
        }
        // Lower bound still clamps up to the 4-digit floor.
        #expect(TOTPGenerator(secret: seed, digits: 1).digits == 4)
        // The exact crashing input — an otpauth URI with digits=10 — must now
        // parse and generate a code rather than trap.
        let gen = try #require(TOTPGenerator(userInput:
            "otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&digits=10"))
        #expect(gen.digits == 9)
        #expect(gen.code().count == 9)
    }

    @Test func nineDigitBoundaryDoesNotOverflow() {
        // 10^9 (1_000_000_000) is < UInt32.max; must produce a full 9-digit code.
        let gen = TOTPGenerator(secret: Data("12345678901234567890".utf8),
                                digits: 9, period: 30, algorithm: .sha1)
        let code = gen.code(at: Date(timeIntervalSince1970: 59))
        #expect(code.count == 9)
        #expect(code.allSatisfy { $0.isNumber })
    }

    @Test func countdown() {
        let generator = TOTPGenerator(secret: Data("x".utf8))
        let remaining = generator.secondsRemaining(at: Date(timeIntervalSince1970: 59))
        #expect(remaining == 1)
        #expect(generator.secondsRemaining(at: Date(timeIntervalSince1970: 60)) == 30)
    }
}
