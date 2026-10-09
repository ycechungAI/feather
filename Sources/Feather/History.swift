import Foundation
import WebKit

struct HistoryEntry: Codable, Equatable {
    var id = UUID()
    var url: URL
    var title: String
    var date: Date
}

/// Browsing history for normal windows (private windows never record). Newest first,
/// capped so the file stays small, and saved a moment after changes to avoid disk churn.
final class History {
    static let shared = History()
    static let changed = Notification.Name("FeatherHistoryChanged")
    private static let limit = 5000

    private(set) var entries: [HistoryEntry] = []
    private let file = Settings.supportDirectory.appendingPathComponent("history.json")
    private var pendingSave: DispatchWorkItem?

    private init() {
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = saved
        }
    }

    func visit(_ url: URL, title: String?) {
        guard url.scheme == "http" || url.scheme == "https" else { return }
        let now = Date()
        // Reloads and redirects back to the same page refresh the latest entry instead of duplicating it.
        if let first = entries.first, first.url == url, now.timeIntervalSince(first.date) < 30 * 60 {
            entries[0].date = now
            if let title, !title.isEmpty { entries[0].title = title }
        } else {
            entries.insert(HistoryEntry(url: url, title: title ?? "", date: now), at: 0)
            if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        }
        changedAndSave()
    }

    /// Titles usually arrive after the URL; attach them to the matching recent visit.
    func updateTitle(_ title: String, for url: URL?) {
        guard let url, !title.isEmpty,
              let i = entries.prefix(50).firstIndex(where: { $0.url == url }), entries[i].title != title else { return }
        entries[i].title = title
        changedAndSave()
    }

    func remove(ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        changedAndSave()
    }

    func removeAll(host: String) {
        entries.removeAll { $0.url.host == host }
        changedAndSave()
    }

    /// Clears history since `date` (nil = everything), optionally with cookies, cache and site storage.
    func clear(since date: Date?, websiteData: Bool) {
        if let date { entries.removeAll { $0.date >= date } } else { entries.removeAll() }
        changedAndSave()
        if websiteData {
            WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                    modifiedSince: date ?? .distantPast) {}
        }
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: file, options: .atomic)
        }
    }

    private func changedAndSave() {
        NotificationCenter.default.post(name: Self.changed, object: nil)
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
