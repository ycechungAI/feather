import AppKit

/// One browser window. It holds many tabs and shows the selected one: the tab's toolbar and its
/// content (bookmark bar, find bar, page). The other tabs' pages are out of the window, so
/// WebKit throttles them. Feather draws the tab strip itself (TabStripView).
final class TabWindow: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    static private(set) var all: [TabWindow] = []

    let isPrivate: Bool
    private(set) var model = TabStripModel()
    private var controllers: [UUID: BrowserWindowController] = [:]
    let strip = TabStripView()
    /// One bookmark bar per window (not per tab), always shown under the tab strip.
    private let bookmarkBar = BookmarkBar()
    private let slot = NSView()
    private weak var shown: BrowserWindowController?
    /// Groups folded down to their label in this window's strip.
    private(set) var collapsedGroups = Set<UUID>()

    init(isPrivate: Bool) {
        self.isPrivate = isPrivate
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.tabbingMode = .disallowed
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 480, height: 320)
        if isPrivate { window.appearance = NSAppearance(named: .darkAqua) }
        if let front = Self.all.last?.window {
            window.setFrame(front.frame.offsetBy(dx: 24, dy: -24), display: false)
        } else {
            window.setFrameAutosaveName("FeatherWindow")
        }
        let root = NSView()
        window.contentView = root
        super.init(window: window)
        window.delegate = self

        strip.owner = self
        strip.translatesAutoresizingMaskIntoConstraints = false
        slot.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(strip)
        root.addSubview(bookmarkBar)
        root.addSubview(slot)
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: root.topAnchor),
            strip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            strip.heightAnchor.constraint(equalToConstant: TabStripView.height),
            bookmarkBar.topAnchor.constraint(equalTo: strip.bottomAnchor),
            bookmarkBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bookmarkBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            slot.topAnchor.constraint(equalTo: bookmarkBar.bottomAnchor),
            slot.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            slot.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            slot.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        bookmarkBar.onOpen = { [weak self] url, newTab in
            guard let self, let tab = self.selectedTab else { return }
            if newTab {
                BrowserWindowController.open(url: url, isPrivate: self.isPrivate, inTabOf: self.window, background: true)
            } else {
                tab.load(url)
            }
        }
        Self.all.append(self)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Tabs

    /// The tabs in strip order.
    var tabs: [BrowserWindowController] { model.tabs.compactMap { controllers[$0.id] } }
    var selectedTab: BrowserWindowController? { model.selected.flatMap { controllers[$0] } }
    func index(of tab: BrowserWindowController) -> Int? { model.index(of: tab.tabID) }

    /// Adds a tab at `index` (nil: just after the selected tab).
    func add(_ tab: BrowserWindowController, at index: Int? = nil, select: Bool) {
        controllers[tab.tabID] = tab
        tab.host = self
        let at = index ?? model.selectedIndex.map { $0 + 1 }
        model.insert(TabItem(id: tab.tabID, url: nil, title: "", pinned: tab.isPinned, group: tab.tabGroupID),
                     at: at, select: select)
        showSelected()
        strip.reload()
    }

    func select(_ tab: BrowserWindowController) {
        model.select(tab.tabID)
        showSelected()
        strip.reload()
    }

    /// Closes a tab. A pinned tab asks first unless `force`. The last tab closes the window.
    func close(_ tab: BrowserWindowController, force: Bool = false) {
        guard controllers[tab.tabID] != nil else { return }
        if tab.isPinned, !force, !isPrivate, let window {
            let alert = NSAlert()
            alert.messageText = "Close pinned tab?"
            alert.informativeText = tab.displayTitle
            alert.addButton(withTitle: "Close Tab")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn { self?.close(tab, force: true) }
            }
            return
        }
        remove(tab)
        tab.tabWillClose()
        if model.tabs.isEmpty { window?.close() }
    }

    /// Takes a tab out of this window without closing it (to move it to another window).
    private func remove(_ tab: BrowserWindowController) {
        controllers[tab.tabID] = nil
        model.close(tab.tabID)
        if shown === tab {
            tab.content.removeFromSuperview()
            tab.didDeselect()
            shown = nil
        }
        showSelected()
        strip.reload()
    }

    /// Moves a tab from another window into this one.
    func adopt(_ tab: BrowserWindowController, at index: Int?) {
        guard let from = tab.host, from !== self else { return }
        from.remove(tab)
        if from.model.tabs.isEmpty { from.window?.close() }
        add(tab, at: index, select: true)
        window?.makeKeyAndOrderFront(nil)
        tab.tabsChanged()
    }

    /// Opens a tab in a window of its own, at `origin` (screen point of the window's top left) if given.
    func moveToNewWindow(_ tab: BrowserWindowController, origin: NSPoint? = nil) {
        guard model.tabs.count > 1 else { return }
        let other = TabWindow(isPrivate: isPrivate)
        if let origin { other.window?.setFrameTopLeftPoint(origin) }
        other.adopt(tab, at: nil)
        other.showWindow(nil)
    }

    /// Moves a tab to a new place in the strip (drag to reorder).
    func move(_ tab: BrowserWindowController, to index: Int) {
        model.move(tab.tabID, to: index)
        strip.reload()
        tab.tabsChanged()
    }

    /// A tab dragged off the strip and dropped at `point` (screen): onto another window's strip
    /// it moves there; anywhere else it gets a window of its own.
    func tearOff(_ tab: BrowserWindowController, at point: NSPoint) {
        let target = Self.all.first { other in
            guard other !== self, other.isPrivate == isPrivate, let w = other.window, w.isVisible else { return false }
            return w.frame.contains(point)
        }
        if let target {
            target.adopt(tab, at: target.strip.insertionIndex(atScreen: point))
        } else {
            moveToNewWindow(tab, origin: NSPoint(x: point.x - 60, y: point.y + 20))
        }
    }

    /// Folds a group down to its label, or unfolds it. Folding the group of the selected tab
    /// selects the nearest tab outside it; a group that is the whole window doesn't fold.
    func toggleCollapsed(_ group: UUID) {
        if collapsedGroups.remove(group) == nil {
            if let selected = model.selectedIndex, model.tabs[selected].group == group {
                let outside = model.tabs.indices.filter { model.tabs[$0].group != group }
                guard let nearest = outside.min(by: { abs($0 - selected) < abs($1 - selected) }) else { return }
                model.select(model.tabs[nearest].id)
                collapsedGroups.insert(group)
                showSelected()
            } else {
                collapsedGroups.insert(group)
            }
        }
        strip.reload()
    }

    // MARK: Tab changes

    func tabChanged(_ tab: BrowserWindowController) {
        if tab === selectedTab { window?.title = tab.displayTitle }
        strip.needsDisplay = true
    }

    func pinChanged(_ tab: BrowserWindowController) {
        model.setPinned(tab.tabID, tab.isPinned)
        strip.reload()
    }

    func groupChanged(_ tab: BrowserWindowController) {
        model.setGroup(tab.tabID, tab.tabGroupID)
        strip.reload()
    }

    private func showSelected() {
        guard let tab = selectedTab, let window else { return }
        if let group = tab.tabGroupID, collapsedGroups.remove(group) != nil { strip.reload() }
        guard shown !== tab else { return }
        if let old = shown {
            old.content.removeFromSuperview()
            old.didDeselect()
        }
        tab.content.translatesAutoresizingMaskIntoConstraints = false
        slot.addSubview(tab.content)
        NSLayoutConstraint.activate([
            tab.content.topAnchor.constraint(equalTo: slot.topAnchor),
            tab.content.leadingAnchor.constraint(equalTo: slot.leadingAnchor),
            tab.content.trailingAnchor.constraint(equalTo: slot.trailingAnchor),
            tab.content.bottomAnchor.constraint(equalTo: slot.bottomAnchor),
        ])
        window.toolbar = tab.toolbar
        window.title = tab.displayTitle
        shown = tab
        tab.didSelect()
    }

    // MARK: Finding windows

    /// Feather's windows, front first.
    static var ordered: [TabWindow] {
        let front = NSApp.orderedWindows.compactMap { $0.windowController as? TabWindow }
        return front + all.filter { w in !front.contains { $0 === w } }
    }

    static func frontmost(isPrivate: Bool) -> TabWindow? {
        if let key = NSApp.keyWindow?.windowController as? TabWindow, key.isPrivate == isPrivate { return key }
        return ordered.first { $0.isPrivate == isPrivate }
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        selectedTab?.didBecomeKey()
    }

    func windowDidResignKey(_ notification: Notification) {
        selectedTab?.didResignKey()
    }

    func windowWillClose(_ notification: Notification) {
        let closing = tabs
        controllers = [:]
        model = TabStripModel()
        shown = nil
        closing.forEach { $0.tabWillClose() }
        Self.all.removeAll { $0 === self }
    }

    // MARK: Actions

    /// Menu commands for a tab (Reload, Find, Back…) go to the selected tab.
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        if let tab = selectedTab, tab.responds(to: action) { return tab }
        return super.supplementalTarget(forAction: action, sender: sender)
    }

    /// ⌘T and the + button.
    @objc override func newWindowForTab(_ sender: Any?) {
        BrowserWindowController.open(url: nil, isPrivate: isPrivate, inTabOf: window, at: .max)
    }

    /// ⌘W: closes the selected tab, and the window with its last tab.
    @objc func closeTab(_ sender: Any?) {
        if let tab = selectedTab { close(tab) } else { window?.close() }
    }

    @objc func showNextTab(_ sender: Any?) { step(1) }
    @objc func showPreviousTab(_ sender: Any?) { step(-1) }

    /// ⌘1…⌘9; the menu item's tag is the number.
    @objc func showTabNumber(_ sender: NSMenuItem) {
        model.select(shortcut: sender.tag)
        showSelected()
        strip.reload()
    }

    @objc func moveTabToNewWindow(_ sender: Any?) {
        if let tab = selectedTab { moveToNewWindow(tab) }
    }

    private func step(_ by: Int) {
        model.selectNext(by)
        showSelected()
        strip.reload()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(showNextTab(_:)), #selector(showPreviousTab(_:)), #selector(moveTabToNewWindow(_:)):
            return model.tabs.count > 1
        case #selector(showTabNumber(_:)):
            return model.tabs.count >= min(item.tag, 1)
        default:
            return true
        }
    }
}
