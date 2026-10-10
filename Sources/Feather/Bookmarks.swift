import Foundation

struct Bookmark: Codable, Equatable {
    var title: String
    var url: URL
}

struct BookmarkFolder: Codable, Equatable {
    var title: String
    var children: [BookmarkNode]
}

/// One node of the bookmark tree: a bookmark or a folder containing more nodes.
enum BookmarkNode: Codable, Equatable {
    case bookmark(Bookmark)
    case folder(BookmarkFolder)

    private enum Kind: String, Codable {
        case bookmark
        case folder
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case bookmark
        case folder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .bookmark:
            self = .bookmark(try container.decode(Bookmark.self, forKey: .bookmark))
        case .folder:
            self = .folder(try container.decode(BookmarkFolder.self, forKey: .folder))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bookmark(let bookmark):
            try container.encode(Kind.bookmark, forKey: .kind)
            try container.encode(bookmark, forKey: .bookmark)
        case .folder(let folder):
            try container.encode(Kind.folder, forKey: .kind)
            try container.encode(folder, forKey: .folder)
        }
    }

    /// Display title: the bookmark's title or the folder's name.
    var title: String {
        switch self {
        case .bookmark(let bookmark): return bookmark.title
        case .folder(let folder): return folder.title
        }
    }

    var bookmark: Bookmark? {
        if case .bookmark(let bookmark) = self { return bookmark }
        return nil
    }

    var folder: BookmarkFolder? {
        if case .folder(let folder) = self { return folder }
        return nil
    }
}

/// Bookmarks, stored as a JSON tree in the app's support folder.
/// Import/export uses the Netscape bookmark HTML format that every major browser reads and writes.
final class Bookmarks {
    static let shared = Bookmarks()
    static let changed = Notification.Name("FeatherBookmarksChanged")

    private(set) var items: [BookmarkNode] = []
    private let file: URL

    private convenience init() {
        self.init(storeURL: Settings.supportDirectory.appendingPathComponent("bookmarks.json"))
    }

    /// Loads from (and saves to) the given file instead of the app's support folder,
    /// so tests don't touch the real bookmarks or the shared singleton.
    init(storeURL: URL) {
        file = storeURL
        if let data = try? Data(contentsOf: file) {
            let decoder = JSONDecoder()
            if let nodes = try? decoder.decode([BookmarkNode].self, from: data) {
                items = nodes
            } else if let flat = try? decoder.decode([Bookmark].self, from: data) {
                // Files written before folders existed are a flat [Bookmark] array.
                items = flat.map(BookmarkNode.bookmark)
                save()
            }
        }
    }

    /// Every bookmark in the tree, depth-first.
    var flattenedBookmarks: [Bookmark] {
        var out: [Bookmark] = []
        Self.collect(from: items, into: &out)
        return out
    }

    private static func collect(from nodes: [BookmarkNode], into out: inout [Bookmark]) {
        for node in nodes {
            switch node {
            case .bookmark(let bookmark): out.append(bookmark)
            case .folder(let folder): collect(from: folder.children, into: &out)
            }
        }
    }

    /// The node at `path`, where each index descends one level from the root.
    func node(at path: IndexPath) -> BookmarkNode? {
        var current = items
        var found: BookmarkNode?
        for depth in 0..<path.count {
            let index = path[depth]
            guard current.indices.contains(index) else { return nil }
            found = current[index]
            if case .folder(let folder) = found {
                current = folder.children
            } else {
                current = []
            }
        }
        return found
    }

    func contains(_ url: URL?) -> Bool {
        guard let url else { return false }
        return flattenedBookmarks.contains { $0.url == url }
    }

    func add(title: String, url: URL) {
        guard !contains(url) else { return }
        items.append(.bookmark(Bookmark(title: title.isEmpty ? (url.host ?? url.absoluteString) : title, url: url)))
        save()
    }

    func remove(_ url: URL) {
        items = removing(url: url, from: items)
        save()
    }

    private func removing(url: URL, from nodes: [BookmarkNode]) -> [BookmarkNode] {
        nodes.compactMap { node in
            switch node {
            case .bookmark(let bookmark):
                return bookmark.url == url ? nil : node
            case .folder(var folder):
                folder.children = removing(url: url, from: folder.children)
                return .folder(folder)
            }
        }
    }

    func remove(at index: Int) {
        removeNode(at: IndexPath(index: index))
    }

    func rename(at index: Int, to title: String) {
        renameNode(at: IndexPath(index: index), to: title)
    }

    /// Renames the bookmark or folder at `path`.
    func renameNode(at path: IndexPath, to title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let indexes = path.map { $0 }
        guard !clean.isEmpty, !indexes.isEmpty, node(at: path) != nil else { return }
        mutateNode(at: indexes) { node in
            switch node {
            case .bookmark(var bookmark):
                bookmark.title = clean
                return .bookmark(bookmark)
            case .folder(var folder):
                folder.title = clean
                return .folder(folder)
            }
        }
        save()
    }

    /// Renames the folder at the root `index`. Does nothing if it isn't a folder.
    func renameFolder(at index: Int, to title: String) {
        let path = IndexPath(index: index)
        guard case .folder = node(at: path) else { return }
        renameNode(at: path, to: title)
    }

    /// Appends an empty folder at the root and returns its index.
    @discardableResult
    func addFolder(title: String) -> Int {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        items.append(.folder(BookmarkFolder(title: clean.isEmpty ? "New Folder" : clean, children: [])))
        save()
        return items.count - 1
    }

    /// Appends an empty folder inside the folder at `parentPath` and returns the new
    /// folder's path. Returns nil when `parentPath` isn't a folder.
    @discardableResult
    func addFolder(title: String, in parentPath: IndexPath) -> IndexPath? {
        guard let folder = node(at: parentPath)?.folder else { return nil }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = parentPath.appending(folder.children.count)
        insertNode(.folder(BookmarkFolder(title: clean.isEmpty ? "New Folder" : clean, children: [])), at: path)
        return path
    }

    /// Moves a root item from one position to another.
    func move(from: Int, to: Int) {
        moveNode(from: IndexPath(index: from), to: IndexPath(index: to))
    }

    /// Removes the node at `path` and returns it. Deleting a folder deletes its contents too.
    @discardableResult
    func removeNode(at path: IndexPath) -> BookmarkNode? {
        let indexes = path.map { $0 }
        guard !indexes.isEmpty else { return nil }
        var removed: BookmarkNode?
        withParentArray(&items, path: indexes) { children in
            let i = indexes.last!
            guard children.indices.contains(i) else { return }
            removed = children.remove(at: i)
        }
        if removed != nil { save() }
        return removed
    }

    /// Inserts a node at `path`. The last index is clamped into the parent's children.
    func insertNode(_ node: BookmarkNode, at path: IndexPath) {
        let indexes = path.map { $0 }
        guard !indexes.isEmpty, parentArrayExists(Array(indexes.dropLast())) else { return }
        withParentArray(&items, path: indexes) { children in
            children.insert(node, at: min(max(indexes.last!, 0), children.count))
        }
        save()
    }

    /// Moves the node at `from` to `to`, adjusting for the removal. Moving a folder
    /// into itself or one of its descendants is refused.
    func moveNode(from: IndexPath, to: IndexPath) {
        let f = from.map { $0 }
        let t = to.map { $0 }
        guard !f.isEmpty, !t.isEmpty, f != t, node(at: from) != nil else { return }
        if t.starts(with: f) { return }
        // Validate against the unmodified tree, before the removal shifts anything.
        guard parentArrayExists(Array(t.dropLast())) else { return }

        var removed: BookmarkNode?
        withParentArray(&items, path: f) { children in
            guard children.indices.contains(f.last!) else { return }
            removed = children.remove(at: f.last!)
        }
        guard let node = removed else { return }

        // The removal shifted indexes in the source's parent array; fix up the destination.
        var at = t
        let fp = Array(f.dropLast())
        let tp = Array(t.dropLast())
        if tp == fp {
            if at.last! > f.last! { at[at.count - 1] -= 1 }
        } else if tp.starts(with: fp), tp.count > fp.count {
            let k = fp.count
            if at[k] > f.last! { at[k] -= 1 }
        }

        withParentArray(&items, path: at) { children in
            children.insert(node, at: min(max(at.last!, 0), children.count))
        }
        save()
    }

    /// Moves the node at `path` one position toward the start of its siblings.
    /// Returns false when it's already first.
    @discardableResult
    func moveUp(at path: IndexPath) -> Bool {
        moveSibling(at: path, by: -1)
    }

    /// Moves the node at `path` one position toward the end of its siblings.
    /// Returns false when it's already last.
    @discardableResult
    func moveDown(at path: IndexPath) -> Bool {
        moveSibling(at: path, by: 1)
    }

    private func moveSibling(at path: IndexPath, by offset: Int) -> Bool {
        let indexes = path.map { $0 }
        guard let last = indexes.last else { return false }
        let parent = Array(indexes.dropLast())
        let count = parent.isEmpty
            ? items.count
            : (node(at: IndexPath(indexes: parent))?.folder?.children.count ?? 0)
        guard count > 1 else { return false }
        // `moveNode` takes an insertion point in the pre-move array, so moving
        // down one place targets the slot two positions along (the removal
        // shifts everything after the source back by one).
        let destination = offset < 0 ? last - 1 : last + 2
        guard destination >= 0, destination <= count else { return false }
        moveNode(from: path, to: IndexPath(indexes: parent).appending(destination))
        return true
    }

    /// True if the child array at `parentPath` (indexes from the root) exists.
    private func parentArrayExists(_ parentPath: [Int]) -> Bool {
        var current = items
        for index in parentPath {
            guard current.indices.contains(index), case .folder(let folder) = current[index] else { return false }
            current = folder.children
        }
        return true
    }

    /// Calls `body` with the child array that directly contains the node at `path`.
    private func withParentArray(_ children: inout [BookmarkNode], path: [Int], _ body: (inout [BookmarkNode]) -> Void) {
        if path.count <= 1 {
            body(&children)
        } else {
            let i = path[0]
            guard children.indices.contains(i), case .folder(var folder) = children[i] else { return }
            withParentArray(&folder.children, path: Array(path.dropFirst()), body)
            children[i] = .folder(folder)
        }
    }

    /// Replaces the node at `path` (child indexes from the root) with `transform(node)`.
    private func mutateNode(at path: [Int], transform: (BookmarkNode) -> BookmarkNode) {
        mutateNode(children: &items, path: path, transform: transform)
    }

    private func mutateNode(children: inout [BookmarkNode], path: [Int], transform: (BookmarkNode) -> BookmarkNode) {
        guard let first = path.first, children.indices.contains(first) else { return }
        if path.count == 1 {
            children[first] = transform(children[first])
        } else if case .folder(var folder) = children[first] {
            mutateNode(children: &folder.children, path: Array(path.dropFirst()), transform: transform)
            children[first] = .folder(folder)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: file, options: .atomic)
        }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    // MARK: Import / export

    /// Adds every http(s) link from a bookmarks HTML file, preserving <H3> folder
    /// structure (nested <DL>s), skipping duplicates. Returns how many were added.
    func importHTML(_ html: String) -> Int {
        var seen = Set(flattenedBookmarks.map { $0.url })
        let added = merge(Self.parseBookmarkHTML(html), into: &items, seen: &seen)
        if added > 0 { save() }
        return added
    }

    /// Merges parsed nodes into `target`, skipping URLs already in `seen`. Returns bookmarks added.
    /// Folders that end up empty are dropped.
    private func merge(_ nodes: [BookmarkNode], into target: inout [BookmarkNode], seen: inout Set<URL>) -> Int {
        var added = 0
        for node in nodes {
            switch node {
            case .bookmark(let bookmark):
                guard seen.insert(bookmark.url).inserted else { continue }
                target.append(node)
                added += 1
            case .folder(let folder):
                target.append(.folder(BookmarkFolder(title: folder.title, children: [])))
                let index = target.count - 1
                if case .folder(var fresh) = target[index] {
                    let n = merge(folder.children, into: &fresh.children, seen: &seen)
                    if n > 0 {
                        target[index] = .folder(fresh)
                        added += n
                    } else {
                        target.remove(at: index)
                    }
                }
            }
        }
        return added
    }

    /// Parses Netscape bookmark HTML into nodes, preserving <H3> folder structure.
    private static func parseBookmarkHTML(_ html: String) -> [BookmarkNode] {
        // Matches <H3>title</H3>, <A ... href="..." ...>title</A>, <DL> and </DL>.
        let pattern = #"<h3\b[^>]*>(.*?)</h3>|<a\b[^>]*?href\s*=\s*"([^"]*)"[^>]*>(.*?)</a>|<(/?)dl\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return [] }
        let ns = html as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        var root: [BookmarkNode] = []
        // Open folders: title plus children collected so far. A nil title is a transparent
        // grouping level (like the outermost <DL>) that merges into its parent on close.
        var stack: [(title: String?, children: [BookmarkNode])] = []
        var pendingTitle: String?

        func append(_ node: BookmarkNode) {
            if stack.isEmpty {
                root.append(node)
            } else {
                stack[stack.count - 1].children.append(node)
            }
        }

        for match in regex.matches(in: html, range: fullRange) {
            let titleRange = match.range(at: 1)
            let hrefRange = match.range(at: 2)
            let linkTitleRange = match.range(at: 3)
            let dlRange = match.range(at: 4)
            if titleRange.location != NSNotFound {
                pendingTitle = unescape(ns.substring(with: titleRange))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else if hrefRange.location != NSNotFound {
                pendingTitle = nil
                let href = unescape(ns.substring(with: hrefRange))
                let title = unescape(ns.substring(with: linkTitleRange))
                    .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: href), let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" else { continue }
                append(.bookmark(Bookmark(title: title.isEmpty ? (url.host ?? href) : title, url: url)))
            } else if dlRange.location != NSNotFound {
                if ns.substring(with: dlRange) == "/" {
                    // </DL>: close the innermost open folder.
                    guard let (title, children) = stack.popLast() else { continue }
                    let insideRealFolder = stack.contains { $0.title != nil }
                    if let title, !isToolbarFolder(title, insideRealFolder: insideRealFolder) {
                        append(.folder(BookmarkFolder(title: title, children: children)))
                    } else {
                        for child in children { append(child) }
                    }
                } else {
                    // <DL>: starts the pending folder's children, or a transparent group.
                    stack.append((title: pendingTitle, children: []))
                    pendingTitle = nil
                }
            }
        }
        // Flush any unclosed levels.
        while let (title, children) = stack.popLast() {
            let insideRealFolder = stack.contains { $0.title != nil }
            if let title, !isToolbarFolder(title, insideRealFolder: insideRealFolder) {
                append(.folder(BookmarkFolder(title: title, children: children)))
            } else {
                for child in children { append(child) }
            }
        }
        return root
    }

    /// The "Bookmarks Bar" wrapper folder browsers put around the whole file isn't a real folder.
    private static func isToolbarFolder(_ title: String, insideRealFolder: Bool) -> Bool {
        guard !insideRealFolder else { return false }
        let lower = title.lowercased()
        return lower == "bookmarks bar" || lower == "bookmarks"
    }

    func exportHTML() -> String {
        let now = Int(Date().timeIntervalSince1970)
        var out = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3 ADD_DATE="\(now)" PERSONAL_TOOLBAR_FOLDER="true">Bookmarks Bar</H3>
            <DL><p>

        """
        Self.export(nodes: items, into: &out, now: now, indent: "        ")
        out += "        </DL><p>\n</DL><p>\n"
        return out
    }

    private static func export(nodes: [BookmarkNode], into out: inout String, now: Int, indent: String) {
        for node in nodes {
            switch node {
            case .bookmark(let b):
                out += "\(indent)    <DT><A HREF=\"\(escape(b.url.absoluteString))\" ADD_DATE=\"\(now)\">\(escape(b.title))</A>\n"
            case .folder(let f):
                out += "\(indent)    <DT><H3 ADD_DATE=\"\(now)\">\(escape(f.title))</H3>\n"
                out += "\(indent)    <DL><p>\n"
                export(nodes: f.children, into: &out, now: now, indent: indent + "    ")
                out += "\(indent)    </DL><p>\n"
            }
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
    }
}
