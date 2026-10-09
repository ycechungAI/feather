import XCTest
@testable import Feather

final class SessionsTests: XCTestCase {
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

    func testSaveSession() {
        let s = makeSessions()
        let session = s.save(name: "Work", urls: [url("https://a.com"), url("https://b.com")])
        XCTAssertEqual(s.all.count, 1)
        XCTAssertEqual(session.name, "Work")
        XCTAssertEqual(session.urls, [url("https://a.com"), url("https://b.com")])
        XCTAssertEqual(s.session(id: session.id), session)
    }

    func testSaveBlankNameGetsDefault() {
        let s = makeSessions()
        let session = s.save(name: "   ", urls: [url("https://a.com")])
        XCTAssertEqual(session.name, "Untitled Session")
    }

    func testSaveTrimsName() {
        let s = makeSessions()
        let session = s.save(name: "  Work  ", urls: [])
        XCTAssertEqual(session.name, "Work")
    }

    func testSaveEmptyURLs() {
        let s = makeSessions()
        let session = s.save(name: "Empty", urls: [])
        XCTAssertTrue(session.urls.isEmpty)
        XCTAssertEqual(s.all.count, 1)
    }

    // MARK: - Rename

    func testRename() {
        let s = makeSessions()
        let session = s.save(name: "Old", urls: [url("https://a.com")])
        s.rename(session.id, to: "New")
        XCTAssertEqual(s.session(id: session.id)?.name, "New")
        // URLs untouched.
        XCTAssertEqual(s.session(id: session.id)?.urls, [url("https://a.com")])
    }

    func testRenameIgnoresBlankName() {
        let s = makeSessions()
        let session = s.save(name: "Keep", urls: [])
        s.rename(session.id, to: "   ")
        XCTAssertEqual(s.session(id: session.id)?.name, "Keep")
    }

    func testRenameUnknownIdDoesNothing() {
        let s = makeSessions()
        s.save(name: "A", urls: [])
        s.rename(UUID(), to: "B")
        XCTAssertEqual(s.all.map { $0.name }, ["A"])
    }

    // MARK: - Delete

    func testDelete() {
        let s = makeSessions()
        let a = s.save(name: "A", urls: [url("https://a.com")])
        let b = s.save(name: "B", urls: [url("https://b.com")])
        s.delete(a.id)
        XCTAssertEqual(s.all.map { $0.id }, [b.id])
        XCTAssertNil(s.session(id: a.id))
    }

    func testDeleteUnknownIdDoesNothing() {
        let s = makeSessions()
        s.save(name: "A", urls: [])
        s.delete(UUID())
        XCTAssertEqual(s.all.count, 1)
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() {
        let store = tempStore()
        let s = Sessions(storeURL: store)
        s.save(name: "Work", urls: [url("https://a.com"), url("https://b.com")])
        s.save(name: "Play", urls: [url("https://c.com")])

        let reloaded = Sessions(storeURL: store)
        XCTAssertEqual(reloaded.all, s.all)
    }

    func testStartsEmptyWhenNoFile() {
        let s = makeSessions()
        XCTAssertTrue(s.all.isEmpty)
    }

    func testSessionIdsAreUnique() {
        let s = makeSessions()
        let a = s.save(name: "A", urls: [])
        let b = s.save(name: "A", urls: [])
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(s.all.count, 2)
    }
}
