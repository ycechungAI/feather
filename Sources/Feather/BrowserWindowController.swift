import AppKit
import WebKit

/// One browser tab. Tabs are native macOS window tabs, so the tab bar, drag-to-detach and
/// Mission Control all come free from the OS with no extra code or memory.
final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
                                     WKNavigationDelegate, WKUIDelegate, WKWebExtensionTab {
    static private(set) var all = Set<BrowserWindowController>()
    private static var privateStore: WKWebsiteDataStore?

    let isPrivate: Bool
    private(set) var webView: WKWebView?
    private let content = NSView()
    private let webArea = NSView()
    private let bookmarkBar = BookmarkBar()
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
    private let extensionPins = NSStackView()
    private var observations: [NSKeyValueObservation] = []

    private var lastActive = Date()
    private var sleepingState: Any?
    private var sleepingURL: URL?
    var sleepingURLForExtensions: URL? { sleepingURL }
    private var upgradedHosts = Set<String>()
    private var insecureAllowed = Set<String>()

    // MARK: Opening

    @discardableResult
    static func open(url: URL?, isPrivate: Bool = false, inTabOf host: NSWindow? = nil,
                     configuration: WKWebViewConfiguration? = nil, background: Bool = false) -> BrowserWindowController {
        let tab = BrowserWindowController(isPrivate: isPrivate, configuration: configuration)
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
        if let url {
            tab.load(url)
        } else if configuration == nil {
            tab.showStartPage()
        }
        return tab
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

    private init(isPrivate: Bool, configuration: WKWebViewConfiguration?) {
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
        makeWebView(configuration: configuration)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func layoutContent() {
        webArea.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bookmarkBar)
        content.addSubview(webArea)
        NSLayoutConstraint.activate([
            bookmarkBar.topAnchor.constraint(equalTo: content.topAnchor),
            bookmarkBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bookmarkBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webArea.topAnchor.constraint(equalTo: bookmarkBar.bottomAnchor),
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
        // Guarded so a future WebKit without it simply skips the call.
        if config.preferences.responds(to: NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")) {
            config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        }
        config.allowsAirPlayForMediaPlayback = true
        Shields.shared.apply(to: config.userContentController, addonInstalls: !isPrivate)
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
        webView.isInspectable = true
        webArea.addSubview(webView)
        self.webView = webView

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
        refreshButtons()
        return webView
    }

    func load(_ url: URL) {
        wake()
        webView?.load(URLRequest(url: url))
    }

    private func showStartPage() {
        load(Settings.homePageURL)
        window?.title = isPrivate ? "Private Tab" : "New Tab"
        DispatchQueue.main.async { [weak self] in self?.focusAddressBar(nil) }
    }

    func shieldsChanged() {
        refreshButtons()
        guard let webView else { return }
        Shields.shared.apply(to: webView.configuration.userContentController, addonInstalls: !isPrivate)
        if window?.isKeyWindow == true { webView.reload() }
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
        observations = []
        webView?.stopLoading()
        Self.all.remove(self)
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
    }

    private func buildToolbar() {
        backButton = toolbarButton("chevron.left", "Back", #selector(navigateBack(_:)))
        forwardButton = toolbarButton("chevron.right", "Forward", #selector(navigateForward(_:)))
        reloadButton = toolbarButton("arrow.clockwise", "Reload", #selector(reloadPage(_:)))
        homeButton = toolbarButton("house", "Home", #selector(goHome(_:)))
        shieldButton = toolbarButton("shield.lefthalf.filled", "Shields", #selector(AppDelegate.toggleShields(_:)))
        shieldButton.target = NSApp.delegate
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
        [Item.back, Item.forward, Item.reload, Item.home, .flexibleSpace, Item.address, Item.star, Item.newTab, .flexibleSpace, Item.pins, Item.pip, Item.extensions, Item.shield]
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
        let title = webView?.title ?? ""
        window?.title = title.isEmpty ? (webView?.url?.host ?? "New Tab") : title
        if !isPrivate { History.shared.updateTitle(title, for: webView?.url) }
        notifyExtensions(.title)
    }

    private func notifyExtensions(_ properties: WKWebExtension.TabChangedProperties) {
        guard !isPrivate, Self.all.contains(self) else { return }
        ExtensionManager.shared.controller.didChangeTabProperties(properties, for: self)
    }

    private func refreshAddress() {
        if !isPrivate, let url = webView?.url { History.shared.visit(url, title: webView?.title) }
        notifyExtensions(.URL)
        guard window?.firstResponder != addressField.currentEditor() else { return }
        let url = webView?.url
        addressField.stringValue = (url?.scheme == "about" || url == nil) ? "" : url!.absoluteString
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
        shieldButton.image = NSImage(systemSymbolName: Settings.shieldsEnabled ? "shield.lefthalf.filled" : "shield.slash",
                                     accessibilityDescription: "Shields")
        shieldButton.contentTintColor = Settings.shieldsEnabled ? .controlAccentColor : .secondaryLabelColor
        shieldButton.toolTip = Settings.shieldsEnabled ? "Shields up: blocking ads & trackers" : "Shields down"
    }

    // MARK: Actions

    @objc private func addressEntered(_ sender: NSTextField) {
        guard let url = URLTools.resolve(sender.stringValue) else { return }
        load(url)
        window?.makeFirstResponder(webView)
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
    /// including YouTube, whose own player hides the browser's built-in PiP option.
    @objc func togglePictureInPicture(_ sender: Any?) {
        guard let webView else { return }
        webView.callAsyncJavaScript(Self.pipScript, arguments: [:], in: nil, in: .page) { [weak self] result in
            switch result {
            case .success(let value as String) where value == "none":
                self?.showNotice("No video found on this page",
                                 "Videos inside embedded players from other sites can be popped out from that site directly.")
            case .success(let value as String) where value.hasPrefix("error:"):
                self?.showNotice("This video can't play in Picture in Picture", String(value.dropFirst(6)))
            case .failure(let error):
                debugLog("pip failed: \(error)")
            default:
                break
            }
        }
    }

    private func showNotice(_ title: String, _ detail: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.beginSheetModal(for: window)
    }

    private static let pipScript = """
        const active = document.pictureInPictureElement
            || [...document.querySelectorAll('video')].find(v => v.webkitPresentationMode === 'picture-in-picture');
        if (active) {
            if (document.pictureInPictureElement) await document.exitPictureInPicture();
            else active.webkitSetPresentationMode('inline');
            return 'exited';
        }
        const videos = [...document.querySelectorAll('video')].filter(v => v.readyState > 0);
        const area = v => v.offsetWidth * v.offsetHeight;
        const video = videos.find(v => !v.paused && area(v) > 0)
            || videos.sort((a, b) => area(b) - area(a))[0];
        if (!video) return 'none';
        video.disablePictureInPicture = false;
        try {
            await video.requestPictureInPicture();
        } catch (e) {
            if (!video.webkitSupportsPresentationMode?.('picture-in-picture')) return 'error:' + e.message;
            video.webkitSetPresentationMode('picture-in-picture');
        }
        return 'entered';
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

        // Hand mailto:, facetime:, app links etc. to the system.
        let scheme = url.scheme?.lowercased() ?? ""
        if !["http", "https", "about", "file", "data", "blob", "javascript"].contains(scheme) {
            NSWorkspace.shared.open(url)
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
        download.delegate = Downloads.shared
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = Downloads.shared
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
