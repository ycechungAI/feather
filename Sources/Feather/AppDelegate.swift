import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var openedFromURL = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApp.mainMenu = MainMenu.build()
        TabSuspender.shared.start()
        ExtensionManager.shared.loadAll()
        Shields.shared.prepare { [weak self] in
            guard self?.openedFromURL == false, BrowserWindowController.all.isEmpty else { return }
            // `Feather https://example.com` from Terminal
            let arg = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("-") }
            BrowserWindowController.open(url: arg.flatMap(URLTools.resolve))
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        History.shared.saveNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Links opened from other apps when Feather is the default browser.
    func application(_ application: NSApplication, open urls: [URL]) {
        openedFromURL = true
        Shields.shared.prepare {
            for url in urls {
                BrowserWindowController.open(url: url, inTabOf: BrowserWindowController.frontmost(isPrivate: false)?.window)
            }
        }
    }

    // MARK: Menu actions

    @objc func newWindow(_ sender: Any?) {
        BrowserWindowController.open(url: nil)
    }

    /// ⌘T when no browser window is open.
    @objc func newWindowForTab(_ sender: Any?) {
        BrowserWindowController.open(url: nil)
    }

    @objc func newPrivateWindow(_ sender: Any?) {
        BrowserWindowController.open(url: nil, isPrivate: true)
    }

    @objc func toggleShields(_ sender: Any?) {
        Settings.shieldsEnabled.toggle()
        BrowserWindowController.all.forEach { $0.shieldsChanged() }
    }

    @objc func toggleHTTPSOnly(_ sender: Any?) {
        Settings.httpsOnly.toggle()
    }

    @objc func reloadBlocklists(_ sender: Any?) {
        Shields.shared.prepare(force: true) {
            BrowserWindowController.all.forEach { $0.shieldsChanged() }
        }
    }

    @objc func openBlocklistFolder(_ sender: Any?) {
        NSWorkspace.shared.open(Settings.supportDirectory)
    }

    @objc func showHistory(_ sender: Any?) {
        HistoryWindowController.shared.show()
    }

    @objc func clearHistory(_ sender: Any?) {
        HistoryWindowController.presentClearDialog(on: NSApp.keyWindow)
    }

    /// Reads a bookmarks .html file exported from Brave, Chrome, Safari, Firefox or Edge.
    @objc func importBookmarks(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.message = "Choose a bookmarks file exported from another browser (.html)"
        panel.allowedContentTypes = [.html]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alert = NSAlert()
        if let data = try? Data(contentsOf: url) {
            let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            let count = Bookmarks.shared.importHTML(html)
            alert.messageText = count == 0 ? "No new bookmarks found" : "Imported \(count) bookmark\(count == 1 ? "" : "s")"
        } else {
            alert.messageText = "Couldn't read that file"
        }
        alert.runModal()
    }

    @objc func exportBookmarks(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Feather Bookmarks.html"
        panel.allowedContentTypes = [.html]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Bookmarks.shared.exportHTML().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleShields(_:)): item.state = Settings.shieldsEnabled ? .on : .off
        case #selector(toggleHTTPSOnly(_:)): item.state = Settings.httpsOnly ? .on : .off
        default: break
        }
        return true
    }
}
