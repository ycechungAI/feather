import Foundation
import Testing
@testable import Feather

struct SiteDataTests {
    private func entry(_ url: String, daysAgo: Double = 0, now: Date = Date()) -> HistoryEntry {
        HistoryEntry(url: URL(string: url)!, title: "", date: now.addingTimeInterval(-daysAgo * 86400))
    }

    // MARK: - SiteRank

    @Test func testSiteGroupsSubdomains() {
        #expect(SiteRank.site(for: "www.youtube.com") == "youtube.com")
        #expect(SiteRank.site(for: "mail.google.com") == "google.com")
        #expect(SiteRank.site(for: "news.bbc.co.uk") == "bbc.co.uk")
        #expect(SiteRank.site(for: "example.com") == "example.com")
        #expect(SiteRank.site(for: "YouTube.com.") == "youtube.com")
    }

    @Test func testTopSitesByVisits() {
        let entries = [
            entry("https://www.youtube.com/a"), entry("https://m.youtube.com/b"), entry("https://youtube.com/c"),
            entry("https://mail.google.com/"), entry("https://www.google.com/search?q=x"),
            entry("https://example.com/"),
        ]
        #expect(SiteRank.topSites(in: entries, limit: 2) == ["youtube.com", "google.com"])
        #expect(SiteRank.topSites(in: entries, limit: 20).count == 3)
    }

    @Test func testRecordMatching() {
        #expect(SiteRank.record("youtube.com", isIn: ["youtube.com"]))
        #expect(!SiteRank.record("googlevideo.com", isIn: ["youtube.com"]))
    }

    // MARK: - History retention

    @Test func testHistoryKeepsSevenDays() {
        let now = Date()
        let entries = [entry("https://a.com", daysAgo: 0, now: now), entry("https://b.com", daysAgo: 6.9, now: now),
                       entry("https://c.com", daysAgo: 7.1, now: now), entry("https://d.com", daysAgo: 30, now: now)]
        let kept = History.pruned(entries, now: now)
        #expect(kept.map(\.url.host) == ["a.com", "b.com"])
    }

    // MARK: - Bulky media

    /// Builds the header bytes as WebKit stores them: name, UInt32 LE length, 1, value.
    private func record(contentType: String) -> Data {
        var data = Data("junk\u{0}\u{1}https://www.youtube.com/video/x.js".utf8)
        data.append(Data("Content-Type".utf8))
        var length = UInt32(contentType.utf8.count).littleEndian
        data.append(Data(bytes: &length, count: 4))
        data.append(1)
        data.append(Data(contentType.utf8))
        data.append(Data("\u{3}\u{0}\u{0}\u{0}\u{1}Age".utf8))
        return data
    }

    @Test func testReadsContentType() {
        #expect(BulkyMedia.contentType(inRecord: record(contentType: "video/MP2T")) == "video/MP2T")
        #expect(BulkyMedia.contentType(inRecord: record(contentType: "text/javascript; charset=utf-8"))
                == "text/javascript; charset=utf-8")
        #expect(BulkyMedia.contentType(inRecord: Data("nothing here".utf8)) == nil)
    }

    @Test func testBulkyRules() {
        #expect(BulkyMedia.isBulky(contentType: "video/MP2T", size: 10_000))
        #expect(BulkyMedia.isBulky(contentType: "audio/webm", size: 10_000))
        #expect(BulkyMedia.isBulky(contentType: "application/vnd.yt-ump", size: 10_000))
        #expect(BulkyMedia.isBulky(contentType: "image/jpeg", size: 2_000_000))
        #expect(!BulkyMedia.isBulky(contentType: "image/png", size: 40_000))
        // Code and styles load on every visit, so they stay at any size.
        #expect(!BulkyMedia.isBulky(contentType: "text/javascript", size: 3_000_000))
        #expect(!BulkyMedia.isBulky(contentType: "text/css", size: 2_000_000))
        #expect(!BulkyMedia.isBulky(contentType: "font/woff2", size: 2_000_000))
        #expect(!BulkyMedia.isBulky(contentType: "application/wasm", size: 5_000_000))
        // An unreadable entry is never removed.
        #expect(!BulkyMedia.isBulky(contentType: nil, size: 50_000_000))
    }

    @Test func testDropRemovesOnlyBulkyEntries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resource = root.appendingPathComponent("Version 17/Records/P/Resource", isDirectory: true)
        try FileManager.default.createDirectory(at: resource, withIntermediateDirectories: true)
        try record(contentType: "video/mp4").write(to: resource.appendingPathComponent("AAA"))
        try Data(count: 5000).write(to: resource.appendingPathComponent("AAA-blob"))
        try record(contentType: "text/javascript").write(to: resource.appendingPathComponent("BBB"))
        try Data(count: 5000).write(to: resource.appendingPathComponent("BBB-blob"))
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(BulkyMedia.drop(in: root) == 5000)
        let left = try FileManager.default.contentsOfDirectory(atPath: resource.path).sorted()
        #expect(left == ["BBB", "BBB-blob"])
    }

    // MARK: - Staying signed in

    @Test func testKeptCookieDomains() {
        let sites = ["google.com", "gmail.com", "youtube.com"]
        #expect(LoginKeeper.isKept(".google.com", sites: sites))
        #expect(LoginKeeper.isKept("accounts.google.com", sites: sites))
        #expect(LoginKeeper.isKept(".youtube.com", sites: sites))
        #expect(!LoginKeeper.isKept(".example.com", sites: sites))
        #expect(!LoginKeeper.isKept("notgoogle.com", sites: sites))
    }
}
