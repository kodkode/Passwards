import Testing
import Foundation
import CryptoKit
@testable import TwoPasswordCore

@Suite("SSH key")
struct SSHKeyTests {
    // Fixtures generated with `ssh-keygen -t ed25519/ecdsa -N "" -C test@2password`.
    static let ed25519PEM = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACDBAa9UyQhtWFSqgrnQkMMOoiJ2hyXLtIb3AshJk+elAgAAAJjJFrbmyRa2
    5gAAAAtzc2gtZWQyNTUxOQAAACDBAa9UyQhtWFSqgrnQkMMOoiJ2hyXLtIb3AshJk+elAg
    AAAECFEorhnYfm4b7r4dKXBwmXMtcA0F+v6QP3H05NwntSKMEBr1TJCG1YVKqCudCQww6i
    InaHJcu0hvcCyEmT56UCAAAADnRlc3RAMnBhc3N3b3JkAQIDBAUGBw==
    -----END OPENSSH PRIVATE KEY-----
    """
    static let ed25519Blob = "AAAAC3NzaC1lZDI1NTE5AAAAIMEBr1TJCG1YVKqCudCQww6iInaHJcu0hvcCyEmT56UC"
    static let ed25519Fingerprint = "SHA256:7qEAOctgQrP5kAdXtRxYw1+eU9rElQ5dgnVyMdExBQA"

    static let ecdsaPEM = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAaAAAABNlY2RzYS
    1zaGEyLW5pc3RwMjU2AAAACG5pc3RwMjU2AAAAQQQkVMTBRO0KEa/sKNqzwWBGtfSFkdyR
    ERduKvSRfkPV0CpWTqYlQrCxmTdCKMbeydTU03QR5Y6K8pAwVR3S82ySAAAAqNYiwy3WIs
    MtAAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBCRUxMFE7QoRr+wo
    2rPBYEa19IWR3JERF24q9JF+Q9XQKlZOpiVCsLGZN0Ioxt7J1NTTdBHljorykDBVHdLzbJ
    IAAAAgJ9gHvJzYRu1Ttk6CktTMG5TZVVsSjekbi43lZqq9pvIAAAAOdGVzdEAycGFzc3dv
    cmQBAg==
    -----END OPENSSH PRIVATE KEY-----
    """
    static let ecdsaFingerprint = "SHA256:TijRGOohiaMFHMxKfSq0rMbAt2k28jTIW+/yuE2XrIU"

    @Test func parsesEd25519() throws {
        let key = try SSHKey.parseOpenSSHPrivateKey(Self.ed25519PEM)
        #expect(key.algorithm == .ed25519)
        #expect(key.comment == "test@2password")
        #expect(key.publicKeyBlob.base64EncodedString() == Self.ed25519Blob)
        #expect(key.fingerprintSHA256 == Self.ed25519Fingerprint)
    }

    @Test func ed25519SignatureVerifies() throws {
        let key = try SSHKey.parseOpenSSHPrivateKey(Self.ed25519PEM)
        let message = Data("the quick brown fox".utf8)
        let sigBlob = try key.sign(message)

        // SSH signature blob: string "ssh-ed25519" + string(64-byte raw sig).
        var reader = SSHWireReader(sigBlob)
        #expect(try reader.readStringUTF8() == "ssh-ed25519")
        let rawSignature = try reader.readString()

        // Recover the public key from the blob and verify.
        var pub = SSHWireReader(key.publicKeyBlob)
        _ = try pub.readString()  // "ssh-ed25519"
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: try pub.readString())
        #expect(publicKey.isValidSignature(rawSignature, for: message))
    }

    @Test func parsesAndSignsECDSAP256() throws {
        let key = try SSHKey.parseOpenSSHPrivateKey(Self.ecdsaPEM)
        #expect(key.algorithm == .ecdsaP256)
        #expect(key.fingerprintSHA256 == Self.ecdsaFingerprint)

        let message = Data("sign me".utf8)
        let sigBlob = try key.sign(message)
        var reader = SSHWireReader(sigBlob)
        #expect(try reader.readStringUTF8() == "ecdsa-sha2-nistp256")
        var inner = SSHWireReader(try reader.readString())
        let r = pad(try inner.readString(), to: 32)
        let s = pad(try inner.readString(), to: 32)

        var pub = SSHWireReader(key.publicKeyBlob)
        _ = try pub.readString()  // "ecdsa-sha2-nistp256"
        _ = try pub.readString()  // "nistp256"
        let point = try pub.readString()  // 0x04 || X || Y
        let publicKey = try P256.Signing.PublicKey(x963Representation: point)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: r + s)
        #expect(publicKey.isValidSignature(signature, for: message))
    }

    @Test func rejectsMalformedKeys() {
        #expect(throws: SSHWireError.self) {
            _ = try SSHKey.parseOpenSSHPrivateKey("not a key")
        }
        // Valid base64, but not the openssh-key-v1 container.
        #expect(throws: SSHWireError.self) {
            _ = try SSHKey.parseOpenSSHPrivateKey(
                "-----BEGIN OPENSSH PRIVATE KEY-----\nQUJDREVG\n-----END OPENSSH PRIVATE KEY-----")
        }
    }

    /// mpint magnitude → fixed-width big-endian (strip leading zero, left-pad).
    private func pad(_ data: Data, to width: Int) -> Data {
        var trimmed = Data(data.drop { $0 == 0 })
        if trimmed.count < width { trimmed = Data(repeating: 0, count: width - trimmed.count) + trimmed }
        return trimmed
    }
}
