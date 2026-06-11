import Foundation
import CryptoKit
import LocalAuthentication
import Security

/// Touch ID unlock: the master key is wrapped to a Secure Enclave P-256 key
/// gated on the current biometric set. Re-enrolling fingerprints invalidates
/// the SE key, which we detect and surface as `.invalidated` so callers can
/// fall back to the password path and re-enroll.
public enum BiometricUnlock {
    static let keyTag = "com.michael.twopassword.se-unlock-key"
    static let wrappedService = "com.michael.twopassword.biometric-wrapped"

    public enum UnlockResult: Sendable {
        case success(SymmetricKey)
        case userCancelled
        case invalidated   // biometric set changed; re-enroll needed
        case unavailable
    }

    public static var isAvailable: Bool {
        var error: NSError?
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    public static var isEnrolled: Bool {
        KeychainStore.loadBlob(service: wrappedService, account: "master") != nil
    }

    /// Wraps and stores the master key. Replaces any previous enrollment.
    public static func enroll(masterKey: SymmetricKey) throws {
        disable()
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            nil
        ) else { throw CryptoError.secureEnclaveFailed }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: Data(keyTag.utf8),
                kSecAttrAccessControl as String: access,
            ],
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw CryptoError.secureEnclaveFailed
        }
        let keyData = masterKey.withUnsafeBytes { Data($0) }
        guard let wrapped = SecKeyCreateEncryptedData(
            publicKey,
            .eciesEncryptionCofactorVariableIVX963SHA256AESGCM,
            keyData as CFData,
            &error
        ) else { throw CryptoError.secureEnclaveFailed }
        try KeychainStore.saveBlob(wrapped as Data, service: wrappedService, account: "master")
    }

    /// Prompts Touch ID and unwraps the master key.
    public static func unlock(reason: String = "unlock 2Password") async -> UnlockResult {
        guard let wrapped = KeychainStore.loadBlob(service: wrappedService, account: "master") else {
            return .unavailable
        }
        let context = LAContext()
        context.localizedReason = reason
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) else {
                return .userCancelled
            }
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .appCancel, .systemCancel: return .userCancelled
            case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout: return .unavailable
            default: return .userCancelled
            }
        } catch {
            return .userCancelled
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(keyTag.utf8),
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
            kSecUseAuthenticationContext as String: context,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            // SE key gone (e.g. biometric set changed) — treat as invalidated.
            return .invalidated
        }
        let privateKey = result as! SecKey
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCreateDecryptedData(
            privateKey,
            .eciesEncryptionCofactorVariableIVX963SHA256AESGCM,
            wrapped as CFData,
            &error
        ) else {
            return .invalidated
        }
        return .success(SymmetricKey(data: keyData as Data))
    }

    public static func disable() {
        KeychainStore.deleteBlob(service: wrappedService, account: "master")
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(keyTag.utf8),
        ]
        SecItemDelete(query as CFDictionary)
    }
}
