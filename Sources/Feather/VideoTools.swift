import AppKit
import WebKit

/// Reads HLS playlists (.m3u8), the format most sites stream video in.
enum HLS {
    struct Variant: Equatable {
        var url: URL
        var bandwidth: Int
        /// The sound comes as its own stream, which would have to be mixed back in.
        var separateAudio: Bool
    }

    struct Media: Equatable {
        var initSegment: URL?
        var segments: [URL]
        var firstSequence: Int
        var targetDuration: Double
        var isFinished: Bool
        /// AES-128 or SAMPLE-AES encryption (or DRM such as FairPlay): Feather doesn't save these.
        var isEncrypted: Bool
    }

    enum Playlist: Equatable {
        case master([Variant])
        case media(Media)
    }

    static func parse(_ text: String, base: URL) -> Playlist? {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.first?.hasPrefix("#EXTM3U") == true else { return nil }
        if lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF") }) {
            let audioGroups = Set(lines.filter { $0.hasPrefix("#EXT-X-MEDIA:") && attribute("TYPE", in: $0) == "AUDIO"
                && attribute("URI", in: $0) != nil }.compactMap { attribute("GROUP-ID", in: $0) })
            var variants: [Variant] = []
            for (i, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF") {
                guard let uri = lines[(i + 1)...].first(where: { !$0.isEmpty && !$0.hasPrefix("#") }),
                      let url = URL(string: uri, relativeTo: base)?.absoluteURL else { continue }
                let audio = attribute("AUDIO", in: line).map(audioGroups.contains) ?? false
                variants.append(Variant(url: url, bandwidth: Int(attribute("BANDWIDTH", in: line) ?? "") ?? 0,
                                        separateAudio: audio))
            }
            return .master(variants)
        }
        var media = Media(initSegment: nil, segments: [], firstSequence: 0, targetDuration: 6,
                          isFinished: false, isEncrypted: false)
        for line in lines {
            if line.hasPrefix("#EXT-X-MAP:"), let uri = attribute("URI", in: line) {
                media.initSegment = URL(string: uri, relativeTo: base)?.absoluteURL
            } else if line.hasPrefix("#EXT-X-KEY:") || line.hasPrefix("#EXT-X-SESSION-KEY:") {
                if attribute("METHOD", in: line)?.uppercased() != "NONE" { media.isEncrypted = true }
            } else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                media.firstSequence = Int(line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count)) ?? 0
            } else if line.hasPrefix("#EXT-X-TARGETDURATION:") {
                media.targetDuration = Double(line.dropFirst("#EXT-X-TARGETDURATION:".count)) ?? 6
            } else if line.hasPrefix("#EXT-X-ENDLIST") {
                media.isFinished = true
            } else if !line.isEmpty, !line.hasPrefix("#"), let url = URL(string: line, relativeTo: base)?.absoluteURL {
                media.segments.append(url)
            }
        }
        return .media(media)
    }

    /// The best variant whose sound is in the same stream as the picture.
    static func bestVariant(_ variants: [Variant]) -> Variant? {
        variants.filter { !$0.separateAudio }.max { $0.bandwidth < $1.bandwidth }
    }

    /// An attribute from a tag line like `#EXT-X-KEY:METHOD=AES-128,URI="key.bin"`.
    static func attribute(_ name: String, in line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        var rest = line[line.index(after: colon)...]
        while !rest.isEmpty {
            guard let eq = rest.firstIndex(of: "=") else { return nil }
            let key = rest[..<eq].trimmingCharacters(in: .whitespaces)
            rest = rest[rest.index(after: eq)...]
            var value: Substring
            if rest.first == "\"" {
                rest = rest.dropFirst()
                let end = rest.firstIndex(of: "\"") ?? rest.endIndex
                value = rest[..<end]
                rest = end < rest.endIndex ? rest[rest.index(after: end)...] : ""
                if rest.first == "," { rest = rest.dropFirst() }
            } else {
                let end = rest.firstIndex(of: ",") ?? rest.endIndex
                value = rest[..<end]
                rest = end < rest.endIndex ? rest[rest.index(after: end)...] : ""
            }
            if key == name { return String(value) }
        }
        return nil
    }
}

/// Reads .srt and .vtt subtitle files into cues for the page's video.
enum Subtitles {
    struct Cue: Equatable {
        var start: Double
        var end: Double
        var text: String
    }

    static func parse(_ text: String) -> [Cue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var cues: [Cue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timing].components(separatedBy: "-->")
            guard parts.count == 2, let start = seconds(parts[0]),
                  let end = seconds(parts[1].split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) ?? "")
            else { continue }
            let body = lines[(timing + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            cues.append(Cue(start: start, end: end, text: body))
        }
        return cues
    }

    /// "01:02:03,456", "01:02:03.456" or "02:03.456".
    static func seconds(_ raw: String) -> Double? {
        let parts = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = Double(part) else { return nil }
            total = total * 60 + value
        }
        return total
    }
}

/// Saves a streamed HLS video: downloads its segments in order with the page's cookies and joins
/// them into one file (fragmented MP4 streams make a .mp4, older MPEG-TS streams a .ts, which
/// plays in IINA or VLC). A live stream keeps recording until you cancel it or the stream ends.
@MainActor
final class StreamDownloader {
    enum Failure: LocalizedError {
        case notAPlaylist, encrypted, separateAudio, empty
        var errorDescription: String? {
            switch self {
            case .notAPlaylist: "The stream's playlist couldn't be read."
            case .encrypted: "This video is encrypted or protected (DRM), so Feather can't save it."
            case .separateAudio: "This stream sends picture and sound separately, which Feather can't join yet."
            case .empty: "The stream has no video segments."
            }
        }
    }

    private let session: URLSession
    private let headers: [String: String]
    private var task: Task<Void, Never>?

    init(referer: URL?, userAgent: String?, cookies: [HTTPCookie]) {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: config)
        var headers: [String: String] = [:]
        if let referer { headers["Referer"] = referer.absoluteString; headers["Origin"] = referer.origin }
        if let userAgent { headers["User-Agent"] = userAgent }
        self.headers = headers
        self.cookies = cookies
    }

    private let cookies: [HTTPCookie]

    /// Checks the stream, then starts saving it into the Downloads folder as an entry in the
    /// Downloads list. Throws right away for streams Feather can't save.
    func start(playlist: URL, title: String, isPrivate: Bool) async throws {
        var media = try await mediaPlaylist(playlist)
        guard !media.isEncrypted else { throw Failure.encrypted }
        guard !media.segments.isEmpty else { throw Failure.empty }
        let ext = media.initSegment != nil || media.segments.first?.pathExtension.lowercased() == "m4s"
            || media.segments.first?.pathExtension.lowercased() == "mp4" ? "mp4" : "ts"
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let destination = Downloads.uniqueURL(in: folder, for: Self.filename(title) + "." + ext)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)

        let progress = Progress(totalUnitCount: Int64(media.segments.count))
        let item = Downloads.shared.trackStream(filename: destination.lastPathComponent, destination: destination,
                                                source: playlist, progress: progress, isPrivate: isPrivate) { [weak self] in
            self?.task?.cancel()
        }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                if let initSegment = media.initSegment { try handle.write(contentsOf: try await self.fetch(initSegment)) }
                var next = media.firstSequence
                var done = Set<Int>()
                while true {
                    let pending = media.segments.enumerated().map { (media.firstSequence + $0.offset, $0.element) }
                        .filter { $0.0 >= next && !done.contains($0.0) }
                    // Four at a time, written in order.
                    for batch in stride(from: 0, to: pending.count, by: 4).map({ Array(pending[$0..<min($0 + 4, pending.count)]) }) {
                        try Task.checkCancellation()
                        let data = try await withThrowingTaskGroup(of: (Int, Data).self) { group in
                            for (i, (_, url)) in batch.enumerated() { group.addTask { (i, try await self.fetch(url)) } }
                            var parts = [Data?](repeating: nil, count: batch.count)
                            for try await (i, d) in group { parts[i] = d }
                            return parts.compactMap { $0 }
                        }
                        for part in data { try handle.write(contentsOf: part) }
                        for (sequence, _) in batch { done.insert(sequence); next = max(next, sequence + 1) }
                        progress.completedUnitCount = Int64(done.count)
                        Downloads.shared.progressChanged()
                    }
                    if media.isFinished { break }
                    // Live: wait for new segments, then fetch the playlist again.
                    try await Task.sleep(for: .seconds(max(media.targetDuration, 2)))
                    media = try await self.mediaPlaylist(playlist)
                    if media.isEncrypted { throw Failure.encrypted }
                    progress.totalUnitCount = Int64(done.count + media.segments.count)
                }
                try handle.close()
                Downloads.shared.finishStream(item)
            } catch {
                try? handle.close()
                // A cancelled recording keeps what was saved; a failure keeps it too, marked failed.
                Downloads.shared.endStream(item, cancelled: error is CancellationError || Task.isCancelled, error: error)
            }
        }
    }

    /// Follows a master playlist to its best variant.
    private func mediaPlaylist(_ url: URL) async throws -> HLS.Media {
        let text = String(decoding: try await fetch(url), as: UTF8.self)
        switch HLS.parse(text, base: url) {
        case .media(let media): return media
        case .master(let variants):
            guard let best = HLS.bestVariant(variants) else {
                throw variants.isEmpty ? Failure.notAPlaylist : Failure.separateAudio
            }
            let text = String(decoding: try await fetch(best.url), as: UTF8.self)
            guard case .media(let media) = HLS.parse(text, base: best.url) else { throw Failure.notAPlaylist }
            return media
        case nil: throw Failure.notAPlaylist
        }
    }

    nonisolated private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        if let cookie = Self.cookieHeader(for: url, from: cookies) { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        var lastError: Error = URLError(.unknown)
        for _ in 0..<3 {
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                return data
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                lastError = error
            }
        }
        throw lastError
    }

    /// The Cookie header the page's own request would carry to `url`.
    nonisolated static func cookieHeader(for url: URL, from cookies: [HTTPCookie]) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path.isEmpty ? "/" : url.path
        let matching = cookies.filter { cookie in
            var domain = cookie.domain.lowercased()
            let subdomains = domain.hasPrefix(".")
            if subdomains { domain.removeFirst() }
            // ".example.com" also covers subdomains; "example.com" is that host only.
            let domainOK = host == domain || (subdomains && host.hasSuffix("." + domain))
            let expired = cookie.expiresDate.map { $0 < Date() } ?? false
            return domainOK && path.hasPrefix(cookie.path) && (!cookie.isSecure || url.scheme == "https") && !expired
        }
        guard !matching.isEmpty else { return nil }
        return matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    /// A file name from the page title, without characters macOS doesn't allow.
    nonisolated static func filename(_ title: String) -> String {
        let cleaned = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Video" : String(cleaned.prefix(120))
    }
}

private extension URL {
    var origin: String? {
        guard let scheme, let host else { return nil }
        return port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
    }
}
