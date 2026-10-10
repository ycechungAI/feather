import AppKit

/// Chrome-style bookmark folder popup: an application-defined popover whose rows
/// support drag-and-drop (reorder within the folder, drag onto the bar, drop into
/// folder rows to nest) and nested subfolder popovers.
final class FolderPopupPresenter {
    static let shared = FolderPopupPresenter()

    private(set) var popovers: [NSPopover] = []
    private var monitors: [Any] = []
    weak var bookmarkBar: BookmarkBar?
    private var changedObserver: NSObjectProtocol?

    private init() {
        installMonitors()
        changedObserver = NotificationCenter.default.addObserver(
            forName: Bookmarks.changed, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // Refresh open popovers in place; explicit actions/outside clicks
            // close them. Deferred so a drop that triggered the change finishes first.
            DispatchQueue.main.async {
                self.popovers.forEach { ($0.contentViewController as? FolderListViewController)?.reload() }
            }
        }
    }

    private func installMonitors() {
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.closeAll() }
                return event
            }
            if let window = event.window,
               self.popovers.contains(where: { $0.contentViewController?.view.window === window }) {
                return event
            }
            self.closeAll()
            return event
        })
    }

    var currentBookmarkBar: BookmarkBar? { bookmarkBar }

    /// Shows the contents of `folderPath` below `anchor`. Clicking the same button
    /// again toggles the popup shut.
    func show(folder folderPath: IndexPath, from anchor: NSView, bookmarkBar: BookmarkBar) {
        self.bookmarkBar = bookmarkBar
        guard anchor.window != nil else { return }
        guard Bookmarks.shared.node(at: folderPath) != nil else { return }
        if (popovers.last?.contentViewController as? FolderListViewController)?.folderPath == folderPath {
            closeAll()
            return
        }
        closeAll()
        open(folderPath: folderPath, anchor: anchor, edge: .maxY)
    }

    /// Opens a nested folder popup to the right of `row`, keeping the ancestors open.
    func openSubfolder(_ folderPath: IndexPath, from row: FolderRowView, keeping controller: FolderListViewController) {
        guard let parentPop = controller.popover,
              let index = popovers.firstIndex(where: { $0 === parentPop }) else { return }
        popovers[(index + 1)...].forEach { $0.close() }
        popovers.removeSubrange((index + 1)...)
        guard Bookmarks.shared.node(at: folderPath) != nil else { return }
        open(folderPath: folderPath, anchor: row, edge: .maxX)
    }

    func closeAll() {
        let open = popovers
        popovers.removeAll()
        open.forEach { $0.close() }
    }

    private func open(folderPath: IndexPath, anchor: NSView, edge: NSRectEdge) {
        let controller = FolderListViewController(folderPath: folderPath, presenter: self)
        controller.updateSize()
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.contentViewController = controller
        controller.popover = popover
        popovers.append(popover)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: edge)
    }
}

/// The content view of a folder popup: a scrollable list of rows plus a footer.
final class FolderListViewController: NSViewController {
    let folderPath: IndexPath
    unowned let presenter: FolderPopupPresenter
    weak var popover: NSPopover?

    private let scroll = NSScrollView()
    private let list = FolderListView()
    private let footer = NSStackView()

    static let rowHeight: CGFloat = 24
    static let footerHeight: CGFloat = 30
    static let width: CGFloat = 240
    static let maxListHeight: CGFloat = 300

    init(folderPath: IndexPath, presenter: FolderPopupPresenter) {
        self.folderPath = folderPath
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()

        list.folderPath = folderPath
        list.presenter = presenter
        list.translatesAutoresizingMaskIntoConstraints = false
        list.buildRows()

        scroll.documentView = list
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // Size the document view to the scroll view's content area; its height
        // comes from intrinsicContentSize (grows with the row count).
        let content = scroll.contentView
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            list.topAnchor.constraint(equalTo: content.topAnchor),
            list.bottomAnchor.constraint(greaterThanOrEqualTo: content.bottomAnchor),
        ])

        footer.orientation = .horizontal
        footer.spacing = 4
        footer.translatesAutoresizingMaskIntoConstraints = false

        let newButton = NSButton(title: "New Folder…", target: self, action: #selector(newFolder(_:)))
        newButton.bezelStyle = .recessed
        newButton.isBordered = false
        newButton.font = .systemFont(ofSize: 11)
        let openAll = NSButton(title: "Open All", target: self, action: #selector(openAll(_:)))
        openAll.bezelStyle = .recessed
        openAll.isBordered = false
        openAll.font = .systemFont(ofSize: 11)
        footer.addArrangedSubview(newButton)
        footer.addArrangedSubview(openAll)

        let divider = NSBox()
        divider.boxType = .separator

        root.addSubview(scroll)
        root.addSubview(divider)
        root.addSubview(footer)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            divider.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 4),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            footer.heightAnchor.constraint(equalToConstant: Self.footerHeight - 8),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -4),
        ])
        view = root
    }

    /// Rebuilds the rows from the model (used after in-place changes).
    func reload() {
        list.buildRows()
        updateSize()
    }

    func updateSize() {
        let rows = (Bookmarks.shared.node(at: folderPath)?.folder?.children.count ?? 0)
        let listHeight = min(CGFloat(max(rows, 1)) * Self.rowHeight, Self.maxListHeight)
        preferredContentSize = NSSize(width: Self.width, height: listHeight + Self.footerHeight)
        popover?.contentSize = preferredContentSize
    }

    @objc private func newFolder(_ sender: Any?) {
        presenter.closeAll()
        presenter.bookmarkBar?.createSubfolder(in: folderPath)
    }

    @objc private func openAll(_ sender: Any?) {
        presenter.closeAll()
        presenter.bookmarkBar?.openAllInFolder(at: folderPath)
    }
}

/// The vertical list of rows inside a folder popup. Accepts drops to reorder.
final class FolderListView: NSView {
    var folderPath: IndexPath = IndexPath()
    weak var presenter: FolderPopupPresenter?
    private var rows: [FolderRowView] = []
    private var indicatorIndex: Int?

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: CGFloat(max(rows.count, 1)) * FolderListViewController.rowHeight)
    }

    func buildRows() {
        rows.forEach { $0.removeFromSuperview() }
        rows.removeAll()
        guard let folder = Bookmarks.shared.node(at: folderPath)?.folder else { return }
        if folder.children.isEmpty {
            let empty = NSTextField(labelWithString: "(Empty)")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .tertiaryLabelColor
            empty.translatesAutoresizingMaskIntoConstraints = false
            addSubview(empty)
            NSLayoutConstraint.activate([
                empty.centerXAnchor.constraint(equalTo: centerXAnchor),
                empty.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            ])
        }
        for (i, child) in folder.children.enumerated() {
            let path = folderPath.appending(i)
            let row = FolderRowView(nodePath: path, isFolder: child.folder != nil, title: child.title)
            row.presenter = presenter
            row.menu = presenter?.bookmarkBar?.rowMenu(for: child, at: path)
            row.onClick = { [weak self] row in self?.handleClick(row) }
            row.onDropIntoFolder = { [weak self] source, folder in self?.handleDropInto(folder, from: source) }
            addSubview(row)
            rows.append(row)
        }
        registerForDraggedTypes([.featherBookmarkNode])
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    private func handleClick(_ row: FolderRowView) {
        if row.isFolder {
            guard let controller = window?.contentViewController as? FolderListViewController else { return }
            presenter?.openSubfolder(row.nodePath, from: row, keeping: controller)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.presenter?.bookmarkBar?.openBookmark(at: row.nodePath, newTab: row.clickModifiers.contains(.command))
            }
        }
    }

    private func handleDropInto(_ folderPath: IndexPath, from source: IndexPath) {
        guard case .folder(let folder) = Bookmarks.shared.node(at: folderPath) else { return }
        Bookmarks.shared.moveNode(from: source, to: folderPath.appending(folder.children.count))
    }

    override func layout() {
        super.layout()
        let h = FolderListViewController.rowHeight
        for (i, row) in rows.enumerated() {
            row.frame = NSRect(x: 0, y: CGFloat(i) * h, width: bounds.width, height: h)
        }
    }

    // MARK: NSDraggingDestination

    private func hasNode(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.types?.contains(.featherBookmarkNode) == true
    }

    private func insertionIndex(for sender: NSDraggingInfo) -> Int {
        let y = convert(sender.draggingLocation, from: nil).y
        for (i, row) in rows.enumerated() where y < row.frame.midY { return i }
        return rows.count
    }

    private func updateIndicator(_ sender: NSDraggingInfo?) {
        guard let sender, hasNode(sender) else {
            indicatorIndex = nil
            needsDisplay = true
            return
        }
        let index = insertionIndex(for: sender)
        if indicatorIndex != index {
            indicatorIndex = index
            needsDisplay = true
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasNode(sender) else { return [] }
        updateIndicator(sender)
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasNode(sender) else { return [] }
        updateIndicator(sender)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        updateIndicator(nil)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        updateIndicator(nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let index = insertionIndex(for: sender)
        updateIndicator(nil)
        guard let s = sender.draggingPasteboard.string(forType: .featherBookmarkNode),
              let source = BookmarkBar.indexPath(from: s),
              let folder = Bookmarks.shared.node(at: folderPath)?.folder else { return false }
        Bookmarks.shared.moveNode(from: source, to: folderPath.appending(min(max(index, 0), folder.children.count)))
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let index = indicatorIndex else { return }
        let y = index < rows.count ? rows[index].frame.minY - 1 : (rows.last?.frame.maxY ?? 0) + 1
        let line = NSRect(x: 4, y: y, width: bounds.width - 8, height: 2)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: line, xRadius: 1, yRadius: 1).fill()
    }
}

/// One row of a folder popup. Starts a drag on mouse-drag; folder rows also
/// accept drops to nest the dragged node inside them.
final class FolderRowView: NSView, NSDraggingSource {
    let nodePath: IndexPath
    let isFolder: Bool
    var clickModifiers: NSEvent.ModifierFlags = []
    var onClick: ((FolderRowView) -> Void)?
    var onDropIntoFolder: ((IndexPath, IndexPath) -> Void)?
    weak var presenter: FolderPopupPresenter?

    private let label = NSTextField(labelWithString: "")
    private var hover = false
    private var dropTarget = false
    private var dragInProgress = false

    init(nodePath: IndexPath, isFolder: Bool, title: String) {
        self.nodePath = nodePath
        self.isFolder = isFolder
        super.init(frame: .zero)
        wantsLayer = true
        label.stringValue = title + (isFolder ? " ▸" : "")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        if isFolder {
            registerForDraggedTypes([.featherBookmarkNode])
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        hover = true
        refresh()
    }

    override func mouseExited(with event: NSEvent) {
        hover = false
        refresh()
    }

    private func refresh() {
        layer?.backgroundColor = (hover || dropTarget) ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).cgColor : .clear
    }

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
        } else {
            clickModifiers = event.modifierFlags
            onClick?(self)
        }
    }

    private func snapshot() -> NSImage {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return NSImage(size: bounds.size) }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.move]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragInProgress = false
        if operation == .none, let window {
            if !window.frame.contains(screenPoint) {
                presenter?.closeAll()
            }
        }
    }

    // MARK: NSDraggingDestination (folder rows only)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isFolder, sender.draggingPasteboard.types?.contains(.featherBookmarkNode) == true else { return [] }
        dropTarget = true
        refresh()
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropTarget = false
        refresh()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropTarget = false
        refresh()
        guard isFolder,
              let s = sender.draggingPasteboard.string(forType: .featherBookmarkNode),
              let source = BookmarkBar.indexPath(from: s),
              source != nodePath else { return false }
        onDropIntoFolder?(source, nodePath)
        return true
    }
}
