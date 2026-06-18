import Testing
import Foundation
import CryptoKit
@testable import TwoPasswordCore

@Suite("SSH agent protocol")
struct SSHAgentTests {
    /// Backend backed by a single parsed SSH key.
    struct OneKeyBackend: SSHAgentBackend {
        let key: SSHKey
        func identities() async -> [(blob: Data, comment: String)] {
            [(key.publicKeyBlob, key.comment)]
        }
        func sign(keyBlob: Data, data: Data, flags: UInt32) async -> Data? {
            keyBlob == key.publicKeyBlob ? try? key.sign(data, flags: flags) : nil
        }
    }

    private func backend() throws -> OneKeyBackend {
        OneKeyBackend(key: try SSHKey.parseOpenSSHPrivateKey(SSHKeyTests.ed25519PEM))
    }

    @Test func requestIdentitiesListsKeys() async throws {
        let backend = try backend()
        let response = await SSHAgentProtocol.handle(Data([11]), backend: backend)  // REQUEST_IDENTITIES

        var reader = SSHWireReader(response)
        #expect(try reader.readByte() == 12)            // SSH_AGENT_IDENTITIES_ANSWER
        #expect(try reader.readUInt32() == 1)
        #expect(try reader.readString() == backend.key.publicKeyBlob)
        #expect(try reader.readStringUTF8() == "test@2password")
    }

    @Test func signRequestProducesVerifiableSignature() async throws {
        let backend = try backend()
        let data = Data("challenge bytes".utf8)

        var request = SSHWireWriter()
        request.writeByte(13)                            // SSH_AGENTC_SIGN_REQUEST
        request.writeString(backend.key.publicKeyBlob)
        request.writeString(data)
        request.writeUInt32(0)                           // flags
        let response = await SSHAgentProtocol.handle(request.data, backend: backend)

        var reader = SSHWireReader(response)
        #expect(try reader.readByte() == 14)             // SSH_AGENT_SIGN_RESPONSE
        var sig = SSHWireReader(try reader.readString())
        #expect(try sig.readStringUTF8() == "ssh-ed25519")
        let rawSignature = try sig.readString()

        var pub = SSHWireReader(backend.key.publicKeyBlob)
        _ = try pub.readString()
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: try pub.readString())
        #expect(publicKey.isValidSignature(rawSignature, for: data))
    }

    @Test func signRequestForUnknownKeyFails() async throws {
        let backend = try backend()
        var request = SSHWireWriter()
        request.writeByte(13)
        request.writeString(Data("not a real key blob".utf8))
        request.writeString(Data("data".utf8))
        request.writeUInt32(0)
        let response = await SSHAgentProtocol.handle(request.data, backend: backend)
        #expect(response == Data([5]))                   // SSH_AGENT_FAILURE
    }

    @Test func unknownRequestFails() async throws {
        let response = await SSHAgentProtocol.handle(Data([99]), backend: try backend())
        #expect(response == Data([5]))
    }

    @Test func endToEndOverUnixSocket() async throws {
        // Full path: real NWListener server ⇄ real POSIX client over a Unix
        // socket, with a real key. Short /tmp path stays under the 104-byte
        // sockaddr_un limit.
        let key = try SSHKey.parseOpenSSHPrivateKey(SSHKeyTests.ed25519PEM)
        let path = "/tmp/2pw-ssh-\(UUID().uuidString.prefix(8)).sock"
        let server = SSHAgentServer(socketPath: path, backend: OneKeyBackend(key: key))
        try await server.start()
        try await Task.sleep(for: .milliseconds(300))  // let the listener bind

        // The client blocks on POSIX reads, so run it off the test's executor.
        let identities = await Task.detached { SSHAgentClient.listIdentities(socketPath: path) }.value
        await server.stop()

        let list = try #require(identities)
        #expect(list.count == 1)
        #expect(list[0].keyType == "ssh-ed25519")
        #expect(list[0].fingerprintSHA256 == SSHKeyTests.ed25519Fingerprint)
    }

    @Test func clientParsesIdentitiesAnswer() async throws {
        // The client (used by the CLI) parses exactly what the server emits.
        let backend = try backend()
        let answer = await SSHAgentProtocol.handle(Data([11]), backend: backend)
        let identities = try #require(SSHAgentClient.parseIdentitiesAnswer(answer))
        #expect(identities.count == 1)
        #expect(identities[0].keyType == "ssh-ed25519")
        #expect(identities[0].comment == "test@2password")
        #expect(identities[0].fingerprintSHA256 == SSHKeyTests.ed25519Fingerprint)
        #expect(identities[0].authorizedKeyLine == backend.key.authorizedKeyLine)
    }
}
