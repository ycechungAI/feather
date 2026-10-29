import AppKit

/// History ▸ Show All History (⌘Y): search, open, and delete visited pages.
final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate,
                                     NSSearchFieldDelegate, NSMenuItemValidation {
    static let shared = HistoryWindowController()

    private let search = NSSearchField()
    private let table = HistoryTable()
    private var rows: [HistoryEntry] = []

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.title = "History"
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("FeatherHistory")
        window.minSize = NSSize(width: 480, height: 300)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: History.changed, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        reload()
        if window?.isVisible == false { window?.center() }
        showWindow(nil)
        window?.makeFirstResponder(search)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        search.placeholderString = "Search history"
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(reload)

        for (id, title, width) in [("title", "Title", 300.0), ("url", "Address", 260.0), ("date", "Visited", 150.0)] {
            let column = NSTableColumn(identifier: .init(id))
            column.title = title
            column.width = width
            (column.dataCell as? NSTextFieldCell)?.lineBreakMode = .byTruncatingTail
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.style = .inset
        table.target = self
        table.doubleAction = #selector(openSelected(_:))
        table.onDelete = { [weak self] in self?.deleteSelected(nil) }
        table.menu = contextMenu()

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true

        let deleteButton = NSButton(title: "Delete", target: self, action: #selector(deleteSelected(_:)))
        let clearButton = NSButton(title: "Clear History…", target: self, action: #selector(clearHistory(_:)))

        let bottom = NSStackView(views: [deleteButton, NSView(), clearButton])
        for view in [search, scroll, bottom] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bottom.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            bottom.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            bottom.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            bottom.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open", action: #selector(openSelected(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Open in New Tab", action: #selector(openInNewTab(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Copy Address", action: #selector(copyAddress(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Delete", action: #selector(deleteSelected(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Delete All from This Site", action: #selector(deleteSite(_:)), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func reload() {
        let query = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        rows = query.isEmpty ? History.shared.entries : History.shared.entries.filter {
            $0.title.lowercased().contains(query) || $0.url.absoluteString.lowercased().contains(query)
        }
        table.reloadData()
    }

    func controlTextDidChange(_ obj: Notification) { reload() }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, objectValueFor column: NSTableColumn?, row: Int) -> Any? {
        let entry = rows[row]
        switch column?.identifier.rawValue {
        case "title": return entry.title.isEmpty ? entry.url.host : entry.title
        case "url": return entry.url.absoluteString
        default: return Self.dateFormat.string(from: entry.date)
        }
    }

    /// Right-clicking an unselected row acts on that row.
    private var targetRows: IndexSet {
        let clicked = table.clickedRow
        if clicked >= 0, !table.selectedRowIndexes.contains(clicked) { return IndexSet(integer: clicked) }
        return table.selectedRowIndexes
    }

    private var targetEntries: [HistoryEntry] {
        targetRows.filter { $0 < rows.count }.map { rows[$0] }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool { !targetEntries.isEmpty }

    // MARK: Actions

    @objc private func openSelected(_ sender: Any?) {
        guard let first = targetEntries.first else { return }
        BrowserWindowController.openFromApp(first.url, newTab: false)
    }

    @objc private func openInNewTab(_ sender: Any?) {
        targetEntries.forEach { BrowserWindowController.openFromApp($0.url, newTab: true) }
    }

    @objc private func copyAddress(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(targetEntries.map(\.url.absoluteString).joined(separator: "\n"), forType: .string)
    }

    @objc func deleteSelected(_ sender: Any?) {
        let ids = Set(targetEntries.map(\.id))
        guard !ids.isEmpty else { return }
        History.shared.remove(ids: ids)
    }

    @objc private func deleteSite(_ sender: Any?) {
        guard let host = targetEntries.first?.url.host else { return }
        History.shared.removeAll(host: host)
    }

    @objc func clearHistory(_ sender: Any?) {
        Self.presentClearDialog(on: window)
    }

    static func presentClearDialog(on window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "Clear History"
        alert.informativeText = "Removes visited pages from Feather's history. Bookmarks are kept."

        let range = NSPopUpButton(frame: .zero, pullsDown: false)
        range.addItems(withTitles: ["the last hour", "today", "today and yesterday", "all history"])
        range.selectItem(at: 3)
        let kept = Settings.keepSignedIn
        let data = NSButton(checkboxWithTitle: "Also clear cookies, cache and site data (signs you out of sites)",
                            target: nil, action: nil)
        if !kept.isEmpty {
            alert.informativeText += " You stay signed in to \(kept.joined(separator: ", "))."
        }
        let label = NSTextField(labelWithString: "Clear:")
        let row = NSStackView(views: [label, range])
        let stack = NSStackView(views: [row, data])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: 400, height: 56)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")

        let done: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            let cal = Calendar.current
            let since: Date?
            switch range.indexOfSelectedItem {
            case 0: since = Date().addingTimeInterval(-3600)
            case 1: since = cal.startOfDay(for: Date())
            case 2: since = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))
            default: since = nil
            }
            History.shared.clear(since: since, websiteData: data.state == .on)
        }
        if let window, window.isVisible { alert.beginSheetModal(for: window, completionHandler: done) } else { done(alert.runModal()) }
    }
}

/// Lets the Delete/Backspace key remove selected rows.
final class HistoryTable: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { onDelete?() } else { super.keyDown(with: event) }
    }
}

/// Fills the History menu with recently visited pages each time it opens.
final class RecentHistoryMenu: NSObject, NSMenuDelegate {
    static let shared = RecentHistoryMenu()
    static let marker = 9_000

    func menuNeedsUpdate(_ menu: NSMenu) {
        while let last = menu.items.last, last.tag != Self.marker { menu.removeItem(last) }
        let recent = History.shared.entries.prefix(15)
        guard !recent.isEmpty else { return }
        menu.addItem(.separator())
        for entry in recent {
            let title = entry.title.isEmpty ? (entry.url.host ?? entry.url.absoluteString) : entry.title
            let item = NSMenuItem(title: title.count > 60 ? String(title.prefix(59)) + "…" : title,
                                  action: #selector(open(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.url
            item.toolTip = entry.url.absoluteString
            menu.addItem(item)
        }
    }

    @objc private func open(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { BrowserWindowController.openFromApp(url, newTab: false) }
    }
}
