import Foundation

struct Suggestion: Equatable {
    enum Kind: Equatable { case history, bookmark, search }
    var kind: Kind
    var title: String
    /// The page to open. For `.search` rows this is the search-results URL.
    var url: URL
}

/// Address-bar suggestions from your own history and bookmarks. Everything here runs locally;
/// remote search suggestions are only fetched when you turn them on in Settings.
enum Suggestions {
    /// Ranks pages matching `query`: address matches beat title matches, bookmarks and frequently
    /// or recently visited pages rank higher, and each page appears once.
    static func rank(query: String, history: [HistoryEntry], bookmarks: [Bookmark],
                     limit: Int = 8, now: Date = Date()) -> [Suggestion] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let bare = strippedPrefix(q)

        struct Candidate { var url: URL; var title: String; var visits = 0; var last: Date?; var bookmarked = false }
        var candidates: [String: Candidate] = [:]
        var order: [String] = []
        func key(_ url: URL) -> String {
            var s = strippedPrefix(url.absoluteString.lowercased())
            if s.hasSuffix("/") { s.removeLast() }
            return s
        }
        for b in bookmarks {
            let k = key(b.url)
            if candidates[k] == nil { order.append(k); candidates[k] = Candidate(url: b.url, title: b.title) }
            candidates[k]?.bookmarked = true
        }
        for e in history {
            let k = key(e.url)
            if candidates[k] == nil { order.append(k); candidates[k] = Candidate(url: e.url, title: e.title) }
            candidates[k]!.visits += 1
            if candidates[k]!.last.map({ e.date > $0 }) ?? true { candidates[k]!.last = e.date }
            if candidates[k]!.title.isEmpty { candidates[k]!.title = e.title }
        }

        var scored: [(score: Double, index: Int, suggestion: Suggestion)] = []
        for (index, k) in order.enumerated() {
            guard let c = candidates[k] else { continue }
            let title = c.title.lowercased()
            var score: Double
            if k.hasPrefix(bare) {
                score = 100 - Double(k.count) / 20 // shorter addresses (site roots) first
            } else if title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(q) }) {
                score = 60
            } else if title.contains(q) {
                score = 40
            } else if k.contains(q) {
                score = 30
            } else {
                continue
            }
            if c.bookmarked { score += 20 }
            score += Double(min(c.visits, 10)) * 2
            if let last = c.last {
                let age = now.timeIntervalSince(last)
                if age < 86_400 { score += 10 } else if age < 7 * 86_400 { score += 5 }
            }
            let display = c.title.isEmpty ? (c.url.host ?? c.url.absoluteString) : c.title
            scored.append((score, index, Suggestion(kind: c.bookmarked ? .bookmark : .history, title: display, url: c.url)))
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
            .prefix(limit).map(\.suggestion)
    }

    /// Parses an OpenSearch suggestions response: `["query", ["one", "two", ...], ...]`.
    static func parseRemote(_ data: Data) -> [String] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              array.count > 1, let list = array[1] as? [Any] else { return [] }
        return list.compactMap { $0 as? String }
    }

    /// Removes "https://", "http://" and "www." so "you" matches "https://www.youtube.com".
    static func strippedPrefix(_ s: String) -> String {
        var s = s
        for prefix in ["https://", "http://"] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        return s
    }
}
