import Foundation
import Testing
@testable import Feather

struct TabGroupsTests {
    private func tempStore() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    private func makeGroups() -> TabGroups {
        TabGroups(storeURL: tempStore())
    }

    private func tab(_ string: String) -> SavedTab { SavedTab(url: URL(string: string)!, title: string) }

    // MARK: - Create

    @Test func testCreate() {
        let g = makeGroups()
        let group = g.create(name: "Work", color: .blue, tabs: [tab("https://a.com"), tab("https://b.com")])
        #expect(g.all.count == 1)
        #expect(group.name == "Work")
        #expect(group.color == .blue)
        #expect(group.tabs == [tab("https://a.com"), tab("https://b.com")])
        #expect(g.group(id: group.id) == group)
    }

    @Test func testCreateBlankNameGetsDefault() {
        let g = makeGroups()
        #expect(g.create(name: "  ", color: .red, tabs: []).name == "Untitled Group")
        #expect(g.create(name: "  Trip ", color: .red, tabs: []).name == "Trip")
    }

    @Test func testSuggestedColorPicksUnusedThenCycles() {
        let g = makeGroups()
        #expect(g.suggestedColor == .grey)
        g.create(name: "A", color: .grey, tabs: [])
        #expect(g.suggestedColor == .blue)
        for color in TabGroupColor.allCases where color != .grey { g.create(name: "x", color: color, tabs: []) }
        #expect(g.suggestedColor == TabGroupColor.allCases[g.all.count % TabGroupColor.allCases.count])
    }

    // MARK: - Rename / recolor

    @Test func testRename() {
        let g = makeGroups()
        let group = g.create(name: "Old", color: .green, tabs: [tab("https://a.com")])
        g.rename(group.id, to: " New ")
        #expect(g.group(id: group.id)?.name == "New")
        #expect(g.group(id: group.id)?.tabs == [tab("https://a.com")])
    }

    @Test func testRenameIgnoresBlankAndUnknown() {
        let g = makeGroups()
        let group = g.create(name: "Keep", color: .green, tabs: [])
        g.rename(group.id, to: "   ")
        g.rename(UUID(), to: "Other")
        #expect(g.all.map(\.name) == ["Keep"])
    }

    @Test func testSetColor() {
        let g = makeGroups()
        let group = g.create(name: "A", color: .green, tabs: [])
        g.setColor(group.id, to: .purple)
        #expect(g.group(id: group.id)?.color == .purple)
    }

    // MARK: - Tabs

    @Test func testAddAndRemoveTabs() {
        let g = makeGroups()
        let group = g.create(name: "A", color: .blue, tabs: [tab("https://a.com")])
        g.addTab(tab("https://b.com"), to: group.id)
        g.addTab(tab("https://a.com"), to: group.id)
        #expect(g.group(id: group.id)?.tabs.map(\.url.absoluteString) == ["https://a.com", "https://b.com", "https://a.com"])
        g.removeTab(url: URL(string: "https://a.com")!, from: group.id)
        #expect(g.group(id: group.id)?.tabs.map(\.url.absoluteString) == ["https://b.com", "https://a.com"])
        g.removeTab(url: URL(string: "https://missing.com")!, from: group.id)
        #expect(g.group(id: group.id)?.tabs.count == 2)
    }

    @Test func testSetTabsKeepsGroupWhenEmpty() {
        let g = makeGroups()
        let group = g.create(name: "A", color: .blue, tabs: [tab("https://a.com")])
        g.setTabs([tab("https://b.com"), tab("https://c.com")], of: group.id)
        #expect(g.group(id: group.id)?.tabs == [tab("https://b.com"), tab("https://c.com")])
        g.setTabs([], of: group.id)
        #expect(g.group(id: group.id)?.tabs == [tab("https://b.com"), tab("https://c.com")])
    }

    @Test func testSyncUsesOpenTabs() {
        let g = makeGroups()
        let a = g.create(name: "A", color: .blue, tabs: [tab("https://a.com")])
        let b = g.create(name: "B", color: .red, tabs: [tab("https://b.com")])
        g.openTabs = { [a.id: [tab("https://a2.com")], UUID(): [tab("https://x.com")]] }
        g.syncNow()
        #expect(g.group(id: a.id)?.tabs == [tab("https://a2.com")])
        #expect(g.group(id: b.id)?.tabs == [tab("https://b.com")]) // closed: kept as saved
        #expect(g.all.count == 2)
    }

    // MARK: - Delete

    @Test func testDelete() {
        let g = makeGroups()
        let a = g.create(name: "A", color: .blue, tabs: [])
        let b = g.create(name: "B", color: .blue, tabs: [])
        g.delete(a.id)
        g.delete(UUID())
        #expect(g.all.map(\.id) == [b.id])
    }

    // MARK: - Persistence

    @Test func testPersistenceRoundTrip() {
        let store = tempStore()
        let g = TabGroups(storeURL: store)
        let a = g.create(name: "Work", color: .orange, tabs: [tab("https://a.com"), tab("https://b.com")])
        g.create(name: "Play", color: .yellow, tabs: [tab("https://c.com")])
        g.rename(a.id, to: "Office")
        g.setColor(a.id, to: .brown)

        let reloaded = TabGroups(storeURL: store)
        #expect(reloaded.all == g.all)
    }

    @Test func testStartsEmptyWhenNoFileOrGarbage() throws {
        #expect(makeGroups().all.isEmpty)
        let store = tempStore()
        try Data("not json".utf8).write(to: store)
        #expect(TabGroups(storeURL: store).all.isEmpty)
    }

    // MARK: - Migration-safe decoding

    @Test func testDecodesMissingFieldsAndUnknownColor() throws {
        let store = tempStore()
        let json = """
        [
          {"id": "11111111-1111-1111-1111-111111111111", "name": "Old", "tabs": [{"url": "https://a.com", "title": "A"}]},
          {"name": "Future", "color": "magenta", "tabs": [{"url": "https://b.com", "title": "B"}, {"title": "no url"}], "pinned": true},
          42
        ]
        """
        try Data(json.utf8).write(to: store)
        let g = TabGroups(storeURL: store)
        #expect(g.all.count == 2)
        #expect(g.all[0].id == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(g.all[0].color == .grey)
        #expect(g.all[0].tabs == [SavedTab(url: URL(string: "https://a.com")!, title: "A")])
        #expect(g.all[1].name == "Future")
        #expect(g.all[1].color == .grey)
        #expect(g.all[1].tabs.map(\.title) == ["B"])
    }

    @Test func testSavedTabGroupIsOptional() throws {
        let old = try JSONDecoder().decode(SavedTab.self, from: Data(#"{"url":"https://a.com","title":"A"}"#.utf8))
        #expect(old.group == nil)
        let id = UUID()
        let grouped = SavedTab(url: URL(string: "https://a.com")!, title: "A", group: id)
        let decoded = try JSONDecoder().decode(SavedTab.self, from: JSONEncoder().encode(grouped))
        #expect(decoded.group == id)
        // Ungrouped tabs are written exactly as before.
        let plain = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        #expect(!plain.contains("group"))
    }
}
