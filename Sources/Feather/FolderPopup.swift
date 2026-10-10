import AppKit

/// A borderless, non-activating panel used to show folder contents. Unlike
/// NSPopover, its frame is set explicitly so the width is always correct.
final class FolderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Chrome-style bookmark folder popup: a floating panel whose rows support
/// drag-and-drop (reorder within the folder, drag onto the bar, drop into
/// folder rows to nest) and nested subfolder popups.
final class FolderPopupPresenter {
    static let shared = FolderPopupPresenter()

    private(set) var panels: [FolderPanel] = []
    private var monitors: [Any] = []
    weak var bookmarkBar: BookmarkBar?
    private var changedObserver: NSObjectProtocol?

    private init() {
        installMonitors()
        changedObserver = NotificationCenter.default.addObserver(
            forName: Bookmarks.changed, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // Refresh open panels in place; explicit actions/outside clicks
            // close them. Deferred so a drop that triggered the change finishes first.
            DispatchQueue.main.async {
                self.panels.forEach { ($0.contentViewController as? FolderListViewController)?.reload() }
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
               self.panels.contains(where: { $0.contentViewController?.view.window === window }) {
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
        if (panels.last?.contentViewController as? FolderListViewController)?.folderPath == folderPath {
            closeAll()
            return
        }
        closeAll()
        open(folderPath: folderPath, anchor: anchor, below: true)
    }

    /// Opens a nested folder popup to the right of `row`, keeping the ancestors open.
    func openSubfolder(_ folderPath: IndexPath, from row: FolderRowView, keeping controller: FolderListViewController) {
        guard let parentPanel = controller.panel,
              let index = panels.firstIndex(where: { $0 === parentPanel }) else { return }
        panels[(index + 1)...].forEach { $0.orderOut(nil) }
        panels.removeSubrange((index + 1)...)
        guard Bookmarks.shared.node(at: folderPath) != nil else { return }
        open(folderPath: folderPath, anchor: row, below: false)
    }

    func closeAll() {
        let open = panels
        panels.removeAll()
        open.forEach { $0.orderOut(nil) }
    }

    private func open(folderPath: IndexPath, anchor: NSView, below: Bool) {
        let controller = FolderListViewController(folderPath: folderPath, presenter: self)
        let size = controller.contentSize

        let panel = FolderPanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentViewController = controller
        controller.panel = panel

        // Position the panel relative to the anchor on screen.
        if let window = anchor.window {
            let anchorFrame = anchor.convert(anchor.bounds, to: nil)
            let screenFrame = window.convertToScreen(anchorFrame)
            var origin: NSPoint
            if below {
                origin = NSPoint(x: screenFrame.minX, y: screenFrame.minY - size.height - 4)
            } else {
                origin = NSPoint(x: screenFrame.maxX + 4, y: screenFrame.maxY - size.height)
            }
            if let screen = window.screen {
                let visible = screen.visibleFrame
                origin.x = max(visible.minX + 4, min(origin.x, visible.maxX - size.width - 4))
                origin.y = max(visible.minY + 4, min(origin.y, visible.maxY - size.height - 4))
            }
            panel.setFrameOrigin(origin)
        }

        panels.append(panel)
        panel.orderFrontRegardless()
    }
}

/// The content view of a folder popup: a scrollable list of rows plus a footer.
final class FolderListViewController: NSViewController {
    let folderPath: IndexPath
    unowned let presenter: FolderPopupPresenter
    weak var panel: FolderPanel?

    private let scroll = NSScrollView()
    private let list = FolderListView()
    private let footer = NSView()

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

    private var rowCount: Int {
        Bookmarks.shared.node(at: folderPath)?.folder?.children.count ?? 0
    }

    var contentSize: NSSize {
        let listHeight = min(CGFloat(max(rowCount, 1)) * Self.rowHeight, Self.maxListHeight)
        return NSSize(width: Self.width, height: listHeight + Self.footerHeight)
    }

    override func loadView() {
        let size = contentSize
        let root = NSView(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height))
        root.wantsLayer = true
        root.layer?.cornerRadius = 6
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.layer?.borderWidth = 0.5
        root.layer?.borderColor = NSColor.separatorColor.cgColor

        let listHeight = min(CGFloat(max(rowCount, 1)) * Self.rowHeight, Self.maxListHeight)

        scroll.frame = NSRect(x: 0, y: Self.footerHeight, width: Self.width, height: listHeight)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autoresizingMask = [.width, .height]

        list.folderPath = folderPath
        list.presenter = presenter
        list.buildRows()
        scroll.documentView = list
        // Document views need constraints to the scroll view's content area.
        list.translatesAutoresizingMaskIntoConstraints = false
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            list.topAnchor.constraint(equalTo: clip.topAnchor),
            list.bottomAnchor.constraint(greaterThanOrEqualTo: clip.bottomAnchor),
        ])
        root.addSubview(scroll)

        footer.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.footerHeight)
        footer.autoresizingMask = [.width]

        let newButton = NSButton(frame: NSRect(x: 4, y: 3, width: 110, height: 24))
        newButton.title = "New Folder…"
        newButton.bezelStyle = .recessed
        newButton.isBordered = false
        newButton.font = .systemFont(ofSize: 11)
        newButton.target = self
        newButton.action = #selector(newFolder(_:))
        newButton.autoresizingMask = [.maxXMargin]
        footer.addSubview(newButton)

        let openAll = NSButton(frame: NSRect(x: 120, y: 3, width: 90, height: 24))
        openAll.title = "Open All"
        openAll.bezelStyle = .recessed
        openAll.isBordered = false
        openAll.font = .systemFont(ofSize: 11)
        openAll.target = self
        openAll.action = #selector(openAll(_:))
        openAll.autoresizingMask = [.maxXMargin]
        footer.addSubview(openAll)

        root.addSubview(footer)

        view = root
    }

    /// Rebuilds the rows from the model (used after in-place changes).
    func reload() {
        list.buildRows()
        let size = contentSize
        panel?.setFrame(NSRect(x: panel?.frame.origin.x ?? 0, y: panel?.frame.origin.y ?? 0, width: size.width, height: size.height), display: true)
        view.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        let listHeight = min(CGFloat(max(rowCount, 1)) * Self.rowHeight, Self.maxListHeight)
        scroll.frame = NSRect(x: 0, y: Self.footerHeight, width: Self.width, height: listHeight)
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
        NSSize(width: FolderListViewController.width, height: CGFloat(max(rows.count, 1)) * FolderListViewController.rowHeight)
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
