import Foundation
import Testing
@testable import Feather

struct SessionsTests {
    private func tempStore() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    private func makeSessions() -> Sessions {
        Sessions(storeURL: tempStore())
    }

    private func url(_ string: String) -> URL { URL(string: string)! }

    // MARK: - Save / list

    @Test func testSaveSession() {
        let s = makeSessions()
        let session = s.save(name: "Work", urls: [url("https://a.com"), url("https://b.com")])
        #expect(s.all.count == 1)
        #expect(session.name == "Work")
        #expect(session.urls == [url("https://a.com"), url("https://b.com")])
        #expect(s.session(id: session.id) == session)
    }

    @Test func testSaveBlankNameGetsDefault() {
        let s = makeSessions()
        let session = s.save(name: "   ", urls: [url("https://a.com")])
        #expect(session.name == "Untitled Session")
    }

    @Test func testSaveTrimsName() {
        let s = makeSessions()
        let session = s.save(name: "  Work  ", urls: [])
        #expect(session.name == "Work")
    }

    @Test func testSaveEmptyURLs() {
        let s = makeSessions()
        let session = s.save(name: "Empty", urls: [])
        #expect(session.urls.isEmpty)
        #expect(s.all.count == 1)
    }

    // MARK: - Rename

    @Test func testRename() {
        let s = makeSessions()
        let session = s.save(name: "Old", urls: [url("https://a.com")])
        s.rename(session.id, to: "New")
        #expect(s.session(id: session.id)?.name == "New")
        // URLs untouched.
        #expect(s.session(id: session.id)?.urls == [url("https://a.com")])
    }

    @Test func testRenameIgnoresBlankName() {
        let s = makeSessions()
        let session = s.save(name: "Keep", urls: [])
        s.rename(session.id, to: "   ")
        #expect(s.session(id: session.id)?.name == "Keep")
    }

    @Test func testRenameUnknownIdDoesNothing() {
        let s = makeSessions()
        s.save(name: "A", urls: [])
        s.rename(UUID(), to: "B")
        #expect(s.all.map { $0.name } == ["A"])
    }

    // MARK: - Delete

    @Test func testDelete() {
        let s = makeSessions()
        let a = s.save(name: "A", urls: [url("https://a.com")])
        let b = s.save(name: "B", urls: [url("https://b.com")])
        s.delete(a.id)
        #expect(s.all.map { $0.id } == [b.id])
        #expect(s.session(id: a.id) == nil)
    }

    @Test func testDeleteUnknownIdDoesNothing() {
        let s = makeSessions()
        s.save(name: "A", urls: [])
        s.delete(UUID())
        #expect(s.all.count == 1)
    }

    // MARK: - Persistence

    @Test func testPersistenceRoundTrip() {
        let store = tempStore()
        let s = Sessions(storeURL: store)
        s.save(name: "Work", urls: [url("https://a.com"), url("https://b.com")])
        s.save(name: "Play", urls: [url("https://c.com")])

        let reloaded = Sessions(storeURL: store)
        #expect(reloaded.all == s.all)
    }

    @Test func testStartsEmptyWhenNoFile() {
        let s = makeSessions()
        #expect(s.all.isEmpty)
    }

    @Test func testSessionIdsAreUnique() {
        let s = makeSessions()
        let a = s.save(name: "A", urls: [])
        let b = s.save(name: "A", urls: [])
        #expect(a.id != b.id)
        #expect(s.all.count == 2)
    }
}
