import Foundation

struct Bookmark: Codable, Equatable {
    var title: String
    var url: URL
}

/// Bookmarks, stored as JSON in the app's support folder.
/// Import/export uses the Netscape bookmark HTML format that every major browser reads and writes.
final class Bookmarks {
    static let shared = Bookmarks()
    static let changed = Notification.Name("FeatherBookmarksChanged")

    private(set) var items: [Bookmark] = []
    private let file = Settings.supportDirectory.appendingPathComponent("bookmarks.json")

    private init() {
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([Bookmark].self, from: data) {
            items = saved
        }
    }

    func contains(_ url: URL?) -> Bool {
        guard let url else { return false }
        return items.contains { $0.url == url }
    }

    func add(title: String, url: URL) {
        guard !contains(url) else { return }
        items.append(Bookmark(title: title.isEmpty ? (url.host ?? url.absoluteString) : title, url: url))
        save()
    }

    func remove(_ url: URL) {
        items.removeAll { $0.url == url }
        save()
    }

    func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        save()
    }

    func rename(at index: Int, to title: String) {
        guard items.indices.contains(index), !title.isEmpty else { return }
        items[index].title = title
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: file, options: .atomic)
        }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    // MARK: Import / export

    /// Adds every http(s) link from a bookmarks HTML file (folders are flattened), skipping duplicates.
    /// Returns how many were added.
    func importHTML(_ html: String) -> Int {
        let pattern = #"<a\s[^>]*?href\s*=\s*"([^"]*)"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return 0 }
        var added = 0
        let ns = html as NSString
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let href = Self.unescape(ns.substring(with: match.range(at: 1)))
            let title = Self.unescape(ns.substring(with: match.range(at: 2)))
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: href), let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https", !contains(url) else { continue }
            items.append(Bookmark(title: title.isEmpty ? (url.host ?? href) : title, url: url))
            added += 1
        }
        if added > 0 { save() }
        return added
    }

    func exportHTML() -> String {
        let now = Int(Date().timeIntervalSince1970)
        var out = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3 ADD_DATE="\(now)" PERSONAL_TOOLBAR_FOLDER="true">Bookmarks Bar</H3>
            <DL><p>

        """
        for b in items {
            out += "            <DT><A HREF=\"\(Self.escape(b.url.absoluteString))\" ADD_DATE=\"\(now)\">\(Self.escape(b.title))</A>\n"
        }
        out += "        </DL><p>\n</DL><p>\n"
        return out
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
    }
}
