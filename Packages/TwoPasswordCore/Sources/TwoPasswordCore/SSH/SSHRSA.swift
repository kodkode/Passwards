import Foundation
import Security

/// RSA signing for the SSH agent. CryptoKit has no RSA, so we import the
/// OpenSSH key components into a `SecKey` (PKCS#1) and sign with Security.
enum SSHRSA {
    /// Signs `data` with an RSA private key given its OpenSSH components
    /// (n, e, d, p, q, iqmp). `algorithm` selects the hash (ssh-rsa SHA-1 /
    /// rsa-sha2-256 / rsa-sha2-512). Returns the raw RSA signature.
    static func sign(data: Data, n: Data, e: Data, d: Data, p: Data, q: Data, iqmp: Data,
                     algorithm: SecKeyAlgorithm) throws -> Data {
        let key = try privateKey(n: n, e: e, d: d, p: p, q: q, iqmp: iqmp)
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, algorithm, data as CFData, &error) else {
            throw SSHWireError.malformedKey
        }
        return signature as Data
    }

    /// Builds a `SecKey` RSA private key from OpenSSH components, computing the
    /// CRT exponents (dP, dQ) that PKCS#1 requires but OpenSSH doesn't store.
    static func privateKey(n: Data, e: Data, d: Data, p: Data, q: Data, iqmp: Data) throws -> SecKey {
        let dBytes = [UInt8](d)
        let pMinus1 = SSHBigInt.decrement([UInt8](p))
        let qMinus1 = SSHBigInt.decrement([UInt8](q))
        let dP = SSHBigInt.mod(dBytes, pMinus1)
        let dQ = SSHBigInt.mod(dBytes, qMinus1)

        // PKCS#1 RSAPrivateKey ::= SEQUENCE { version, n, e, d, p, q, dP, dQ, qInv }
        let der = derSequence([
            derInteger([0]),
            derInteger([UInt8](n)),
            derInteger([UInt8](e)),
            derInteger([UInt8](d)),
            derInteger([UInt8](p)),
            derInteger([UInt8](q)),
            derInteger(dP),
            derInteger(dQ),
            derInteger([UInt8](iqmp)),
        ])
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(Data(der) as CFData, attributes as CFDictionary, &error) else {
            throw SSHWireError.malformedKey
        }
        return key
    }

    /// Public `SecKey` from (n, e) — PKCS#1 RSAPublicKey. Used by tests to verify.
    static func publicKey(n: Data, e: Data) throws -> SecKey {
        let der = derSequence([derInteger([UInt8](n)), derInteger([UInt8](e))])
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(Data(der) as CFData, attributes as CFDictionary, &error) else {
            throw SSHWireError.malformedKey
        }
        return key
    }

    // MARK: Minimal DER

    private static func derInteger(_ magnitude: [UInt8]) -> [UInt8] {
        var bytes = magnitude
        while bytes.count > 1 && bytes.first == 0 { bytes.removeFirst() }
        if let first = bytes.first, first & 0x80 != 0 { bytes.insert(0, at: 0) }  // keep positive
        return [0x02] + derLength(bytes.count) + bytes
    }

    private static func derSequence(_ elements: [[UInt8]]) -> [UInt8] {
        let body = elements.flatMap { $0 }
        return [0x30] + derLength(body.count) + body
    }

    private static func derLength(_ length: Int) -> [UInt8] {
        if length < 0x80 { return [UInt8(length)] }
        var value = length
        var bytes: [UInt8] = []
        while value > 0 { bytes.insert(UInt8(value & 0xFF), at: 0); value >>= 8 }
        return [0x80 | UInt8(bytes.count)] + bytes
    }
}
