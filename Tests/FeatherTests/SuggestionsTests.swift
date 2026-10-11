import Foundation
import Testing
@testable import Feather

struct SuggestionsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func visit(_ url: String, _ title: String = "", daysAgo: Double = 0) -> HistoryEntry {
        HistoryEntry(url: URL(string: url)!, title: title, date: now.addingTimeInterval(-daysAgo * 86_400))
    }

    private func bookmark(_ url: String, _ title: String) -> Bookmark {
        Bookmark(title: title, url: URL(string: url)!)
    }

    @Test func emptyQueryReturnsNothing() {
        let r = Suggestions.rank(query: "  ", history: [visit("https://a.com")], bookmarks: [], now: now)
        #expect(r.isEmpty)
    }

    @Test func addressPrefixIgnoresSchemeAndWWW() {
        let r = Suggestions.rank(query: "you", history: [visit("https://www.youtube.com/", "YouTube")],
                                 bookmarks: [], now: now)
        #expect(r.map(\.url.absoluteString) == ["https://www.youtube.com/"])
    }

    @Test func addressMatchBeatsTitleMatch() {
        let r = Suggestions.rank(query: "git",
                                 history: [visit("https://example.com/post", "Learning Git"),
                                           visit("https://github.com/", "GitHub")],
                                 bookmarks: [], now: now)
        #expect(r.first?.url.host == "github.com")
        #expect(r.count == 2)
    }

    @Test func titleWordMatch() {
        let r = Suggestions.rank(query: "weather", history: [visit("https://example.com/x", "Local Weather Today")],
                                 bookmarks: [], now: now)
        #expect(r.count == 1)
    }

    @Test func noMatchIsExcluded() {
        let r = Suggestions.rank(query: "zzz", history: [visit("https://a.com", "Apple")], bookmarks: [], now: now)
        #expect(r.isEmpty)
    }

    @Test func duplicateVisitsAppearOnce() {
        let history = [visit("https://news.com/"), visit("https://news.com"), visit("http://www.news.com/")]
        let r = Suggestions.rank(query: "news", history: history, bookmarks: [], now: now)
        #expect(r.count == 1)
    }

    @Test func bookmarkAndHistoryMerge() {
        let r = Suggestions.rank(query: "docs", history: [visit("https://docs.swift.org/")],
                                 bookmarks: [bookmark("https://docs.swift.org/", "Swift Docs")], now: now)
        #expect(r.count == 1)
        #expect(r.first?.kind == .bookmark)
        #expect(r.first?.title == "Swift Docs")
    }

    @Test func bookmarksAndFrequentPagesRankHigher() {
        let history = [visit("https://shop-a.com/", "Shop A", daysAgo: 30)]
            + Array(repeating: visit("https://shop-b.com/", "Shop B", daysAgo: 30), count: 5)
        let r = Suggestions.rank(query: "shop", history: history, bookmarks: [], now: now)
        #expect(r.first?.title == "Shop B")

        let r2 = Suggestions.rank(query: "shop", history: [visit("https://shop-a.com/", "Shop A", daysAgo: 30)],
                                  bookmarks: [bookmark("https://shop-c.com/", "Shop C")], now: now)
        #expect(r2.first?.title == "Shop C")
    }

    @Test func recentBeatsOld() {
        let history = [visit("https://old.example.com/", "Example", daysAgo: 60),
                       visit("https://new.example.com/", "Example", daysAgo: 0.1)]
        let r = Suggestions.rank(query: "example", history: history, bookmarks: [], now: now)
        #expect(r.first?.url.host == "new.example.com")
    }

    @Test func shorterAddressFirstForSamePrefix() {
        let history = [visit("https://site.com/a/very/long/path", "Site"), visit("https://site.com/", "Site")]
        let r = Suggestions.rank(query: "site", history: history, bookmarks: [], now: now)
        #expect(r.first?.url.absoluteString == "https://site.com/")
    }

    @Test func respectsLimit() {
        let history = (0..<20).map { visit("https://site\($0).com/", "Site \($0)") }
        #expect(Suggestions.rank(query: "site", history: history, bookmarks: [], limit: 5, now: now).count == 5)
    }

    @Test func untitledPagesShowHost() {
        let r = Suggestions.rank(query: "abc", history: [visit("https://abc.com/")], bookmarks: [], now: now)
        #expect(r.first?.title == "abc.com")
    }

    @Test func parsesOpenSearchResponse() {
        let data = Data(#"["swi",["swift","swift ui","swiftly"],[],[]]"#.utf8)
        #expect(Suggestions.parseRemote(data) == ["swift", "swift ui", "swiftly"])
        #expect(Suggestions.parseRemote(Data("garbage".utf8)).isEmpty)
        #expect(Suggestions.parseRemote(Data(#"{"a":1}"#.utf8)).isEmpty)
    }
}
