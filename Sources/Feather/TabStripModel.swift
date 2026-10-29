import Foundation

/// One tab in a window's tab strip, as the strip sees it.
struct TabItem: Equatable, Identifiable {
    var id = UUID()
    var url: URL?
    var title: String
    var pinned = false
    var group: UUID?
}

/// The ordered tabs of one window and which is selected. Pure data, no AppKit, so ordering,
/// pinning, groups and saving are testable. Rules: pinned tabs stay together at the left;
/// tabs of one group stay side by side; closing the selected tab selects its right neighbour.
struct TabStripModel: Equatable {
    private(set) var tabs: [TabItem] = []
    private(set) var selected: UUID?

    init() {}

    /// Rebuilds a strip from a saved window.
    init(saved: SavedWindow) {
        for tab in saved.tabs {
            tabs.append(TabItem(url: tab.url, title: tab.title, pinned: tab.pinned == true, group: tab.group))
        }
        tabs = tabs.filter(\.pinned) + tabs.filter { !$0.pinned }
        if tabs.indices.contains(saved.selected) { selected = tabs[saved.selected].id } else { selected = tabs.first?.id }
    }

    var pinnedCount: Int { tabs.prefix { $0.pinned }.count }
    var selectedIndex: Int? { selected.flatMap(index(of:)) }
    func index(of id: UUID) -> Int? { tabs.firstIndex { $0.id == id } }
    func tab(_ id: UUID) -> TabItem? { tabs.first { $0.id == id } }

    /// Inserts a tab at `index` (default: the end), kept inside its pinned or unpinned region.
    mutating func insert(_ tab: TabItem, at index: Int? = nil, select: Bool = true) {
        let item = tab
        let region = item.pinned ? 0...pinnedCount : pinnedCount...tabs.count
        let at = min(max(index ?? tabs.count, region.lowerBound), region.upperBound)
        tabs.insert(item, at: at)
        if select || selected == nil { selected = item.id }
    }

    /// Removes a tab. If it was selected, the tab that slides into its place is selected
    /// (the last tab if it was last). Returns the new selection.
    @discardableResult
    mutating func close(_ id: UUID) -> UUID? {
        guard let i = index(of: id) else { return selected }
        tabs.remove(at: i)
        if selected == id { selected = tabs.isEmpty ? nil : tabs[min(i, tabs.count - 1)].id }
        return selected
    }

    mutating func select(_ id: UUID) {
        if index(of: id) != nil { selected = id }
    }

    /// ⌘1…⌘8 pick that tab; ⌘9 picks the last one.
    mutating func select(shortcut number: Int) {
        guard !tabs.isEmpty, (1...9).contains(number) else { return }
        select(tabs[number == 9 ? tabs.count - 1 : min(number - 1, tabs.count - 1)].id)
    }

    /// ⌃Tab / ⌃⇧Tab, wrapping around.
    mutating func selectNext(_ step: Int = 1) {
        guard let i = selectedIndex, !tabs.isEmpty else { return }
        selected = tabs[((i + step) % tabs.count + tabs.count) % tabs.count].id
    }

    /// Drag-to-reorder. A tab can't leave its pinned or unpinned region.
    mutating func move(_ id: UUID, to index: Int) {
        guard let from = self.index(of: id) else { return }
        let item = tabs.remove(at: from)
        let region = item.pinned ? 0...pinnedCount : pinnedCount...tabs.count
        tabs.insert(item, at: min(max(index, region.lowerBound), region.upperBound))
    }

    /// Pinning moves the tab to the end of the pinned tabs; unpinning, to just after them.
    mutating func setPinned(_ id: UUID, _ pinned: Bool) {
        guard let i = index(of: id), tabs[i].pinned != pinned else { return }
        var item = tabs.remove(at: i)
        item.pinned = pinned
        tabs.insert(item, at: pinnedCount)
    }

    /// Joining a group moves an unpinned tab next to the group's last tab, unless it's
    /// already beside one of the group's tabs.
    mutating func setGroup(_ id: UUID, _ group: UUID?) {
        guard let i = index(of: id), tabs[i].group != group else { return }
        if group == nil || tabs[i].pinned || [i - 1, i + 1].contains(where: { tabs.indices.contains($0) && tabs[$0].group == group }) {
            tabs[i].group = group
            return
        }
        var item = tabs.remove(at: i)
        item.group = group
        if let group, !item.pinned, let last = tabs.lastIndex(where: { $0.group == group && !$0.pinned }) {
            tabs.insert(item, at: last + 1)
        } else {
            tabs.insert(item, at: min(i, tabs.count))
        }
    }

    mutating func update(_ id: UUID, url: URL?, title: String) {
        guard let i = index(of: id) else { return }
        tabs[i].url = url
        tabs[i].title = title
    }

    /// The strip's runs of tabs of the same group, for drawing a group label before each run.
    /// A nil group is a run of ungrouped tabs.
    var runs: [(group: UUID?, range: Range<Int>)] {
        var result: [(group: UUID?, range: Range<Int>)] = []
        for (i, tab) in tabs.enumerated() {
            if let last = result.last, last.group == tab.group {
                result[result.count - 1].range = last.range.lowerBound..<(i + 1)
            } else {
                result.append((tab.group, i..<(i + 1)))
            }
        }
        return result
    }

    /// This window as saved in the session. Tabs without a web address (blank, internal) are skipped.
    func saved() -> SavedWindow? {
        var out: [SavedTab] = []
        var sel = 0
        for tab in tabs {
            guard let url = tab.url, ["http", "https", "file"].contains(url.scheme ?? "") else { continue }
            if tab.id == selected { sel = out.count }
            out.append(SavedTab(url: url, title: tab.title, group: tab.group, pinned: tab.pinned ? true : nil))
        }
        return out.isEmpty ? nil : SavedWindow(tabs: out, selected: sel)
    }
}
