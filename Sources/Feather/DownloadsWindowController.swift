import AppKit

/// Window ▸ Downloads (⌥⌘L): progress, cancel, show in Finder, open, and the recent list.
final class DownloadsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = DownloadsWindowController()

    private let table = NSTableView()
    private let empty = NSTextField(labelWithString: "No downloads")
    private var clearButton: NSButton!

    private static let sizeFormat: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.title = "Downloads"
        window.tabbingMode = .disallowed // a separate window, never a tab in a browser window
        window.setFrameAutosaveName("FeatherDownloads")
        window.minSize = NSSize(width: 380, height: 220)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: Downloads.changed, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        reload()
        if window?.isVisible == false { window?.center() }
        showWindow(nil)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let column = NSTableColumn(identifier: .init("d"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.headerView = nil
        table.rowHeight = 52
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openClicked(_:))
        table.menu = contextMenu()

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true

        empty.textColor = .secondaryLabelColor
        empty.alignment = .center

        clearButton = NSButton(title: "Clear List", target: self, action: #selector(clearList(_:)))
        let folder = NSButton(title: "Open Downloads Folder", target: self, action: #selector(openFolder(_:)))
        let bottom = NSStackView(views: [folder, NSView(), clearButton])

        for view in [scroll, empty, bottom] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            bottom.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            bottom.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            bottom.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            bottom.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open", action: #selector(openClicked(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Show in Finder", action: #selector(revealClicked(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Copy Address", action: #selector(copySource(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Remove from List", action: #selector(removeClicked(_:)), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func reload() {
        let items = Downloads.shared.items
        empty.isHidden = !items.isEmpty
        clearButton.isEnabled = items.contains { $0.state != .active }
        // Reload rows in place so progress updates don't reset the selection.
        if table.numberOfRows == items.count {
            table.reloadData(forRowIndexes: IndexSet(integersIn: 0..<items.count), columnIndexes: IndexSet(integer: 0))
        } else {
            table.reloadData()
        }
    }

    private var targetItem: DownloadItem? {
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        let items = Downloads.shared.items
        return row >= 0 && row < items.count ? items[row] : nil
    }

    @objc private func openClicked(_ sender: Any?) { targetItem.map(Downloads.shared.open) }
    @objc private func revealClicked(_ sender: Any?) { targetItem.map(Downloads.shared.reveal) }
    @objc private func removeClicked(_ sender: Any?) { targetItem.map(Downloads.shared.remove) }
    @objc private func clearList(_ sender: Any?) { Downloads.shared.clearList() }

    @objc private func copySource(_ sender: Any?) {
        guard let source = targetItem?.source else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(source.absoluteString, forType: .string)
    }

    @objc private func openFolder(_ sender: Any?) {
        NSWorkspace.shared.open(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { Downloads.shared.items.count }

    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let items = Downloads.shared.items
        guard row < items.count else { return nil }
        let view = (tableView.makeView(withIdentifier: DownloadRow.id, owner: nil) as? DownloadRow) ?? DownloadRow()
        view.configure(items[row])
        return view
    }

    static func status(of item: DownloadItem) -> String {
        let f = sizeFormat
        switch item.state {
        case .active:
            if let p = item.progress, p.totalUnitCount > 0 {
                return "\(f.string(fromByteCount: p.completedUnitCount)) of \(f.string(fromByteCount: p.totalUnitCount))"
            }
            return "Starting…"
        case .finished:
            let missing = item.destination.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true
            return missing ? "Moved or deleted" : f.string(fromByteCount: item.totalBytes)
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

/// One row: file icon, name, status/progress, and a Cancel or Show in Finder button.
private final class DownloadRow: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("DownloadRow")

    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private let action = NSButton()
    private weak var item: DownloadItem?

    init() {
        super.init(frame: .zero)
        identifier = Self.id
        name.lineBreakMode = .byTruncatingMiddle
        name.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        bar.style = .bar
        bar.controlSize = .small
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        action.isBordered = false
        action.target = self
        action.action = #selector(act(_:))

        let text = NSStackView(views: [name, bar, status])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        for v in [icon, text, action] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(equalTo: action.leadingAnchor, constant: -8),
            bar.widthAnchor.constraint(equalTo: text.widthAnchor),
            action.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            action.centerYAnchor.constraint(equalTo: centerYAnchor),
            action.widthAnchor.constraint(equalToConstant: 20),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ item: DownloadItem) {
        self.item = item
        name.stringValue = item.filename
        status.stringValue = DownloadsWindowController.status(of: item)
        let ext = item.destination?.pathExtension ?? (item.filename as NSString).pathExtension
        icon.image = NSWorkspace.shared.icon(for: .init(filenameExtension: ext) ?? .data)
        let active = item.state == .active
        bar.isHidden = !active
        if active { bar.doubleValue = item.progress?.fractionCompleted ?? 0 }
        let symbol = active ? "xmark.circle.fill" : "magnifyingglass.circle.fill"
        action.image = NSImage(systemSymbolName: symbol, accessibilityDescription: active ? "Cancel" : "Show in Finder")
        action.toolTip = active ? "Cancel download" : "Show in Finder"
        action.contentTintColor = .secondaryLabelColor
        action.isHidden = !active && item.state != .finished
    }

    @objc private func act(_ sender: Any?) {
        guard let item else { return }
        if item.state == .active { Downloads.shared.cancel(item) } else { Downloads.shared.reveal(item) }
    }
}
