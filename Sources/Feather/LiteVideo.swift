import Foundation

/// Converts heavy desktop YouTube and Twitch pages into lightweight Mobile Web
/// (`m.youtube.com` / `m.twitch.tv` with a Mobile Safari User-Agent, active MSE buffer eviction,
/// and DOM pruning) when Eco Memory mode is on, and converts them back to desktop when turned off.
enum LiteVideo {
    private static let desktopYouTubeHosts: Set<String> = [
        "youtube.com", "www.youtube.com",
    ]
    private static let allYouTubeHosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com",
    ]
    private static let desktopTwitchHosts: Set<String> = [
        "twitch.tv", "www.twitch.tv",
    ]
    private static let allTwitchHosts: Set<String> = [
        "twitch.tv", "www.twitch.tv", "m.twitch.tv",
    ]
    private static let twitchDesktopOnlyPrefixes: Set<String> = [
        "popout", "embed", "subscriptions", "settings", "wallet", "drops", "inventory", "dashboard", "u",
    ]

    /// Mobile Safari User-Agent used only on `m.youtube.com` and `m.twitch.tv` while Eco Memory
    /// is on, so both sites serve their lightweight mobile web bundles and native HLS/mobile
    /// streams instead of redirecting back to heavy desktop SPAs.
    static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    static func isLiteHost(_ host: String?) -> Bool {
        guard let h = host?.lowercased() else { return false }
        return h == "m.youtube.com" || h == "m.twitch.tv" || h == "m.facebook.com"
            || h.hasPrefix("m.") || h.contains(".m.wikipedia.org")
    }

    /// Returns the lightweight mobile URL for a desktop YouTube, Twitch, Wikipedia, or Facebook page,
    /// or `nil` if `url` is not in the known-mobile list or is already on a mobile host.
    static func liteURL(for url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        guard !isLiteHost(host) else { return nil }

        // Twitch: www.twitch.tv/<channel> or /videos/<id> -> m.twitch.tv/...
        if desktopTwitchHosts.contains(host) {
            let parts = url.path.split(separator: "/").map(String.init)
            if let first = parts.first?.lowercased(), twitchDesktopOnlyPrefixes.contains(first) {
                return nil
            }
            var out = comps
            out.scheme = "https"
            out.host = "m.twitch.tv"
            return out.url
        }

        // Wikipedia: en.wikipedia.org -> en.m.wikipedia.org
        if host.hasSuffix(".wikipedia.org"), !host.contains(".m.wikipedia.org") {
            var out = comps
            out.scheme = "https"
            out.host = host.replacingOccurrences(of: ".wikipedia.org", with: ".m.wikipedia.org")
            return out.url
        }

        // Facebook: www.facebook.com / facebook.com -> m.facebook.com
        if host == "facebook.com" || host == "www.facebook.com" {
            var out = comps
            out.scheme = "https"
            out.host = "m.facebook.com"
            return out.url
        }

        // YouTube: watch, shorts, live, youtu.be -> m.youtube.com/watch?v=<id>&app=m
        let videoID: String?
        let pathParts = url.path.split(separator: "/").map(String.init)
        if host == "youtu.be" {
            videoID = pathParts.first
        } else if desktopYouTubeHosts.contains(host) {
            if pathParts == ["watch"] {
                videoID = comps.queryItems?.first(where: { $0.name == "v" })?.value
            } else if pathParts.count >= 2, pathParts[0] == "shorts" || pathParts[0] == "live" {
                videoID = pathParts[1]
            } else {
                videoID = nil
            }
        } else {
            return nil
        }

        guard let id = videoID, isValidVideoID(id) else { return nil }

        var out = URLComponents()
        out.scheme = "https"
        out.host = "m.youtube.com"
        out.path = "/watch"
        var items = [
            URLQueryItem(name: "v", value: id),
            URLQueryItem(name: "app", value: "m"),
        ]
        if let rawStart = comps.queryItems?.first(where: { $0.name == "t" || $0.name == "start" })?.value,
           let seconds = parseTimestamp(rawStart), seconds > 0 {
            items.append(URLQueryItem(name: "t", value: "\(seconds)s"))
        }
        if let list = comps.queryItems?.first(where: { $0.name == "list" })?.value, !list.isEmpty {
            items.append(URLQueryItem(name: "list", value: list))
        }
        out.queryItems = items
        return out.url
    }

    /// Converts a known mobile URL back to its desktop counterpart.
    static func desktopURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if host == "m.youtube.com" {
            comps.scheme = "https"
            comps.host = "www.youtube.com"
            var items = (comps.queryItems ?? []).filter { $0.name != "app" }
            items.append(URLQueryItem(name: "app", value: "desktop"))
            comps.queryItems = items
            return comps.url
        }
        if host == "m.twitch.tv" {
            comps.scheme = "https"
            comps.host = "www.twitch.tv"
            return comps.url
        }
        if host == "m.facebook.com" {
            comps.scheme = "https"
            comps.host = "www.facebook.com"
            return comps.url
        }
        if host.contains(".m.wikipedia.org") {
            comps.scheme = "https"
            comps.host = host.replacingOccurrences(of: ".m.wikipedia.org", with: ".wikipedia.org")
            return comps.url
        }
        return nil
    }

    /// Builds a candidate `m.<domain>` URL for any general website (skipping local/IP/mobile hosts).
    static func candidateMobileURL(for url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), !isLiteHost(host), !URLTools.isLocal(host),
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard bare.contains(".") else { return nil }
        comps.host = "m.\(bare)"
        return comps.url
    }

    /// Resolves the best mobile URL for a heavy (>500 MB) page: checks known mobile mappings first,
    /// then probes `m.<domain>` with a quick 2 s HEAD request, and falls back to the original URL
    /// (loaded with a Mobile Safari User-Agent) if no dedicated `m.` subdomain exists.
    static func resolveMobileURL(for url: URL) async -> URL {
        if let known = liteURL(for: url) { return known }
        guard let candidate = candidateMobileURL(for: url) else { return url }
        var req = URLRequest(url: candidate)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 2.0
        req.setValue(mobileUserAgent, forHTTPHeaderField: "User-Agent")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.0
        config.timeoutIntervalForResource = 2.0
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        if let (_, resp) = try? await session.data(for: req),
           let http = resp as? HTTPURLResponse, (200..<400).contains(http.statusCode),
           let finalURL = http.url, finalURL.host?.lowercased().hasPrefix("m.") == true {
            return finalURL
        }
        return url
    }

    /// Stable content key for per-tab bypass and per-video/channel process resets.
    static func contentKey(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        if let ytID = videoID(for: url) { return "yt:\(ytID)" }
        if allTwitchHosts.contains(host) {
            let parts = url.path.split(separator: "/").map { $0.lowercased() }
            guard let first = parts.first, !twitchDesktopOnlyPrefixes.contains(first) else { return nil }
            if first == "videos", parts.count >= 2 { return "tw:video:\(parts[1])" }
            return "tw:\(first)"
        }
        return nil
    }

    /// Extracts the YouTube video ID from a watch, shorts, live, or youtu.be URL.
    static func videoID(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        let id: String?
        if host == "youtu.be" {
            id = parts.first
        } else if allYouTubeHosts.contains(host) {
            if parts == ["watch"] {
                id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value
            } else if parts.count >= 2, ["shorts", "live", "embed"].contains(parts[0]) {
                id = parts[1]
            } else {
                id = nil
            }
        } else {
            return nil
        }
        guard let id, isValidVideoID(id) else { return nil }
        return id
    }

    /// Injected at document-start on YouTube and Twitch while Eco Memory is on:
    /// 1. Tracks MSE SourceBuffers and periodically evicts already-played video/audio chunks
    ///    older than 10 s behind currentTime so long videos/streams don't balloon in RAM.
    /// 2. Hides and prunes heavy below-the-fold feeds, comments, shorts shelves, and ambient blur.
    static let ecoDietScript = #"""
    (() => {
      const host = location.hostname.toLowerCase();
      const isYT = /(^|\.)youtube\.com$/.test(host);
      const isTW = /(^|\.)twitch\.tv$/.test(host);
      if (!isYT && !isTW) return;
      const key = Symbol.for('feather.ecoDiet');
      if (window[key]) return;
      Object.defineProperty(window, key, { value: true });

      // 1. Track MSE SourceBuffers and evict played chunks > 10 s behind playback.
      const buffers = new Set();
      if (typeof MediaSource !== 'undefined' && MediaSource.prototype?.addSourceBuffer) {
        const origAdd = MediaSource.prototype.addSourceBuffer;
        MediaSource.prototype.addSourceBuffer = function (...args) {
          const sb = origAdd.apply(this, args);
          buffers.add(sb);
          return sb;
        };
        setInterval(() => {
          const v = document.querySelector('video');
          if (v && isFinite(v.currentTime)) {
            const cutoff = v.currentTime - 10;
            for (const sb of [...buffers]) {
              try {
                if (sb.updating) continue;
                const b = sb.buffered;
                if (b.length > 0 && b.start(0) < cutoff && cutoff > 0) {
                  sb.remove(b.start(0), cutoff);
                }
              } catch (e) {
                buffers.delete(sb);
              }
            }
          }
          // Live HLS streams fetch a segment every ~2 s; clear accumulated resource timing entries.
          try { performance.clearResourceTimings?.(); } catch (e) {}
        }, 5000);
      }

      // 2. Hide and prune heavy non-player DOM bloat (and cap live Twitch chat DOM to 30 messages).
      const hideSelectors = isYT ? [
        '#cinematics', 'ytd-watch-next-secondary-results-renderer', '#related', '#comments',
        'ytd-live-chat-frame', 'ytd-merch-shelf-renderer',
        'ytm-comment-section-renderer', 'ytm-reel-shelf-renderer',
        'ytm-single-column-watch-next-results-renderer .related-chips-slot-wrapper'
      ].join(', ') : [
        '[data-test-selector="open-in-app-banner"]',
        '.extension-container'
      ].join(', ');
      const injectCSS = () => {
        if (document.getElementById('feather-eco-diet')) return;
        const style = document.createElement('style');
        style.id = 'feather-eco-diet';
        style.textContent = hideSelectors + ' { display: none !important; }';
        (document.head || document.documentElement).appendChild(style);
      };
      const prune = () => {
        injectCSS();
        const pruneSel = isYT
          ? '#cinematics, ytd-live-chat-frame, ytm-comment-section-renderer, ytm-reel-shelf-renderer'
          : '[data-test-selector="open-in-app-banner"], .extension-container';
        for (const el of document.querySelectorAll(pruneSel)) {
          el.remove();
        }
        if (isTW) {
          // Cap live Twitch chat list to the newest 30 messages so emotes/DOM don't climb forever.
          for (const log of document.querySelectorAll('[role="log"], .chat-scrollable-area__message-container')) {
            while (log.children.length > 30) log.firstElementChild?.remove();
          }
        }
      };
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', prune, { once: true });
      } else {
        prune();
      }
      setInterval(prune, 8000);
    })();
    """#

    /// Parses YouTube timestamps like "90", "90s", "1m30s", or "1h2m3s" into whole seconds.
    static func parseTimestamp(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if let plain = Int(s) { return plain }
        var total = 0, current = 0, matched = false
        for ch in s {
            if let digit = ch.wholeNumberValue {
                current = current * 10 + digit
            } else if ch == "h" {
                total += current * 3600; current = 0; matched = true
            } else if ch == "m" {
                total += current * 60; current = 0; matched = true
            } else if ch == "s" {
                total += current; current = 0; matched = true
            } else {
                return nil
            }
        }
        total += current
        return matched ? total : nil
    }

    private static func isValidVideoID(_ id: String) -> Bool {
        guard (6...20).contains(id.count) else { return false }
        return id.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
        }
    }
}
