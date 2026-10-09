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
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let query = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
        return URL(string: Settings.searchURL + query)
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
        host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local")
            || host.hasSuffix(".test") || host == "[::1]" || host.hasPrefix("127.")
            || host.hasPrefix("10.") || host.hasPrefix("192.168.")
    }
}
