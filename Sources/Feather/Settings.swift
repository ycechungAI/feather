import Foundation

/// User preferences, stored in UserDefaults. Change from Terminal with e.g.
///   defaults write dev.feather.browser searchURL "https://www.google.com/search?q="
enum Settings {
    private static let d = UserDefaults.standard

    static func registerDefaults() {
        d.register(defaults: [
            "shieldsEnabled": true,
            "httpsOnly": true,
            "suspendMinutes": 10,
            "searchURL": "https://www.google.com/search?q=",
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

    /// Background tabs idle longer than this are put to sleep (0 disables).
    static var suspendAfter: TimeInterval { TimeInterval(d.integer(forKey: "suspendMinutes") * 60) }

    static var searchURL: String { d.string(forKey: "searchURL") ?? "https://www.google.com/search?q=" }

    /// The home page: the search engine's homepage (e.g. https://www.google.com).
    /// Override with: defaults write dev.feather.browser homeURL "https://example.com"
    static var homePageURL: URL {
        if let custom = d.string(forKey: "homeURL"), let url = URL(string: custom) {
            return url
        }
        if let search = URL(string: searchURL),
           let scheme = search.scheme, let host = search.host,
           let home = URL(string: "\(scheme)://\(host)") {
            return home
        }
        return URL(string: "https://www.google.com")!
    }

    /// Present as current Safari so sites (YouTube in particular) serve their full, modern experience.
    static let userAgentSuffix: String = {
        let plist = "/Applications/Safari.app/Contents/Info.plist"
        let version = (NSDictionary(contentsOfFile: plist)?["CFBundleShortVersionString"] as? String)
            ?? "\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).0"
        return "Version/\(version) Safari/605.1.15"
    }()

    /// Folder for user-supplied blocklists.
    static var supportDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Feather", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
