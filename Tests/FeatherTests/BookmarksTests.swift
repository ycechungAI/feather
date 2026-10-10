import XCTest
@testable import Feather

final class BookmarksTests: XCTestCase {
    private func tempStore() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    private func makeBookmarks() -> Bookmarks {
        Bookmarks(storeURL: tempStore())
    }

    private func url(_ string: String) -> URL { URL(string: string)! }

    // MARK: - Basic CRUD

    func testAddBookmark() {
        let b = makeBookmarks()
        b.add(title: "Example", url: url("https://example.com"))
        XCTAssertEqual(b.items.count, 1)
        XCTAssertEqual(b.items.first?.bookmark?.title, "Example")
        XCTAssertEqual(b.items.first?.bookmark?.url, url("https://example.com"))
    }

    func testAddUsesHostWhenTitleEmpty() {
        let b = makeBookmarks()
        b.add(title: "", url: url("https://example.com/page"))
        XCTAssertEqual(b.items.first?.title, "example.com")
    }

    func testAddDuplicateURLIgnored() {
        let b = makeBookmarks()
        b.add(title: "A", url: url("https://example.com"))
        b.add(title: "B", url: url("https://example.com"))
        XCTAssertEqual(b.items.count, 1)
        XCTAssertEqual(b.items.first?.title, "A")
    }

    func testContains() {
        let b = makeBookmarks()
        XCTAssertFalse(b.contains(url("https://example.com")))
        XCTAssertFalse(b.contains(nil))
        b.add(title: "A", url: url("https://example.com"))
        XCTAssertTrue(b.contains(url("https://example.com")))
    }

    func testRemoveByURL() {
        let b = makeBookmarks()
        b.add(title: "A", url: url("https://a.com"))
        b.add(title: "B", url: url("https://b.com"))
        b.remove(url("https://a.com"))
        XCTAssertEqual(b.flattenedBookmarks.map { $0.url }, [url("https://b.com")])
    }

    func testRemoveByURLFindsNestedBookmarks() {
        let b = makeBookmarks()
        b.add(title: "A", url: url("https://a.com"))
        let fi = b.addFolder(title: "F")
        b.moveNode(from: IndexPath(index: 0), to: IndexPath(indexes: [fi, 0]))
        b.remove(url("https://a.com"))
        XCTAssertTrue(b.flattenedBookmarks.isEmpty)
        // The folder itself remains, now empty.
        XCTAssertEqual(b.items.count, 1)
        XCTAssertNotNil(b.items.first?.folder)
    }

    func testRemoveAtRoot() {
        let b = makeBookmarks()
        b.add(title: "A", url: url("https://a.com"))
        b.add(title: "B", url: url("https://b.com"))
        b.remove(at: 0)
        XCTAssertEqual(b.items.count, 1)
        XCTAssertEqual(b.items.first?.title, "B")
    }

    func testRemoveAtInvalidIndexDoesNothing() {
        let b = makeBookmarks()
        b.add(title: "A", url: url("https://a.com"))
        b.remove(at: 5)
        b.remove(at: -1)
        XCTAssertEqual(b.items.count, 1)
    }

    func testRenameBookmark() {
        let b = makeBookmarks()
        b.add(title: "A", url: url("https://a.com"))
        b.rename(at: 0, to: "Renamed")
        XCTAssertEqual(b.items.first?.title, "Renamed")
    }

    func testRenameIgnoresEmptyTitle() {
        let b = makeBookmarks()
        b.add(title: "A", url: url("https://a.com"))
        b.rename(at: 0, to: "   ")
        XCTAssertEqual(b.items.first?.title, "A")
    }

    // MARK: - Reordering

    func testMoveRootForward() {
        let b = makeBookmarks()
        ["a", "b", "c", "d"].forEach { b.add(title: $0, url: url("https://\($0).com")) }
        b.move(from: 0, to: 3)
        XCTAssertEqual(b.items.map { $0.title }, ["b", "c", "a", "d"])
    }

    func testMoveRootBackward() {
        let b = makeBookmarks()
        ["a", "b", "c", "d"].forEach { b.add(title: $0, url: url("https://\($0).com")) }
        b.move(from: 3, to: 0)
        XCTAssertEqual(b.items.map { $0.title }, ["d", "a", "b", "c"])
    }

    func testMoveToSameIndexIsNoOp() {
        let b = makeBookmarks()
        ["a", "b"].forEach { b.add(title: $0, url: url("https://\($0).com")) }
        b.move(from: 1, to: 1)
        XCTAssertEqual(b.items.map { $0.title }, ["a", "b"])
    }

    func testMoveWithInvalidSourceDoesNothing() {
        let b = makeBookmarks()
        b.add(title: "a", url: url("https://a.com"))
        b.move(from: 9, to: 0)
        XCTAssertEqual(b.items.map { $0.title }, ["a"])
    }

    // MARK: - Folders

    func testAddFolder() {
        let b = makeBookmarks()
        let index = b.addFolder(title: "Dev")
        XCTAssertEqual(index, 0)
        XCTAssertEqual(b.items.first?.folder?.title, "Dev")
        XCTAssertEqual(b.items.first?.folder?.children.count, 0)
    }

    func testAddFolderBlankTitleGetsDefault() {
        let b = makeBookmarks()
        b.addFolder(title: "   ")
        XCTAssertEqual(b.items.first?.folder?.title, "New Folder")
    }

    func testRenameFolder() {
        let b = makeBookmarks()
        b.addFolder(title: "Dev")
        b.renameFolder(at: 0, to: "Work")
        XCTAssertEqual(b.items.first?.folder?.title, "Work")
    }

    func testRenameFolderIgnoresNonFolders() {
        let b = makeBookmarks()
        b.add(title: "A", url: url("https://a.com"))
        b.renameFolder(at: 0, to: "Nope")
        XCTAssertEqual(b.items.first?.title, "A")
        XCTAssertNil(b.items.first?.folder)
    }

    func testDeleteFolderDeletesContents() {
        let b = makeBookmarks()
        let fi = b.addFolder(title: "F")
        b.add(title: "A", url: url("https://a.com"))
        b.moveNode(from: IndexPath(index: 1), to: IndexPath(indexes: [fi, 0]))
        XCTAssertEqual(b.flattenedBookmarks.count, 1)
        b.removeNode(at: IndexPath(index: fi))
        XCTAssertTrue(b.items.isEmpty)
        XCTAssertTrue(b.flattenedBookmarks.isEmpty)
    }

    func testMoveNodeIntoFolder() {
        let b = makeBookmarks()
        b.add(title: "A", url: url("https://a.com"))
        let fi = b.addFolder(title: "F")
        b.moveNode(from: IndexPath(index: 0), to: IndexPath(indexes: [fi, 0]))
        XCTAssertEqual(b.items.count, 1)
        XCTAssertEqual(b.items.first?.folder?.children.map { $0.title }, ["A"])
    }

    func testMoveNodeOutOfFolder() {
        let b = makeBookmarks()
        let fi = b.addFolder(title: "F")
        b.add(title: "A", url: url("https://a.com"))
        b.moveNode(from: IndexPath(index: 1), to: IndexPath(indexes: [fi, 0]))
        b.moveNode(from: IndexPath(indexes: [fi, 0]), to: IndexPath(index: 1))
        XCTAssertEqual(b.items.map { $0.title }, ["F", "A"])
        XCTAssertEqual(b.items.first?.folder?.children.count, 0)
    }

    func testMoveFolderIntoItselfIsRefused() {
        let b = makeBookmarks()
        let fi = b.addFolder(title: "F")
        b.moveNode(from: IndexPath(index: fi), to: IndexPath(indexes: [fi, 0]))
        XCTAssertEqual(b.items.count, 1)
        XCTAssertEqual(b.items.first?.folder?.children.count, 0)
    }

    func testMoveNodeBetweenFolders() {
        let b = makeBookmarks()
        let f1 = b.addFolder(title: "One")
        let f2 = b.addFolder(title: "Two")
        b.add(title: "A", url: url("https://a.com"))
        b.moveNode(from: IndexPath(index: 2), to: IndexPath(indexes: [f1, 0]))
        b.moveNode(from: IndexPath(indexes: [f1, 0]), to: IndexPath(indexes: [f2, 0]))
        XCTAssertNil(b.node(at: IndexPath(indexes: [f1, 0])))
        XCTAssertEqual(b.node(at: IndexPath(indexes: [f2, 0]))?.title, "A")
    }

    func testNodeAtInvalidPathReturnsNil() {
        let b = makeBookmarks()
        XCTAssertNil(b.node(at: IndexPath(index: 0)))
        b.addFolder(title: "F")
        XCTAssertNil(b.node(at: IndexPath(indexes: [0, 5])))
        XCTAssertNil(b.node(at: IndexPath()))
    }

    func testFlattenedBookmarks() {
        let b = makeBookmarks()
        b.add(title: "Root", url: url("https://root.com"))
        let fi = b.addFolder(title: "F")
        b.add(title: "A", url: url("https://a.com"))
        b.moveNode(from: IndexPath(index: 2), to: IndexPath(indexes: [fi, 0]))
        XCTAssertEqual(b.flattenedBookmarks.map { $0.title }, ["Root", "A"])
    }

    // MARK: - Reordering within a folder

    func testMoveUpAndDownAtRoot() {
        let b = makeBookmarks()
        ["a", "b", "c"].forEach { b.add(title: $0, url: url("https://\($0).com")) }
        XCTAssertTrue(b.moveDown(at: IndexPath(index: 0)))
        XCTAssertEqual(b.items.map { $0.title }, ["b", "a", "c"])
        XCTAssertTrue(b.moveUp(at: IndexPath(index: 1)))
        XCTAssertEqual(b.items.map { $0.title }, ["a", "b", "c"])
        XCTAssertFalse(b.moveUp(at: IndexPath(index: 0)))
        XCTAssertFalse(b.moveDown(at: IndexPath(index: 2)))
    }

    func testMoveUpAndDownWithinFolder() {
        let b = makeBookmarks()
        let fi = b.addFolder(title: "F")
        ["x", "y", "z"].forEach { b.add(title: $0, url: url("https://\($0).com")) }
        for i in 0..<3 {
            b.moveNode(from: IndexPath(index: 1), to: IndexPath(indexes: [fi, i]))
        }
        XCTAssertEqual(b.items[fi].folder?.children.map { $0.title }, ["x", "y", "z"])
        XCTAssertTrue(b.moveDown(at: IndexPath(indexes: [fi, 0])))
        XCTAssertEqual(b.items[fi].folder?.children.map { $0.title }, ["y", "x", "z"])
        XCTAssertTrue(b.moveUp(at: IndexPath(indexes: [fi, 1])))
        XCTAssertEqual(b.items[fi].folder?.children.map { $0.title }, ["x", "y", "z"])
        XCTAssertFalse(b.moveUp(at: IndexPath(indexes: [fi, 0])))
        XCTAssertFalse(b.moveDown(at: IndexPath(indexes: [fi, 2])))
    }

    func testAddFolderInsideFolder() {
        let b = makeBookmarks()
        let fi = b.addFolder(title: "F")
        let sub = b.addFolder(title: "Sub", in: IndexPath(index: fi))
        XCTAssertEqual(sub, IndexPath(indexes: [fi, 0]))
        XCTAssertEqual(b.items[fi].folder?.children.first?.folder?.title, "Sub")
    }

    func testAddFolderInsideBookmarkIsNoOp() {
        let b = makeBookmarks()
        b.add(title: "A", url: url("https://a.com"))
        XCTAssertNil(b.addFolder(title: "Sub", in: IndexPath(index: 0)))
        XCTAssertEqual(b.items.count, 1)
    }

    func testMoveFolderIntoFolder() {
        let b = makeBookmarks()
        b.addFolder(title: "One")
        let two = b.addFolder(title: "Two")
        b.moveNode(from: IndexPath(index: 0), to: IndexPath(indexes: [two, 0]))
        XCTAssertEqual(b.items.map { $0.title }, ["Two"])
        XCTAssertEqual(b.items[0].folder?.children.first?.folder?.title, "One")
    }

    func testMoveFolderIntoDescendantIsRefused() {
        let b = makeBookmarks()
        let fi = b.addFolder(title: "F")
        b.addFolder(title: "Sub", in: IndexPath(index: fi))
        // F must not be movable into its own child.
        b.moveNode(from: IndexPath(index: fi), to: IndexPath(indexes: [fi, 0, 0]))
        XCTAssertEqual(b.items.count, 1)
        XCTAssertEqual(b.items[0].folder?.children.first?.folder?.title, "Sub")
        XCTAssertEqual(b.items[0].folder?.children.first?.folder?.children.count, 0)
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() {
        let store = tempStore()
        let b = Bookmarks(storeURL: store)
        b.add(title: "A", url: url("https://a.com"))
        let fi = b.addFolder(title: "F")
        b.add(title: "B", url: url("https://b.com"))
        b.moveNode(from: IndexPath(index: 2), to: IndexPath(indexes: [fi, 0]))

        let reloaded = Bookmarks(storeURL: store)
        XCTAssertEqual(reloaded.items, b.items)
    }

    func testMigrationFromFlatJSON() throws {
        let store = tempStore()
        let old = #"[{"title":"A","url":"https://a.com"},{"title":"B","url":"https://b.com"}]"#
        try old.write(to: store, atomically: true, encoding: .utf8)

        let b = Bookmarks(storeURL: store)
        XCTAssertEqual(b.items.count, 2)
        XCTAssertEqual(b.items.map { $0.title }, ["A", "B"])
        XCTAssertTrue(b.items.allSatisfy { $0.bookmark != nil })

        // The migrated file is rewritten in the new format.
        let json = try String(contentsOf: store, encoding: .utf8)
        XCTAssertTrue(json.contains("\"kind\""))
    }

    // MARK: - Import / export

    private var nestedHTML: String {
        """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
        <DT><H3>Dev</H3>
        <DL><p>
        <DT><A HREF="https://a.com">A</A>
        <DT><H3>Sub</H3>
        <DL><p>
        <DT><A HREF="https://b.com">B</A>
        </DL><p>
        </DL><p>
        <DT><A HREF="https://c.com">C</A>
        </DL><p>
        """
    }

    func testImportHTMLPreservesNestedFolders() {
        let b = makeBookmarks()
        XCTAssertEqual(b.importHTML(nestedHTML), 3)
        XCTAssertEqual(b.items.count, 2)
        let folder = b.items.first?.folder
        XCTAssertEqual(folder?.title, "Dev")
        XCTAssertEqual(folder?.children.count, 2)
        XCTAssertEqual(folder?.children.first?.title, "A")
        XCTAssertEqual(folder?.children.last?.folder?.title, "Sub")
        XCTAssertEqual(folder?.children.last?.folder?.children.first?.title, "B")
        XCTAssertEqual(b.items.last?.title, "C")
    }

    func testImportHTMLSkipsDuplicates() {
        let b = makeBookmarks()
        b.add(title: "A", url: url("https://a.com"))
        // B and C are new; A is already present.
        XCTAssertEqual(b.importHTML(nestedHTML), 2)
    }

    func testImportHTMLTreatsBookmarksBarAsTransparent() {
        let b = makeBookmarks()
        let html = """
        <DL><p>
        <DT><H3 PERSONAL_TOOLBAR_FOLDER="true">Bookmarks Bar</H3>
        <DL><p>
        <DT><A HREF="https://a.com">A</A>
        </DL><p>
        </DL><p>
        """
        XCTAssertEqual(b.importHTML(html), 1)
        XCTAssertEqual(b.items.count, 1)
        XCTAssertEqual(b.items.first?.title, "A")
    }

    func testExportHTMLContainsFolderStructure() {
        let b = makeBookmarks()
        let fi = b.addFolder(title: "Dev")
        b.add(title: "A", url: url("https://a.com"))
        b.moveNode(from: IndexPath(index: 1), to: IndexPath(indexes: [fi, 0]))

        let html = b.exportHTML()
        XCTAssertTrue(html.contains(">Dev</H3>"))
        XCTAssertTrue(html.contains("https://a.com"))
        // The folder's heading comes before its children.
        let h3 = try! XCTUnwrap(html.range(of: ">Dev</H3>")?.lowerBound)
        let link = try! XCTUnwrap(html.range(of: "https://a.com")?.lowerBound)
        XCTAssertLessThan(h3, link)
    }

    func testExportImportRoundTrip() {
        let b = makeBookmarks()
        let fi = b.addFolder(title: "Dev")
        b.add(title: "A", url: url("https://a.com"))
        b.moveNode(from: IndexPath(index: 1), to: IndexPath(indexes: [fi, 0]))
        b.add(title: "C", url: url("https://c.com"))

        let b2 = makeBookmarks()
        XCTAssertEqual(b2.importHTML(b.exportHTML()), 2)
        XCTAssertEqual(b2.flattenedBookmarks.map { $0.title }, ["A", "C"])
        XCTAssertEqual(b2.items.first?.folder?.title, "Dev")
    }
}
