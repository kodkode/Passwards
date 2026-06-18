import Foundation
import TwoPasswordCore

/// Headless CLI: the same binary, invoked from a terminal with a subcommand
/// instead of launching the GUI. Focused on the SSH agent — setup help and
/// listing the public keys it serves (public-key only; the vault is never
/// touched by the CLI, only by the running app behind the agent socket).
nonisolated enum CLIMode {
    /// First-argument subcommands that switch the binary into CLI mode.
    static let commands: Set<String> = [
        "ssh-agent", "ssh-keys", "item", "read", "help", "--help", "-h", "version", "--version", "-v",
    ]

    static func run(_ arguments: [String]) -> Never {
        switch arguments.first {
        case "ssh-agent":            printAgentInfo()
        case "ssh-keys":             listKeys()
        case "item":                 runItem(Array(arguments.dropFirst()))
        case "read":                 runRead(Array(arguments.dropFirst()))
        case "version", "--version", "-v": print("2password \(appVersion)")
        default:                     printHelp()
        }
        exit(0)
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private static func printHelp() {
        print("""
        2password — command line

        Usage: 2password <command>

        Commands:
          ssh-agent          Print the SSH agent socket path and the SSH_AUTH_SOCK export line.
          ssh-keys           List the public keys the SSH agent is serving (authorized_keys form).
          item list          List vault items (id, title, username, category).
          item get <item> [field]
                             Read a field (default: password) from an item by id or title.
                             Prompts Touch ID. e.g. 2password item get GitHub
          read op://item/field
                             Read a field via a secret reference. Prompts Touch ID.
          version            Print the version.
          help               Show this help.

        item/read require Command-Line Access (Settings → Advanced) and the vault unlocked.
        """)
    }

    private static func printAgentInfo() {
        let path = SSHAgentServer.defaultSocketPath()
        print(path)
        print("export SSH_AUTH_SOCK=\"\(path)\"")
    }

    private static func listKeys() {
        guard let identities = SSHAgentClient.listIdentities(socketPath: SSHAgentServer.defaultSocketPath()) else {
            errorOut("Couldn't reach the 2Password SSH agent.\nEnable it in Settings → SSH Agent, and make sure 2Password is unlocked.")
        }
        if identities.isEmpty {
            FileHandle.standardError.write(Data("# No SSH keys are being served (is the vault unlocked, with SSH Key items?).\n".utf8))
            return
        }
        for identity in identities {
            print(identity.authorizedKeyLine)                                  // stdout: pipeable
            FileHandle.standardError.write(Data("  \(identity.fingerprintSHA256)\n".utf8))  // stderr: human note
        }
    }

    // MARK: item / read (control channel)

    private static func runItem(_ args: [String]) {
        switch args.first {
        case "list":
            let response = control(CLIRequest(command: .list))
            guard let items = response.items else { errorOut(response.error ?? "no response") }
            if items.isEmpty { print("# No items."); return }
            for item in items {
                print("\(item.id)\t\(item.title)\t\(item.username)\t\(item.category)")
            }
        case "get":
            guard args.count >= 2 else { errorOut("usage: 2password item get <item> [field]") }
            let response = control(CLIRequest(command: .get, query: args[1], field: args.count >= 3 ? args[2] : nil))
            emitValue(response)
        default:
            errorOut("usage: 2password item <list|get>")
        }
    }

    private static func runRead(_ args: [String]) {
        guard let refString = args.first, let ref = SecretReference.parse(refString) else {
            errorOut("usage: 2password read op://[vault/]item/field")
        }
        emitValue(control(CLIRequest(command: .get, query: ref.item, field: ref.field)))
    }

    /// Print a `get` value to stdout (pipeable); the item/field context to stderr.
    private static func emitValue(_ response: CLIResponse) {
        guard let value = response.value else { errorOut(response.error ?? "no value") }
        if let title = response.itemTitle, let label = response.fieldLabel {
            FileHandle.standardError.write(Data("# \(label) for \(title)\n".utf8))
        }
        print(value)
    }

    private static func control(_ request: CLIRequest) -> CLIResponse {
        guard let response = CLIControlClient.send(request, socketPath: CLIControlServer.defaultSocketPath()) else {
            errorOut("Couldn't reach 2Password. Enable Settings → Advanced → Command-Line Access, and unlock the app.")
        }
        return response
    }

    private static func errorOut(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
