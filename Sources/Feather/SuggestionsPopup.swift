import AppKit

/// The dropdown under the address bar. It never takes keyboard focus: typing stays in the
/// address field, which forwards ↑/↓/Return/Esc here.
final class SuggestionsPopup: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let panel: NSPanel
    private let table = ClickThroughTable()
    private(set) var items: [Suggestion] = []
    private weak var anchor: NSView?
    private var remoteTask: Task<Void, Never>?
    private var generation = 0
    var onChoose: ((Suggestion) -> Void)?

    private static let rowHeight: CGFloat = 26

    override init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        super.init()
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false

        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.masksToBounds = true

        let column = NSTableColumn(identifier: .init("s"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.backgroundColor = .clear
        table.style = .plain
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked(_:))
        table.refusesFirstResponder = true

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: effect.topAnchor, constant: 4),
            scroll.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -4),
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -4),
        ])
        panel.contentView = effect
    }

    var isVisible: Bool { panel.isVisible }
    var selected: Suggestion? { table.selectedRow >= 0 && table.selectedRow < items.count ? items[table.selectedRow] : nil }

    /// Updates the list for `query`. Local matches show immediately; remote search suggestions
    /// (only when allowed) are appended after a short pause in typing.
    func update(query: String, below anchor: NSView, allowRemote: Bool) {
        self.anchor = anchor
        generation += 1
        let current = generation
        remoteTask?.cancel()
        let local = Suggestions.rank(query: query, history: History.shared.entries,
                                     bookmarks: Bookmarks.shared.flattenedBookmarks, limit: 6)
        show(local)

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard allowRemote, Settings.searchSuggestions, !trimmed.isEmpty,
              let endpoint = Settings.searchEngine?.suggestURL,
              let url = SearchEngine.url(for: trimmed, prefix: endpoint) else { return }
        remoteTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled,
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let self, self.generation == current else { return }
            let known = Set(local.map(\.title))
            let remote = Suggestions.parseRemote(data).prefix(4).compactMap { text -> Suggestion? in
                guard text.lowercased() != trimmed.lowercased(), !known.contains(text),
                      let target = SearchEngine.url(for: text, prefix: Settings.searchURL) else { return nil }
                return Suggestion(kind: .search, title: text, url: target)
            }
            self.show(local + remote)
        }
    }

    private func show(_ list: [Suggestion]) {
        items = list
        table.reloadData()
        table.deselectAll(nil)
        guard !list.isEmpty, let anchor, let window = anchor.window else { return hide() }
        let rect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let height = CGFloat(list.count) * Self.rowHeight + 8
        let width = max(rect.width, 420)
        panel.setFrame(NSRect(x: rect.minX, y: rect.minY - height - 4, width: width, height: height), display: true)
        if !panel.isVisible {
            window.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
        }
    }

    func hide() {
        generation += 1
        remoteTask?.cancel()
        guard panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// ↑/↓ from the address field. Returns false when the popup isn't showing.
    func moveSelection(by delta: Int) -> Bool {
        guard panel.isVisible, !items.isEmpty else { return false }
        var row = table.selectedRow + delta
        if row < -1 { row = items.count - 1 }
        if row >= items.count { row = -1 }
        if row < 0 { table.deselectAll(nil) } else {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
        return true
    }

    @objc private func clicked(_ sender: Any?) {
        let row = table.clickedRow
        guard row >= 0, row < items.count else { return }
        onChoose?(items[row])
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let cell = NSTableCellView()
        let symbol: String
        switch item.kind {
        case .history: symbol = "clock"
        case .bookmark: symbol = "star"
        case .search: symbol = "magnifyingglass"
        }
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor
        let title = NSTextField(labelWithString: item.title)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var views: [NSView] = [icon, title]
        if item.kind != .search {
            let address = NSTextField(labelWithString: Suggestions.strippedPrefix(item.url.absoluteString))
            address.textColor = .secondaryLabelColor
            address.lineBreakMode = .byTruncatingTail
            address.setContentCompressionResistancePriority(.init(100), for: .horizontal)
            views.append(address)
        }
        let stack = NSStackView(views: views)
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
        ])
        return cell
    }
}

/// Lets a single click choose a row even though the popup's window is never key.
private final class ClickThroughTable: NSTableView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
