import Foundation

/// A tab that can come back: its address, title and (in memory only) its back/forward history.
struct ClosedTab {
    var url: URL
    var title: String
    var state: Any?
}

struct SavedTab: Codable, Equatable {
    var url: URL
    var title: String
    /// The saved tab group the tab belongs to, if any. Optional, so older files still load.
    var group: UUID? = nil
}

struct SavedWindow: Codable, Equatable {
    var tabs: [SavedTab]
    var selected: Int
}

/// ⇧⌘T (reopen closed tab) and restoring the last session after a quit or crash.
/// The open tabs are written to `last-session.json` a moment after every change, so even a
/// crash loses at most a second of tab changes. Private windows are never saved.
final class SessionRestore {
    static let shared = SessionRestore(storeURL: Settings.supportDirectory.appendingPathComponent("last-session.json"))
    static let closedTabLimit = 20

    private let storeURL: URL
    private(set) var closedTabs: [ClosedTab] = []
    /// The session as it was when Feather started, before this run overwrote the file.
    private(set) var previousSession: [SavedWindow]
    /// Returns the windows to save; set by the app so this class stays free of AppKit.
    var snapshot: () -> [SavedWindow] = { [] }
    private var pendingSave: DispatchWorkItem?

    init(storeURL: URL) {
        self.storeURL = storeURL
        previousSession = Self.read(storeURL)
    }

    // MARK: Closed tabs

    func pushClosed(_ tab: ClosedTab) {
        guard tab.url.scheme == "http" || tab.url.scheme == "https" || tab.url.scheme == "file" else { return }
        closedTabs.append(tab)
        if closedTabs.count > Self.closedTabLimit { closedTabs.removeFirst(closedTabs.count - Self.closedTabLimit) }
    }

    func popClosed() -> ClosedTab? { closedTabs.popLast() }

    // MARK: Last session

    /// Hands over the previous session once (for restoring); later calls return nothing.
    func takePreviousSession() -> [SavedWindow] {
        defer { previousSession = [] }
        return previousSession
    }

    /// Saves shortly, coalescing bursts of tab changes into one write.
    func setNeedsSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        save(snapshot())
    }

    /// Writes `windows`. An empty list is ignored: closing the last window (which quits Feather)
    /// should leave that window's tabs to restore next time, not an empty session.
    func save(_ windows: [SavedWindow]) {
        let windows = windows.filter { !$0.tabs.isEmpty }
        guard !windows.isEmpty, let data = try? JSONEncoder().encode(windows) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    func load() -> [SavedWindow] { Self.read(storeURL) }

    private static func read(_ url: URL) -> [SavedWindow] {
        guard let data = try? Data(contentsOf: url),
              let windows = try? JSONDecoder().decode([SavedWindow].self, from: data) else { return [] }
        return windows.filter { !$0.tabs.isEmpty }
    }
}
