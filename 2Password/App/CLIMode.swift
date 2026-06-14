import Foundation
import TwoPasswordCore

/// Headless CLI: the same binary, invoked from a terminal with a subcommand
/// instead of launching the GUI. Focused on the SSH agent — setup help and
/// listing the public keys it serves (public-key only; the vault is never
/// touched by the CLI, only by the running app behind the agent socket).
nonisolated enum CLIMode {
    /// First-argument subcommands that switch the binary into CLI mode.
    static let commands: Set<String> = [
        "ssh-agent", "ssh-keys", "help", "--help", "-h", "version", "--version", "-v",
    ]

    static func run(_ arguments: [String]) -> Never {
        switch arguments.first {
        case "ssh-agent":            printAgentInfo()
        case "ssh-keys":             listKeys()
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
          ssh-agent    Print the SSH agent socket path and the SSH_AUTH_SOCK export line.
          ssh-keys     List the public keys the SSH agent is serving (authorized_keys form).
                       Requires the agent enabled in Settings → SSH Agent and the vault unlocked.
          version      Print the version.
          help         Show this help.
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

    private static func errorOut(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
