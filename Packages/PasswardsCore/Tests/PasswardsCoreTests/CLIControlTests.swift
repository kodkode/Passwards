import Testing
import Foundation
@testable import PasswardsCore

@Suite("CLI control")
struct CLIControlTests {
    struct MockBackend: CLIControlBackend {
        func handle(_ request: CLIRequest) async -> CLIResponse {
            switch request.command {
            case .list:
                return CLIResponse(items: [CLIItemSummary(id: "1", title: "GitHub", username: "me", category: "login")])
            case .get:
                guard request.query == "GitHub" else { return CLIResponse(error: "no item matching “\(request.query ?? "")”") }
                return CLIResponse(value: "hunter2", itemTitle: "GitHub", fieldLabel: request.field ?? "password")
            }
        }
    }

    @Test func secretReferenceParsing() {
        #expect(SecretReference.parse("op://Personal/GitHub/password")
                == SecretReference(vault: "Personal", item: "GitHub", field: "password"))
        #expect(SecretReference.parse("op://GitHub/password")
                == SecretReference(vault: nil, item: "GitHub", field: "password"))
        #expect(SecretReference.parse("op://GitHub") == nil)        // too few components
        #expect(SecretReference.parse("op://a//c") == nil)          // empty component
        #expect(SecretReference.parse("https://x/y/z") == nil)      // wrong scheme
    }

    @Test func endToEndOverUnixSocket() async throws {
        let path = "/tmp/2pw-cli-\(UUID().uuidString.prefix(8)).sock"
        let server = CLIControlServer(socketPath: path, backend: MockBackend())
        try await server.start()
        try await Task.sleep(for: .milliseconds(300))

        let list = await Task.detached {
            CLIControlClient.send(CLIRequest(command: .list), socketPath: path)
        }.value
        #expect(list?.items?.count == 1)
        #expect(list?.items?.first?.title == "GitHub")

        let got = await Task.detached {
            CLIControlClient.send(CLIRequest(command: .get, query: "GitHub", field: "password"), socketPath: path)
        }.value
        await server.stop()

        #expect(got?.value == "hunter2")
        #expect(got?.fieldLabel == "password")
    }
}
