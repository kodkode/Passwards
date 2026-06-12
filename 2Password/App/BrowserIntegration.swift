import Foundation
import TwoPasswordCore

/// Installs Chrome native-messaging host manifests so Chromium browsers can
/// launch this binary in `--browser-host` mode. The sandbox grants write
/// access only to each browser's NativeMessagingHosts directory (see the
/// temporary-exception entitlements).
nonisolated enum BrowserIntegration {
    static let hostName = "com.michael.twopassword"
    /// Pinned by the "key" entry in the extension's manifest.json.
    static let extensionID = "pijjbphhjoehicfedodffoboeidfgpcn"

    struct Browser: Identifiable {
        let id: String
        let name: String
        /// NativeMessagingHosts directory, relative to home.
        let hostsPath: String

        var hostsDirectory: URL {
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(hostsPath, isDirectory: true)
        }

        var manifestURL: URL {
            hostsDirectory.appendingPathComponent("\(BrowserIntegration.hostName).json")
        }
    }

    static let known: [Browser] = [
        Browser(id: "chrome", name: "Google Chrome",
                hostsPath: "Library/Application Support/Google/Chrome/NativeMessagingHosts"),
        Browser(id: "brave", name: "Brave",
                hostsPath: "Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"),
        Browser(id: "edge", name: "Microsoft Edge",
                hostsPath: "Library/Application Support/Microsoft Edge/NativeMessagingHosts"),
        Browser(id: "arc", name: "Arc",
                hostsPath: "Library/Application Support/Arc/User Data/NativeMessagingHosts"),
        Browser(id: "vivaldi", name: "Vivaldi",
                hostsPath: "Library/Application Support/Vivaldi/NativeMessagingHosts"),
        Browser(id: "chromium", name: "Chromium",
                hostsPath: "Library/Application Support/Chromium/NativeMessagingHosts"),
    ]

    /// Browsers whose profile actually exists on this Mac.
    static var detected: [Browser] {
        known.filter { FileManager.default.fileExists(atPath: $0.hostsDirectory.path) }
    }

    enum Status {
        case notInstalled
        /// Manifest exists but points at a different binary (e.g. the app moved).
        case stale
        case installed
    }

    static func status(for browser: Browser) -> Status {
        guard let data = try? Data(contentsOf: browser.manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .notInstalled
        }
        return manifest["path"] as? String == currentExecutablePath ? .installed : .stale
    }

    private static var currentExecutablePath: String {
        Bundle.main.executableURL!.resolvingSymlinksInPath().path
    }

    static func install(for browser: Browser) throws {
        let manifest: [String: Any] = [
            "name": hostName,
            "description": "2Password browser integration",
            "path": currentExecutablePath,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(extensionID)/"],
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: browser.manifestURL)
    }

    static func uninstall(for browser: Browser) {
        try? FileManager.default.removeItem(at: browser.manifestURL)
    }
}
