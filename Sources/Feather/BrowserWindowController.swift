import AppKit
import WebKit

/// One browser tab. Tabs are native macOS window tabs, so the tab bar, drag-to-detach and
/// Mission Control all come free from the OS with no extra code or memory.
final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
                                     WKNavigationDelegate, WKUIDelegate, WKWebExtensionTab,
                                     NSTextFieldDelegate, NSMenuItemValidation {
    static private(set) var all = Set<BrowserWindowController>()
    private static var privateStore: WKWebsiteDataStore?

    let isPrivate: Bool
    private(set) var webView: WKWebView?
    private let content = NSView()
    private let webArea = NSView()
    private let bookmarkBar = BookmarkBar()
    private let findBar = FindBar()
    private var findBarHeight: NSLayoutConstraint!
    private let suggestions = SuggestionsPopup()
    private let addressField = NSTextField()
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var reloadButton: NSButton!
    private var homeButton: NSButton!
    private var shieldButton: NSButton!
    private var newTabButton: NSButton!
    private var starButton: NSButton!
    private var pipButton: NSButton!
    private var extensionsButton: NSButton!
    private var downloadsButton: NSButton!
    private let extensionPins = NSStackView()
    private var observations: [NSKeyValueObservation] = []
    private var audioObservation: KVOObserver?

    /// The page title without the 🔊/🔇 prefix.
    private var baseTitle = ""
    private(set) var isPlayingAudio = false
    private(set) var isMuted = false
    /// Whether ad blocking is currently applied to this tab's content controller.
    private var shieldsApplied: Bool?
    /// Set when this blank tab closes itself after handing off a download.
    private var closingForDownload = false

    private var lastActive = Date()
    private var sleepingState: Any?
    private var sleepingURL: URL?
    var sleepingURLForExtensions: URL? { sleepingURL }
    private var upgradedHosts = Set<String>()
    private var insecureAllowed = Set<String>()

    // MARK: Opening

    @discardableResult
    static func open(url: URL?, isPrivate: Bool = false, inTabOf host: NSWindow? = nil,
                     configuration: WKWebViewConfiguration? = nil, background: Bool = false,
                     state: Any? = nil, asleep: SavedTab? = nil) -> BrowserWindowController {
        let tab = BrowserWindowController(isPrivate: isPrivate, configuration: configuration, asleep: asleep)
        all.insert(tab)
        if let host, let window = tab.window {
            host.addTabbedWindow(window, ordered: .above)
        }
        if background {
            tab.window?.orderBack(nil)
            host?.makeKeyAndOrderFront(nil)
        } else {
            tab.showWindow(nil)
        }
        if !isPrivate { ExtensionManager.shared.controller.didOpenTab(tab) }
        if asleep != nil {
            // Restored background tab: it loads only when you first switch to it.
        } else if let state, let webView = tab.webView {
            webView.interactionState = state
        } else if let url {
            tab.load(url)
        } else if configuration == nil {
            tab.showStartPage()
        }
        if !isPrivate { SessionRestore.shared.setNeedsSave() }
        return tab
    }

    /// ⇧⌘T: brings back the most recently closed tab, with its back/forward history.
    static func reopenClosedTab() {
        guard let closed = SessionRestore.shared.popClosed() else { return }
        open(url: closed.url, inTabOf: frontmost(isPrivate: false)?.window, state: closed.state)
    }

    /// Reopens saved windows. Only each window's selected tab loads now; the others sleep
    /// until you switch to them, so restoring many tabs costs almost no memory.
    static func restore(windows: [SavedWindow]) {
        for saved in windows where !saved.tabs.isEmpty {
            let selected = min(max(saved.selected, 0), saved.tabs.count - 1)
            var host: NSWindow?
            var selectedTab: BrowserWindowController?
            for (i, tab) in saved.tabs.enumerated() {
                let opened = i == selected
                    ? open(url: tab.url, inTabOf: host, background: host != nil)
                    : open(url: nil, inTabOf: host, background: host != nil, asleep: tab)
                if host == nil { host = opened.window }
                if i == selected { selectedTab = opened }
            }
            selectedTab?.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// The open normal windows and their tabs, front window first, for the saved session.
    static func sessionSnapshot() -> [SavedWindow] {
        var seen = Set<ObjectIdentifier>()
        var windows: [SavedWindow] = []
        let ordered = NSApp.orderedWindows.compactMap { $0.windowController as? BrowserWindowController }
            .filter { !$0.isPrivate && all.contains($0) }
        let rest = all.filter { !$0.isPrivate && !ordered.contains($0) }
        for tab in ordered + rest {
            guard let window = tab.window, !seen.contains(ObjectIdentifier(window)) else { continue }
            let group = window.tabbedWindows ?? [window]
            group.forEach { seen.insert(ObjectIdentifier($0)) }
            let tabs = group.compactMap { $0.windowController as? BrowserWindowController }
                .filter { all.contains($0) }
            var saved: [SavedTab] = []
            var selected = 0
            for t in tabs {
                guard let entry = t.savedTab else { continue }
                if t.window === window.tabGroup?.selectedWindow { selected = saved.count }
                saved.append(entry)
            }
            guard !saved.isEmpty else { continue }
            windows.append(SavedWindow(tabs: saved, selected: selected))
        }
        return windows
    }

    private var currentURL: URL? { webView?.url ?? sleepingURL }

    private var savedTab: SavedTab? {
        guard let url = currentURL, ["http", "https", "file"].contains(url.scheme ?? "") else { return nil }
        return SavedTab(url: url, title: baseTitle)
    }

    /// Opens a URL from outside a tab (history, menus) in the frontmost normal window.
    static func openFromApp(_ url: URL, newTab: Bool) {
        if let front = frontmost(isPrivate: false) {
            if newTab {
                open(url: url, inTabOf: front.window)
            } else {
                front.load(url)
                front.window?.makeKeyAndOrderFront(nil)
            }
        } else {
            open(url: url)
        }
    }

    /// Restores a saved session: each URL opens as a tab in the frontmost
    /// window, or in a fresh window when none is open.
    static func restore(_ session: Session) {
        var host = frontmost(isPrivate: false)?.window
        for url in session.urls {
            if host == nil {
                host = open(url: url).window
            } else {
                open(url: url, inTabOf: host, background: true)
            }
        }
        host?.makeKeyAndOrderFront(nil)
    }

    static func frontmost(isPrivate: Bool) -> BrowserWindowController? {
        let key = NSApp.keyWindow?.windowController as? BrowserWindowController
        if let key, key.isPrivate == isPrivate { return key }
        return NSApp.orderedWindows.lazy.compactMap { $0.windowController as? BrowserWindowController }
            .first { $0.isPrivate == isPrivate }
    }

    private init(isPrivate: Bool, configuration: WKWebViewConfiguration?, asleep: SavedTab? = nil) {
        self.isPrivate = isPrivate
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = isPrivate ? "feather.private" : "feather"
        window.titleVisibility = .hidden
        window.setFrameAutosaveName("FeatherWindow")
        window.minSize = NSSize(width: 480, height: 320)
        if isPrivate { window.appearance = NSAppearance(named: .darkAqua) }
        window.contentView = content
        super.init(window: window)
        window.delegate = self
        layoutContent()
        buildToolbar()
        if let asleep {
            sleepingURL = asleep.url
            setTitle(asleep.title.isEmpty ? (asleep.url.host ?? "Tab") : asleep.title)
            refreshButtons()
        } else {
            makeWebView(configuration: configuration)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func layoutContent() {
        webArea.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bookmarkBar)
        content.addSubview(findBar)
        content.addSubview(webArea)
        findBar.isHidden = true
        findBarHeight = findBar.heightAnchor.constraint(equalToConstant: 0)
        findBar.onClose = { [weak self] in self?.closeFindBar(nil) }
        NSLayoutConstraint.activate([
            bookmarkBar.topAnchor.constraint(equalTo: content.topAnchor),
            bookmarkBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bookmarkBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            findBar.topAnchor.constraint(equalTo: bookmarkBar.bottomAnchor),
            findBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            findBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            findBarHeight,
            webArea.topAnchor.constraint(equalTo: findBar.bottomAnchor),
            webArea.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webArea.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webArea.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        bookmarkBar.onOpen = { [weak self] url, newTab in
            guard let self else { return }
            if newTab {
                Self.open(url: url, isPrivate: self.isPrivate, inTabOf: self.window, background: true)
            } else {
                self.load(url)
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(refreshStar),
                                               name: Bookmarks.changed, object: nil)
    }

    // MARK: Web view

    private func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        if isPrivate {
            if Self.privateStore == nil { Self.privateStore = .nonPersistent() }
            config.websiteDataStore = Self.privateStore!
        } else {
            config.websiteDataStore = .default()
        }
        config.applicationNameForUserAgent = Settings.userAgentSuffix
        config.preferences.isFraudulentWebsiteWarningEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.preferences.isElementFullscreenEnabled = true
        // WebKit keeps Picture in Picture off for apps unless this (non-public) preference is set.
        // It must be set through KVC: `perform(_:with: NSNumber)` passes a pointer to the BOOL
        // parameter and leaves PiP off. Guarded so a future WebKit without it skips the call.
        if config.preferences.responds(to: NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")) {
            config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        }
        config.allowsAirPlayForMediaPlayback = true
        Shields.shared.apply(to: config.userContentController, addonInstalls: !isPrivate, host: nil)
        shieldsApplied = Settings.shieldsActive(for: nil)
        if !isPrivate { config.webExtensionController = ExtensionManager.shared.controller }
        return config
    }

    @discardableResult
    private func makeWebView(configuration: WKWebViewConfiguration? = nil) -> WKWebView {
        let webView = WKWebView(frame: webArea.bounds, configuration: configuration ?? makeConfiguration())
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        // The Web Inspector can read page state (including private windows), so only
        // expose it to builds run with FEATHER_DEBUG=1.
        webView.isInspectable = ProcessInfo.processInfo.environment["FEATHER_DEBUG"] != nil
        webArea.addSubview(webView)
        self.webView = webView
        findBar.webView = webView
        if configuration != nil {
            // A page-opened tab (window.open) arrives with its opener's content rules;
            // re-check them on its first navigation.
            shieldsApplied = nil
        }

        observations = [
            webView.observe(\.title) { [weak self] _, _ in MainActor.assumeIsolated { self?.refreshTitle() } },
            webView.observe(\.url) { [weak self] _, _ in MainActor.assumeIsolated { self?.refreshAddress() } },
            webView.observe(\.canGoBack) { [weak self] _, _ in MainActor.assumeIsolated { self?.refreshButtons() } },
            webView.observe(\.canGoForward) { [weak self] _, _ in MainActor.assumeIsolated { self?.refreshButtons() } },
            webView.observe(\.isLoading) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    self?.refreshButtons()
                    self?.notifyExtensions(.loading)
                }
            },
        ]
        // Sound indicator. `_isPlayingAudio` is WebKit's own (non-public, KVO-compliant) flag;
        // without it the tab simply shows no indicator.
        if webView.responds(to: NSSelectorFromString("_isPlayingAudio")) {
            audioObservation = KVOObserver(webView, keyPath: "_isPlayingAudio") { [weak self, weak webView] in
                guard let self, let webView, webView === self.webView else { return }
                self.isPlayingAudio = (webView.value(forKey: "_isPlayingAudio") as? Bool) ?? false
                self.refreshTitle()
                self.notifyExtensions(.playingAudio)
            }
        }
        if isMuted { applyMute(to: webView) }
        refreshButtons()
        return webView
    }

    func load(_ url: URL) {
        wake()
        webView?.load(URLRequest(url: url))
    }

    private func showStartPage() {
        load(Settings.homePageURL)
        setTitle(isPrivate ? "Private Tab" : "New Tab")
        DispatchQueue.main.async { [weak self] in self?.focusAddressBar(nil) }
    }

    /// Re-applies blocking after a Shields setting changes. `rulesChanged` (new blocklists)
    /// reloads the visible tab even when blocking stays on.
    func shieldsChanged(rulesChanged: Bool = false) {
        refreshButtons()
        guard let webView else { return }
        let before = shieldsApplied
        shieldsApplied = nil // force a fresh apply so a recompiled rule list is picked up
        applyShields(for: webView.url?.host)
        if before != shieldsApplied || rulesChanged, window?.isKeyWindow == true { webView.reload() }
    }

    /// Each tab has its own content controller, so blocking can follow the site you're on.
    private func applyShields(for host: String?) {
        guard let webView else { return }
        let active = Settings.shieldsActive(for: host)
        guard active != shieldsApplied else { return }
        Shields.shared.apply(to: webView.configuration.userContentController, addonInstalls: !isPrivate, host: host)
        shieldsApplied = active
        refreshButtons()
    }

    // MARK: Sleeping tabs

    func suspendIfIdle(now: Date, after limit: TimeInterval) {
        guard let webView, let window, !window.isKeyWindow,
              !window.occlusionState.contains(.visible),
              now.timeIntervalSince(lastActive) >= limit,
              webView.url != nil,
              webView.cameraCaptureState == .none, webView.microphoneCaptureState == .none else { return }
        webView.requestMediaPlaybackState { [weak self] state in
            guard state != .playing, let self, self.window?.isKeyWindow == false else { return }
            self.sleep()
        }
    }

    private func sleep() {
        guard let webView else { return }
        sleepingState = webView.interactionState
        sleepingURL = webView.url
        observations = []
        audioObservation = nil
        if isPlayingAudio { isPlayingAudio = false; refreshTitle() }
        webView.stopLoading()
        webView.removeFromSuperview()
        self.webView = nil
    }

    private func wake() {
        guard webView == nil else { return }
        let webView = makeWebView()
        if let state = sleepingState {
            webView.interactionState = state
        } else if let url = sleepingURL {
            webView.load(URLRequest(url: url))
        }
        sleepingState = nil
        sleepingURL = nil
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        lastActive = Date()
        if webView == nil {
            wake()
            window?.makeFirstResponder(webView)
        }
        if !isPrivate { SessionRestore.shared.setNeedsSave() }
        if !isPrivate {
            let controller = ExtensionManager.shared.controller
            controller.didActivateTab(self)
            controller.didFocusWindow(ExtensionWindow.for(self))
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        lastActive = Date()
    }

    func windowWillClose(_ notification: Notification) {
        debugLog("tab closed")
        suggestions.hide()
        if !isPrivate, !closingForDownload, let url = currentURL {
            SessionRestore.shared.pushClosed(ClosedTab(url: url, title: baseTitle,
                                                       state: webView?.interactionState ?? sleepingState))
        }
        observations = []
        audioObservation = nil
        webView?.stopLoading()
        Self.all.remove(self)
        if !isPrivate { SessionRestore.shared.setNeedsSave() }
        if !isPrivate { ExtensionManager.shared.controller.didCloseTab(self) }
        if isPrivate, !Self.all.contains(where: \.isPrivate) {
            Self.privateStore = nil // forget everything from the private session
        }
    }

    /// The "+" button in the tab bar and ⌘T.
    @objc override func newWindowForTab(_ sender: Any?) {
        Self.open(url: nil, isPrivate: isPrivate, inTabOf: window)
    }

    // MARK: Toolbar

    private enum Item {
        static let back = NSToolbarItem.Identifier("back")
        static let forward = NSToolbarItem.Identifier("forward")
        static let reload = NSToolbarItem.Identifier("reload")
        static let home = NSToolbarItem.Identifier("home")
        static let address = NSToolbarItem.Identifier("address")
        static let shield = NSToolbarItem.Identifier("shield")
        static let newTab = NSToolbarItem.Identifier("newTab")
        static let star = NSToolbarItem.Identifier("star")
        static let pip = NSToolbarItem.Identifier("pip")
        static let extensions = NSToolbarItem.Identifier("extensions")
        static let pins = NSToolbarItem.Identifier("pins")
        static let downloads = NSToolbarItem.Identifier("downloads")
    }

    private func buildToolbar() {
        backButton = toolbarButton("chevron.left", "Back", #selector(navigateBack(_:)))
        forwardButton = toolbarButton("chevron.right", "Forward", #selector(navigateForward(_:)))
        reloadButton = toolbarButton("arrow.clockwise", "Reload", #selector(reloadPage(_:)))
        homeButton = toolbarButton("house", "Home", #selector(goHome(_:)))
        shieldButton = toolbarButton("shield.lefthalf.filled", "Shields", #selector(showShieldsMenu(_:)))
        downloadsButton = toolbarButton("arrow.down.circle", "Downloads (⌥⌘L)", #selector(AppDelegate.showDownloads(_:)))
        downloadsButton.target = NSApp.delegate
        NotificationCenter.default.addObserver(self, selector: #selector(refreshDownloadsButton),
                                               name: Downloads.changed, object: nil)
        extensionsButton = toolbarButton("puzzlepiece.extension", "Extensions", #selector(showExtensionsMenu(_:)))
        if isPrivate {
            extensionsButton.isEnabled = false
            extensionsButton.toolTip = "Extensions don't run in private windows"
        }
        extensionPins.orientation = .horizontal
        extensionPins.spacing = 2
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildPins),
                                               name: ExtensionManager.changed, object: nil)
        rebuildPins()
        pipButton = toolbarButton("pip.enter", "Picture in Picture", #selector(togglePictureInPicture(_:)))
        starButton = toolbarButton("star", "Bookmark This Page", #selector(toggleBookmark(_:)))
        newTabButton = toolbarButton("plus", "New Tab", #selector(newWindowForTab(_:)))

        addressField.placeholderString = "Search or enter website"
        addressField.bezelStyle = .roundedBezel
        addressField.lineBreakMode = .byTruncatingTail
        addressField.usesSingleLineMode = true
        addressField.cell?.isScrollable = true
        addressField.target = self
        addressField.action = #selector(addressEntered(_:))
        addressField.delegate = self
        suggestions.onChoose = { [weak self] suggestion in self?.choose(suggestion) }

        let toolbar = NSToolbar(identifier: "FeatherToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
    }

    private func toolbarButton(_ symbol: String, _ label: String, _ action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)!
        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.toolTip = label
        return button
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Item.back, Item.forward, Item.reload, Item.home, .flexibleSpace, Item.address, Item.star, Item.newTab, .flexibleSpace, Item.downloads, Item.pins, Item.pip, Item.extensions, Item.shield]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        switch id {
        case Item.back: item.view = backButton; item.label = "Back"
        case Item.forward: item.view = forwardButton; item.label = "Forward"
        case Item.reload: item.view = reloadButton; item.label = "Reload"
        case Item.home: item.view = homeButton; item.label = "Home"
        case Item.shield: item.view = shieldButton; item.label = "Shields"
        case Item.pins: item.view = extensionPins; item.label = "Pinned Extensions"
        case Item.extensions: item.view = extensionsButton; item.label = "Extensions"
        case Item.pip: item.view = pipButton; item.label = "Picture in Picture"
        case Item.star: item.view = starButton; item.label = "Bookmark"
        case Item.newTab: item.view = newTabButton; item.label = "New Tab"
        case Item.downloads:
            item.view = downloadsButton
            item.label = "Downloads"
            item.isHidden = !Self.showsDownloadsButton
        case Item.address:
            item.view = addressField
            item.label = "Address"
            item.visibilityPriority = .high
            // Centered and capped, shrinking with the window down to a compact minimum.
            addressField.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
            addressField.widthAnchor.constraint(lessThanOrEqualToConstant: 560).isActive = true
            let preferred = addressField.widthAnchor.constraint(equalToConstant: 560)
            preferred.priority = .defaultLow
            preferred.isActive = true
        default: return nil
        }
        return item
    }

    private func refreshTitle() {
        if let webView {
            let title = webView.title ?? ""
            setTitle(title.isEmpty ? (webView.url?.host ?? "New Tab") : title)
            if !isPrivate { History.shared.updateTitle(title, for: webView.url) }
        } else {
            setTitle(baseTitle)
        }
        notifyExtensions(.title)
    }

    /// Sets the tab's title, with 🔇 when muted or 🔊 while it plays sound.
    private func setTitle(_ title: String) {
        baseTitle = title
        let prefix = isMuted ? "🔇 " : (isPlayingAudio ? "🔊 " : "")
        window?.title = prefix + title
    }

    private func notifyExtensions(_ properties: WKWebExtension.TabChangedProperties) {
        guard !isPrivate, Self.all.contains(self) else { return }
        ExtensionManager.shared.controller.didChangeTabProperties(properties, for: self)
    }

    private func refreshAddress() {
        if !isPrivate, let url = webView?.url {
            History.shared.visit(url, title: webView?.title)
            SessionRestore.shared.setNeedsSave()
        }
        notifyExtensions(.URL)
        refreshButtons()
        guard window?.firstResponder != addressField.currentEditor() else { return }
        refreshAddressField()
        refreshStar()
    }

    @objc private func refreshStar() {
        let saved = Bookmarks.shared.contains(webView?.url)
        starButton.image = NSImage(systemSymbolName: saved ? "star.fill" : "star",
                                   accessibilityDescription: saved ? "Remove Bookmark" : "Bookmark This Page")
        starButton.contentTintColor = saved ? .systemYellow : nil
        starButton.toolTip = saved ? "Remove bookmark (⌘D)" : "Bookmark this page (⌘D)"
        starButton.isEnabled = webView?.url.map { $0.scheme == "http" || $0.scheme == "https" } ?? false
    }

    /// ☆ button and ⌘D: bookmark the page, or remove it if already bookmarked.
    @objc func toggleBookmark(_ sender: Any?) {
        guard let url = webView?.url, url.scheme == "http" || url.scheme == "https" else { return }
        if Bookmarks.shared.contains(url) {
            Bookmarks.shared.remove(url)
        } else {
            Bookmarks.shared.add(title: webView?.title ?? "", url: url)
        }
    }

    private func refreshButtons() {
        backButton.isEnabled = webView?.canGoBack ?? false
        forwardButton.isEnabled = webView?.canGoForward ?? false
        let loading = webView?.isLoading ?? false
        reloadButton.image = NSImage(systemSymbolName: loading ? "xmark" : "arrow.clockwise",
                                     accessibilityDescription: loading ? "Stop" : "Reload")
        let host = webView?.url?.host
        let active = Settings.shieldsActive(for: host)
        shieldButton.image = NSImage(systemSymbolName: active ? "shield.lefthalf.filled" : "shield.slash",
                                     accessibilityDescription: "Shields")
        shieldButton.contentTintColor = active ? .controlAccentColor : .secondaryLabelColor
        shieldButton.toolTip = !Settings.shieldsEnabled ? "Shields down everywhere"
            : active ? "Shields up: blocking ads & trackers" : "Shields down for \(host ?? "this site")"
    }

    // MARK: Downloads button

    /// Shown while anything downloads, and afterwards until the list is cleared.
    private static var showsDownloadsButton: Bool { !Downloads.shared.items.isEmpty && downloadsSeenThisRun }
    private static var downloadsSeenThisRun = false

    @objc private func refreshDownloadsButton() {
        if Downloads.shared.hasActive { Self.downloadsSeenThisRun = true }
        let show = Self.showsDownloadsButton
        downloadsButton.contentTintColor = Downloads.shared.hasActive ? .controlAccentColor : nil
        if let item = window?.toolbar?.items.first(where: { $0.itemIdentifier == Item.downloads }), item.isHidden == show {
            item.isHidden = !show
        }
    }

    // MARK: Actions

    @objc private func addressEntered(_ sender: NSTextField) {
        // Return in the address field: a highlighted suggestion wins over the typed text.
        if let chosen = suggestions.selected { return choose(chosen) }
        suggestions.hide()
        guard let url = URLTools.resolve(sender.stringValue) else { return }
        load(url)
        window?.makeFirstResponder(webView)
    }

    private func choose(_ suggestion: Suggestion) {
        suggestions.hide()
        addressField.stringValue = suggestion.url.absoluteString
        load(suggestion.url)
        window?.makeFirstResponder(webView)
    }

    // MARK: Address bar suggestions (NSTextFieldDelegate)

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === addressField else { return }
        suggestions.update(query: addressField.stringValue, below: addressField, allowRemote: !isPrivate)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === addressField else { return }
        suggestions.hide()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === addressField else { return false }
        switch selector {
        case #selector(NSResponder.moveDown(_:)): return suggestions.moveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)): return suggestions.moveSelection(by: -1)
        case #selector(NSResponder.cancelOperation(_:)):
            if suggestions.isVisible { suggestions.hide(); return true }
            // A second Esc puts back the page's address.
            refreshAddressField()
            return true
        default: return false
        }
    }

    private func refreshAddressField() {
        let url = webView?.url ?? sleepingURL
        addressField.stringValue = (url?.scheme == "about" || url == nil) ? "" : url!.absoluteString
    }

    // MARK: Find in page

    @objc func showFindBar(_ sender: Any?) {
        wake()
        findBar.webView = webView
        if findBar.isHidden {
            findBar.isHidden = false
            findBarHeight.constant = 32
        }
        findBar.activate()
    }

    @objc func findNextMatch(_ sender: Any?) {
        if findBar.isHidden { showFindBar(sender) } else { findBar.find(backwards: false) }
    }

    @objc func findPreviousMatch(_ sender: Any?) {
        if findBar.isHidden { showFindBar(sender) } else { findBar.find(backwards: true) }
    }

    @objc func closeFindBar(_ sender: Any?) {
        guard !findBar.isHidden else { return }
        findBar.isHidden = true
        findBarHeight.constant = 0
        window?.makeFirstResponder(webView)
        // Clears WebKit's match highlights.
        webView?.evaluateJavaScript("window.getSelection().removeAllRanges()")
    }

    // MARK: Sound

    /// View ▸ Mute Tab (⌃⌘M).
    @objc func toggleMute(_ sender: Any?) {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        if let webView { applyMute(to: webView) }
        refreshTitle()
        notifyExtensions(.muted)
    }

    /// Mutes every sound from the page using WebKit's own (non-public) page mute when available,
    /// otherwise by muting the page's audio and video elements.
    private func applyMute(to webView: WKWebView) {
        let selector = NSSelectorFromString("_setPageMuted:")
        if webView.responds(to: selector) {
            typealias SetMuted = @convention(c) (AnyObject, Selector, UInt) -> Void
            let call = unsafeBitCast(webView.method(for: selector), to: SetMuted.self)
            call(webView, selector, isMuted ? 1 : 0) // 1 = _WKMediaAudioMuted
        } else {
            webView.evaluateJavaScript("document.querySelectorAll('audio,video').forEach(m => m.muted = \(isMuted))")
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleMute(_:)):
            item.title = isMuted ? "Unmute Tab" : "Mute Tab"
            return webView != nil || sleepingURL != nil
        case #selector(findNextMatch(_:)), #selector(findPreviousMatch(_:)):
            return !FindBar.lastQuery.isEmpty || !findBar.isHidden
        case #selector(closeFindBar(_:)):
            return !findBar.isHidden
        default:
            return true
        }
    }

    // MARK: Shields menu

    @objc private func showShieldsMenu(_ sender: NSButton) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let rawHost = webView?.url?.host
        let host = rawHost.map(Shields.exceptionHost)
        let isWeb = webView?.url.map { $0.scheme == "http" || $0.scheme == "https" } ?? false

        let header = NSMenuItem(title: host.map { "Shields for \($0)" } ?? "Shields", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let site = NSMenuItem(title: "Block Ads & Trackers on This Site", action: #selector(toggleSiteShields(_:)), keyEquivalent: "")
        site.target = self
        site.state = Settings.shieldsActive(for: rawHost) ? .on : .off
        site.isEnabled = Settings.shieldsEnabled && isWeb && host != nil
        menu.addItem(site)
        if Settings.shieldsEnabled, !Settings.shieldsActive(for: rawHost) {
            let note = NSMenuItem(title: "Turned off for this site", action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
        }
        menu.addItem(.separator())
        let global = NSMenuItem(title: "Block Ads & Trackers Everywhere", action: #selector(AppDelegate.toggleShields(_:)), keyEquivalent: "")
        global.target = NSApp.delegate
        global.state = Settings.shieldsEnabled ? .on : .off
        menu.addItem(global)
        let manage = NSMenuItem(title: "Manage Site Exceptions…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: "")
        manage.target = NSApp.delegate
        menu.addItem(manage)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    /// Turns Shields off (or back on) for the current site, then reloads so the change shows.
    @objc private func toggleSiteShields(_ sender: Any?) {
        guard let rawHost = webView?.url?.host else { return }
        let host = Shields.exceptionHost(for: rawHost)
        var list = Settings.shieldsAllowlist
        if Settings.shieldsActive(for: rawHost) {
            list.append(host)
        } else {
            // Remove every entry covering this host (it may have been added as a parent domain).
            list.removeAll { Shields.isAllowlisted(host: rawHost, in: [$0]) }
        }
        Settings.shieldsAllowlist = list
        NotificationCenter.default.post(name: Settings.changed, object: nil)
        for tab in Self.all where tab !== self { tab.shieldsChanged() }
        applyShields(for: rawHost)
        webView?.reload()
    }

    @objc func focusAddressBar(_ sender: Any?) {
        window?.makeFirstResponder(addressField)
        addressField.currentEditor()?.selectAll(nil)
    }

    /// Pinned extensions sit just left of the PiP button. Rebuilt whenever the
    /// extension list or an action (badge/icon) changes.
    @objc private func rebuildPins() {
        // ExtensionManager.changed can fire from a background Task; AppKit needs the main thread.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.rebuildPins() }
            return
        }
        let oldCount = extensionPins.arrangedSubviews.count
        extensionPins.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !isPrivate else { return }
        let manager = ExtensionManager.shared
        for record in manager.installed where record.enabled && record.pinned {
            guard let context = manager.contexts[record.id] else { continue }
            extensionPins.addArrangedSubview(ExtensionPinButton(id: record.id, name: record.name, context: context, tab: self))
        }
        // NSToolbarItem snapshots its custom view's size at insertion, so when the
        // button count changes the item must be re-created to pick up the new size.
        if extensionPins.arrangedSubviews.count != oldCount {
            refreshPinsItem()
        }
    }

    /// Re-inserts the pins toolbar item so it re-measures the (possibly resized) button stack.
    private func refreshPinsItem() {
        guard let toolbar = window?.toolbar,
              let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == Item.pins }) else { return }
        toolbar.removeItem(at: index)
        extensionPins.removeFromSuperview() // detach from the removed item before re-inserting
        toolbar.insertItem(withItemIdentifier: Item.pins, at: index)
    }

    @objc private func showExtensionsMenu(_ sender: NSButton) {
        ExtensionManager.shared.popupAnchor = sender
        let menu = ExtensionMenu.shared.build(for: self)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    /// Pops the page's video into a floating window (or brings it back). Works on any site,
    /// including YouTube, whose own player hides the browser's built-in PiP option, and videos
    /// inside embedded players from other sites (church streams, Vimeo, YouTube embeds).
    @objc func togglePictureInPicture(_ sender: Any?) {
        guard let webView else { return }
        allFrames(of: webView) { [weak self] frames in
            self?.togglePictureInPicture(in: frames)
        }
    }

    private func togglePictureInPicture(in frames: [WKFrameInfo?]) {
        guard let webView else { return }
        // Ask every frame what it has, then act in the one frame that matters.
        var probes: [(frame: WKFrameInfo?, active: Bool, score: Double)] = []
        let group = DispatchGroup()
        for frame in frames {
            group.enter()
            webView.callAsyncJavaScript(Self.pipProbeScript, arguments: [:], in: frame, in: .page) { result in
                if case .success(let value as String) = result,
                   let data = value.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    probes.append((frame, json["active"] as? Bool ?? false, json["score"] as? Double ?? 0))
                } else if case .failure(let error) = result {
                    debugLog("pip probe failed: \(error)")
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let target = probes.first(where: \.active) ?? probes.filter { $0.score > 0 }.max { $0.score < $1.score }
            guard let target else {
                return self.showNotice("No video found on this page",
                                       "Start the video playing, then try Picture in Picture again.")
            }
            webView.callAsyncJavaScript(Self.pipScript, arguments: [:], in: target.frame, in: .page) { [weak self] result in
                switch result {
                case .success(let value as String) where value == "none":
                    self?.showNotice("No video found on this page", "Start the video playing, then try again.")
                case .success(let value as String) where value.hasPrefix("error:"):
                    self?.showNotice("This video can't play in Picture in Picture", String(value.dropFirst(6)))
                case .success(let value as String) where value == "entered":
                    self?.confirmPictureInPicture(in: target.frame)
                case .failure(let error):
                    self?.showNotice("Picture in Picture didn't start", error.localizedDescription)
                default:
                    break
                }
            }
        }
    }

    /// The page can report success while macOS never shows the floating window; say so instead
    /// of failing silently.
    private func confirmPictureInPicture(in frame: WKFrameInfo?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let webView = self?.webView else { return }
            webView.callAsyncJavaScript(Self.pipProbeScript, arguments: [:], in: frame, in: .page) { [weak self] result in
                guard case .success(let value as String) = result, !value.contains("\"active\":true") else { return }
                self?.showNotice("Picture in Picture didn't start",
                                 "macOS didn't open the floating window for this video. Try pausing and playing it, then try again.")
            }
        }
    }

    /// The main frame plus every embedded frame, so videos in iframes can be reached.
    /// Uses WebKit's private frame tree; falls back to just the main frame.
    private func allFrames(of webView: WKWebView, _ completion: @escaping ([WKFrameInfo?]) -> Void) {
        let selector = NSSelectorFromString("_frames:")
        guard webView.responds(to: selector) else { return completion([nil]) }
        typealias Frames = @convention(c) (AnyObject, Selector, @escaping @convention(block) (NSObject?) -> Void) -> Void
        let call = unsafeBitCast(webView.method(for: selector), to: Frames.self)
        call(webView, selector) { root in
            var frames: [WKFrameInfo?] = []
            func collect(_ node: NSObject) {
                if let info = node.value(forKey: "info") as? WKFrameInfo { frames.append(info) }
                for child in (node.value(forKey: "childFrames") as? [NSObject]) ?? [] { collect(child) }
            }
            if let root { collect(root) }
            DispatchQueue.main.async { completion(frames.isEmpty ? [nil] : frames) }
        }
    }

    private func showNotice(_ title: String, _ detail: String) {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.beginSheetModal(for: window)
    }

    /// Reports whether this frame has a video in PiP, and how good its best candidate is
    /// (playing beats paused, bigger beats smaller).
    private static let pipProbeScript = """
        const videos = [...document.querySelectorAll('video')];
        const active = !!document.pictureInPictureElement
            || videos.some(v => v.webkitPresentationMode === 'picture-in-picture');
        let score = 0;
        for (const v of videos) {
            if (v.readyState === 0 || v.offsetWidth === 0 || v.offsetHeight === 0) continue;
            score = Math.max(score, v.offsetWidth * v.offsetHeight + (v.paused ? 0 : 1e9));
        }
        return JSON.stringify({active, score});
        """

    private static let pipScript = """
        const active = document.pictureInPictureElement
            || [...document.querySelectorAll('video')].find(v => v.webkitPresentationMode === 'picture-in-picture');
        if (active) {
            if (document.pictureInPictureElement) await document.exitPictureInPicture();
            else active.webkitSetPresentationMode('inline');
            return 'exited';
        }
        // Candidate videos: must have data and be visible.
        let videos = [...document.querySelectorAll('video')]
            .filter(v => v.readyState > 0 && v.offsetWidth > 0 && v.offsetHeight > 0);
        // On YouTube, prefer the main player video over ads/previews.
        const ytVideo = document.querySelector('#movie_player video, .html5-main-video');
        if (ytVideo && videos.includes(ytVideo)) {
            videos = [ytVideo, ...videos.filter(v => v !== ytVideo)];
        }
        const area = v => v.offsetWidth * v.offsetHeight;
        const video = videos.find(v => !v.paused)
            || videos.sort((a, b) => area(b) - area(a))[0];
        if (!video) return 'none';
        // YouTube disables PiP on its video element; clear both the property and the attribute.
        video.disablePictureInPicture = false;
        video.removeAttribute('disablepictureinpicture');
        let lastError = '';
        if (typeof video.requestPictureInPicture === 'function') {
            try {
                await video.requestPictureInPicture();
                return 'entered';
            } catch (e) { lastError = e.message || String(e); }
        } else {
            lastError = 'requestPictureInPicture not available';
        }
        try {
            if (video.webkitSupportsPresentationMode
                && video.webkitSupportsPresentationMode('picture-in-picture')) {
                video.webkitSetPresentationMode('picture-in-picture');
                return 'entered';
            }
            lastError += ' | webkit PiP not supported';
        } catch (e) { lastError += ' | ' + (e.message || e); }
        return 'error:' + lastError;
        """

    @objc func navigateBack(_ sender: Any?) { webView?.goBack() }
    @objc func navigateForward(_ sender: Any?) { webView?.goForward() }

    @objc func reloadPage(_ sender: Any?) {
        guard let webView else { return }
        if webView.isLoading { webView.stopLoading() } else { webView.reload() }
    }

    /// The Home toolbar button: loads the home page (the search engine's homepage).
    @objc func goHome(_ sender: Any?) {
        load(Settings.homePageURL)
    }

    @objc func zoomIn(_ sender: Any?) { webView?.pageZoom = min((webView?.pageZoom ?? 1) + 0.1, 3) }
    @objc func zoomOut(_ sender: Any?) { webView?.pageZoom = max((webView?.pageZoom ?? 1) - 0.1, 0.3) }
    @objc func zoomReset(_ sender: Any?) { webView?.pageZoom = 1 }

    @objc func printPage(_ sender: Any?) {
        guard let webView, let window else { return }
        webView.printOperation(with: .shared).runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.allow) }

        if action.shouldPerformDownload { return decisionHandler(.download) }

        // Firefox add-on files open the install prompt instead of downloading.
        if url.pathExtension.lowercased() == "xpi", !isPrivate {
            let window = self.window
            Task { await ExtensionManager.shared.install(fromWeb: url, window: window) }
            return decisionHandler(.cancel)
        }
        // Extension pages (settings, popups opened as tabs) load inside WebKit.
        if ExtensionManager.shared.controller.extensionContext(for: url) != nil {
            return decisionHandler(.allow)
        }

        // ⌘-click or middle-click opens a new tab.
        if action.navigationType == .linkActivated,
           action.modifierFlags.contains(.command) || action.buttonNumber == 2 {
            Self.open(url: url, isPrivate: isPrivate, inTabOf: window,
                      background: !action.modifierFlags.contains(.shift))
            return decisionHandler(.cancel)
        }

        // `javascript:` must never be honoured as a navigation: a page that manages to
        // steer one here could otherwise run script outside its own origin.
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "javascript" { return decisionHandler(.cancel) }

        // Hand mailto:, facetime:, app links etc. to the system, but only for a real
        // user click so a page can't silently launch other apps.
        if !["http", "https", "about", "file", "data", "blob"].contains(scheme) {
            if action.navigationType == .linkActivated { NSWorkspace.shared.open(url) }
            return decisionHandler(.cancel)
        }

        if action.targetFrame?.isMainFrame == true {
            if action.request.httpMethod == "GET", let clean = URLTools.stripTracking(url) {
                decisionHandler(.cancel)
                webView.load(URLRequest(url: clean))
                return
            }
            if Settings.httpsOnly, let host = url.host?.lowercased(), !insecureAllowed.contains(host),
               let secure = URLTools.httpsUpgrade(url) {
                upgradedHosts.insert(host)
                decisionHandler(.cancel)
                webView.load(URLRequest(url: secure))
                return
            }
            // Per-site Shields: switch blocking on or off before the new page starts loading.
            applyShields(for: url.host)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        // Add-on files served without a .xpi name still go to the installer.
        if response.isForMainFrame, !isPrivate, response.response.mimeType == "application/x-xpinstall",
           let url = response.response.url {
            let window = self.window
            Task { await ExtensionManager.shared.install(fromWeb: url, window: window) }
            return decisionHandler(.cancel)
        }
        let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        if !response.canShowMIMEType || (response.isForMainFrame && disposition.lowercased().hasPrefix("attachment")) {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        startedDownload(download, in: webView)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        startedDownload(download, in: webView)
    }

    /// Tracks the download, and closes this tab if it was opened only for the download (a
    /// target=_blank link to a file) and never showed a page, as Safari and Chrome do.
    private func startedDownload(_ download: WKDownload, in webView: WKWebView) {
        Downloads.shared.track(download, isPrivate: isPrivate)
        guard webView.backForwardList.currentItem == nil, sleepingURL == nil,
              let window, window.tabbedWindows?.count ?? 1 > 1 else { return }
        closingForDownload = true
        DispatchQueue.main.async { window.close() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return } // interrupted by policy change

        // An HTTPS upgrade failed: offer to continue insecurely, once per host.
        if let failed = ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL, failed.scheme == "https",
           let host = failed.host?.lowercased(), upgradedHosts.contains(host), let window {
            let alert = NSAlert()
            alert.messageText = "\(host) doesn't support a secure connection"
            alert.informativeText = "Anyone on your network could see or change this page. Continue anyway?"
            alert.addButton(withTitle: "Go Back")
            alert.addButton(withTitle: "Continue to HTTP Site")
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertSecondButtonReturn, let self,
                      var comps = URLComponents(url: failed, resolvingAgainstBaseURL: false) else { return }
                comps.scheme = "http"
                self.insecureAllowed.insert(host)
                if let url = comps.url { self.load(url) }
            }
            return
        }
        showError(ns)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return }
        showError(ns)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        debugLog("loaded \(webView.url?.absoluteString ?? "-") \"\(webView.title ?? "")\"")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload() // a crashed or memory-killed page recovers on its own
    }

    private func showError(_ error: NSError) {
        debugLog("error \(error)")
        let message = error.localizedDescription
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        webView?.loadHTMLString(Self.page(title: "Can't open this page", body: message),
                                baseURL: nil)
    }

    // MARK: WKUIDelegate

    /// target=_blank links and window.open (only allowed on a real click).
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        Self.open(url: nil, isPrivate: isPrivate, inTabOf: window, configuration: configuration).webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        window?.close()
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        let alert = makeAlert(frame, message)
        alert.addButton(withTitle: "OK")
        present(alert) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        let alert = makeAlert(frame, message)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) {
        let alert = makeAlert(frame, prompt)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        guard let window else { return completionHandler(nil) }
        panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) }
    }

    private func makeAlert(_ frame: WKFrameInfo, _ message: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "\(frame.securityOrigin.host) says:"
        alert.informativeText = message
        return alert
    }

    private func present(_ alert: NSAlert, _ done: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window { alert.beginSheetModal(for: window, completionHandler: done) } else { done(alert.runModal()) }
    }

    // MARK: Built-in pages

    private static func page(title: String, body: String) -> String {
        """
        <!doctype html><meta charset="utf-8"><title>\(title)</title>
        <meta name="color-scheme" content="light dark">
        <style>
          body{font:15px -apple-system,system-ui;display:grid;place-items:center;height:90vh;margin:0;color:#666}
          h1{font-weight:600;font-size:28px;color:CanvasText;margin:0 0 8px} div{text-align:center;max-width:520px;padding:16px}
        </style>
        <div><h1>\(title)</h1><p>\(body)</p></div>
        """
    }
}

/// Set FEATHER_DEBUG=1 to log page loads and errors to stderr.
func debugLog(_ message: @autoclosure () -> String) {
    if ProcessInfo.processInfo.environment["FEATHER_DEBUG"] != nil { NSLog("Feather: %@", message()) }
}

// MARK: - Tabs as seen by extensions

extension BrowserWindowController {
    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { ExtensionWindow.for(self) }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        window?.tabGroup?.windows.firstIndex(of: window!) ?? 0
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? { webView }
    func title(for context: WKWebExtensionContext) -> String? { webView?.title ?? window?.title }
    func url(for context: WKWebExtensionContext) -> URL? { webView?.url ?? sleepingURLForExtensions }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !(webView?.isLoading ?? false) }
    func isSelected(for context: WKWebExtensionContext) -> Bool { window?.isKeyWindow ?? false }
    func zoomFactor(for context: WKWebExtensionContext) -> Double { Double(webView?.pageZoom ?? 1) }
    func isPlayingAudio(for context: WKWebExtensionContext) -> Bool { isPlayingAudio }
    func isMuted(for context: WKWebExtensionContext) -> Bool { isMuted }

    func setMuted(_ muted: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        setMuted(muted)
        completionHandler(nil)
    }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        window?.makeKeyAndOrderFront(nil)
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        window?.close()
        completionHandler(nil)
    }

    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        load(url)
        completionHandler(nil)
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if fromOrigin { webView?.reloadFromOrigin() } else { webView?.reload() }
        completionHandler(nil)
    }

    func goBack(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        webView?.goBack()
        completionHandler(nil)
    }

    func goForward(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        webView?.goForward()
        completionHandler(nil)
    }

    func setZoomFactor(_ zoomFactor: Double, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        webView?.pageZoom = zoomFactor
        completionHandler(nil)
    }
}

/// Observes a key path by name, for WebKit properties that have no Swift key path.
final class KVOObserver: NSObject {
    private let object: NSObject
    private let keyPath: String
    private let onChange: () -> Void

    init(_ object: NSObject, keyPath: String, onChange: @escaping () -> Void) {
        self.object = object
        self.keyPath = keyPath
        self.onChange = onChange
        super.init()
        object.addObserver(self, forKeyPath: keyPath, options: [.new], context: nil)
    }

    deinit { object.removeObserver(self, forKeyPath: keyPath) }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if Thread.isMainThread { onChange() } else { DispatchQueue.main.async(execute: onChange) }
    }
}
