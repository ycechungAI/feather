import AppKit
import UniformTypeIdentifiers
import WebKit

/// Builds the Extensions menu (toolbar puzzle button and menu bar) and handles its actions.
final class ExtensionMenu: NSObject, NSMenuDelegate {
    static let shared = ExtensionMenu()
    private static let addonsURL = URL(string: "https://addons.mozilla.org/firefox/extensions/")!

    private var manager: ExtensionManager { .shared }
    private weak var tab: BrowserWindowController?

    /// Menu bar version: rebuilt every time it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        fill(menu, for: BrowserWindowController.frontmost(isPrivate: false))
    }

    func build(for tab: BrowserWindowController?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        fill(menu, for: tab)
        return menu
    }

    private func fill(_ menu: NSMenu, for tab: BrowserWindowController?) {
        self.tab = tab
        let loaded = manager.installed.filter(\.enabled).compactMap { record in
            manager.contexts[record.id].map { (record, $0) }
        }
        if manager.installed.isEmpty {
            menu.addItem(disabled("No extensions installed"))
        } else if loaded.isEmpty {
            menu.addItem(disabled("All extensions are turned off"))
        }
        for (record, context) in loaded {
            let action = context.action(for: tab)
            var title = action?.label.isEmpty == false ? action!.label : record.name
            if let badge = action?.badgeText, !badge.isEmpty { title += "  (\(badge))" }
            let item = NSMenuItem(title: title, action: #selector(runAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = record.id
            item.image = (action?.icon(for: CGSize(width: 16, height: 16))
                          ?? context.webExtension.icon(for: CGSize(width: 16, height: 16)))
            item.image?.size = NSSize(width: 16, height: 16)
            item.isEnabled = tab != nil && (action?.isEnabled ?? true)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        if let slug = ExtensionManager.addonSlug(tab?.webView?.url) {
            let item = NSMenuItem(title: "Add “\(slug)” to Feather", action: #selector(installCurrentAddon(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = slug
            menu.addItem(item)
        }
        menu.addItem(actionItem("Get Firefox Add-ons…", #selector(browseAddons(_:))))
        menu.addItem(actionItem("Install Add-on from File…", #selector(installFromFile(_:))))

        if !manager.installed.isEmpty {
            let manage = NSMenuItem(title: "Manage Extensions", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            sub.autoenablesItems = false
            for record in manager.installed.sorted(by: { $0.name < $1.name }) {
                let entry = NSMenuItem(title: record.name, action: nil, keyEquivalent: "")
                entry.submenu = optionsMenu(for: record.id, tab: tab)
                sub.addItem(entry)
            }
            manage.submenu = sub
            menu.addItem(manage)
        }
    }

    /// Per-extension options: used in Manage Extensions and when right-clicking a pinned button.
    func optionsMenu(for id: String, tab: BrowserWindowController?) -> NSMenu {
        self.tab = tab
        let options = NSMenu()
        options.autoenablesItems = false
        guard let record = manager.installed.first(where: { $0.id == id }) else { return options }
        if manager.incompatibility(for: id) != nil {
            options.addItem(actionItem("⚠️ Doesn't Work in Feather…", #selector(explainProblem(_:)), id))
            options.addItem(.separator())
        }
        let pin = actionItem("Pin to Toolbar", #selector(togglePinned(_:)), id)
        pin.state = record.pinned ? .on : .off
        options.addItem(pin)
        let toggle = actionItem("Turned On", #selector(toggleEnabled(_:)), id)
        toggle.state = record.enabled ? .on : .off
        options.addItem(toggle)
        let settings = actionItem("Settings…", #selector(openSettings(_:)), id)
        settings.isEnabled = manager.contexts[id]?.webExtension.hasOptionsPage == true
        options.addItem(settings)
        options.addItem(.separator())
        options.addItem(actionItem("Remove…", #selector(removeExtension(_:)), id))
        return options
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector, _ id: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = id
        item.isEnabled = true
        return item
    }

    // MARK: Actions

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let context = manager.contexts[id] else { return }
        if manager.explainIncompatibility(id, window: tab?.window) { return }
        context.performAction(for: tab)
    }

    @objc private func explainProblem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        _ = manager.explainIncompatibility(id, window: tab?.window)
    }

    @objc private func installCurrentAddon(_ sender: NSMenuItem) {
        guard let slug = sender.representedObject as? String else { return }
        let window = tab?.window
        Task { await manager.install(addonSlug: slug, window: window) }
    }

    @objc private func browseAddons(_ sender: Any?) {
        BrowserWindowController.openFromApp(Self.addonsURL, newTab: true)
    }

    @objc func installFromFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.message = "Choose a Firefox add-on (.xpi), a .zip, or an unpacked extension folder"
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "xpi") ?? .zip, .zip, .folder]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let window = tab?.window ?? NSApp.keyWindow
        Task { await manager.install(from: url, window: window) }
    }

    @objc private func togglePinned(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let record = manager.installed.first(where: { $0.id == id }) else { return }
        manager.setPinned(id, !record.pinned)
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let record = manager.installed.first(where: { $0.id == id }) else { return }
        manager.setEnabled(id, !record.enabled)
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let context = manager.contexts[id],
              let url = context.optionsPageURL else { return }
        BrowserWindowController.open(url: url, inTabOf: tab?.window, configuration: context.webViewConfiguration)
    }

    @objc private func removeExtension(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let record = manager.installed.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Remove “\(record.name)”?"
        alert.informativeText = "The extension and its saved data will be deleted from Feather."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            manager.remove(id, deleteFiles: true)
        }
    }
}

/// A pinned extension's toolbar button: its icon, badge, and popup.
final class ExtensionPinButton: NSButton {
    private let id: String
    private weak var context: WKWebExtensionContext?
    private weak var tab: BrowserWindowController?

    init(id: String, name: String, context: WKWebExtensionContext, tab: BrowserWindowController) {
        self.id = id
        self.context = context
        self.tab = tab
        super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 24))
        let extAction = context.action(for: tab)
        let size = CGSize(width: 18, height: 18)
        image = extAction?.icon(for: size) ?? context.webExtension.icon(for: size)
            ?? NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: name)
        image?.size = size
        imageScaling = .scaleProportionallyDown
        bezelStyle = .texturedRounded
        isBordered = false
        let label = extAction?.label ?? ""
        toolTip = label.isEmpty ? name : label
        setAccessibilityLabel(toolTip)
        target = self
        action = #selector(clicked(_:))
        isEnabled = extAction?.isEnabled ?? true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 28).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true
        if let badge = extAction?.badgeText, !badge.isEmpty { addBadge(badge) }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func addBadge(_ text: String) {
        let badge = NSTextField(labelWithString: String(text.prefix(4)))
        badge.font = .systemFont(ofSize: 8, weight: .bold)
        badge.textColor = .white
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.systemRed.cgColor
        badge.layer?.cornerRadius = 5
        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)
        NSLayoutConstraint.activate([
            badge.trailingAnchor.constraint(equalTo: trailingAnchor),
            badge.bottomAnchor.constraint(equalTo: bottomAnchor),
            badge.heightAnchor.constraint(equalToConstant: 10),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 12),
        ])
    }

    @objc private func clicked(_ sender: Any?) {
        if ExtensionManager.shared.explainIncompatibility(id, window: window) { return }
        ExtensionManager.shared.popupAnchor = self
        context?.performAction(for: tab)
    }

    override func rightMouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(ExtensionMenu.shared.optionsMenu(for: id, tab: tab), with: event, for: self)
    }
}
