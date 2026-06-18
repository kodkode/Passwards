import Testing
import Foundation
import CryptoKit
import Security
@testable import PasswardsCore

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

    @Test func parsesKeyWithStrippedNewlines() throws {
        // A key pasted into a single-line field loses its newlines — must still parse.
        let collapsed = Self.ed25519PEM.replacingOccurrences(of: "\n", with: "")
        let key = try SSHKey.parseOpenSSHPrivateKey(collapsed)
        #expect(key.publicKeyBlob.base64EncodedString() == Self.ed25519Blob)
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

    static let rsaPEM = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABFwAAAAdzc2gtcn
    NhAAAAAwEAAQAAAQEAmoOhKUu3PHQeNZzxifvPzVEaHl1O+lUf7rmcy/VHbnt7fR3HLo2t
    3nUjuFIxiMa4plglvu4IMn1KGZJxoVIMuEMZJ/QNvhiEpg2BHVDrT5PSXqTQxcilU/jomX
    hYglUlrFg/P7ND9eWJAsyR89XZNNxGMLxysc9IGY3G76ddLvR5En5xeYHoUOE9NYQd7Gt7
    dUkGDTMie4c8BK0Iim++Vrm3xMFSQuHwCBe9BJ/Frs3p7k6hhHm2o6fgAXpUUOFpz9J1N4
    DMrb9hpbGubuLnI3otUFxNhmeRnKUfuRrUaWu3c/gEuqEc+zdlAdsTVNzeANwod9kmQpND
    5euRB3MX3QAAA8je7T6c3u0+nAAAAAdzc2gtcnNhAAABAQCag6EpS7c8dB41nPGJ+8/NUR
    oeXU76VR/uuZzL9Udue3t9Hccuja3edSO4UjGIxrimWCW+7ggyfUoZknGhUgy4Qxkn9A2+
    GISmDYEdUOtPk9JepNDFyKVT+OiZeFiCVSWsWD8/s0P15YkCzJHz1dk03EYwvHKxz0gZjc
    bvp10u9HkSfnF5gehQ4T01hB3sa3t1SQYNMyJ7hzwErQiKb75WubfEwVJC4fAIF70En8Wu
    zenuTqGEebajp+ABelRQ4WnP0nU3gMytv2Glsa5u4ucjei1QXE2GZ5GcpR+5GtRpa7dz+A
    S6oRz7N2UB2xNU3N4A3Ch32SZCk0Pl65EHcxfdAAAAAwEAAQAAAQBhVNd5TvO/BhpdhV51
    oAT3fcYpKHfuox65X3zQ0dJMW0afutlUjvTedAWrP0NquFtqlY45ZnINc/TwhNpFV40hqU
    q4azkY7RLqEwmpMOb5utFCwymr3UefzOSggDmo6AASP4igFMmTpSKYe8rYwXXQoY0peBv7
    u+ncBv4wysmdIHJfe6G2HuPtXZ4CJRNEHqjLcFgG2ktVZR5O3cZskiTfCTqeZvAKxHsP1J
    oOy2g3xL0pkCly3DJGz8NDkT108J9hFUleGHu00rcLu9DxFGXDhHN5Nx5VH8NKNaqfEVXl
    3SFM0dSq52pIgdb4dl3aeN1oymyvq9B9PGewOtUd5/IBAAAAgQCbAR6c+Plcimf8FQM5Vm
    lPiwV7qpJnQ2paga1DeFgEdo3721xEOsS9+ixWmygwa5eU1VvNHqOIGqmX+HkLOEjApW1p
    cRtJuKqNpuXzjovOpsri+PlFKYQCKW6lXTTjN1DaKnbt4/1lajthr/xALxxl32traC+nUS
    h8+NDDYbRllwAAAIEAyzvnsqeh77CgV2kduiqu+8WUuRsFSEs1u2kHtyMVUWydAJWjkKUE
    +YF2gZEwuz2OwJEwH8jn7Ut1UODmpxlnCOn7mpbwG/jARfVktFKrT18BT0PnLWkz0cXPGp
    9NgpMIDMKGaiIRLmcEZ3FYhsmk+nc5maGHxrduwxD28nG9n10AAACBAMKhhqiVjyuqaFP/
    6XdJ/llJ3N8ZOCBZk+MRs6jJl/5RF9y75w28qr3IrggwrqbO5va5Q/ewm66/egBh0MUL4k
    HhuUv5iIZO5iSyMvcj+pTJB1NGvOyxa5TdofgMk0o9aHP3/8LWJqrIYwozUVdgaF0RpQ3V
    yaR+RQ8636OVolKBAAAADnRlc3RAMnBhc3N3b3JkAQIDBA==
    -----END OPENSSH PRIVATE KEY-----
    """
    static let rsaFingerprint = "SHA256:jYojQWAg4Y2snoQacHYS7YwxKJ7sWs7m8+ZtT7URnHU"

    @Test func parsesAndSignsRSA() throws {
        let key = try SSHKey.parseOpenSSHPrivateKey(Self.rsaPEM)
        #expect(key.algorithm == .rsa)
        #expect(key.comment == "test@2password")
        #expect(key.fingerprintSHA256 == Self.rsaFingerprint)
        guard case let .rsa(n, e, _, _, _, _) = key.material else {
            Issue.record("expected RSA material"); return
        }
        let publicKey = try SSHRSA.publicKey(n: n, e: e)
        let message = Data("rsa sign me".utf8)

        // Honors the SIGN_REQUEST flags: rsa-sha2-256 (2) and rsa-sha2-512 (4),
        // and the resulting signature verifies under the corresponding hash.
        for (flags, format, secAlg): (UInt32, String, SecKeyAlgorithm) in [
            (2, "rsa-sha2-256", .rsaSignatureMessagePKCS1v15SHA256),
            (4, "rsa-sha2-512", .rsaSignatureMessagePKCS1v15SHA512),
        ] {
            let blob = try key.sign(message, flags: flags)
            var reader = SSHWireReader(blob)
            #expect(try reader.readStringUTF8() == format)
            let rawSignature = try reader.readString()
            var error: Unmanaged<CFError>?
            let valid = SecKeyVerifySignature(publicKey, secAlg, message as CFData, rawSignature as CFData, &error)
            #expect(valid, "RSA \(format) signature should verify")
        }
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
