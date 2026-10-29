import AppKit

/// Feather ▸ Settings (⌘,). Every change applies immediately; there's no Save button.
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTextFieldDelegate {
    static let shared = SettingsWindowController()

    private let engine = NSPopUpButton()
    private let customSearch = NSTextField()
    private let home = NSTextField()
    private let sleep = NSPopUpButton()
    private let cacheLimit = NSPopUpButton()
    private var shields: NSButton!
    private var httpsOnly: NSButton!
    private var suggestions: NSButton!
    private var restore: NSButton!
    private var inspector: NSButton!
    private let exceptions = NSTableView()
    private var removeException: NSButton!
    private let defaultStatus = NSTextField(labelWithString: "")
    private var defaultButton: NSButton!
    private var grid: NSGridView!

    private static let sleepChoices: [(String, Int)] = [
        ("5 minutes", 5), ("10 minutes", 10), ("30 minutes", 30), ("1 hour", 60), ("Never", 0),
    ]

    private static let cacheChoices: [(String, Int)] = [
        ("250 MB", 250), ("500 MB", 500), ("1 GB", 1000), ("2 GB", 2000), ("5 GB", 5000),
    ]

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 650),
                              styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Settings"
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: Settings.changed, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        refresh()
        if window?.isVisible == false { window?.center() }
        showWindow(nil)
    }

    // MARK: Layout

    private func buildUI() {
        guard let content = window?.contentView else { return }

        engine.addItems(withTitles: SearchEngine.all.map(\.name) + ["Custom"])
        engine.target = self
        engine.action = #selector(engineChanged(_:))
        customSearch.placeholderString = "https://example.com/search?q="
        customSearch.delegate = self
        home.placeholderString = "https://www.google.com"
        home.delegate = self
        let useCurrent = NSButton(title: "Use Current Page", target: self, action: #selector(useCurrentPage(_:)))
        useCurrent.controlSize = .small

        sleep.addItems(withTitles: Self.sleepChoices.map(\.0))
        sleep.target = self
        sleep.action = #selector(sleepChanged(_:))

        cacheLimit.addItems(withTitles: Self.cacheChoices.map(\.0))
        cacheLimit.target = self
        cacheLimit.action = #selector(cacheLimitChanged(_:))
        let cacheBox = NSStackView(views: [cacheLimit, note("Keeps scripts, styles and fonts for your 20 most visited sites. "
                                                            + "Video, audio and large images aren't kept. A bigger limit keeps more.")])
        cacheBox.orientation = .vertical
        cacheBox.alignment = .leading
        cacheBox.spacing = 2
        let signedIn = note("Clearing cookies and site data never signs you out of "
                            + (Settings.keepSignedIn.isEmpty ? "any site." : Settings.keepSignedIn.joined(separator: ", ") + "."))

        shields = checkbox("Block ads & trackers (Shields)", #selector(toggled(_:)))
        httpsOnly = checkbox("HTTPS-Only Mode: always use secure connections", #selector(toggled(_:)))
        suggestions = checkbox("Show search engine suggestions", #selector(toggled(_:)))
        restore = checkbox("Reopen tabs from last time when Feather starts", #selector(toggled(_:)))
        inspector = checkbox("Show Inspect Element (Web Inspector, with the console)", #selector(toggled(_:)))
        let inspectorBox = NSStackView(views: [inspector, note("Right-click a page ▸ Inspect Element, or View ▸ Show Web Inspector (⌥⌘I). "
                                                               + "Applies to pages loaded after you turn it on.")])
        inspectorBox.orientation = .vertical
        inspectorBox.alignment = .leading
        inspectorBox.spacing = 2

        let suggestionsNote = note("Sends what you type in the address bar to your search engine. "
                                   + "Matches from your history and bookmarks always stay on this Mac.")

        let hostColumn = NSTableColumn(identifier: .init("host"))
        hostColumn.resizingMask = .autoresizingMask
        exceptions.addTableColumn(hostColumn)
        exceptions.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        exceptions.headerView = nil
        exceptions.dataSource = self
        exceptions.usesAlternatingRowBackgroundColors = true
        exceptions.target = self
        exceptions.action = #selector(exceptionSelected(_:))
        let exceptionsScroll = NSScrollView()
        exceptionsScroll.documentView = exceptions
        exceptionsScroll.hasVerticalScroller = true
        exceptionsScroll.borderType = .bezelBorder
        exceptionsScroll.translatesAutoresizingMaskIntoConstraints = false
        exceptionsScroll.heightAnchor.constraint(equalToConstant: 90).isActive = true
        exceptionsScroll.widthAnchor.constraint(equalToConstant: 300).isActive = true
        removeException = NSButton(title: "Remove", target: self, action: #selector(removeException(_:)))
        removeException.controlSize = .small
        let exceptionsBox = NSStackView(views: [exceptionsScroll, removeException,
                                                note("Turn Shields off for a site from the shield button in the toolbar.")])
        exceptionsBox.orientation = .vertical
        exceptionsBox.alignment = .leading
        exceptionsBox.spacing = 4

        defaultButton = NSButton(title: "Make Feather the Default Browser", target: self,
                                 action: #selector(makeDefault(_:)))
        let defaultBox = NSStackView(views: [defaultButton, defaultStatus])
        defaultBox.orientation = .vertical
        defaultBox.alignment = .leading
        defaultStatus.textColor = .secondaryLabelColor
        defaultStatus.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let homeRow = NSStackView(views: [home, useCurrent])
        let suggestionsBox = NSStackView(views: [suggestions, suggestionsNote])
        suggestionsBox.orientation = .vertical
        suggestionsBox.alignment = .leading
        suggestionsBox.spacing = 2

        grid = NSGridView(views: [
            [label("Search engine:"), engine],
            [NSGridCell.emptyContentView, customSearch],
            [label("Home page:"), homeRow],
            [label("Sleep inactive tabs after:"), sleep],
            [label("Web cache limit:"), cacheBox],
            [label("Stay signed in:"), signedIn],
            [label("Privacy:"), shields],
            [NSGridCell.emptyContentView, httpsOnly],
            [NSGridCell.emptyContentView, suggestionsBox],
            [label("Shields off for:"), exceptionsBox],
            [label("Startup:"), restore],
            [label("Default browser:"), defaultBox],
            [label("Developer:"), inspectorBox],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        for row in [4, 9, 11, 12] { grid.row(at: row).yPlacement = .top; grid.row(at: row).rowAlignment = .none }
        grid.row(at: 8).rowAlignment = .none
        grid.row(at: 8).yPlacement = .top
        grid.row(at: 9).topPadding = 6
        grid.row(at: 10).topPadding = 6
        customSearch.widthAnchor.constraint(equalToConstant: 320).isActive = true
        home.widthAnchor.constraint(equalToConstant: 300).isActive = true
        suggestionsNote.preferredMaxLayoutWidth = 340

        grid.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
    }

    private func label(_ text: String) -> NSTextField { NSTextField(labelWithString: text) }

    private func note(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.textColor = .secondaryLabelColor
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.preferredMaxLayoutWidth = 340
        return field
    }

    private func checkbox(_ title: String, _ action: Selector) -> NSButton {
        NSButton(checkboxWithTitle: title, target: self, action: action)
    }

    // MARK: State

    @objc private func refresh() {
        guard isWindowLoaded else { return }
        if let preset = Settings.searchEngine, let i = SearchEngine.all.firstIndex(of: preset) {
            engine.selectItem(at: i)
            grid.row(at: 1).isHidden = true
        } else {
            engine.selectItem(at: SearchEngine.all.count)
            grid.row(at: 1).isHidden = false
        }
        if window?.firstResponder != customSearch.currentEditor() { customSearch.stringValue = Settings.searchURL }
        if window?.firstResponder != home.currentEditor() { home.stringValue = Settings.homePageURL.absoluteString }
        let minutes = Settings.suspendMinutes
        sleep.selectItem(at: Self.sleepChoices.firstIndex { $0.1 == minutes } ?? 1)
        let limit = Settings.cacheLimitMB
        cacheLimit.selectItem(at: Self.cacheChoices.lastIndex { $0.1 <= limit } ?? 1)
        shields.state = Settings.shieldsEnabled ? .on : .off
        httpsOnly.state = Settings.httpsOnly ? .on : .off
        suggestions.state = Settings.searchSuggestions ? .on : .off
        suggestions.isEnabled = Settings.searchEngine?.suggestURL != nil
        restore.state = Settings.restoreSession ? .on : .off
        inspector.state = Settings.webInspector ? .on : .off
        exceptions.reloadData()
        removeException.isEnabled = exceptions.selectedRow >= 0
        refreshDefaultBrowser()
    }

    private func refreshDefaultBrowser() {
        let current = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        let isDefault = current?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
        defaultButton.isEnabled = !isDefault && Bundle.main.bundleIdentifier != nil
        defaultStatus.stringValue = isDefault ? "Feather is your default browser."
            : "Current default: \(current.map { FileManager.default.displayName(atPath: $0.path) } ?? "none")"
    }

    // MARK: Actions

    @objc private func engineChanged(_ sender: NSPopUpButton) {
        let i = sender.indexOfSelectedItem
        if i < SearchEngine.all.count {
            let chosen = SearchEngine.all[i]
            let oldHome = Settings.searchEngine?.homeURL
            Settings.searchURL = chosen.searchURL
            // Keep the home page in step with the engine unless you've set your own.
            if oldHome == Settings.homePageURL.absoluteString, let url = URL(string: chosen.homeURL) {
                Settings.homePageURL = url
            }
        } else {
            grid.row(at: 1).isHidden = false
            window?.makeFirstResponder(customSearch)
        }
        NotificationCenter.default.post(name: Settings.changed, object: nil)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        if field === customSearch {
            if let url = URL(string: text), url.scheme == "https" || url.scheme == "http", url.host != nil {
                Settings.searchURL = text
            }
        } else if field === home {
            if let url = URLTools.resolve(text), url.scheme == "https" || url.scheme == "http" {
                Settings.homePageURL = url
            }
        }
        NotificationCenter.default.post(name: Settings.changed, object: nil)
    }

    @objc private func useCurrentPage(_ sender: Any?) {
        guard let url = BrowserWindowController.frontmost(isPrivate: false)?.webView?.url,
              url.scheme == "https" || url.scheme == "http" else { return }
        Settings.homePageURL = url
        NotificationCenter.default.post(name: Settings.changed, object: nil)
    }

    @objc private func sleepChanged(_ sender: NSPopUpButton) {
        Settings.suspendMinutes = Self.sleepChoices[sender.indexOfSelectedItem].1
        NotificationCenter.default.post(name: Settings.changed, object: nil)
    }

    @objc private func cacheLimitChanged(_ sender: NSPopUpButton) {
        Settings.cacheLimitMB = Self.cacheChoices[sender.indexOfSelectedItem].1
        CacheLimiter.shared.enforce()
        NotificationCenter.default.post(name: Settings.changed, object: nil)
    }

    @objc private func toggled(_ sender: NSButton) {
        let on = sender.state == .on
        switch sender {
        case shields:
            Settings.shieldsEnabled = on
            BrowserWindowController.all.forEach { $0.shieldsChanged() }
        case httpsOnly: Settings.httpsOnly = on
        case suggestions: Settings.searchSuggestions = on
        case restore: Settings.restoreSession = on
        case inspector:
            Settings.webInspector = on
            BrowserWindowController.all.forEach { $0.webView?.isInspectable = on }
        default: break
        }
        NotificationCenter.default.post(name: Settings.changed, object: nil)
    }

    @objc private func exceptionSelected(_ sender: Any?) {
        removeException.isEnabled = exceptions.selectedRow >= 0
    }

    @objc private func removeException(_ sender: Any?) {
        let list = Settings.shieldsAllowlist
        let row = exceptions.selectedRow
        guard row >= 0, row < list.count else { return }
        Settings.shieldsAllowlist = list.filter { $0 != list[row] }
        BrowserWindowController.all.forEach { $0.shieldsChanged() }
        NotificationCenter.default.post(name: Settings.changed, object: nil)
    }

    /// macOS shows its own confirmation ("Use Feather as your default browser?").
    @objc private func makeDefault(_ sender: Any?) {
        setDefault(schemes: ["http", "https"])
    }

    /// Registers each scheme in turn. macOS asks the user to confirm, and choosing a browser for
    /// `http` usually covers `https` too, so `https` is only set if it still points elsewhere.
    private func setDefault(schemes: [String]) {
        let app = Bundle.main.bundleURL
        guard let scheme = schemes.first else { return refreshDefaultBrowser() }
        let rest = Array(schemes.dropFirst())
        if let current = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "\(scheme)://example.com")!),
           current.standardizedFileURL == app.standardizedFileURL {
            return setDefault(schemes: rest)
        }
        NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: scheme) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    let alert = NSAlert(error: error)
                    alert.informativeText = "You can also choose Feather in System Settings ▸ Desktop & Dock ▸ Default web browser."
                    alert.runModal()
                    self?.refreshDefaultBrowser()
                } else {
                    self?.setDefault(schemes: rest)
                }
            }
        }
    }

    // MARK: Exceptions table

    func numberOfRows(in tableView: NSTableView) -> Int { Settings.shieldsAllowlist.count }

    func tableView(_ tableView: NSTableView, objectValueFor column: NSTableColumn?, row: Int) -> Any? {
        let list = Settings.shieldsAllowlist
        return row < list.count ? list[row] : nil
    }
}
