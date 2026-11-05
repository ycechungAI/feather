import AppKit

/// The Bookmarks menu: "Bookmark This Page", then all bookmarks (folders as
/// submenus), then Import/Export. Rebuilt every time it opens. ⌘-click (or
/// ⌘ on the menu item) opens a bookmark in a new tab.
final class BookmarksMenu: NSObject, NSMenuDelegate {
    static let shared = BookmarksMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let bookmarkThisPage = NSMenuItem(
            title: "Bookmark This Page",
            action: #selector(BrowserWindowController.toggleBookmark(_:)),
            keyEquivalent: "d")
        menu.addItem(bookmarkThisPage)

        let items = Bookmarks.shared.items
        if !items.isEmpty {
            menu.addItem(.separator())
            for node in items {
                menu.addItem(menuItem(for: node))
            }
        }

        menu.addItem(.separator())

        let importItem = NSMenuItem(
            title: "Import Bookmarks…",
            action: #selector(AppDelegate.importBookmarks(_:)),
            keyEquivalent: "")
        menu.addItem(importItem)

        let exportItem = NSMenuItem(
            title: "Export Bookmarks…",
            action: #selector(AppDelegate.exportBookmarks(_:)),
            keyEquivalent: "")
        menu.addItem(exportItem)
    }

    private func menuItem(for node: BookmarkNode) -> NSMenuItem {
        switch node {
        case .bookmark(let b):
            let item = NSMenuItem(title: b.title, action: #selector(openBookmark(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = b.url.absoluteString
            item.toolTip = b.url.absoluteString
            return item
        case .folder(let f):
            let item = NSMenuItem(title: f.title, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for child in f.children {
                sub.addItem(menuItem(for: child))
            }
            if sub.items.isEmpty {
                let empty = NSMenuItem(title: "(Empty)", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                sub.addItem(empty)
            }
            item.submenu = sub
            return item
        }
    }

    @objc private func openBookmark(_ sender: NSMenuItem) {
        guard let string = sender.representedObject as? String,
              let url = URL(string: string) else { return }
        let newTab = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
        BrowserWindowController.openFromApp(url, newTab: newTab)
    }
}
