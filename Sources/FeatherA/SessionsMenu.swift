import AppKit

/// The Sessions menu: save the frontmost window's tabs as a named session,
/// and restore, rename or delete saved sessions. Rebuilt every time it opens.
final class SessionsMenu: NSObject, NSMenuDelegate {
    static let shared = SessionsMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let save = NSMenuItem(title: "Save Tabs as Session…", action: #selector(saveTabsAsSession(_:)), keyEquivalent: "")
        save.target = self
        menu.addItem(save)

        let sessions = Sessions.shared.all
        guard !sessions.isEmpty else { return }
        menu.addItem(.separator())

        let dateStyle: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f
        }()

        for session in sessions {
            let item = NSMenuItem(title: session.name, action: nil, keyEquivalent: "")
            let sub = NSMenu()

            let restore = NSMenuItem(title: "Restore", action: #selector(restore(_:)), keyEquivalent: "")
            restore.target = self
            restore.representedObject = session.id.uuidString
            sub.addItem(restore)

            sub.addItem(.separator())

            let rename = NSMenuItem(title: "Rename…", action: #selector(rename(_:)), keyEquivalent: "")
            rename.target = self
            rename.representedObject = session.id.uuidString
            sub.addItem(rename)

            let delete = NSMenuItem(title: "Delete", action: #selector(delete(_:)), keyEquivalent: "")
            delete.target = self
            delete.representedObject = session.id.uuidString
            sub.addItem(delete)

            item.submenu = sub
            let tabs = session.urls.count
            item.toolTip = "\(tabs) tab\(tabs == 1 ? "" : "s") · saved \(dateStyle.string(from: session.created))"
            menu.addItem(item)
        }
    }

    // MARK: - Actions

    /// Saves the frontmost window's tabs as a new named session.
    @objc func saveTabsAsSession(_ sender: Any?) {
        guard let window = BrowserWindowController.frontmost(isPrivate: false)?.window else { return }
        let urls = Self.tabURLs(of: window)
        guard !urls.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Save Tabs as Session"
        alert.informativeText = "Save \(urls.count) tab\(urls.count == 1 ? "" : "s") as a new session:"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Session name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let done: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn,
               !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Sessions.shared.save(name: field.stringValue, urls: urls)
            }
        }
        if let keyWindow = NSApp.keyWindow {
            alert.beginSheetModal(for: keyWindow, completionHandler: done)
        } else {
            done(alert.runModal())
        }
    }

    @objc private func restore(_ sender: NSMenuItem) {
        guard let session = session(for: sender) else { return }
        BrowserWindowController.restore(session)
    }

    @objc private func rename(_ sender: NSMenuItem) {
        guard let session = session(for: sender) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Session"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = session.name
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let done: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                Sessions.shared.rename(session.id, to: field.stringValue)
            }
        }
        if let keyWindow = NSApp.keyWindow {
            alert.beginSheetModal(for: keyWindow, completionHandler: done)
        } else {
            done(alert.runModal())
        }
    }

    @objc private func delete(_ sender: NSMenuItem) {
        guard let id = id(for: sender) else { return }
        Sessions.shared.delete(id)
    }

    // MARK: - Helpers

    private func session(for sender: NSMenuItem) -> Session? {
        guard let id = id(for: sender) else { return nil }
        return Sessions.shared.session(id: id)
    }

    private func id(for sender: NSMenuItem) -> UUID? {
        guard let string = sender.representedObject as? String else { return nil }
        return UUID(uuidString: string)
    }

    /// The http(s) URLs of every tab in the window's tab group, in tab order.
    /// Sleeping tabs contribute their saved URL; blank/new-tab pages are skipped.
    static func tabURLs(of window: NSWindow) -> [URL] {
        let tabs = (window.windowController as? TabWindow)?.tabs ?? []
        return tabs.compactMap { controller in
            let url = controller.webView?.url ?? controller.sleepingURLForExtensions
            guard let url, let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { return nil }
            return url
        }
    }
}
