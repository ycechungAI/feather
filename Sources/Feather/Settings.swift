import Foundation

/// A search provider. `searchURL` and `suggestURL` end where the query is appended.
struct SearchEngine: Equatable {
    let name: String
    let searchURL: String
    let homeURL: String
    /// OpenSearch suggestions endpoint (JSON `[query, [suggestions]]`), if the engine has one.
    let suggestURL: String?

    static let all: [SearchEngine] = [
        SearchEngine(name: "Google", searchURL: "https://www.google.com/search?q=",
                     homeURL: "https://www.google.com",
                     suggestURL: "https://suggestqueries.google.com/complete/search?client=firefox&q="),
        SearchEngine(name: "DuckDuckGo", searchURL: "https://duckduckgo.com/?q=",
                     homeURL: "https://duckduckgo.com",
                     suggestURL: "https://duckduckgo.com/ac/?type=list&q="),
        SearchEngine(name: "Bing", searchURL: "https://www.bing.com/search?q=",
                     homeURL: "https://www.bing.com",
                     suggestURL: "https://api.bing.com/osjson.aspx?query="),
        SearchEngine(name: "Brave Search", searchURL: "https://search.brave.com/search?q=",
                     homeURL: "https://search.brave.com",
                     suggestURL: "https://search.brave.com/api/suggest?q="),
        SearchEngine(name: "Startpage", searchURL: "https://www.startpage.com/do/search?q=",
                     homeURL: "https://www.startpage.com", suggestURL: nil),
    ]

    /// The preset whose search URL matches, or nil for a custom URL.
    static func matching(searchURL: String) -> SearchEngine? {
        all.first { $0.searchURL == searchURL }
    }

    /// The full search URL for `query`.
    static func url(for query: String, prefix: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        return URL(string: prefix + encoded)
    }
}

/// User preferences, stored in UserDefaults and editable in Feather ▸ Settings (⌘,).
enum Settings {
    private static let d = UserDefaults.standard
    /// Posted after any setting changes from the Settings window or the Shields menu.
    static let changed = Notification.Name("FeatherSettingsChanged")

    static func registerDefaults() {
        d.register(defaults: [
            "shieldsEnabled": true,
            "httpsOnly": true,
            "suspendMinutes": 5,
            "searchURL": "https://www.google.com/search?q=",
            "homeURL": "https://www.google.com",
            "searchSuggestions": false,
            "restoreSession": true,
            "shieldsAllowlist": [String](),
            "keepSignedIn": ["google.com", "gmail.com", "youtube.com"],
            "cacheLimitMB": 500,
            "webInspector": false,
        ])
    }

    static var shieldsEnabled: Bool {
        get { d.bool(forKey: "shieldsEnabled") }
        set { d.set(newValue, forKey: "shieldsEnabled") }
    }

    static var httpsOnly: Bool {
        get { d.bool(forKey: "httpsOnly") }
        set { d.set(newValue, forKey: "httpsOnly") }
    }

    /// Background tabs idle longer than this many minutes are put to sleep (0 disables).
    static var suspendMinutes: Int {
        get { d.integer(forKey: "suspendMinutes") }
        set { d.set(newValue, forKey: "suspendMinutes") }
    }

    static var suspendAfter: TimeInterval { TimeInterval(suspendMinutes * 60) }

    static var searchURL: String {
        get { d.string(forKey: "searchURL") ?? "https://www.google.com/search?q=" }
        set { d.set(newValue, forKey: "searchURL") }
    }

    /// The chosen preset engine, if the search URL is one of them.
    static var searchEngine: SearchEngine? { SearchEngine.matching(searchURL: searchURL) }

    /// Send what you type in the address bar to the search engine for suggestions. Off by default.
    static var searchSuggestions: Bool {
        get { d.bool(forKey: "searchSuggestions") }
        set { d.set(newValue, forKey: "searchSuggestions") }
    }

    /// Reopen the tabs from last time on launch.
    static var restoreSession: Bool {
        get { d.bool(forKey: "restoreSession") }
        set { d.set(newValue, forKey: "restoreSession") }
    }

    /// The home page (default https://www.google.com).
    static var homePageURL: URL {
        get {
            let fallback = URL(string: "https://www.google.com")!
            guard let raw = d.string(forKey: "homeURL"),
                  let url = URL(string: raw), url.scheme != nil else { return fallback }
            return url
        }
        set { d.set(newValue.absoluteString, forKey: "homeURL") }
    }

    /// Sites where Shields are turned off (hosts; subdomains included).
    static var shieldsAllowlist: [String] {
        get { d.stringArray(forKey: "shieldsAllowlist") ?? [] }
        set { d.set(Array(Set(newValue.map { $0.lowercased() })).sorted(), forKey: "shieldsAllowlist") }
    }

    /// Sites whose cookies survive Clear History's "cookies and site data" option, so you stay
    /// signed in (default Google, Gmail and YouTube). Subdomains are included.
    static var keepSignedIn: [String] {
        get { d.stringArray(forKey: "keepSignedIn") ?? [] }
        set { d.set(Array(Set(newValue.map { $0.lowercased() })).sorted(), forKey: "keepSignedIn") }
    }

    /// The most disk space the web cache may use, in MB (default 500).
    static var cacheLimitMB: Int {
        get { max(d.integer(forKey: "cacheLimitMB"), 100) }
        set { d.set(newValue, forKey: "cacheLimitMB") }
    }

    /// Settings ▸ Developer: Inspect Element and View ▸ Show Web Inspector. Off by default, because
    /// the inspector can read everything on a page.
    static var webInspector: Bool {
        get { d.bool(forKey: "webInspector") }
        set { d.set(newValue, forKey: "webInspector") }
    }

    /// Whether ad and tracker blocking should run on pages from `host`.
    static func shieldsActive(for host: String?) -> Bool {
        shieldsEnabled && !Shields.isAllowlisted(host: host, in: shieldsAllowlist)
    }

    /// Present as current Safari so sites (YouTube in particular) serve their full, modern experience.
    static let userAgentSuffix: String = {
        "Version/\(safariVersion) Safari/605.1.15"
    }()

    static let safariVersion: String = {
        let plist = "/Applications/Safari.app/Contents/Info.plist"
        return (NSDictionary(contentsOfFile: plist)?["CFBundleShortVersionString"] as? String)
            ?? "\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).0"
    }()

    /// Folder for user-supplied blocklists.
    static var supportDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Feather", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
