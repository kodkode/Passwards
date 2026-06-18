import AppKit
import SwiftUI
import CryptoKit

/// Fetches website icons directly from the site (no third-party proxy that
/// would learn vault domains), caching to disk. Falls back to nil so callers
/// show the category icon instead.
actor FaviconLoader {
    static let shared = FaviconLoader()

    private var memoryCache: [String: NSImage?] = [:]
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private let cacheDirectory: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("FaviconCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.richIconsEnabled) as? Bool ?? true
    }

    func icon(forURLString urlString: String) async -> NSImage? {
        guard Self.enabled, let host = Self.host(from: urlString) else { return nil }
        if let cached = memoryCache[host] { return cached }
        if let running = inFlight[host] { return await running.value }

        let task = Task<NSImage?, Never> { [cacheDirectory] in
            let cacheFile = cacheDirectory.appendingPathComponent(Self.cacheKey(host))
            if let data = try? Data(contentsOf: cacheFile), let image = NSImage(data: data) {
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
                          // Some sites answer 404s with a 200 HTML page; NSImage
                          // would reject it, but skip the obvious case cheaply.
                          !data.prefix(64).contains(UInt8(ascii: "<")) || NSImage(data: data) != nil,
                          let image = NSImage(data: data), image.isValid else { continue }
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

    func clearCache() {
        memoryCache.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    static func host(from urlString: String) -> String? {
        let candidate = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
        guard let host = URL(string: candidate)?.host()?.lowercased(),
              host.contains("."), isPublicHost(host) else { return nil }
        return host
    }

    /// Refuses hosts that would turn a favicon fetch into an SSRF probe of the
    /// local network or a cloud metadata endpoint (e.g. an imported item whose
    /// URL is `http://169.254.169.254/` or `http://192.168.1.1/`). Blocks
    /// loopback/private/link-local/reserved IPv4 literals, any IPv6 literal, and
    /// localhost/.local names. (Literal check only — it does not resolve DNS, so
    /// a name pointing at a private IP isn't covered; favicons are best-effort.)
    static func isPublicHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") { return false }
        if host.contains(":") { return false }   // IPv6 literal — refuse outright
        let parts = host.split(separator: ".")
        let octets = parts.compactMap { Int($0) }
        guard parts.count == 4, octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else {
            return true   // a normal DNS hostname, not an IPv4 literal
        }
        let a = octets[0], b = octets[1]
        if a == 0 || a == 10 || a == 127 { return false }      // this-net, private, loopback
        if a == 169 && b == 254 { return false }               // link-local + cloud metadata
        if a == 172 && (16...31).contains(b) { return false }  // private
        if a == 192 && b == 168 { return false }               // private
        if a == 100 && (64...127).contains(b) { return false } // CGNAT
        if a >= 224 { return false }                           // multicast / reserved
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
    var size: CGFloat = 32

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
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
                CategoryIconView(category: fallback, size: size)
            }
        }
        .task(id: urlString) {
            image = await FaviconLoader.shared.icon(forURLString: urlString)
        }
    }
}

import PasswardsCore
