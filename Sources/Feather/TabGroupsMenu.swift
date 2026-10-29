import AppKit

extension TabGroupColor {
    var nsColor: NSColor {
        switch self {
        case .grey: .systemGray
        case .blue: .systemBlue
        case .red: .systemRed
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .purple: .systemPurple
        case .orange: .systemOrange
        case .brown: .systemBrown
        }
    }

    /// A small filled circle, for menus.
    var swatch: NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            self.nsColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }
}

/// The Tab Groups menu: make a group from the current tab or window, add or remove the
/// current tab, and open, rename, recolor, close or delete saved groups. Rebuilt every time
/// it opens. The bookmarks bar's group chips use the same per-group menu.
final class TabGroupsMenu: NSObject, NSMenuDelegate, NSMenuItemValidation {
    static let shared = TabGroupsMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let raw = menu.identifier?.rawValue, let id = UUID(uuidString: raw) {
            groupMenu(for: id).items.forEach { item in
                item.menu?.removeItem(item)
                menu.addItem(item)
            }
            return
        }
        let groups = TabGroups.shared.all
        let current = currentTab?.tabGroupID

        menu.addItem(item("New Group from Current Tab…", #selector(newGroupFromTab(_:))))
        menu.addItem(item("New Group from Window’s Tabs…", #selector(newGroupFromWindow(_:))))

        let add = NSMenuItem(title: "Add Current Tab to Group", action: nil, keyEquivalent: "")
        let addMenu = NSMenu()
        for group in groups {
            let entry = item(group.name, #selector(addTabToGroup(_:)), group.id)
            entry.image = group.color.swatch
            entry.state = group.id == current ? .on : .off
            addMenu.addItem(entry)
        }
        add.submenu = addMenu
        add.isEnabled = !groups.isEmpty
        menu.addItem(add)
        menu.addItem(item("Remove Current Tab from Group", #selector(removeTabFromGroup(_:))))

        guard !groups.isEmpty else { return }
        menu.addItem(.separator())
        for group in groups {
            let entry = NSMenuItem(title: group.name, action: nil, keyEquivalent: "")
            entry.image = group.color.swatch
            entry.submenu = groupMenu(for: group.id)
            let open = BrowserWindowController.members(of: group.id).count
            entry.toolTip = "\(group.tabs.count) tab\(group.tabs.count == 1 ? "" : "s")" + (open > 0 ? " · open" : "")
            menu.addItem(entry)
        }
    }

    /// A chip's right-click menu, filled in when it opens so it matches what's open then.
    func chipMenu(for id: UUID) -> NSMenu {
        let menu = NSMenu()
        menu.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        menu.autoenablesItems = false
        menu.delegate = self
        return menu
    }

    /// One group's commands, for its Tab Groups submenu and its chip on the bookmarks bar.
    func groupMenu(for id: UUID) -> NSMenu {
        let menu = NSMenu()
        let isOpen = !BrowserWindowController.members(of: id).isEmpty
        menu.addItem(item(isOpen ? "Show Tabs" : "Open Tabs", #selector(showGroup(_:)), id))
        menu.addItem(item(isOpen ? "Move to New Window" : "Open in New Window", #selector(openGroupInNewWindow(_:)), id))
        menu.addItem(.separator())
        menu.addItem(item("Rename…", #selector(renameGroup(_:)), id))
        let colors = NSMenuItem(title: "Change Color", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        let currentColor = TabGroups.shared.group(id: id)?.color
        for color in TabGroupColor.allCases {
            let entry = item(color.name, #selector(changeColor(_:)), id)
            entry.image = color.swatch
            entry.tag = TabGroupColor.allCases.firstIndex(of: color)!
            entry.state = color == currentColor ? .on : .off
            colorMenu.addItem(entry)
        }
        colors.submenu = colorMenu
        menu.addItem(colors)
        menu.addItem(.separator())
        let close = item("Close Group", #selector(closeGroup(_:)), id)
        close.isEnabled = isOpen
        menu.addItem(close)
        menu.addItem(item("Delete Group…", #selector(deleteGroup(_:)), id))
        menu.autoenablesItems = false
        return menu
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(newGroupFromTab(_:)), #selector(newGroupFromWindow(_:)):
            return currentTab?.savedTab != nil
        case #selector(addTabToGroup(_:)):
            return currentTab?.savedTab != nil
        case #selector(removeTabFromGroup(_:)):
            return currentTab?.tabGroupID != nil
        default:
            return true
        }
    }

    // MARK: - Actions

    @objc func newGroupFromTab(_ sender: Any?) {
        guard let tab = currentTab, tab.savedTab != nil else { return }
        createGroup(from: [tab])
    }

    @objc func newGroupFromWindow(_ sender: Any?) {
        guard let window = currentTab?.window else { return }
        let tabs = (window.tabbedWindows ?? [window])
            .compactMap { $0.windowController as? BrowserWindowController }
            .filter { $0.savedTab != nil }
        createGroup(from: tabs)
    }

    @objc private func addTabToGroup(_ sender: NSMenuItem) {
        guard let id = id(for: sender) else { return }
        currentTab?.addToTabGroup(id)
    }

    @objc private func removeTabFromGroup(_ sender: Any?) {
        currentTab?.removeFromTabGroup()
    }

    @objc private func showGroup(_ sender: NSMenuItem) {
        guard let id = id(for: sender) else { return }
        BrowserWindowController.showTabGroup(id)
    }

    @objc private func openGroupInNewWindow(_ sender: NSMenuItem) {
        guard let id = id(for: sender) else { return }
        BrowserWindowController.moveTabGroupToNewWindow(id)
    }

    @objc private func renameGroup(_ sender: NSMenuItem) {
        guard let id = id(for: sender), let group = TabGroups.shared.group(id: id) else { return }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = group.name
        present(title: "Rename Tab Group", info: nil, accessory: field, field: field, button: "Save") {
            TabGroups.shared.rename(id, to: field.stringValue)
        }
    }

    @objc private func changeColor(_ sender: NSMenuItem) {
        guard let id = id(for: sender), TabGroupColor.allCases.indices.contains(sender.tag) else { return }
        TabGroups.shared.setColor(id, to: TabGroupColor.allCases[sender.tag])
    }

    @objc private func closeGroup(_ sender: NSMenuItem) {
        guard let id = id(for: sender) else { return }
        BrowserWindowController.closeTabGroup(id)
    }

    @objc private func deleteGroup(_ sender: NSMenuItem) {
        guard let id = id(for: sender), let group = TabGroups.shared.group(id: id) else { return }
        present(title: "Delete “\(group.name)”?",
                info: "The group is removed from Feather. Its open tabs stay open, outside any group.",
                accessory: nil, field: nil, button: "Delete") {
            TabGroups.shared.delete(id)
        }
    }

    // MARK: - Helpers

    /// The selected tab of the front normal window.
    private var currentTab: BrowserWindowController? {
        BrowserWindowController.frontmost(isPrivate: false)
    }

    /// Asks for a name and color, then groups the tabs.
    private func createGroup(from tabs: [BrowserWindowController]) {
        let saved = tabs.compactMap(\.savedTab).map { SavedTab(url: $0.url, title: $0.title) }
        guard !saved.isEmpty else { return }

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Group name"
        let colors = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 140, height: 26), pullsDown: false)
        for color in TabGroupColor.allCases {
            colors.addItem(withTitle: color.name)
            colors.lastItem?.image = color.swatch
        }
        colors.selectItem(at: TabGroupColor.allCases.firstIndex(of: TabGroups.shared.suggestedColor) ?? 0)
        let stack = NSStackView(views: [field, colors])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 280, height: 58)

        let count = saved.count
        present(title: "New Tab Group", info: "Group \(count) tab\(count == 1 ? "" : "s"):",
                accessory: stack, field: field, button: "Create") {
            let color = TabGroupColor.allCases[max(colors.indexOfSelectedItem, 0)]
            let group = TabGroups.shared.create(name: field.stringValue, color: color, tabs: saved)
            tabs.forEach { $0.tabGroupID = group.id }
        }
    }

    private func present(title: String, info: String?, accessory: NSView?, field: NSTextField?,
                         button: String, onConfirm: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        if let info { alert.informativeText = info }
        alert.accessoryView = accessory
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        if let field { alert.window.initialFirstResponder = field }
        let done: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn { onConfirm() }
        }
        if let keyWindow = NSApp.keyWindow {
            alert.beginSheetModal(for: keyWindow, completionHandler: done)
        } else {
            done(alert.runModal())
        }
    }

    private func item(_ title: String, _ action: Selector, _ id: UUID? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = id?.uuidString
        return item
    }

    private func id(for sender: NSMenuItem) -> UUID? {
        (sender.representedObject as? String).flatMap(UUID.init(uuidString:))
    }
}
