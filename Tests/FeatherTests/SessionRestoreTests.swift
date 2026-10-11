import Foundation
import Testing
@testable import Feather

struct SessionRestoreTests {
    private func tempStore() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    }

    private func closed(_ s: String) -> ClosedTab { ClosedTab(url: URL(string: s)!, title: s, state: nil) }
    private func tab(_ s: String) -> SavedTab { SavedTab(url: URL(string: s)!, title: s) }

    @Test func reopensMostRecentFirst() {
        let r = SessionRestore(storeURL: tempStore())
        r.pushClosed(closed("https://a.com"))
        r.pushClosed(closed("https://b.com"))
        #expect(r.popClosed()?.url.host == "b.com")
        #expect(r.popClosed()?.url.host == "a.com")
        #expect(r.popClosed() == nil)
    }

    @Test func closedStackIsCapped() {
        let r = SessionRestore(storeURL: tempStore())
        for i in 0..<30 { r.pushClosed(closed("https://site\(i).com")) }
        #expect(r.closedTabs.count == SessionRestore.closedTabLimit)
        #expect(r.closedTabs.first?.url.host == "site10.com")
        #expect(r.popClosed()?.url.host == "site29.com")
    }

    @Test func ignoresNonWebPages() {
        let r = SessionRestore(storeURL: tempStore())
        r.pushClosed(closed("about:blank"))
        r.pushClosed(closed("webkit-extension://abc/options.html"))
        #expect(r.closedTabs.isEmpty)
    }

    @Test func sessionRoundTrip() {
        let store = tempStore()
        let windows = [SavedWindow(tabs: [tab("https://a.com"), tab("https://b.com")], selected: 1),
                       SavedWindow(tabs: [tab("https://c.com")], selected: 0)]
        SessionRestore(storeURL: store).save(windows)
        #expect(SessionRestore(storeURL: store).load() == windows)
    }

    @Test func previousSessionIsHandedOverOnce() {
        let store = tempStore()
        SessionRestore(storeURL: store).save([SavedWindow(tabs: [tab("https://a.com")], selected: 0)])
        let next = SessionRestore(storeURL: store)
        #expect(next.takePreviousSession().count == 1)
        #expect(next.takePreviousSession().isEmpty)
    }

    @Test func emptySessionDoesNotOverwrite() {
        let store = tempStore()
        let r = SessionRestore(storeURL: store)
        let windows = [SavedWindow(tabs: [tab("https://a.com")], selected: 0)]
        r.save(windows)
        r.save([])
        r.save([SavedWindow(tabs: [], selected: 0)])
        #expect(r.load() == windows)
    }

    @Test func saveNowUsesSnapshot() {
        let r = SessionRestore(storeURL: tempStore())
        r.snapshot = { [SavedWindow(tabs: [SavedTab(url: URL(string: "https://x.com")!, title: "X")], selected: 0)] }
        r.saveNow()
        #expect(r.load().first?.tabs.first?.title == "X")
    }

    @Test func missingOrCorruptFileIsEmpty() throws {
        let store = tempStore()
        #expect(SessionRestore(storeURL: store).load().isEmpty)
        try "not json".write(to: store, atomically: true, encoding: .utf8)
        #expect(SessionRestore(storeURL: store).load().isEmpty)
    }
}
