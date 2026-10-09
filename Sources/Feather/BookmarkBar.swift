import AppKit

extension NSPasteboard.PasteboardType {
    /// A dragged bookmark-bar node, encoded as a dot-separated IndexPath ("2", "1.0").
    static let featherBookmarkNode = NSPasteboard.PasteboardType("com.feather.bookmark-node")
}

/// Writes a dragged node's IndexPath to the pasteboard.
private final class BookmarkNodeDragWriter: NSObject, NSPasteboardWriting {
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

/// A bookmark-bar button. Starts a drag to reorder on mouse-drag; folder buttons
/// also accept drops, filing the dragged node into the folder.
private final class BookmarkButton: NSButton, NSDraggingSource {
    /// IndexPath of the node this button represents (a single index for root items).
    var nodePath = IndexPath()
    /// Folder buttons pop a menu on click and accept drops.
    var isFolder = false
    /// Called with (dragged node path, folder path) when a node is dropped on a folder button.
    var onDropOnFolder: ((IndexPath, IndexPath) -> Void)?

    private var dragInProgress = false

    override func mouseDragged(with event: NSEvent) {
        if !dragInProgress {
            dragInProgress = true
            let item = NSDraggingItem(pasteboardWriter: BookmarkNodeDragWriter(path: nodePath))
            item.draggingFrame = bounds
            beginDraggingSession(with: [item], event: event, source: self)
        }
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragInProgress = false
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

/// The horizontal stack of bookmark buttons. Accepts drops to reorder root items.
private final class BookmarkDropStack: NSStackView {
    /// Called with (dragged node path, destination root insertion index).
    var onDrop: ((IndexPath, Int) -> Void)?

    private func insertionIndex(for sender: NSDraggingInfo) -> Int {
        let location = convert(sender.draggingLocation, from: nil)
        for (i, view) in arrangedSubviews.enumerated() {
            if location.x < view.frame.midX { return i }
        }
        return arrangedSubviews.count
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .move }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .move }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let string = sender.draggingPasteboard.string(forType: .featherBookmarkNode),
              let source = BookmarkBar.indexPath(from: string) else { return false }
        onDrop?(source, insertionIndex(for: sender))
        return true
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
        if isFolder {
            button.registerForDraggedTypes([.featherBookmarkNode])
        }

        let menu = NSMenu()
        if isFolder {
            menu.addItem(withTitle: "Open All in Tabs", action: #selector(openAllInFolder(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Rename…", action: #selector(renameNode(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Delete", action: #selector(deleteNode(_:)), keyEquivalent: "")
        } else {
            menu.addItem(withTitle: "Open in New Tab", action: #selector(openInNewTab(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Rename…", action: #selector(renameNode(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Delete", action: #selector(deleteNode(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "New Folder with Bookmark…", action: #selector(newFolderWithNode(_:)), keyEquivalent: "")
        }
        menu.items.forEach { $0.target = self; $0.representedObject = path }
        button.menu = menu
        return button
    }

    /// Popup menu of a folder's children, with submenus for nested folders.
    private func folderMenu(at path: IndexPath) -> NSMenu {
        let menu = NSMenu()
        guard case .folder(let folder) = Bookmarks.shared.node(at: path) else { return menu }
        for (i, child) in folder.children.enumerated() {
            let childPath = path.appending(i)
            switch child {
            case .bookmark(let b):
                let item = NSMenuItem(title: b.title, action: #selector(clicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = childPath
                item.toolTip = b.url.absoluteString
                menu.addItem(item)
            case .folder(let f):
                let item = NSMenuItem(title: f.title, action: nil, keyEquivalent: "")
                item.submenu = folderMenu(at: childPath)
                menu.addItem(item)
            }
        }
        if menu.items.isEmpty {
            let item = NSMenuItem(title: "(Empty)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        return menu
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
    }

    private func dropNode(_ source: IndexPath, into folderPath: IndexPath) {
        guard case .folder(let folder) = Bookmarks.shared.node(at: folderPath) else { return }
        Bookmarks.shared.moveNode(from: source, to: folderPath.appending(folder.children.count))
    }

    // MARK: - Actions

    @objc private func clicked(_ sender: Any?) {
        let path: IndexPath?
        if let button = sender as? BookmarkButton {
            path = button.nodePath
        } else if let item = sender as? NSMenuItem {
            path = item.representedObject as? IndexPath
        } else {
            path = nil
        }
        guard let path, case .bookmark(let b) = Bookmarks.shared.node(at: path) else { return }
        let newTab = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
        onOpen?(b.url, newTab)
    }

    @objc private func openFolder(_ sender: Any?) {
        guard let button = sender as? BookmarkButton else { return }
        let menu = folderMenu(at: button.nodePath)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func openInNewTab(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? IndexPath,
              case .bookmark(let b) = Bookmarks.shared.node(at: path) else { return }
        onOpen?(b.url, true)
    }

    @objc private func openAllInFolder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? IndexPath,
              case .folder(let folder) = Bookmarks.shared.node(at: path) else { return }
        for b in flattenedBookmarks(in: folder) {
            onOpen?(b.url, true)
        }
    }

    @objc private func deleteNode(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? IndexPath else { return }
        Bookmarks.shared.removeNode(at: path)
    }

    @objc private func renameNode(_ sender: NSMenuItem) {
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
        promptForFolderName { name in
            Bookmarks.shared.addFolder(title: name)
        }
    }

    @objc private func newFolderWithNode(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? IndexPath else { return }
        promptForFolderName { name in
            let folderIndex = Bookmarks.shared.addFolder(title: name)
            Bookmarks.shared.moveNode(from: path, to: IndexPath(indexes: [folderIndex, 0]))
        }
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
