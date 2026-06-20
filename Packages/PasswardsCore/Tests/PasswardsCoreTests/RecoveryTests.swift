import Testing
import Foundation
import CryptoKit
import CloudKit
@testable import PasswardsCore

private func bytes(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }

@Suite("Recovery code")
struct RecoveryCodeTests {
    @Test("enableRecovery → recover round-trips master key and Secret Key")
    func roundTrip() throws {
        let account = try AccountCrypto.createAccount(email: "t@example.com", password: "pw", iterations: 1000)
        let (code, blob, encCode) = try AccountCrypto.enableRecovery(
            masterKey: account.masterKey, secretKey: account.secretKey, accountID: account.record.accountID
        )
        let recovered = try AccountCrypto.recover(recoveryBlob: blob, code: code, accountID: account.record.accountID)
        #expect(bytes(recovered.masterKey) == bytes(account.masterKey))
        #expect(recovered.secretKey == account.secretKey)

        // The stored code can be revealed again under the master key.
        let revealed = try AccountCrypto.revealRecoveryCode(
            encRecoveryCode: encCode, masterKey: account.masterKey, accountID: account.record.accountID
        )
        #expect(revealed == code.formatted)
    }

    @Test("Wrong recovery code fails to open the blob")
    func wrongCode() throws {
        let account = try AccountCrypto.createAccount(email: "t@example.com", password: "pw", iterations: 1000)
        let (_, blob, _) = try AccountCrypto.enableRecovery(
            masterKey: account.masterKey, secretKey: account.secretKey, accountID: account.record.accountID
        )
        let wrong = try RecoveryCode.generate()
        #expect(throws: CryptoError.self) {
            _ = try AccountCrypto.recover(recoveryBlob: blob, code: wrong, accountID: account.record.accountID)
        }
    }

    @Test("Blob is bound to its account ID (AAD)")
    func aadBinding() throws {
        let account = try AccountCrypto.createAccount(email: "t@example.com", password: "pw", iterations: 1000)
        let (code, blob, _) = try AccountCrypto.enableRecovery(
            masterKey: account.masterKey, secretKey: account.secretKey, accountID: account.record.accountID
        )
        #expect(throws: CryptoError.self) {
            _ = try AccountCrypto.recover(recoveryBlob: blob, code: code, accountID: "OTHER1")
        }
    }

    @Test("Recovery code survives a password change")
    func survivesPasswordChange() throws {
        let account = try AccountCrypto.createAccount(email: "t@example.com", password: "old-pw", iterations: 1000)
        let (code, blob, encCode) = try AccountCrypto.enableRecovery(
            masterKey: account.masterKey, secretKey: account.secretKey, accountID: account.record.accountID
        )
        // Persist the recovery fields onto the key record, then change the password.
        let withRecovery = AccountCrypto.AccountKeyRecord(
            accountID: account.record.accountID, email: account.record.email,
            kdfSalt: account.record.kdfSalt, kdfIterations: account.record.kdfIterations,
            encMasterKey: account.record.encMasterKey,
            recoveryEnabled: true, recoveryBlob: blob, encRecoveryCode: encCode
        )
        let changed = try AccountCrypto.changePassword(
            record: withRecovery, masterKey: account.masterKey, newPassword: "new-pw", secretKey: account.secretKey
        )
        // changePassword forwards the recovery material untouched.
        #expect(changed.recoveryEnabled)
        #expect(changed.recoveryBlob == blob)
        #expect(changed.encRecoveryCode == encCode)
        // And the (unchanged) recovery code still opens it.
        let recovered = try AccountCrypto.recover(recoveryBlob: changed.recoveryBlob!, code: code, accountID: changed.accountID)
        #expect(bytes(recovered.masterKey) == bytes(account.masterKey))
        // The new password (with the recovered Secret Key) unlocks the new record.
        let unlocked = try AccountCrypto.unlock(record: changed, password: "new-pw", secretKey: recovered.secretKey)
        #expect(bytes(unlocked) == bytes(account.masterKey))
    }

    @Test("Full forgotten-password recovery flow then unlock with new password")
    func endToEnd() throws {
        let account = try AccountCrypto.createAccount(email: "t@example.com", password: "forgotten", iterations: 1000)
        let (code, blob, _) = try AccountCrypto.enableRecovery(
            masterKey: account.masterKey, secretKey: account.secretKey, accountID: account.record.accountID
        )
        // User forgot "forgotten"; recover with the code, then set "fresh-pw".
        let recovered = try AccountCrypto.recover(recoveryBlob: blob, code: code, accountID: account.record.accountID)
        let newRecord = try AccountCrypto.changePassword(
            record: account.record, masterKey: recovered.masterKey, newPassword: "fresh-pw", secretKey: recovered.secretKey
        )
        let unlocked = try AccountCrypto.unlock(record: newRecord, password: "fresh-pw", secretKey: recovered.secretKey)
        #expect(bytes(unlocked) == bytes(account.masterKey))
        // The old password no longer works.
        #expect(throws: CryptoError.self) {
            _ = try AccountCrypto.unlock(record: newRecord, password: "forgotten", secretKey: recovered.secretKey)
        }
    }
}

@Suite("RecoveryCode format")
struct RecoveryCodeFormatTests {
    @Test("Generated code has the expected shape and entropy alphabet")
    func generated() throws {
        let code = try RecoveryCode.generate()
        #expect(code.secret.count == RecoveryCode.length)
        #expect(code.secret.allSatisfy { RecoveryCode.alphabet.contains($0) })
        #expect(code.formatted.hasPrefix("RC-"))
    }

    @Test("Parsing tolerates dashes, spaces, and lowercase")
    func parsing() throws {
        let code = try RecoveryCode.generate()
        let messy = "  " + code.formatted.lowercased().replacingOccurrences(of: "-", with: " ") + " "
        let parsed = try #require(RecoveryCode(parsing: messy))
        #expect(parsed == code)
    }

    @Test("Round-trips through formatted")
    func formattedRoundTrip() throws {
        let code = try RecoveryCode.generate()
        #expect(RecoveryCode(parsing: code.formatted) == code)
    }

    @Test("Rejects malformed input")
    func rejects() {
        #expect(RecoveryCode(parsing: "") == nil)
        #expect(RecoveryCode(parsing: "A3-ABCDEF-GHJKMN") == nil)        // wrong prefix
        #expect(RecoveryCode(parsing: "RC-SHORT") == nil)               // too short
        #expect(RecoveryCode(parsing: "RC-" + String(repeating: "1", count: 30)) == nil) // '1' not in alphabet
    }
}

@Suite("Recovery storage + sync")
struct RecoveryStorageTests {
    private let zoneID = CKRecordZone.ID(zoneName: SyncEngine.zoneName)

    @Test("CKRecord round-trips recovery fields")
    func ckRoundTrip() throws {
        let original = AccountRecord(
            id: "ABC234", email: "m@example.com",
            kdfSalt: Data(repeating: 1, count: 16), kdfIterations: 1000,
            encMasterKey: Data(repeating: 2, count: 60), createdAt: Date(),
            recoveryEnabled: true,
            recoveryBlob: Data(repeating: 7, count: 80),
            encRecoveryCode: Data(repeating: 8, count: 40)
        )
        let record = RecordCoder.record(for: original, recordID: CKRecord.ID(recordName: "account", zoneID: zoneID))
        let decoded = try #require(RecordCoder.accountKeyRecord(from: record))
        #expect(decoded.recoveryEnabled)
        #expect(decoded.recoveryBlob == original.recoveryBlob)
        #expect(decoded.encRecoveryCode == original.encRecoveryCode)
    }

    @Test("A CKRecord without recovery fields decodes as disabled (backward-compatible)")
    func ckBackwardCompatible() throws {
        let record = CKRecord(recordType: "Account", recordID: CKRecord.ID(recordName: "account", zoneID: zoneID))
        record["accountID"] = "ABC234"
        record["email"] = "m@example.com"
        record["kdfSalt"] = Data(repeating: 1, count: 16)
        record["kdfIterations"] = 1000
        record["encMasterKey"] = Data(repeating: 2, count: 60)
        let decoded = try #require(RecordCoder.accountKeyRecord(from: record))
        #expect(decoded.recoveryEnabled == false)
        #expect(decoded.recoveryBlob == nil)
        #expect(decoded.encRecoveryCode == nil)
    }

    @Test("Repository enable/disable updates account row (and the v4 columns exist)")
    func repositoryFlow() async throws {
        // Build an environment that retains the Secret Key (TestEnvironment hides it).
        let database = try AppDatabase.inMemory()
        let keyStore = KeyStore()
        let account = try AccountCrypto.createAccount(email: "t@example.com", password: "pw", iterations: 1000)
        await keyStore.setMasterKey(account.masterKey)
        let vaults = VaultRepository(database: database, keyStore: keyStore)
        try await vaults.saveAccount(account.record)
        let id = account.record.accountID

        // Enable recovery and persist via the repository (also proves the v4 columns exist).
        let (code, blob, encCode) = try AccountCrypto.enableRecovery(
            masterKey: account.masterKey, secretKey: account.secretKey, accountID: id
        )
        try await vaults.setRecoveryFields(recoveryBlob: blob, encRecoveryCode: encCode, accountID: id)
        var row = try #require(await vaults.account())
        #expect(row.recoveryEnabled)
        #expect(row.recoveryBlob == blob)

        // Recover from the stored row.
        let recovered = try AccountCrypto.recover(recoveryBlob: row.recoveryBlob!, code: code, accountID: id)
        #expect(bytes(recovered.masterKey) == bytes(account.masterKey))

        // saveAccount (e.g. a password change) preserves the recovery fields.
        let rekeyed = try AccountCrypto.changePassword(
            record: row.keyRecord, masterKey: account.masterKey, newPassword: "new", secretKey: account.secretKey
        )
        try await vaults.saveAccount(rekeyed)
        row = try #require(await vaults.account())
        #expect(row.recoveryEnabled)
        #expect(row.recoveryBlob == blob)

        // Disable overwrites the blobs with random bytes and flips the flag.
        let tombstone = try AccountCrypto.recoveryTombstone()
        try await vaults.disableRecovery(tombstone: tombstone, accountID: id)
        row = try #require(await vaults.account())
        #expect(row.recoveryEnabled == false)
        #expect(row.recoveryBlob == tombstone)
        // The old code can no longer open the tombstoned blob.
        #expect(throws: CryptoError.self) {
            _ = try AccountCrypto.recover(recoveryBlob: row.recoveryBlob!, code: code, accountID: id)
        }
    }
}
