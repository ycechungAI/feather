import AppKit

/// The always-visible strip of bookmarks under the toolbar. Bookmarks that don't fit
/// are reachable from the » button at the right edge.
final class BookmarkBar: NSView {
    static let height: CGFloat = 28

    /// Called with the URL and whether it should open in a new background tab.
    var onOpen: ((URL, Bool) -> Void)?

    private let stack = NSStackView()
    private let clip = NSView()
    private let overflowButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "Press ⌘D or click ☆ to add a bookmark here")

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .horizontal
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
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

    @objc private func reload() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let items = Bookmarks.shared.items
        for (index, bookmark) in items.enumerated() {
            stack.addArrangedSubview(button(for: bookmark, index: index))
        }
        emptyLabel.isHidden = !items.isEmpty
        overflowButton.isHidden = items.isEmpty
    }

    private func button(for bookmark: Bookmark, index: Int) -> NSButton {
        let title = bookmark.title.count > 24 ? String(bookmark.title.prefix(23)) + "…" : bookmark.title
        let button = NSButton(title: title, target: self, action: #selector(clicked(_:)))
        button.bezelStyle = .recessed
        button.showsBorderOnlyWhileMouseInside = true
        button.font = .systemFont(ofSize: 12)
        button.tag = index
        button.toolTip = "\(bookmark.title)\n\(bookmark.url.absoluteString)"
        button.setContentCompressionResistancePriority(.required, for: .horizontal)

        let menu = NSMenu()
        menu.addItem(withTitle: "Open in New Tab", action: #selector(openInNewTab(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Rename…", action: #selector(rename(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Delete", action: #selector(delete(_:)), keyEquivalent: "")
        menu.items.forEach { $0.target = self; $0.tag = index }
        button.menu = menu
        return button
    }

    private func bookmark(_ sender: Any?) -> Bookmark? {
        let tag = (sender as? NSButton)?.tag ?? (sender as? NSMenuItem)?.tag ?? -1
        return Bookmarks.shared.items.indices.contains(tag) ? Bookmarks.shared.items[tag] : nil
    }

    @objc private func clicked(_ sender: Any?) {
        guard let b = bookmark(sender) else { return }
        let newTab = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
        onOpen?(b.url, newTab)
    }

    @objc private func openInNewTab(_ sender: NSMenuItem) {
        if let b = bookmark(sender) { onOpen?(b.url, true) }
    }

    @objc private func delete(_ sender: NSMenuItem) {
        Bookmarks.shared.remove(at: sender.tag)
    }

    @objc private func rename(_ sender: NSMenuItem) {
        guard let b = bookmark(sender) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Bookmark"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = b.title
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let index = sender.tag
        let done: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn { Bookmarks.shared.rename(at: index, to: field.stringValue) }
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: done) } else { done(alert.runModal()) }
    }

    @objc private func showAll(_ sender: NSButton) {
        let menu = NSMenu()
        for (index, b) in Bookmarks.shared.items.enumerated() {
            let item = NSMenuItem(title: b.title, action: #selector(clicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.toolTip = b.url.absoluteString
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }
}
