import SwiftUI
import UIKit
import CryptoKit
import PasswardsCore
import PasswardsOrchestration

/// Fetches website icons directly from the site (no third-party proxy that would
/// learn vault domains), caching to disk. Falls back to nil so callers show the
/// category icon. iOS port of the macOS `FaviconLoader` — same SSRF guard.
actor IOSFaviconLoader {
    static let shared = IOSFaviconLoader()

    private var memoryCache: [String: UIImage?] = [:]
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let cacheDirectory: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("FaviconCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.richIconsEnabled) as? Bool ?? true
    }

    func icon(forURLString urlString: String) async -> UIImage? {
        guard Self.enabled, let host = Self.host(from: urlString) else { return nil }
        if let cached = memoryCache[host] { return cached }
        if let running = inFlight[host] { return await running.value }

        let task = Task<UIImage?, Never> { [cacheDirectory] in
            let cacheFile = cacheDirectory.appendingPathComponent(Self.cacheKey(host))
            if let data = try? Data(contentsOf: cacheFile), let image = UIImage(data: data) {
                return image
            }
            let hostVariants = host.hasPrefix("www.") ? [host] : [host, "www.\(host)"]
            for hostVariant in hostVariants {
                for path in ["apple-touch-icon.png", "favicon.ico"] {
                    guard let url = URL(string: "https://\(hostVariant)/\(path)") else { continue }
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 8
                    guard let (data, response) = try? await URLSession.shared.data(for: request),
                          let http = response as? HTTPURLResponse, http.statusCode == 200,
                          data.count > 100,
                          let image = UIImage(data: data) else { continue }
                    try? data.write(to: cacheFile)
                    return image
                }
            }
            return nil
        }
        inFlight[host] = task
        let image = await task.value
        inFlight[host] = nil
        memoryCache[host] = image
        return image
    }

    static func host(from urlString: String) -> String? {
        let candidate = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
        guard let host = URL(string: candidate)?.host()?.lowercased(),
              host.contains("."), isPublicHost(host) else { return nil }
        return host
    }

    /// Refuses hosts that would turn a favicon fetch into an SSRF probe of the
    /// local network or a cloud metadata endpoint. (Mirrors macOS `FaviconLoader`.)
    static func isPublicHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") { return false }
        if host.contains(":") { return false }
        let parts = host.split(separator: ".")
        let octets = parts.compactMap { Int($0) }
        guard parts.count == 4, octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else {
            return true
        }
        let a = octets[0], b = octets[1]
        if a == 0 || a == 10 || a == 127 { return false }
        if a == 169 && b == 254 { return false }
        if a == 172 && (16...31).contains(b) { return false }
        if a == 192 && b == 168 { return false }
        if a == 100 && (64...127).contains(b) { return false }
        if a >= 224 { return false }
        return true
    }

    private static func cacheKey(_ host: String) -> String {
        SHA256.hash(data: Data(host.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Async favicon image with rounded-rect framing; nil → category icon fallback.
struct FaviconView: View {
    let urlString: String
    let fallback: PasswardsCore.Category
    var size: CGFloat = 40

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.78, height: size * 0.78)
                    .frame(width: size, height: size)
                    .background(.white, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    }
            } else {
                CategoryIcon(category: fallback, size: size)
            }
        }
        .task(id: urlString) {
            image = await IOSFaviconLoader.shared.icon(forURLString: urlString)
        }
    }
}
