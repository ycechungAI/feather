import AppKit

enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        main.addSubmenu("Feather", [
            item("About Feather", #selector(AppDelegate.showAbout(_:))),
            .separator(),
            item("Settings…", #selector(AppDelegate.showSettings(_:)), ","),
            .separator(),
            item("Hide Feather", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit Feather", #selector(NSApplication.terminate(_:)), "q"),
        ])

        main.addSubmenu("File", [
            item("New Tab", #selector(NSResponder.newWindowForTab(_:)), "t"),
            item("New Window", #selector(AppDelegate.newWindow(_:)), "n"),
            item("New Private Window", #selector(AppDelegate.newPrivateWindow(_:)), "n", [.command, .shift]),
            item("Open Location…", #selector(BrowserWindowController.focusAddressBar(_:)), "l"),
            .separator(),
            item("Close Tab", #selector(TabWindow.closeTab(_:)), "w"),
            item("Close Window", #selector(NSWindow.performClose(_:)), "w", [.command, .shift]),
            item("Reopen Closed Tab", #selector(AppDelegate.reopenClosedTab(_:)), "t", [.command, .shift]),
            item("Print…", #selector(BrowserWindowController.printPage(_:)), "p"),
        ])

        main.addSubmenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Find…", #selector(BrowserWindowController.showFindBar(_:)), "f"),
            item("Find Next", #selector(BrowserWindowController.findNextMatch(_:)), "g"),
            item("Find Previous", #selector(BrowserWindowController.findPreviousMatch(_:)), "g", [.command, .shift]),
            item("Hide Find Bar", #selector(BrowserWindowController.closeFindBar(_:)), "f", [.command, .shift]),
        ])

        main.addSubmenu("View", [
            item("Reload Page", #selector(BrowserWindowController.reloadPage(_:)), "r"),
            item("Actual Size", #selector(BrowserWindowController.zoomReset(_:)), "0"),
            item("Zoom In", #selector(BrowserWindowController.zoomIn(_:)), "+"),
            item("Zoom Out", #selector(BrowserWindowController.zoomOut(_:)), "-"),
            .separator(),
            item("Picture in Picture", #selector(BrowserWindowController.togglePictureInPicture(_:)), "p", [.command, .option]),
            item("Download Video", #selector(BrowserWindowController.downloadVideo(_:)), "s", [.command, .option]),
            item("Load Subtitle File…", #selector(BrowserWindowController.loadSubtitleFile(_:)), "", []),
            item("Mute Tab", #selector(BrowserWindowController.toggleMute(_:)), "m", [.command, .control]),
            item("Show Web Inspector", #selector(BrowserWindowController.showWebInspector(_:)), "i", [.command, .option]),
            item("Downloads", #selector(AppDelegate.showDownloads(_:)), "l", [.command, .option]),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ])

        let history = main.addSubmenu("History", [
            item("Back", #selector(BrowserWindowController.navigateBack(_:)), "["),
            item("Forward", #selector(BrowserWindowController.navigateForward(_:)), "]"),
            .separator(),
            item("Show All History", #selector(AppDelegate.showHistory(_:)), "y"),
            item("Reopen Last Session", #selector(AppDelegate.reopenLastSession(_:))),
            item("Clear History…", #selector(AppDelegate.clearHistory(_:)), "\u{8}", [.command, .shift]),
        ])
        history.items.last?.tag = RecentHistoryMenu.marker
        history.delegate = RecentHistoryMenu.shared

        let bookmarks = main.addSubmenu("Bookmarks", [])
        bookmarks.delegate = BookmarksMenu.shared

        let sessions = main.addSubmenu("Sessions", [])
        sessions.delegate = SessionsMenu.shared

        let tabGroups = main.addSubmenu("Tab Groups", [])
        tabGroups.delegate = TabGroupsMenu.shared

        let extensions = main.addSubmenu("Extensions", [])
        extensions.delegate = ExtensionMenu.shared

        main.addSubmenu("Shields", [
            item("Block Ads & Trackers", #selector(AppDelegate.toggleShields(_:))),
            item("HTTPS-Only Mode", #selector(AppDelegate.toggleHTTPSOnly(_:))),
            .separator(),
            item("Reload Blocklists", #selector(AppDelegate.reloadBlocklists(_:))),
            item("Open Blocklist Folder", #selector(AppDelegate.openBlocklistFolder(_:))),
        ])

        let window = main.addSubmenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Show Previous Tab", #selector(TabWindow.showPreviousTab(_:)), "{"),
            item("Show Next Tab", #selector(TabWindow.showNextTab(_:)), "}"),
            item("Next Tab", #selector(TabWindow.showNextTab(_:)), "\t", [.control]),
            item("Previous Tab", #selector(TabWindow.showPreviousTab(_:)), "\t", [.control, .shift]),
            item("Move Tab to New Window", #selector(TabWindow.moveTabToNewWindow(_:))),
            .separator(),
        ] + (1...9).map { n in
            let tab = item(n == 9 ? "Last Tab" : "Tab \(n)", #selector(TabWindow.showTabNumber(_:)), "\(n)")
            tab.tag = n
            return tab
        } + [
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        NSApp.windowsMenu = window
        return main
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "",
                             _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        return item
    }
}

private extension NSMenu {
    @discardableResult
    func addSubmenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
        let sub = NSMenu(title: title)
        items.forEach(sub.addItem)
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = sub
        addItem(holder)
        return sub
    }
}
