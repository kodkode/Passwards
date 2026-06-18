import Testing
import Foundation
import CryptoKit
@testable import PasswardsCore

@Suite("Key derivation")
struct KeyDerivationTests {
    @Test("PBKDF2-HMAC-SHA256 known vectors")
    func pbkdf2Vectors() throws {
        // Widely published PBKDF2-HMAC-SHA256 vectors (password/salt, dkLen 32).
        let cases: [(iterations: Int, expectedHex: String)] = [
            (1, "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"),
            (2, "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43"),
            (4096, "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a"),
        ]
        for c in cases {
            let out = try KeyDerivation.pbkdf2SHA256(
                password: Data("password".utf8),
                salt: Data("salt".utf8),
                iterations: c.iterations,
                outputByteCount: 32
            )
            #expect(out.hexString == c.expectedHex)
        }
    }

    @Test("HKDF-SHA256 RFC 5869 test case 1")
    func hkdfVector() {
        let ikm = Data(repeating: 0x0b, count: 22)
        let salt = Data((0...0x0c).map { UInt8($0) })
        let info = Data((0xf0...0xf9).map { UInt8($0) })
        let okm = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: salt, info: info, outputByteCount: 42
        )
        let expected = "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"
        #expect(okm.withUnsafeBytes { Data($0) }.hexString == expected)
    }

    @Test("AUK is deterministic and sensitive to every input")
    func aukDeterminism() throws {
        let sk = SecretKey(accountID: "ABC234", secret: String(repeating: "X", count: 26))
        let salt = Data(repeating: 7, count: 16)
        let derive = { (pw: String, email: String, key: SecretKey) in
            try KeyDerivation.deriveAccountUnlockKey(
                password: pw, email: email, salt: salt, secretKey: key, iterations: 1000
            ).withUnsafeBytes { Data($0) }
        }
        let base = try derive("hunter2", "a@b.com", sk)
        #expect(try derive("hunter2", "a@b.com", sk) == base)
        #expect(try derive("hunter3", "a@b.com", sk) != base)
        #expect(try derive("hunter2", "other@b.com", sk) != base)
        let sk2 = SecretKey(accountID: "ABC234", secret: String(repeating: "Y", count: 26))
        #expect(try derive("hunter2", "a@b.com", sk2) != base)
        // Email case-insensitivity and password NFKD normalization
        #expect(try derive("hunter2", "A@B.COM", sk) == base)
        #expect(try derive("caf\u{00E9}", "a@b.com", sk) == derive("cafe\u{0301}", "a@b.com", sk))
    }
}

@Suite("Secret key")
struct SecretKeyTests {
    @Test func generationAndFormat() throws {
        let key = try SecretKey.generate()
        #expect(key.accountID.count == 6)
        #expect(key.secret.count == 26)
        let formatted = key.formatted
        #expect(formatted.hasPrefix("A3-"))
        #expect(formatted.split(separator: "-").count == 7)
        #expect(formatted.split(separator: "-").map(\.count) == [2, 6, 6, 5, 5, 5, 5])
    }

    @Test func parsingRoundTrip() throws {
        let key = try SecretKey.generate()
        #expect(SecretKey(parsing: key.formatted) == key)
        #expect(SecretKey(parsing: key.formatted.lowercased()) == key)
        #expect(SecretKey(parsing: key.formatted.replacingOccurrences(of: "-", with: " ")) == key)
        #expect(SecretKey(parsing: "B4-AAAAAA-AAAAAA-AAAAA-AAAAA-AAAAA-AAAAA") == nil)
        #expect(SecretKey(parsing: "A3-SHORT") == nil)
        #expect(SecretKey(parsing: "A3-AAAAA0-AAAAAA-AAAAA-AAAAA-AAAAA-AAAAA") == nil) // '0' not in alphabet
    }

    @Test func uniqueness() throws {
        let keys = try (0..<50).map { _ in try SecretKey.generate().formatted }
        #expect(Set(keys).count == 50)
    }
}

@Suite("Encrypted blobs")
struct EncryptedBlobTests {
    @Test func roundTrip() throws {
        let key = EncryptedBlob.generateKey()
        let plaintext = Data("attack at dawn".utf8)
        let sealed = try EncryptedBlob.seal(plaintext, key: key, aad: "item:123")
        #expect(try EncryptedBlob.open(sealed, key: key, aad: "item:123") == plaintext)
    }

    @Test("AAD swap fails — ciphertext can't move between records")
    func aadSwapFails() throws {
        let key = EncryptedBlob.generateKey()
        let sealed = try EncryptedBlob.seal(Data("secret".utf8), key: key, aad: "item:123")
        #expect(throws: CryptoError.self) {
            try EncryptedBlob.open(sealed, key: key, aad: "item:456")
        }
    }

    @Test func wrongKeyFails() throws {
        let sealed = try EncryptedBlob.seal(Data("secret".utf8), key: EncryptedBlob.generateKey(), aad: "x")
        #expect(throws: CryptoError.self) {
            try EncryptedBlob.open(sealed, key: EncryptedBlob.generateKey(), aad: "x")
        }
    }

    @Test func tamperedCiphertextFails() throws {
        let key = EncryptedBlob.generateKey()
        var sealed = try EncryptedBlob.seal(Data("secret".utf8), key: key, aad: "x")
        sealed[sealed.count / 2] ^= 0xFF
        #expect(throws: CryptoError.self) {
            try EncryptedBlob.open(sealed, key: key, aad: "x")
        }
    }

    @Test func keyWrapping() throws {
        let outer = EncryptedBlob.generateKey()
        let inner = EncryptedBlob.generateKey()
        let wrapped = try EncryptedBlob.wrapKey(inner, under: outer, aad: "vault:v1")
        let unwrapped = try EncryptedBlob.unwrapKey(wrapped, under: outer, aad: "vault:v1")
        #expect(unwrapped == inner)
    }
}

@Suite("Account crypto")
struct AccountCryptoTests {
    @Test("create → unlock → lock → unlock round trip")
    func fullRoundTrip() throws {
        let account = try AccountCrypto.createAccount(email: "m@example.com", password: "correct horse", iterations: 1000)
        let unlocked = try AccountCrypto.unlock(record: account.record, password: "correct horse", secretKey: account.secretKey)
        #expect(unlocked == account.masterKey)
    }

    @Test func wrongPasswordFails() throws {
        let account = try AccountCrypto.createAccount(email: "m@example.com", password: "right", iterations: 1000)
        #expect(throws: CryptoError.self) {
            try AccountCrypto.unlock(record: account.record, password: "wrong", secretKey: account.secretKey)
        }
    }

    @Test func wrongSecretKeyFails() throws {
        let account = try AccountCrypto.createAccount(email: "m@example.com", password: "pw", iterations: 1000)
        let other = try SecretKey.generate()
        #expect(throws: CryptoError.self) {
            try AccountCrypto.unlock(record: account.record, password: "pw", secretKey: other)
        }
    }

    @Test func passwordChange() throws {
        let account = try AccountCrypto.createAccount(email: "m@example.com", password: "old", iterations: 1000)
        let newRecord = try AccountCrypto.changePassword(
            record: account.record, masterKey: account.masterKey, newPassword: "new", secretKey: account.secretKey
        )
        #expect(try AccountCrypto.unlock(record: newRecord, password: "new", secretKey: account.secretKey) == account.masterKey)
        #expect(throws: CryptoError.self) {
            try AccountCrypto.unlock(record: newRecord, password: "old", secretKey: account.secretKey)
        }
    }

    @Test("full-iteration derivation stays under 2 seconds", .timeLimit(.minutes(1)))
    func derivationBenchmark() throws {
        let account = try AccountCrypto.createAccount(email: "m@example.com", password: "benchmark")
        let start = ContinuousClock.now
        _ = try AccountCrypto.unlock(record: account.record, password: "benchmark", secretKey: account.secretKey)
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(2))
    }
}

@Suite("KeyStore")
struct KeyStoreTests {
    @Test func vaultAndItemKeyFlow() async throws {
        let store = KeyStore()
        let masterKey = EncryptedBlob.generateKey()
        await store.setMasterKey(masterKey)

        let vaultKey = EncryptedBlob.generateKey()
        let encVaultKey = try EncryptedBlob.wrapKey(vaultKey, under: masterKey, aad: "vault:v1")
        let resolved = try await store.vaultKey(vaultID: "v1", encVaultKey: encVaultKey)
        #expect(resolved == vaultKey)

        let itemKey = EncryptedBlob.generateKey()
        let encItemKey = try EncryptedBlob.wrapKey(itemKey, under: vaultKey, aad: "item:i1")
        let resolvedItem = try await store.itemKey(itemID: "i1", encItemKey: encItemKey, vaultID: "v1", encVaultKey: encVaultKey)
        #expect(resolvedItem == itemKey)

        await store.lock()
        #expect(await store.isUnlocked == false)
        await #expect(throws: CryptoError.self) {
            _ = try await store.vaultKey(vaultID: "v1", encVaultKey: encVaultKey)
        }
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
