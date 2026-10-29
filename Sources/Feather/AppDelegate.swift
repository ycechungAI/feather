import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var openedFromURL = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false // Feather draws its own tabs
        NSApp.mainMenu = MainMenu.build()
        TabSuspender.shared.start()
        CacheLimiter.shared.start()
        ExtensionManager.shared.loadAll()
        SessionRestore.shared.snapshot = { BrowserWindowController.sessionSnapshot() }
        TabGroups.shared.openTabs = { BrowserWindowController.openTabGroups() }
        Shields.shared.prepare { [weak self] in
            // `Feather https://example.com` from Terminal
            let arg = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("-") }.flatMap(URLTools.resolve)
            if Settings.restoreSession {
                BrowserWindowController.restore(windows: SessionRestore.shared.takePreviousSession())
            }
            if let arg {
                BrowserWindowController.open(url: arg, inTabOf: BrowserWindowController.frontmost(isPrivate: false)?.window)
            } else if self?.openedFromURL == false, BrowserWindowController.all.isEmpty {
                BrowserWindowController.open(url: nil)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        History.shared.saveNow()
        TabGroups.shared.syncNow()
        SessionRestore.shared.saveNow()
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
        NotificationCenter.default.post(name: Settings.changed, object: nil)
    }

    @objc func toggleHTTPSOnly(_ sender: Any?) {
        Settings.httpsOnly.toggle()
        NotificationCenter.default.post(name: Settings.changed, object: nil)
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    @objc func showDownloads(_ sender: Any?) {
        DownloadsWindowController.shared.show()
    }

    @objc func reopenClosedTab(_ sender: Any?) {
        BrowserWindowController.reopenClosedTab()
    }

    /// History ▸ Reopen Last Session, for when automatic restore is off (or was skipped).
    @objc func reopenLastSession(_ sender: Any?) {
        BrowserWindowController.restore(windows: SessionRestore.shared.takePreviousSession())
    }

    @objc func showAbout(_ sender: Any?) {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "development build"
        let webKit = Bundle(for: WKWebView.self).infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let credits = NSMutableAttributedString(
            string: "A light, private browser for macOS.\n\nWebKit \(webKit) (the engine in Safari \(Settings.safariVersion))\nmacOS \(os)",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                         .foregroundColor: NSColor.secondaryLabelColor])
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        credits.addAttribute(.paragraphStyle, value: center, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Feather",
            .applicationVersion: version,
            .version: "",
            .credits: credits,
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func reloadBlocklists(_ sender: Any?) {
        Shields.shared.prepare(force: true) {
            BrowserWindowController.all.forEach { $0.shieldsChanged(rulesChanged: true) }
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
        case #selector(reopenClosedTab(_:)): return !SessionRestore.shared.closedTabs.isEmpty
        case #selector(reopenLastSession(_:)): return !SessionRestore.shared.previousSession.isEmpty
        default: break
        }
        return true
    }
}
