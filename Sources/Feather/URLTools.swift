import Foundation

enum URLTools {
    /// Turns address-bar text into a URL: a full URL, a bare domain, or a search.
    static func resolve(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "about"].contains(scheme),
           url.host != nil || scheme == "about" || scheme == "file" {
            return url
        }
        if !text.contains(" ") {
            let lower = text.lowercased()
            if lower.hasPrefix("localhost") || lower.hasPrefix("127.0.0.1") {
                return URL(string: "http://" + text)
            }
            if text.contains("."), let url = URL(string: "https://" + text), url.host != nil {
                return url
            }
        }
        return SearchEngine.url(for: text, prefix: Settings.searchURL)
    }

    private static let trackingParams: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid",
        "mc_cid", "mc_eid", "igshid", "_hsenc", "_hsmi", "oly_anon_id", "oly_enc_id",
    ]

    /// Removes click-tracking parameters. Returns nil when nothing changed.
    static func stripTracking(_ url: URL) -> URL? {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems, !items.isEmpty else { return nil }
        let kept = items.filter { !trackingParams.contains($0.name.lowercased()) }
        guard kept.count != items.count else { return nil }
        comps.queryItems = kept.isEmpty ? nil : kept
        return comps.url
    }

    /// Returns the https:// version of a plain-http URL for public hosts, else nil.
    static func httpsUpgrade(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "http", let host = url.host?.lowercased(), !isLocal(host),
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = "https"
        if comps.port == 80 { comps.port = nil }
        return comps.url
    }

    static func isLocal(_ host: String) -> Bool {
        var h = host.lowercased()
        if h.hasPrefix("["), h.hasSuffix("]") { h = String(h.dropFirst().dropLast()) }
        if h == "localhost" || h.hasSuffix(".localhost") || h.hasSuffix(".local") || h.hasSuffix(".test") {
            return true
        }
        // IPv6 loopback (::1), link-local (fe80::/10) and unique-local (fc00::/7).
        if h.contains(":") {
            return h == "::1" || h.hasPrefix("fe80:") || h.hasPrefix("fc") || h.hasPrefix("fd")
        }
        // IPv4: loopback (127/8), "this network" (0/8), private (10/8, 172.16/12,
        // 192.168/16) and link-local (169.254/16).
        let octets = h.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4,
              let a = Int(octets[0]), let b = Int(octets[1]),
              let c = Int(octets[2]), let d = Int(octets[3]),
              [a, b, c, d].allSatisfy({ (0...255).contains($0) }) else { return false }
        return a == 127 || a == 0 || a == 10
            || (a == 192 && b == 168)
            || (a == 172 && (16...31).contains(b))
            || (a == 169 && b == 254)
    }
}
