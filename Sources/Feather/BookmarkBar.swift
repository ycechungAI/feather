import AppKit

extension NSPasteboard.PasteboardType {
    /// A dragged bookmark-bar node, encoded as a dot-separated IndexPath ("2", "1.0").
    static let featherBookmarkNode = NSPasteboard.PasteboardType("com.feather.bookmark-node")
}

/// Writes a dragged node's IndexPath to the pasteboard.
final class BookmarkNodeDragWriter: NSObject, NSPasteboardWriting {
    let path: IndexPath

    init(path: IndexPath) {
        self.path = path
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.featherBookmarkNode]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        guard type == .featherBookmarkNode else { return nil }
        return path.map { "\($0)" }.joined(separator: ".")
    }
}

/// The destination of a "Move to" menu command: the node to move and the
/// parent array to append it to (empty IndexPath = the bookmark bar itself).
private final class MoveTarget: NSObject {
    let node: IndexPath
    let parent: IndexPath
    init(node: IndexPath, parent: IndexPath) {
        self.node = node
        self.parent = parent
    }
}

/// A bookmark-bar button. Starts a drag to reorder on mouse-drag; folder buttons
/// also accept drops, filing the dragged node into the folder.
private final class BookmarkButton: NSButton, NSDraggingSource {    /// IndexPath of the node this button represents (a single index for root items).
    var nodePath = IndexPath()
    /// Folder buttons pop a menu on click and accept drops.
    var isFolder = false
    /// Called with (dragged node path, folder path) when a node is dropped on a folder button.
    var onDropOnFolder: ((IndexPath, IndexPath) -> Void)?
    /// Called with the dragged node's path when it's dragged off the bar to delete it.
    var onDeleteDragged: ((IndexPath) -> Void)?

    private var dragInProgress = false
    /// Modifier keys held when this button was last clicked. `NSButton`'s cell
    /// normally supplies these via `NSApp.currentEvent`; because we perform the
    /// click ourselves we capture them up front.
    var clickModifiers: NSEvent.ModifierFlags = []

    /// NSButton's cell consumes press-drag events, so mouseDragged never fires.
    /// Track the press here instead: moving past a small threshold starts a drag
    /// session, while releasing without moving performs the button's click action.
    /// We use an explicit `.distantFuture` expiry so `nextEvent` blocks until the
    /// user actually drags or releases (instead of returning nil immediately).
    override func mouseDown(with event: NSEvent) {
        let start = convert(event.locationInWindow, from: nil)
        var dragEvent: NSEvent?
        tracking: while let next = window?.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            switch next.type {
            case .leftMouseUp:
                break tracking
            case .leftMouseDragged:
                let p = convert(next.locationInWindow, from: nil)
                if abs(p.x - start.x) + abs(p.y - start.y) > 4 {
                    dragEvent = next
                    break tracking
                }
            default:
                break
            }
        }

        if let dragEvent {
            dragInProgress = true
            let item = NSDraggingItem(pasteboardWriter: BookmarkNodeDragWriter(path: nodePath))
            item.setDraggingFrame(bounds, contents: snapshot())
            beginDraggingSession(with: [item], event: dragEvent, source: self)
        } else if let action {
            // The mouse-up was consumed above, so fire the action directly.
            clickModifiers = event.modifierFlags
            NSApp.sendAction(action, to: target, from: self)
        }
    }

    /// A snapshot of the button, used as the drag image while reordering.
    private func snapshot() -> NSImage {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return NSImage(size: bounds.size)
        }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.move, .delete]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragInProgress = false
        if operation == .delete {
            onDeleteDragged?(nodePath)
        }
    }

    // MARK: NSDraggingDestination (folder buttons only)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isFolder, sender.draggingPasteboard.types?.contains(.featherBookmarkNode) == true else { return [] }
        highlight(true)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        highlight(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlight(false)
        guard isFolder,
              let string = sender.draggingPasteboard.string(forType: .featherBookmarkNode),
              let source = BookmarkBar.indexPath(from: string),
              source != nodePath else { return false }
        onDropOnFolder?(source, nodePath)
        return true
    }
}

/// The horizontal stack of bookmark buttons. Accepts drops to reorder root items
/// and paints a Chrome-style insertion caret while a drag is in progress.
private final class BookmarkDropStack: NSStackView {
    /// Called with (dragged node path, destination root insertion index).
    var onDrop: ((IndexPath, Int) -> Void)?

    private var indicatorIndex: Int?

    private func hasDraggedNode(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.types?.contains(.featherBookmarkNode) == true
    }

    private func insertionIndex(for sender: NSDraggingInfo) -> Int {
        let location = convert(sender.draggingLocation, from: nil)
        for (i, view) in arrangedSubviews.enumerated() {
            if location.x < view.frame.midX { return i }
        }
        return arrangedSubviews.count
    }

    private func moveIndicator(to index: Int?) {
        guard indicatorIndex != index else { return }
        indicatorIndex = index
        needsDisplay = true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasDraggedNode(sender) else { return [] }
        moveIndicator(to: insertionIndex(for: sender))
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasDraggedNode(sender) else { return [] }
        moveIndicator(to: insertionIndex(for: sender))
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        moveIndicator(to: nil)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        moveIndicator(to: nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let index = insertionIndex(for: sender)
        moveIndicator(to: nil)
        guard let string = sender.draggingPasteboard.string(forType: .featherBookmarkNode),
              let source = BookmarkBar.indexPath(from: string) else { return false }
        onDrop?(source, index)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let index = indicatorIndex else { return }
        let x: CGFloat
        if index < arrangedSubviews.count {
            x = arrangedSubviews[index].frame.minX - spacing / 2
        } else if let last = arrangedSubviews.last {
            x = last.frame.maxX + spacing / 2
        } else {
            x = bounds.midX
        }
        let caret = NSRect(x: x - 1, y: 0, width: 2, height: bounds.height)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: caret, xRadius: 1, yRadius: 1).fill()
    }
}

/// The always-visible strip of bookmarks under the toolbar. Bookmarks that don't fit
/// are reachable from the » button at the right edge.
final class BookmarkBar: NSView {
    static let height: CGFloat = 28

    /// Called with the URL and whether it should open in a new background tab.
    var onOpen: ((URL, Bool) -> Void)?

    private let stack = BookmarkDropStack()
    private let clip = NSView()
    private let overflowButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "Press ⌘D or click ☆ to add a bookmark here")

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .horizontal
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.registerForDraggedTypes([.featherBookmarkNode])
        stack.onDrop = { [weak self] source, index in self?.dropNode(source, at: index) }
        clip.clipsToBounds = true
        clip.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(stack)

        overflowButton.image = NSImage(systemSymbolName: "chevron.right.2", accessibilityDescription: "All Bookmarks")
        overflowButton.bezelStyle = .recessed
        overflowButton.isBordered = false
        overflowButton.toolTip = "All bookmarks"
        overflowButton.target = self
        overflowButton.action = #selector(showAll(_:))
        overflowButton.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 11)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false

        // Right-clicking empty bar space offers to create a folder.
        let barMenu = NSMenu()
        let newFolderItem = NSMenuItem(title: "New Folder…", action: #selector(newFolder(_:)), keyEquivalent: "")
        newFolderItem.target = self
        barMenu.addItem(newFolderItem)
        menu = barMenu

        [clip, overflowButton, emptyLabel, line].forEach(addSubview)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            clip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            clip.trailingAnchor.constraint(equalTo: overflowButton.leadingAnchor, constant: -4),
            clip.topAnchor.constraint(equalTo: topAnchor),
            clip.bottomAnchor.constraint(equalTo: line.topAnchor),
            stack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            stack.centerYAnchor.constraint(equalTo: clip.centerYAnchor),
            overflowButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            overflowButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            overflowButton.widthAnchor.constraint(equalToConstant: 24),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: Bookmarks.changed, object: nil)
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Decodes a dot-separated IndexPath string from a drag pasteboard.
    static func indexPath(from string: String) -> IndexPath? {
        let parts = string.split(separator: ".")
        let indexes = parts.compactMap { Int($0) }
        guard !indexes.isEmpty, indexes.count == parts.count else { return nil }
        return IndexPath(indexes: indexes)
    }

    @objc private func reload() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let items = Bookmarks.shared.items
        for (index, node) in items.enumerated() {
            stack.addArrangedSubview(button(for: node, path: IndexPath(index: index)))
        }
        emptyLabel.isHidden = !items.isEmpty
        overflowButton.isHidden = items.isEmpty
    }

    private func button(for node: BookmarkNode, path: IndexPath) -> BookmarkButton {
        let isFolder = node.folder != nil
        let rawTitle = node.title
        let title = (rawTitle.count > 24 ? String(rawTitle.prefix(23)) + "…" : rawTitle) + (isFolder ? " ▾" : "")
        let button = BookmarkButton(title: title, target: self, action: isFolder ? #selector(openFolder(_:)) : #selector(clicked(_:)))
        button.bezelStyle = .recessed
        button.showsBorderOnlyWhileMouseInside = true
        button.font = .systemFont(ofSize: 12)
        button.nodePath = path
        button.isFolder = isFolder
        switch node {
        case .bookmark(let b):
            button.toolTip = "\(b.title)\n\(b.url.absoluteString)"
        case .folder(let f):
            let count = f.children.count
            button.toolTip = "\(f.title)\nFolder (\(count) item\(count == 1 ? "" : "s"))"
        }
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.onDropOnFolder = { [weak self] source, folderPath in self?.dropNode(source, into: folderPath) }
        button.onDeleteDragged = { [weak self] path in self?.deleteDraggedNode(at: path) }
        if isFolder {
            button.registerForDraggedTypes([.featherBookmarkNode])
        }

        let menu = NSMenu()
        if isFolder {
            menu.addItem(withTitle: "Open All in Tabs", action: #selector(openAllInFolder(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Rename…", action: #selector(renameNode(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Delete", action: #selector(deleteNode(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            let moveTo = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
            moveTo.submenu = moveToMenu(for: path)
            menu.addItem(moveTo)
            menu.addItem(.separator())
            menu.addItem(withTitle: "New Folder…", action: #selector(newSubfolder(_:)), keyEquivalent: "")
        } else {
            menu.addItem(withTitle: "Open in New Tab", action: #selector(openInNewTab(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Rename…", action: #selector(renameNode(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Delete", action: #selector(deleteNode(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            let moveTo = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
            moveTo.submenu = moveToMenu(for: path)
            menu.addItem(moveTo)
            menu.addItem(.separator())
            menu.addItem(withTitle: "New Folder with Bookmark…", action: #selector(newFolderWithNode(_:)), keyEquivalent: "")
        }
        menu.items.forEach { $0.target = self; $0.representedObject = path }
        button.menu = menu
        return button
    }

    /// Popup menu of a folder's children. Each child opens a submenu with its
    /// actions (Open, Move to, Rename, Delete); nested folders list their
    /// children first.
    private func folderMenu(at path: IndexPath) -> NSMenu {
        let menu = NSMenu()
        guard case .folder(let folder) = Bookmarks.shared.node(at: path) else { return menu }
        for (i, child) in folder.children.enumerated() {
            menu.addItem(folderChildItem(for: child, at: path.appending(i)))
        }
        if menu.items.isEmpty {
            let item = NSMenuItem(title: "(Empty)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        return menu
    }

    /// One row of a folder popup: the child's actions in a submenu.
    private func folderChildItem(for child: BookmarkNode, at childPath: IndexPath) -> NSMenuItem {
        let item = NSMenuItem(title: child.title, action: nil, keyEquivalent: "")
        let actions = NSMenu()

        switch child {
        case .bookmark:
            let open = NSMenuItem(title: "Open", action: #selector(clicked(_:)), keyEquivalent: "")
            open.target = self
            open.representedObject = childPath
            actions.addItem(open)

            let openTab = NSMenuItem(title: "Open in New Tab", action: #selector(openInNewTab(_:)), keyEquivalent: "")
            openTab.target = self
            openTab.representedObject = childPath
            actions.addItem(openTab)
        case .folder:
            for subItem in folderMenu(at: childPath).items {
                actions.addItem(subItem)
            }
            if actions.items.isEmpty {
                let empty = NSMenuItem(title: "(Empty)", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                actions.addItem(empty)
            } else {
                actions.addItem(.separator())
            }

            let openAll = NSMenuItem(title: "Open All in Tabs", action: #selector(openAllInFolder(_:)), keyEquivalent: "")
            openAll.target = self
            openAll.representedObject = childPath
            actions.addItem(openAll)

            let newSub = NSMenuItem(title: "New Folder…", action: #selector(newSubfolder(_:)), keyEquivalent: "")
            newSub.target = self
            newSub.representedObject = childPath
            actions.addItem(newSub)
        }

        actions.addItem(.separator())

        let moveUp = NSMenuItem(title: "Move Up", action: #selector(moveNodeUp(_:)), keyEquivalent: "")
        moveUp.target = self
        moveUp.representedObject = childPath
        actions.addItem(moveUp)

        let moveDown = NSMenuItem(title: "Move Down", action: #selector(moveNodeDown(_:)), keyEquivalent: "")
        moveDown.target = self
        moveDown.representedObject = childPath
        actions.addItem(moveDown)

        actions.addItem(.separator())

        let moveTo = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
        moveTo.submenu = moveToMenu(for: childPath)
        actions.addItem(moveTo)

        let rename = NSMenuItem(title: "Rename…", action: #selector(renameNode(_:)), keyEquivalent: "")
        rename.target = self
        rename.representedObject = childPath
        actions.addItem(rename)

        let delete = NSMenuItem(title: "Delete", action: #selector(deleteNode(_:)), keyEquivalent: "")
        delete.target = self
        delete.representedObject = childPath
        actions.addItem(delete)

        item.submenu = actions
        if let url = child.bookmark?.url {
            item.toolTip = url.absoluteString
        }
        return item
    }

    /// A "Move to" submenu for the node at `path`, listing the bookmark bar
    /// (when the node is inside a folder) and every folder. A folder can't be
    /// moved into itself or one of its descendants.
    private func moveToMenu(for path: IndexPath) -> NSMenu {
        let menu = NSMenu()
        let pathIndexes = path.map { $0 }

        func validDestination(_ folderPath: IndexPath) -> Bool {
            let f = folderPath.map { $0 }
            return f != pathIndexes && !f.starts(with: pathIndexes)
        }

        func addDestination(title: String, parent: IndexPath) {
            let item = NSMenuItem(title: title, action: #selector(moveNodeTo(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = MoveTarget(node: path, parent: parent)
            menu.addItem(item)
        }

        if pathIndexes.count > 1 {
            addDestination(title: "Bookmarks Bar", parent: IndexPath())
            menu.addItem(.separator())
        }

        func collect(_ nodes: [BookmarkNode], base: IndexPath, depth: Int) {
            for (i, node) in nodes.enumerated() {
                guard case .folder(let folder) = node else { continue }
                let folderPath = base.appending(i)
                if validDestination(folderPath) {
                    let indent = String(repeating: "  ", count: depth)
                    addDestination(title: "\(indent)\(folder.title)", parent: folderPath)
                }
                collect(folder.children, base: folderPath, depth: depth + 1)
            }
        }
        collect(Bookmarks.shared.items, base: IndexPath(), depth: 0)

        if menu.items.isEmpty {
            let item = NSMenuItem(title: "(No destinations)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        return menu
    }

    @objc private func moveNodeTo(_ sender: NSMenuItem) {
        FolderPopupPresenter.shared.closeAll()
        guard let target = sender.representedObject as? MoveTarget else { return }
        let parent = target.parent
        let count: Int
        if parent.isEmpty {
            count = Bookmarks.shared.items.count
        } else {
            guard case .folder(let folder) = Bookmarks.shared.node(at: parent) else { return }
            count = folder.children.count
        }
        Bookmarks.shared.moveNode(from: target.node, to: parent.appending(count))
    }

    private func flattenedBookmarks(in folder: BookmarkFolder) -> [Bookmark] {
        var out: [Bookmark] = []
        for child in folder.children {
            switch child {
            case .bookmark(let b): out.append(b)
            case .folder(let f): out.append(contentsOf: flattenedBookmarks(in: f))
            }
        }
        return out
    }

    // MARK: - Drops

    private func dropNode(_ source: IndexPath, at rootIndex: Int) {
        Bookmarks.shared.moveNode(from: source, to: IndexPath(index: rootIndex))
        // Deferred: this runs inside the bar's performDragOperation, and the
        // popover may be the window holding the drag source.
        DispatchQueue.main.async { FolderPopupPresenter.shared.closeAll() }
    }

    private func dropNode(_ source: IndexPath, into folderPath: IndexPath) {
        guard case .folder(let folder) = Bookmarks.shared.node(at: folderPath) else { return }
        Bookmarks.shared.moveNode(from: source, to: folderPath.appending(folder.children.count))
        DispatchQueue.main.async { FolderPopupPresenter.shared.closeAll() }
    }

    /// Deletes the node dragged off the bar (poof). Deleting a folder deletes its contents.
    private func deleteDraggedNode(at path: IndexPath) {
        Bookmarks.shared.removeNode(at: path)
    }

    // MARK: - Actions

    @objc private func clicked(_ sender: Any?) {
        FolderPopupPresenter.shared.closeAll()
        let path: IndexPath?
        var newTab = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
        if let button = sender as? BookmarkButton {
            path = button.nodePath
            newTab = button.clickModifiers.contains(.command)
        } else if let item = sender as? NSMenuItem {
            path = item.representedObject as? IndexPath
        } else {
            path = nil
        }
        guard let path, case .bookmark(let b) = Bookmarks.shared.node(at: path) else { return }
        onOpen?(b.url, newTab)
    }

    @objc private func openFolder(_ sender: Any?) {
        guard let button = sender as? BookmarkButton else { return }
        FolderPopupPresenter.shared.show(folder: button.nodePath, from: button, bookmarkBar: self)
    }

    @objc private func openInNewTab(_ sender: NSMenuItem) {
        FolderPopupPresenter.shared.closeAll()
        guard let path = sender.representedObject as? IndexPath,
              case .bookmark(let b) = Bookmarks.shared.node(at: path) else { return }
        onOpen?(b.url, true)
    }

    @objc private func openAllInFolder(_ sender: NSMenuItem) {
        FolderPopupPresenter.shared.closeAll()
        guard let path = sender.representedObject as? IndexPath,
              case .folder(let folder) = Bookmarks.shared.node(at: path) else { return }
        for b in flattenedBookmarks(in: folder) {
            onOpen?(b.url, true)
        }
    }

    @objc private func deleteNode(_ sender: NSMenuItem) {
        FolderPopupPresenter.shared.closeAll()
        guard let path = sender.representedObject as? IndexPath else { return }
        Bookmarks.shared.removeNode(at: path)
    }

    @objc private func renameNode(_ sender: NSMenuItem) {
        FolderPopupPresenter.shared.closeAll()
        guard let path = sender.representedObject as? IndexPath,
              let node = Bookmarks.shared.node(at: path) else { return }
        let alert = NSAlert()
        alert.messageText = node.folder == nil ? "Rename Bookmark" : "Rename Folder"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = node.title
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let done: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn { Bookmarks.shared.renameNode(at: path, to: field.stringValue) }
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: done) } else { done(alert.runModal()) }
    }

    @objc private func newFolder(_ sender: Any?) {
        FolderPopupPresenter.shared.closeAll()
        promptForFolderName { name in
            Bookmarks.shared.addFolder(title: name)
        }
    }

    @objc private func newFolderWithNode(_ sender: NSMenuItem) {
        FolderPopupPresenter.shared.closeAll()
        guard let path = sender.representedObject as? IndexPath else { return }
        promptForFolderName { name in
            let folderIndex = Bookmarks.shared.addFolder(title: name)
            Bookmarks.shared.moveNode(from: path, to: IndexPath(indexes: [folderIndex, 0]))
        }
    }

    @objc private func newSubfolder(_ sender: NSMenuItem) {
        FolderPopupPresenter.shared.closeAll()
        guard let path = sender.representedObject as? IndexPath else { return }
        promptForFolderName { name in
            Bookmarks.shared.addFolder(title: name, in: path)
        }
    }

    @objc private func moveNodeUp(_ sender: NSMenuItem) {
        FolderPopupPresenter.shared.closeAll()
        guard let path = sender.representedObject as? IndexPath else { return }
        Bookmarks.shared.moveUp(at: path)
    }

    @objc private func moveNodeDown(_ sender: NSMenuItem) {
        FolderPopupPresenter.shared.closeAll()
        guard let path = sender.representedObject as? IndexPath else { return }
        Bookmarks.shared.moveDown(at: path)
    }

    private func promptForFolderName(completion: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = "Name for the new folder:"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Folder name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let done: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn,
               !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                completion(field.stringValue)
            }
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: done) } else { done(alert.runModal()) }
    }

    // MARK: - Folder popup helpers

    /// Opens the bookmark at `path` (used by folder-popup rows).
    func openBookmark(at path: IndexPath, newTab: Bool) {
        FolderPopupPresenter.shared.closeAll()
        guard case .bookmark(let b) = Bookmarks.shared.node(at: path) else { return }
        onOpen?(b.url, newTab)
    }

    /// Opens every bookmark inside `folderPath` in background tabs.
    func openAllInFolder(at folderPath: IndexPath) {
        FolderPopupPresenter.shared.closeAll()
        guard case .folder(let folder) = Bookmarks.shared.node(at: folderPath) else { return }
        for b in flattenedBookmarks(in: folder) {
            onOpen?(b.url, true)
        }
    }

    /// Prompts for a name and creates a subfolder inside `parent`.
    func createSubfolder(in parent: IndexPath) {
        FolderPopupPresenter.shared.closeAll()
        promptForFolderName { name in
            Bookmarks.shared.addFolder(title: name, in: parent)
        }
    }

    /// The context menu for a folder-popup row (same actions as the bar's menus).
    func rowMenu(for node: BookmarkNode, at path: IndexPath) -> NSMenu {
        let menu = NSMenu()
        if node.folder == nil {
            menu.addItem(withTitle: "Open", action: #selector(clicked(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Open in New Tab", action: #selector(openInNewTab(_:)), keyEquivalent: "")
        } else {
            menu.addItem(withTitle: "Open All in Tabs", action: #selector(openAllInFolder(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "New Folder…", action: #selector(newSubfolder(_:)), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Move Up", action: #selector(moveNodeUp(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Move Down", action: #selector(moveNodeDown(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let moveTo = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
        moveTo.submenu = moveToMenu(for: path)
        menu.addItem(moveTo)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Rename…", action: #selector(renameNode(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Delete", action: #selector(deleteNode(_:)), keyEquivalent: "")
        menu.items.forEach { $0.target = self; $0.representedObject = path }
        return menu
    }

    @objc private func showAll(_ sender: NSButton) {
        let menu = NSMenu()
        for (index, node) in Bookmarks.shared.items.enumerated() {
            let path = IndexPath(index: index)
            switch node {
            case .bookmark(let b):
                let item = NSMenuItem(title: b.title, action: #selector(clicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = path
                item.toolTip = b.url.absoluteString
                menu.addItem(item)
            case .folder(let f):
                let item = NSMenuItem(title: f.title, action: nil, keyEquivalent: "")
                item.submenu = folderMenu(at: path)
                menu.addItem(item)
            }
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }
}
