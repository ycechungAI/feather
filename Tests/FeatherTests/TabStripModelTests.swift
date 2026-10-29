import Foundation
import Testing
@testable import Feather

struct TabStripModelTests {
    private func tab(_ n: String, pinned: Bool = false, group: UUID? = nil) -> TabItem {
        TabItem(url: URL(string: "https://\(n).com"), title: n, pinned: pinned, group: group)
    }

    private func strip(_ names: String...) -> (TabStripModel, [UUID]) {
        var m = TabStripModel()
        var ids: [UUID] = []
        for n in names { let t = tab(n); ids.append(t.id); m.insert(t) }
        return (m, ids)
    }

    private func titles(_ m: TabStripModel) -> [String] { m.tabs.map(\.title) }

    @Test func insertSelectsAndAppends() {
        let (m, ids) = strip("a", "b", "c")
        #expect(titles(m) == ["a", "b", "c"])
        #expect(m.selected == ids[2])
    }

    @Test func backgroundInsertKeepsSelection() {
        var (m, ids) = strip("a")
        m.insert(tab("b"), select: false)
        #expect(m.selected == ids[0])
    }

    @Test func closeSelectsRightNeighbourThenLast() {
        var (m, ids) = strip("a", "b", "c", "d")
        m.select(ids[1])
        #expect(m.close(ids[1]) == ids[2])
        #expect(m.close(ids[3]) == ids[2]) // closing an unselected tab keeps the selection
        m.select(ids[2])
        #expect(m.close(ids[2]) == ids[0])
        #expect(m.close(ids[0]) == nil)
        #expect(m.tabs.isEmpty)
    }

    @Test func shortcutsAndCycling() {
        var (m, ids) = strip("a", "b", "c")
        m.select(shortcut: 1); #expect(m.selected == ids[0])
        m.select(shortcut: 9); #expect(m.selected == ids[2])
        m.select(shortcut: 5); #expect(m.selected == ids[2]) // past the end: last
        m.selectNext(); #expect(m.selected == ids[0])
        m.selectNext(-1); #expect(m.selected == ids[2])
    }

    @Test func pinMovesToPinnedRegionAndUnpinLeavesIt() {
        var (m, ids) = strip("a", "b", "c")
        m.setPinned(ids[2], true)
        #expect(titles(m) == ["c", "a", "b"])
        m.setPinned(ids[0], true)
        #expect(titles(m) == ["c", "a", "b"] && m.pinnedCount == 2)
        m.setPinned(ids[2], false)
        #expect(titles(m) == ["a", "c", "b"] && m.pinnedCount == 1)
    }

    @Test func moveStaysInsideRegion() {
        var (m, ids) = strip("a", "b", "c", "d")
        m.setPinned(ids[0], true)
        m.move(ids[3], to: 0)
        #expect(titles(m) == ["a", "d", "b", "c"]) // can't go before the pinned tab
        m.move(ids[0], to: 3)
        #expect(titles(m) == ["a", "d", "b", "c"]) // pinned can't leave the left end
        m.move(ids[1], to: 3)
        #expect(titles(m) == ["a", "d", "c", "b"])
    }

    @Test func insertingPinnedGoesLeft() {
        var (m, _) = strip("a", "b")
        m.insert(tab("p", pinned: true))
        #expect(titles(m) == ["p", "a", "b"])
        m.insert(tab("x"), at: 0)
        #expect(titles(m) == ["p", "x", "a", "b"])
    }

    @Test func groupMembersStayTogether() {
        let g = UUID()
        var (m, ids) = strip("a", "b", "c", "d")
        m.setGroup(ids[0], g)
        m.setGroup(ids[3], g)
        #expect(titles(m) == ["a", "d", "b", "c"])
        let runs = m.runs
        #expect(runs.map(\.range) == [0..<2, 2..<4])
        #expect(runs.map(\.group) == [g, nil])
        m.setGroup(ids[0], nil)
        #expect(m.tab(ids[0])?.group == nil)
    }

    @Test func runsOfEmptyStripIsEmpty() {
        #expect(TabStripModel().runs.isEmpty)
    }

    @Test func savingSkipsBlankTabsAndKeepsSelection() throws {
        var m = TabStripModel()
        let g = UUID()
        m.insert(tab("a", pinned: true))
        m.insert(TabItem(url: nil, title: "New Tab"))
        let b = tab("b", group: g)
        m.insert(b)
        let saved = try #require(m.saved())
        #expect(saved.tabs.map(\.title) == ["a", "b"])
        #expect(saved.selected == 1)
        #expect(saved.tabs[0].pinned == true && saved.tabs[1].group == g && saved.tabs[1].pinned == nil)
    }

    @Test func savedRoundTrip() throws {
        let g = UUID()
        let saved = SavedWindow(tabs: [
            SavedTab(url: URL(string: "https://x.com")!, title: "x"),
            SavedTab(url: URL(string: "https://p.com")!, title: "p", pinned: true),
            SavedTab(url: URL(string: "https://g.com")!, title: "g", group: g),
        ], selected: 2)
        let m = TabStripModel(saved: saved)
        #expect(titles(m) == ["p", "x", "g"]) // pinned first
        #expect(m.selectedIndex == 2)
        let again = try #require(m.saved())
        #expect(again.tabs.map(\.title) == ["p", "x", "g"] && again.selected == 2)
        #expect(TabStripModel().saved() == nil)
    }
}
