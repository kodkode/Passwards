import Foundation

/// Client side of the CLI control channel: encodes a `CLIRequest`, sends it over
/// the Unix socket, and decodes the `CLIResponse`. Blocking — for the one-shot
/// `passwards` CLI process.
public enum CLIControlClient {
    public static func send(_ request: CLIRequest, socketPath: String) -> CLIResponse? {
        guard let body = try? JSONEncoder().encode(request),
              let response = UnixSocketClient.request(body, socketPath: socketPath),
              let decoded = try? JSONDecoder().decode(CLIResponse.self, from: response) else { return nil }
        return decoded
    }
}
