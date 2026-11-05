import Foundation

/// A tab group's color. Each one has an emoji dot, because the dot is all a native
/// macOS tab title can show.
enum TabGroupColor: String, Codable, CaseIterable {
    case grey, blue, red, yellow, green, purple, orange, brown

    var dot: String {
        switch self {
        case .grey: "⚪️"
        case .blue: "🔵"
        case .red: "🔴"
        case .yellow: "🟡"
        case .green: "🟢"
        case .purple: "🟣"
        case .orange: "🟠"
        case .brown: "🟤"
        }
    }

    var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// A color a newer version added (or a typo in the file) reads as grey instead of
    /// failing the whole group.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .grey
    }
}

/// A saved tab group: a name, a color and its tabs. The tabs are kept up to date while the
/// group is open, and stay saved after it closes.
struct TabGroup: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var color: TabGroupColor
    var tabs: [SavedTab]
    var created: Date

    init(id: UUID = UUID(), name: String, color: TabGroupColor, tabs: [SavedTab], created: Date = Date()) {
        self.id = id
        self.name = name
        self.color = color
        self.tabs = tabs
        self.created = created
    }

    /// Missing fields get defaults, so files from older or newer versions still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled Group"
        color = (try? c.decodeIfPresent(TabGroupColor.self, forKey: .color)) ?? .grey
        tabs = (try? c.decodeIfPresent([Lossy<SavedTab>].self, forKey: .tabs))?.compactMap(\.value) ?? []
        created = (try? c.decodeIfPresent(Date.self, forKey: .created)) ?? Date()
    }
}

/// Decodes one element of an array, or nil if it's malformed, so one bad entry
/// doesn't lose the rest.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// Saved tab groups, stored as JSON in the app's support folder.
final class TabGroups {
    static let shared = TabGroups()
    static let changed = Notification.Name("FeatherTabGroupsChanged")

    private(set) var groups: [TabGroup] = []
    private let file: URL
    /// Returns each open group's tabs, in tab order; set by the app so this class stays free of AppKit.
    var openTabs: () -> [UUID: [SavedTab]] = { [:] }
    private var pendingSync: DispatchWorkItem?

    private convenience init() {
        self.init(storeURL: Settings.supportDirectory.appendingPathComponent("tab-groups.json"))
    }

    /// Loads from (and saves to) the given file instead of the app's support folder,
    /// so tests don't touch the real groups or the shared singleton.
    init(storeURL: URL) {
        file = storeURL
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode([Lossy<TabGroup>].self, from: data) {
            groups = decoded.compactMap(\.value)
        }
    }

    var all: [TabGroup] { groups }

    func group(id: UUID) -> TabGroup? {
        groups.first { $0.id == id }
    }

    /// The color for a new group: the first one no group uses yet, then round again.
    var suggestedColor: TabGroupColor {
        let used = Set(groups.map(\.color))
        return TabGroupColor.allCases.first { !used.contains($0) }
            ?? TabGroupColor.allCases[groups.count % TabGroupColor.allCases.count]
    }

    @discardableResult
    func create(name: String, color: TabGroupColor, tabs: [SavedTab]) -> TabGroup {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = TabGroup(name: clean.isEmpty ? "Untitled Group" : clean, color: color, tabs: tabs)
        groups.append(group)
        persist()
        return group
    }

    func rename(_ id: UUID, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        modify(id) { $0.name = clean }
    }

    func setColor(_ id: UUID, to color: TabGroupColor) {
        modify(id) { $0.color = color }
    }

    func addTab(_ tab: SavedTab, to id: UUID) {
        modify(id) { $0.tabs.append(tab) }
    }

    /// Removes the first tab with this URL.
    func removeTab(url: URL, from id: UUID) {
        modify(id) { group in
            if let i = group.tabs.firstIndex(where: { $0.url == url }) { group.tabs.remove(at: i) }
        }
    }

    /// Replaces a group's tabs with what's open now. An empty list is ignored: when a group's
    /// window closes, its tabs stay saved for next time.
    func setTabs(_ tabs: [SavedTab], of id: UUID) {
        guard !tabs.isEmpty else { return }
        modify(id) { $0.tabs = tabs }
    }

    func delete(_ id: UUID) {
        let before = groups.count
        groups.removeAll { $0.id == id }
        if groups.count != before { persist() }
    }

    // MARK: Following open tabs

    /// Updates open groups shortly, after a burst of tab changes settles. Closing a window
    /// closes its tabs one by one; by the time this runs they're all gone and the group is kept.
    func setNeedsSync() {
        pendingSync?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.syncNow() }
        pendingSync = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func syncNow() {
        pendingSync?.cancel()
        pendingSync = nil
        for (id, tabs) in openTabs() { setTabs(tabs, of: id) }
    }

    private func modify(_ id: UUID, _ change: (inout TabGroup) -> Void) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        var group = groups[i]
        change(&group)
        guard group != groups[i] else { return }
        groups[i] = group
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(groups) {
            try? data.write(to: file, options: .atomic)
        }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}
