import SwiftUI
import UIKit
import ImageIO
import CryptoKit
import PasswardsCore
import PasswardsOrchestration

/// Fetches website icons directly from the site (no third-party proxy that would
/// learn vault domains). Discovers the real icon by parsing the page's
/// `<link rel="…icon…">` tags (largest `sizes` wins), then falls back to
/// `/apple-touch-icon.png`, `-precomposed.png`, and `/favicon.ico`. Decodes via
/// ImageIO so multi-size `.ico` works, caching a normalized PNG to disk + memory.
/// Falls back to nil so callers show the category tile.
///
/// SSRF-guarded on EVERY hop: the initial host, every HTML-discovered icon URL,
/// and every HTTP redirect target must pass `isPublicHost`. iOS port of the macOS
/// `FaviconLoader`, extended with HTML discovery, ImageIO decoding, and redirect
/// hardening.
actor IOSFaviconLoader {
    static let shared = IOSFaviconLoader()

    private var memoryCache: [String: UIImage?] = [:]      // incl. negative (nil) entries → no re-probe
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let cacheDirectory: URL
    private let session: URLSession

    private static let htmlMaxBytes = 256 * 1024
    private static let iconMaxBytes = 1_000_000
    private static let thumbnailMaxPixels = 384            // crisp at ≤52pt @3x, small in cache
    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("FaviconCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 12
        cfg.httpMaximumConnectionsPerHost = 4
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Redirect guard closes the "public host 302s to a private IP" SSRF vector.
        session = URLSession(configuration: cfg, delegate: SSRFRedirectGuard(), delegateQueue: nil)
    }

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.richIconsEnabled) as? Bool ?? true
    }

    func icon(forURLString urlString: String) async -> UIImage? {
        guard Self.enabled, let host = Self.host(from: urlString) else { return nil }
        if let cached = memoryCache[host] { return cached }
        if let running = inFlight[host] { return await running.value }

        let task = Task<UIImage?, Never> { [cacheDirectory, session] in
            await Self.resolve(host: host, cacheDirectory: cacheDirectory, session: session)
        }
        inFlight[host] = task
        let image = await task.value
        inFlight[host] = nil
        memoryCache[host] = image      // caches misses too
        return image
    }

    func clearCache() {
        memoryCache.removeAll()
        inFlight.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Resolution (nonisolated statics; run off the actor, Sendable-clean)

    private static func resolve(host: String, cacheDirectory: URL, session: URLSession) async -> UIImage? {
        let cacheFile = cacheDirectory.appendingPathComponent(cacheKey(host))
        if let data = try? Data(contentsOf: cacheFile), let img = decodeBestFrame(data) { return img }

        var image = await bestIcon(host: host, session: session)

        // Subdomain with no icon of its own (auth0.openai.com, account.live.com…):
        // fall back to the registrable domain's icon — the brand mark the user expects.
        if image == nil,
           let reg = WatchtowerAuditor.registrableDomain("https://\(host)"),
           reg != host, isPublicHost(reg) {
            image = await bestIcon(host: reg, session: session)
        }

        if let image, let png = image.pngData() { try? png.write(to: cacheFile) }   // normalize cache
        return image
    }

    /// Walks the candidate list (best declared size first) and returns the first icon
    /// that is actually sharp (≥ `crispPixels`). A small icon that decodes early no
    /// longer wins over a large apple-touch-icon later in the list — it is kept only
    /// as a last resort if nothing crisp exists.
    private static let crispPixels = 96
    private static func bestIcon(host: String, session: URLSession) async -> UIImage? {
        var fallback: UIImage? = nil
        for url in await candidateIconURLs(host: host, session: session) {
            // Re-gate every URL immediately before fetching (defence in depth).
            guard let h = url.host()?.lowercased(), isPublicHost(h) else { continue }
            guard let data = await fetchBounded(url, maxBytes: iconMaxBytes, session: session),
                  data.count > 70, let img = decodeBestFrame(data) else { continue }
            if Int(max(img.size.width, img.size.height)) >= crispPixels { return img }
            if fallback.map({ img.size.width > $0.size.width }) ?? true { fallback = img }
        }
        return fallback
    }

    // MARK: Candidate discovery

    /// Best-first candidate icon URLs: HTML-declared links (largest `sizes` first)
    /// then the well-known fallback paths, across the bare host and its `www.` variant.
    private static func candidateIconURLs(host: String, session: URLSession) async -> [URL] {
        let hostVariants = host.hasPrefix("www.") ? [host] : [host, "www.\(host)"]

        var discovered: [(url: URL, score: Int)] = []
        for hv in hostVariants {
            guard isPublicHost(hv), let base = URL(string: "https://\(hv)/") else { continue }
            guard let data = await fetchBounded(base, maxBytes: htmlMaxBytes, session: session) else { continue }
            let html = String(decoding: data, as: UTF8.self)
            let links = parseIconLinks(html: html, base: base)
            if !links.isEmpty { discovered = links; break }    // first responding host wins
        }
        discovered.sort { $0.score > $1.score }

        var urls = discovered.map(\.url)
        for hv in hostVariants {
            for path in ["apple-touch-icon.png", "apple-touch-icon-precomposed.png", "favicon.ico"] {
                if let u = URL(string: "https://\(hv)/\(path)") { urls.append(u) }
            }
        }

        // https-only + public-host + dedupe, order preserved.
        var seen = Set<String>()
        return urls.filter { url in
            guard let scheme = url.scheme?.lowercased(), scheme == "https",
                  let h = url.host()?.lowercased(), isPublicHost(h) else { return false }
            return seen.insert(url.absoluteString).inserted
        }
    }

    /// Parses `<link rel="apple-touch-icon"|"apple-touch-icon-precomposed"|"icon"|
    /// "shortcut icon">` from `<head>`, honoring `sizes` (largest dimension) and
    /// resolving relative hrefs against `base`. Largest-first.
    private static func parseIconLinks(html: String, base: URL) -> [(url: URL, score: Int)] {
        // Scan only the <head> region (where icon links live); bounds the regex work.
        let head: String = html.range(of: "</head>", options: .caseInsensitive)
            .map { String(html[html.startIndex..<$0.lowerBound]) } ?? html
        guard let linkRE = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: [.caseInsensitive])
        else { return [] }

        let ns = head as NSString
        let iconRels: Set<String> = ["icon", "shortcut", "apple-touch-icon", "apple-touch-icon-precomposed"]
        var out: [(URL, Int)] = []
        for m in linkRE.matches(in: head, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: m.range)
            guard let rel = attr("rel", in: tag)?.lowercased() else { continue }
            let rels = Set(rel.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init))
            guard !rels.isDisjoint(with: iconRels) else { continue }   // "shortcut icon" contains "icon"
            guard let href = attr("href", in: tag)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !href.isEmpty,
                  let resolved = URL(string: href, relativeTo: base)?.absoluteURL else { continue }

            var score = 0
            if let sizes = attr("sizes", in: tag)?.lowercased() {
                if sizes.contains("any") {
                    score = 1024                                        // scalable / SVG — prefer highly
                } else {
                    for token in sizes.split(separator: " ") {
                        if let d = token.split(separator: "x").compactMap({ Int($0) }).max() {
                            score = max(score, d)
                        }
                    }
                }
            }
            if score == 0 {
                score = (rels.contains("apple-touch-icon") || rels.contains("apple-touch-icon-precomposed"))
                    ? 180 : 32                                          // apple-touch ≈180px, opaque
            }
            out.append((resolved, score))
        }
        return out
    }

    /// One HTML attribute value from a tag (double / single / unquoted).
    private static func attr(_ name: String, in tag: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))",
            options: [.caseInsensitive]) else { return nil }
        let ns = tag as NSString
        guard let m = re.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)) else { return nil }
        for g in 1...3 {
            let r = m.range(at: g)
            if r.location != NSNotFound { return ns.substring(with: r) }
        }
        return nil
    }

    // MARK: Networking (bounded, streaming)

    /// Streams up to `maxBytes` then stops — bounds HTML scans (~256KB) and icon
    /// downloads (~1MB) so a giant page/asset can't blow memory. 8s timeout, browser UA.
    private static func fetchBounded(_ url: URL, maxBytes: Int, session: URLSession) async -> Data? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml,image/*;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        guard let (bytes, response) = try? await session.bytes(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        var data = Data()
        data.reserveCapacity(min(maxBytes, 64 * 1024))
        do {
            for try await b in bytes {
                data.append(b)
                if data.count >= maxBytes { break }
            }
        } catch {
            return data.isEmpty ? nil : data
        }
        return data.isEmpty ? nil : data
    }

    // MARK: Decode (ImageIO → multi-size .ico; largest frame; bounded thumbnail)

    private static func decodeBestFrame(_ data: Data) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { return nil }                 // HTML "200" 404 pages → 0 frames → rejected

        var bestIndex = 0, bestPixels = -1
        for i in 0..<count {
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let w = (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0
            let h = (props?[kCGImagePropertyPixelHeight] as? Int) ?? 0
            if w * h > bestPixels { bestPixels = w * h; bestIndex = i }
        }

        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixels,   // no upscale past native
        ]
        if let cg = CGImageSourceCreateThumbnailAtIndex(src, bestIndex, opts as CFDictionary),
           cg.width >= 16, cg.height >= 16 {
            return UIImage(cgImage: cg, scale: 1, orientation: .up)
        }
        if let cg = CGImageSourceCreateImageAtIndex(src, bestIndex, nil), cg.width >= 16, cg.height >= 16 {
            return UIImage(cgImage: cg, scale: 1, orientation: .up)
        }
        return nil
    }

    // MARK: SSRF guard (mirrors macOS `FaviconLoader`; applied to every fetched URL)

    static func host(from urlString: String) -> String? {
        let candidate = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
        guard let host = URL(string: candidate)?.host()?.lowercased(),
              host.contains("."), isPublicHost(host) else { return nil }
        return host
    }

    /// Refuses hosts that would turn a favicon fetch into an SSRF probe of the local
    /// network or a cloud metadata endpoint. Blocks loopback/private/link-local/
    /// reserved IPv4 literals, any IPv6 literal, and localhost/.local names.
    static func isPublicHost(_ host: String) -> Bool {
        if host.isEmpty { return false }
        if host == "localhost" || host.hasSuffix(".local") { return false }
        if host.contains(":") { return false }                  // IPv6 literal — refuse outright
        let parts = host.split(separator: ".")
        let octets = parts.compactMap { Int($0) }
        guard parts.count == 4, octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else {
            return true                                         // a normal DNS hostname
        }
        let a = octets[0], b = octets[1]
        if a == 0 || a == 10 || a == 127 { return false }
        if a == 169 && b == 254 { return false }                // link-local + cloud metadata
        if a == 172 && (16...31).contains(b) { return false }
        if a == 192 && b == 168 { return false }
        if a == 100 && (64...127).contains(b) { return false }  // CGNAT
        if a >= 224 { return false }                            // multicast / reserved
        return true
    }

    private static func cacheKey(_ host: String) -> String {
        SHA256.hash(data: Data(host.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Refuses HTTP redirects that would leave a public host for a private / link-local
/// one — closes the redirect-based SSRF hole a host precheck alone misses. `nonisolated`
/// so it is constructible from the actor's `init` and callable on URLSession's
/// background delegate queue under MainActor-default isolation. Holds no mutable state.
private nonisolated final class SSRFRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let url = request.url, let host = url.host()?.lowercased(),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              IOSFaviconLoader.isPublicHost(host) else { return nil }   // cancel the redirect
        return request
    }
}

/// The stateless favicon leaf: renders a resolved `UIImage` on a white rounded tile.
/// No `@State`, no `.task`, no `UIViewRepresentable` — the image is owned by
/// `IOSVaultModel` and passed in as a plain value, so nothing here can be reset by
/// Home's re-render churn or by the same item appearing in two sections. Deterministic
/// sizing on iOS 18 and 26.
struct FaviconImage: View {
    let image: UIImage
    var size: CGFloat = 40

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.25, style: .continuous) }

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: .fit)
            .frame(width: size * 0.68, height: size * 0.68)
            .frame(width: size, height: size)
            .background(.white, in: shape)
            .overlay(shape.strokeBorder(Color(uiColor: .separator), lineWidth: 0.5))
            .clipShape(shape)
    }
}
