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

/// User preferences, stored in UserDefaults and editable in FeatherA ▸ Settings (⌘,).
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
            "askPanelPosition": "right",
            "saveChatHistory": true,
            "askPanelWidth": 380,
            "askPanelHeight": 340,
            "askPanelOpenByDefault": true,
            "showHomeButton": false,
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

    /// Where the Ask AI side panel docks: "right" (default), "left", or "bottom".
    static var askPanelPosition: String {
        get { d.string(forKey: "askPanelPosition") ?? "right" }
        set { d.set(newValue, forKey: "askPanelPosition") }
    }
    /// Last width of the Ask AI side panel (for right/left docking).
    static var askPanelWidth: Double {
        get { d.object(forKey: "askPanelWidth") == nil ? 380 : d.double(forKey: "askPanelWidth") }
        set { d.set(newValue, forKey: "askPanelWidth") }
    }

    /// Last height of the Ask AI panel (for bottom docking).
    static var askPanelHeight: Double {
        get { d.object(forKey: "askPanelHeight") == nil ? 340 : d.double(forKey: "askPanelHeight") }
        set { d.set(newValue, forKey: "askPanelHeight") }
    }

    /// Whether the Ask AI side panel opens automatically when a tab/window opens.
    static var askPanelOpenByDefault: Bool {
        get { d.object(forKey: "askPanelOpenByDefault") == nil ? true : d.bool(forKey: "askPanelOpenByDefault") }
        set { d.set(newValue, forKey: "askPanelOpenByDefault") }
    }

    /// Show the Home button in the toolbar. Off by default; can be turned back on in Settings.
    static var showHomeButton: Bool {
        get { d.object(forKey: "showHomeButton") == nil ? false : d.bool(forKey: "showHomeButton") }
        set { d.set(newValue, forKey: "showHomeButton") }
    }

    /// Whether chat history persists across sessions. When off, history is in-memory only.
    static var saveChatHistory: Bool {
        get { d.object(forKey: "saveChatHistory") == nil ? true : d.bool(forKey: "saveChatHistory") }
        set { d.set(newValue, forKey: "saveChatHistory") }
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
            .appendingPathComponent("FeatherA", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
