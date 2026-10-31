import Foundation
import Testing
@testable import Feather

struct DownloadFilenameTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("feather-dl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func touch(_ url: URL) { FileManager.default.createFile(atPath: url.path, contents: Data()) }

    @Test func usesTheSuggestedName() throws {
        let dir = try folder()
        #expect(Downloads.uniqueURL(in: dir, for: "report.pdf") == dir.appendingPathComponent("report.pdf"))
    }

    @Test func numbersCollisionsBeforeTheExtension() throws {
        let dir = try folder()
        touch(dir.appendingPathComponent("report.pdf"))
        #expect(Downloads.uniqueURL(in: dir, for: "report.pdf").lastPathComponent == "report (1).pdf")
        touch(dir.appendingPathComponent("report (1).pdf"))
        #expect(Downloads.uniqueURL(in: dir, for: "report.pdf").lastPathComponent == "report (2).pdf")
    }

    @Test func numbersNamesWithoutExtension() throws {
        let dir = try folder()
        touch(dir.appendingPathComponent("README"))
        #expect(Downloads.uniqueURL(in: dir, for: "README").lastPathComponent == "README (1)")
    }

    /// A site's suggested name must never place the file outside the Downloads folder.
    @Test func pathsInTheNameCannotEscapeTheFolder() throws {
        let dir = try folder()
        for name in ["../../.zshrc", "/etc/passwd", "a/b/c.txt", "..", ".", ""] {
            let url = Downloads.uniqueURL(in: dir, for: name)
            #expect(url.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL, "\(name)")
            #expect(![".", ".."].contains(url.lastPathComponent), "\(name)")
        }
    }

    @Test func emptyNamesBecomeDownload() throws {
        let dir = try folder()
        #expect(Downloads.uniqueURL(in: dir, for: "").lastPathComponent == "Download")
        #expect(Downloads.uniqueURL(in: dir, for: "..").lastPathComponent == "Download")
    }

    /// A download that was running when Feather quit can't resume; the list shows it failed.
    @Test func interruptedDownloadsRestoreAsFailed() {
        let record = DownloadItem.Record(id: UUID(), filename: "a.zip", destination: nil, source: nil,
                                         date: Date(), state: .active, totalBytes: 10)
        #expect(DownloadItem(record).state == .failed)
        var done = record
        done.state = .finished
        #expect(DownloadItem(done).state == .finished)
    }
}

struct HistoryPruningTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func entry(daysAgo: Double, _ path: String = "") -> HistoryEntry {
        HistoryEntry(url: URL(string: "https://example.com/\(path)")!, title: path,
                     date: now.addingTimeInterval(-daysAgo * 24 * 3600))
    }

    @Test func dropsVisitsOlderThanAWeek() {
        let entries = [entry(daysAgo: 0, "a"), entry(daysAgo: 6.9, "b"), entry(daysAgo: 7.1, "c"), entry(daysAgo: 30, "d")]
        #expect(History.pruned(entries, now: now).map(\.title) == ["a", "b"])
    }

    @Test func keepsAtMost5000Visits() {
        let entries = (0..<5100).map { entry(daysAgo: Double($0) / 10_000, "\($0)") }
        let kept = History.pruned(entries, now: now)
        #expect(kept.count == 5000)
        #expect(kept.first?.title == "0")
        #expect(kept.last?.title == "4999")
    }

    @Test func keepsOrderNewestFirst() {
        let entries = [entry(daysAgo: 0, "new"), entry(daysAgo: 1, "mid"), entry(daysAgo: 2, "old")]
        #expect(History.pruned(entries, now: now) == entries)
    }

    @Test func emptyStaysEmpty() {
        #expect(History.pruned([], now: now).isEmpty)
    }
}

struct SettingsTests {
    /// Sites like YouTube serve their full experience only to a browser that looks like Safari.
    @Test func userAgentLooksLikeSafari() {
        let parts = Settings.userAgentSuffix.split(separator: " ")
        #expect(parts.count == 2)
        #expect(parts[0].hasPrefix("Version/"))
        #expect(parts[0].dropFirst(8).first?.isNumber == true)
        #expect(parts[1] == "Safari/605.1.15")
    }

    @Test func supportDirectoryIsFeathers() {
        #expect(Settings.supportDirectory.lastPathComponent == "Feather")
        #expect(Settings.supportDirectory.path.contains("Application Support"))
    }
}
