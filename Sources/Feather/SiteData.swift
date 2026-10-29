import Foundation
import WebKit

/// Groups hosts into sites ("www.youtube.com" and "m.youtube.com" are both "youtube.com") and
/// ranks them by how often you visit them.
enum SiteRank {
    /// Second-level labels that sit under a country code, as in "bbc.co.uk".
    private static let countrySecondLevels: Set<String> = ["co", "com", "ac", "org", "net", "gov", "edu", "ne", "or"]

    /// Resources that a site loads from its own CDN, cached along with the site itself.
    /// googlevideo.com (YouTube's video segments) is left out on purpose: it is the bulk of the cache.
    static let companions: [String: [String]] = [
        "youtube.com": ["ytimg.com", "ggpht.com"],
        "google.com": ["gstatic.com", "googleapis.com", "googleusercontent.com"],
        "gmail.com": ["gstatic.com", "googleusercontent.com"],
    ]

    static func site(for host: String) -> String {
        var labels = host.lowercased().split(separator: ".").map(String.init)
        if labels.last == "" { labels.removeLast() }
        guard labels.count > 2 else { return labels.joined(separator: ".") }
        let keep = labels[labels.count - 1].count == 2 && countrySecondLevels.contains(labels[labels.count - 2]) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }

    /// The `limit` most visited sites, most visited first (ties go to the most recent visit).
    static func topSites(in entries: [HistoryEntry], limit: Int) -> [String] {
        var counts: [String: (count: Int, last: Date)] = [:]
        for entry in entries {
            guard let host = entry.url.host else { continue }
            let site = site(for: host)
            let old = counts[site] ?? (0, .distantPast)
            counts[site] = (old.count + 1, max(old.last, entry.date))
        }
        return counts.sorted { a, b in
            a.value.count != b.value.count ? a.value.count > b.value.count : a.value.last > b.value.last
        }.prefix(limit).map(\.key)
    }

    /// Whether a WebKit data record (named by its site, e.g. "youtube.com") belongs to one of `sites`.
    static func record(_ name: String, isIn sites: Set<String>) -> Bool {
        sites.contains(site(for: name))
    }
}

/// Keeps WebKit's disk cache small. WebKit sizes its own cache from the free disk space (often
/// gigabytes) and has no setting for it, so Feather trims it:
/// - Bulky media (video and audio chunks, big images) is dropped: it's rarely loaded twice and
///   was ~80% of the cache. Scripts, styles and fonts, which a site needs on every visit, stay.
/// - Only your 20 most visited sites (plus sites open in a tab) keep a cache.
/// - The whole cache never stays above Settings.cacheLimitMB (500 MB unless you raise it).
/// Only cache data is ever removed; cookies and site storage, where logins live, are never touched.
@MainActor
final class CacheLimiter {
    static let shared = CacheLimiter()
    static var limitBytes: Int64 { Int64(Settings.cacheLimitMB) * 1_000_000 }
    static let keptSites = 20

    static let cacheTypes: Set<String> = [
        WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache,
        WKWebsiteDataTypeFetchCache, WKWebsiteDataTypeOfflineWebApplicationCache,
    ]

    private let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("WebKit", isDirectory: true)
    private var timer: Timer?
    private var running = false
    private var lastTrim = Date.distantPast

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.enforce() }
        // Video fills the cache fast, so the size is checked every 2 minutes (a quick folder scan).
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            MainActor.assumeIsolated { CacheLimiter.shared.enforce() }
        }
        timer?.tolerance = 30
    }

    /// Drops the cache of sites outside the top 20 (every 10 minutes), then, if the cache is still
    /// over the limit, drops the least visited of the top sites until it fits.
    func enforce() {
        guard !running else { return }
        running = true
        let store = WKWebsiteDataStore.default()
        let ranked = SiteRank.topSites(in: History.shared.entries, limit: Self.keptSites)
        let open = Set(BrowserWindowController.all.compactMap { $0.webView?.url?.host }.map(SiteRank.site))
        var keep = Set(ranked).union(open)
        for site in keep { keep.formUnion(SiteRank.companions[site] ?? []) }
        let trimRest = Date().timeIntervalSince(lastTrim) > 600

        dropBulkyMediaThenMeasure { [weak self] size in
            guard let self else { return }
            guard trimRest || size > Self.limitBytes else { self.running = false; return }
            store.fetchDataRecords(ofTypes: Self.cacheTypes) { records in
                let rest = records.filter { !SiteRank.record($0.displayName, isIn: keep) }
                store.removeData(ofTypes: Self.cacheTypes, for: rest) {
                    self.lastTrim = Date()
                    debugLog("cache: \(size / 1_000_000) MB, dropped \(rest.count) sites outside the top \(Self.keptSites)")
                    let kept = records.filter { SiteRank.record($0.displayName, isIn: keep) }
                    // Least visited first; open tabs that aren't in the top sites go first of all.
                    let order = kept.sorted { rank(of: $0, in: ranked) > rank(of: $1, in: ranked) }
                    self.shrink(store, order[...])
                }
            }
        }
    }

    /// Removes sites from the front of `queue`, five at a time, until the cache fits; as a last
    /// resort clears the whole cache.
    private func shrink(_ store: WKWebsiteDataStore, _ queue: ArraySlice<WKWebsiteDataRecord>) {
        measure { [weak self] size in
            guard let self else { return }
            guard size > Self.limitBytes else { self.running = false; return }
            if queue.isEmpty {
                debugLog("cache: still \(size / 1_000_000) MB, clearing all of it")
                store.removeData(ofTypes: Self.cacheTypes, modifiedSince: .distantPast) { self.running = false }
                return
            }
            let batch = Array(queue.prefix(5))
            store.removeData(ofTypes: Self.cacheTypes, for: batch) {
                self.shrink(store, queue.dropFirst(5))
            }
        }
    }

    /// Deletes bulky media from the cache folder, then measures it, off the main thread.
    private func dropBulkyMediaThenMeasure(_ done: @escaping @MainActor (Int64) -> Void) {
        let directory = self.directory
        DispatchQueue.global(qos: .utility).async {
            let freed = BulkyMedia.drop(in: directory.appendingPathComponent("NetworkCache", isDirectory: true))
            if freed > 0 { debugLog("cache: dropped \(freed / 1_000_000) MB of video, audio and large images") }
            let size = Self.size(of: directory)
            DispatchQueue.main.async { MainActor.assumeIsolated { done(size) } }
        }
    }

    /// The cache folder's size on disk, measured off the main thread.
    private func measure(_ done: @escaping @MainActor (Int64) -> Void) {
        let directory = self.directory
        DispatchQueue.global(qos: .utility).async {
            let size = Self.size(of: directory)
            DispatchQueue.main.async { MainActor.assumeIsolated { done(size) } }
        }
    }

    nonisolated static func size(of directory: URL) -> Int64 {
        // Cache bodies are hard-linked from two places, so each file is counted once by its identity.
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey, .fileResourceIdentifierKey]
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        var seen = Set<AnyHashable>()
        for case let file as URL in files {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            if let id = values.fileResourceIdentifier as? AnyHashable, !seen.insert(id).inserted { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

/// Finds bulky media in WebKit's disk cache by reading each entry's Content-Type.
///
/// WebKit's NetworkCache keeps every response as `Records/<partition>/Resource/<key>` (metadata,
/// with the response headers) and, for bigger bodies, `<key>-blob`, a hard link into `Blobs/`.
/// Removing both files of an entry makes WebKit treat it as a cache miss and fetch it again.
/// If the format ever changes so the type can't be read, nothing is removed here; the size cap
/// still applies through WebKit's own API.
enum BulkyMedia {
    /// Images and unknown types above this size are dropped; code and styles are kept at any size.
    static let largeBytes: Int64 = 1_000_000

    static func isBulky(contentType: String?, size: Int64) -> Bool {
        guard let type = contentType?.lowercased().trimmingCharacters(in: .whitespaces) else { return false }
        if type.hasPrefix("video/") || type.hasPrefix("audio/") || type.hasPrefix("application/vnd.yt-ump") {
            return true
        }
        let essential = ["javascript", "ecmascript", "text/css", "font/", "woff", "wasm", "text/html", "json", "xml", "svg"]
        if essential.contains(where: type.contains) { return false }
        return size > largeBytes
    }

    /// The Content-Type header stored in a cache record. Strings there are a little-endian
    /// UInt32 length, a byte that is 1 for 8-bit text, then the characters.
    static func contentType(inRecord data: Data) -> String? {
        let bytes = [UInt8](data)
        let name = Array("content-type".utf8)
        guard bytes.count > name.count + 5 else { return nil }
        var i = 0
        while i + name.count + 5 <= bytes.count {
            var match = true
            for j in 0..<name.count where bytes[i + j] | 0x20 != name[j] | 0x20 { match = false; break }
            if match {
                let start = i + name.count
                let length = Int(bytes[start]) | Int(bytes[start + 1]) << 8 | Int(bytes[start + 2]) << 16 | Int(bytes[start + 3]) << 24
                let text = start + 5
                guard bytes[start + 4] == 1, length > 0, length < 256, text + length <= bytes.count else { return nil }
                return String(decoding: bytes[text..<(text + length)], as: UTF8.self)
            }
            i += 1
        }
        return nil
    }

    /// Removes bulky entries under `networkCache` and returns the bytes freed.
    @discardableResult
    static func drop(in networkCache: URL) -> Int64 {
        let fm = FileManager.default
        var freed: Int64 = 0
        let versions = ((try? fm.contentsOfDirectory(at: networkCache, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("Version ") }
        for version in versions {
            let records = version.appendingPathComponent("Records", isDirectory: true)
            guard let files = fm.enumerator(at: records, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for case let blob as URL in files where blob.lastPathComponent.hasSuffix("-blob") {
                let record = blob.deletingLastPathComponent()
                    .appendingPathComponent(String(blob.lastPathComponent.dropLast(5)))
                let size = Int64((try? blob.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                guard let handle = try? FileHandle(forReadingFrom: record) else { continue }
                let header = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
                try? handle.close()
                guard isBulky(contentType: contentType(inRecord: header), size: size) else { continue }
                if (try? fm.removeItem(at: record)) != nil, (try? fm.removeItem(at: blob)) != nil { freed += size }
            }
            // A body in Blobs/ that no entry links to any more frees its space once removed.
            let blobs = version.appendingPathComponent("Blobs", isDirectory: true)
            for file in (try? fm.contentsOfDirectory(atPath: blobs.path)) ?? [] {
                let path = blobs.appendingPathComponent(file).path
                // WebKit writes a body here before linking it to its entry, so skip fresh files.
                if let attrs = try? fm.attributesOfItem(atPath: path),
                   (attrs[.referenceCount] as? NSNumber)?.intValue == 1,
                   let modified = attrs[.modificationDate] as? Date, modified.timeIntervalSinceNow < -60 {
                    try? fm.removeItem(atPath: path)
                }
            }
        }
        return freed
    }
}

/// Position in the ranking, with unranked sites (open tabs only) last.
private func rank(of record: WKWebsiteDataRecord, in ranked: [String]) -> Int {
    let site = SiteRank.site(for: record.displayName)
    if let i = ranked.firstIndex(of: site) { return i }
    // A companion CDN ranks with the site that uses it.
    if let owner = ranked.firstIndex(where: { SiteRank.companions[$0]?.contains(site) == true }) { return owner }
    return Int.max
}

/// Sites you stay signed in to: clearing cookies and site data keeps their cookies, so
/// Google, Gmail and YouTube never sign you out.
enum LoginKeeper {
    /// Clears all website data modified since `date` (nil = everything), except the cookies of
    /// the sites in Settings.keepSignedIn, which are saved first and put back afterwards.
    @MainActor
    static func clearWebsiteData(since date: Date?, done: @escaping () -> Void = {}) {
        let store = WKWebsiteDataStore.default()
        let sites = Settings.keepSignedIn
        store.httpCookieStore.getAllCookies { cookies in
            let kept = cookies.filter { isKept($0.domain, sites: sites) }
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: date ?? .distantPast) {
                let group = DispatchGroup()
                for cookie in kept {
                    group.enter()
                    store.httpCookieStore.setCookie(cookie) { group.leave() }
                }
                group.notify(queue: .main) { done() }
            }
        }
    }

    /// Whether a cookie domain (".google.com", "mail.google.com") belongs to a kept site.
    static func isKept(_ cookieDomain: String, sites: [String]) -> Bool {
        let host = cookieDomain.hasPrefix(".") ? String(cookieDomain.dropFirst()) : cookieDomain
        return Shields.isAllowlisted(host: host, in: sites)
    }
}
