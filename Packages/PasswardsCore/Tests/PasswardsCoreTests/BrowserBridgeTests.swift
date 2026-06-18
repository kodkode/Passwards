import Foundation
import Testing
import CryptoKit
@testable import PasswardsCore

@Suite("Browser bridge")
struct BrowserBridgeTests {

    // MARK: Framing

    @Test func framingRoundTripsAcrossChunkedDelivery() throws {
        let messages = [
            BrowserWireMessage(type: .pairRequest, publicKey: "AAAA"),
            BrowserWireMessage(type: .enc, seq: 7, payload: "BBBB"),
            BrowserWireMessage(type: .error, message: "nope"),
        ]
        var stream = Data()
        for m in messages { stream += try NativeMessageFraming.encodeMessage(m) }

        // Deliver in pathological 3-byte chunks.
        var buffer = Data()
        var decoded: [BrowserWireMessage] = []
        var offset = stream.startIndex
        while offset < stream.endIndex {
            let next = stream.index(offset, offsetBy: 3, limitedBy: stream.endIndex) ?? stream.endIndex
            buffer += stream[offset..<next]
            for frame in try NativeMessageFraming.drainFrames(from: &buffer) {
                decoded.append(try NativeMessageFraming.decodeMessage(frame))
            }
            offset = next
        }
        #expect(decoded == messages)
        #expect(buffer.isEmpty)
    }

    @Test func framingRejectsOversizedFrames() throws {
        var bogus = Data()
        var length = UInt32(50_000_000).littleEndian
        withUnsafeBytes(of: &length) { bogus.append(contentsOf: $0) }
        bogus += Data(repeating: 0, count: 8)
        #expect(throws: NativeMessageFraming.FramingError.self) {
            var buffer = bogus
            _ = try NativeMessageFraming.drainFrames(from: &buffer)
        }
    }

    // MARK: Pairing

    @Test func pairingDerivesSameSecretAndCodeOnBothSides() throws {
        let ext = Curve25519.KeyAgreement.PrivateKey()
        let app = Curve25519.KeyAgreement.PrivateKey()
        let extPub = ext.publicKey.rawRepresentation
        let appPub = app.publicKey.rawRepresentation

        let extSide = try BrowserChannelCrypto.pairing(
            myPrivateKey: ext, peerPublicKey: appPub, extensionPublicKey: extPub, appPublicKey: appPub)
        let appSide = try BrowserChannelCrypto.pairing(
            myPrivateKey: app, peerPublicKey: extPub, extensionPublicKey: extPub, appPublicKey: appPub)

        #expect(extSide.secret == appSide.secret)
        #expect(extSide.verificationCode == appSide.verificationCode)
        #expect(extSide.verificationCode.count == 6)
        #expect(extSide.verificationCode.allSatisfy { $0.isNumber })
    }

    @Test func pairingRejectsGarbagePublicKey() {
        let ext = Curve25519.KeyAgreement.PrivateKey()
        #expect(throws: BrowserChannelCrypto.ChannelError.invalidPublicKey) {
            _ = try BrowserChannelCrypto.pairing(
                myPrivateKey: ext, peerPublicKey: Data([1, 2, 3]),
                extensionPublicKey: Data(), appPublicKey: Data())
        }
    }

    // MARK: Session + sealed envelopes

    private func makeSession() throws -> (extToApp: SymmetricKey, appToExt: SymmetricKey,
                                          extToApp2: SymmetricKey, appToExt2: SymmetricKey) {
        let pairingSecret = SymmetricKey(size: .bits256)
        let extEph = Curve25519.KeyAgreement.PrivateKey()
        let appEph = Curve25519.KeyAgreement.PrivateKey()
        let extPub = extEph.publicKey.rawRepresentation
        let appPub = appEph.publicKey.rawRepresentation

        let extKeys = try BrowserChannelCrypto.sessionKeys(
            myEphemeral: extEph, peerEphemeralPublicKey: appPub, pairingSecret: pairingSecret,
            extensionEphemeralPublicKey: extPub, appEphemeralPublicKey: appPub)
        let appKeys = try BrowserChannelCrypto.sessionKeys(
            myEphemeral: appEph, peerEphemeralPublicKey: extPub, pairingSecret: pairingSecret,
            extensionEphemeralPublicKey: extPub, appEphemeralPublicKey: appPub)
        return (extKeys.extensionToApp, extKeys.appToExtension, appKeys.extensionToApp, appKeys.appToExtension)
    }

    @Test func sessionKeysAgreeAndDirectionsDiffer() throws {
        let keys = try makeSession()
        #expect(keys.extToApp == keys.extToApp2)
        #expect(keys.appToExt == keys.appToExt2)
        #expect(keys.extToApp != keys.appToExt)
    }

    @Test func wrongPairingSecretDerivesUselessKeys() throws {
        let extEph = Curve25519.KeyAgreement.PrivateKey()
        let appEph = Curve25519.KeyAgreement.PrivateKey()
        let extPub = extEph.publicKey.rawRepresentation
        let appPub = appEph.publicKey.rawRepresentation

        let honest = try BrowserChannelCrypto.sessionKeys(
            myEphemeral: extEph, peerEphemeralPublicKey: appPub, pairingSecret: SymmetricKey(size: .bits256),
            extensionEphemeralPublicKey: extPub, appEphemeralPublicKey: appPub)
        let impostor = try BrowserChannelCrypto.sessionKeys(
            myEphemeral: appEph, peerEphemeralPublicKey: extPub, pairingSecret: SymmetricKey(size: .bits256),
            extensionEphemeralPublicKey: extPub, appEphemeralPublicKey: appPub)

        let sealed = try BrowserChannelCrypto.seal(Data("hi".utf8), role: .extensionSide, seq: 0, key: honest.extensionToApp)
        #expect(throws: BrowserChannelCrypto.ChannelError.decryptFailed) {
            _ = try BrowserChannelCrypto.open(sealed, from: .extensionSide, expectedSeq: 0, key: impostor.extensionToApp)
        }
    }

    @Test func rpcRoundTripsThroughSealedEnvelope() throws {
        let keys = try makeSession()
        let request = BrowserRequest(id: 3, method: .credentialsQuery, url: "https://accounts.github.com/login")
        let sealed = try BrowserChannelCrypto.seal(
            JSONEncoder().encode(request), role: .extensionSide, seq: 12, key: keys.extToApp)
        let opened = try BrowserChannelCrypto.open(sealed, from: .extensionSide, expectedSeq: 12, key: keys.extToApp2)
        #expect(try JSONDecoder().decode(BrowserRequest.self, from: opened) == request)
    }

    @Test func replayedAndReorderedEnvelopesFail() throws {
        let keys = try makeSession()
        let sealed = try BrowserChannelCrypto.seal(Data("x".utf8), role: .app, seq: 5, key: keys.appToExt)

        // Replay: receiver has already advanced past seq 5.
        #expect(throws: BrowserChannelCrypto.ChannelError.sequenceMismatch) {
            _ = try BrowserChannelCrypto.open(sealed, from: .app, expectedSeq: 6, key: keys.appToExt2)
        }
        // Cross-direction: same seq sealed for the other direction must not open.
        #expect(throws: BrowserChannelCrypto.ChannelError.decryptFailed) {
            var forged = sealed
            forged.seq = 5
            _ = try BrowserChannelCrypto.open(forged, from: .extensionSide, expectedSeq: 5, key: keys.appToExt2)
        }
    }

    @Test func tamperedCiphertextFails() throws {
        let keys = try makeSession()
        var sealed = try BrowserChannelCrypto.seal(Data("secret".utf8), role: .extensionSide, seq: 0, key: keys.extToApp)
        var combined = Data(base64Encoded: sealed.payload!)!
        combined[combined.count - 1] ^= 0xFF
        sealed.payload = combined.base64EncodedString()
        #expect(throws: BrowserChannelCrypto.ChannelError.decryptFailed) {
            _ = try BrowserChannelCrypto.open(sealed, from: .extensionSide, expectedSeq: 0, key: keys.extToApp2)
        }
    }
}
