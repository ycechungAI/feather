import AppKit
import WebKit

struct InstalledExtension: Codable {
    var id: String
    var file: String
    var name: String
    var enabled: Bool
    /// Shown as its own button on the toolbar.
    var pinned = true
    /// Optional permissions the user granted later, when the extension asked.
    var extraPermissions: [String] = []
    var extraPatterns: [String] = []

    init(id: String, file: String, name: String, enabled: Bool) {
        (self.id, self.file, self.name, self.enabled) = (id, file, name, enabled)
    }

    /// Tolerates lists saved by older versions that lack newer fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        file = try c.decode(String.self, forKey: .file)
        name = try c.decode(String.self, forKey: .name)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? true
        extraPermissions = try c.decodeIfPresent([String].self, forKey: .extraPermissions) ?? []
        extraPatterns = try c.decodeIfPresent([String].self, forKey: .extraPatterns) ?? []
    }
}

/// Runs Firefox add-ons (WebExtensions) through WebKit's built-in extension engine.
/// A Firefox .xpi is a ZIP that WebKit loads directly, so nothing is unpacked or executed outside WebKit.
/// Extensions never run in private windows.
final class ExtensionManager: NSObject, WKWebExtensionControllerDelegate {
    static let shared = ExtensionManager()
    static let changed = Notification.Name("FeatherExtensionsChanged")

    let controller = WKWebExtensionController(configuration: .default())
    private(set) var installed: [InstalledExtension] = []
    private(set) var contexts: [String: WKWebExtensionContext] = [:]
    /// The toolbar button a popup should hang from.
    weak var popupAnchor: NSView?

    private let folder = Settings.supportDirectory.appendingPathComponent("Extensions", isDirectory: true)
    private var listFile: URL { folder.appendingPathComponent("extensions.json") }

    private override init() {
        super.init()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: listFile),
           let saved = try? JSONDecoder().decode([InstalledExtension].self, from: data) {
            installed = saved
        }
        controller.delegate = self
    }

    func loadAll() {
        for record in installed where record.enabled {
            Task { await activate(record) }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(installed) { try? data.write(to: listFile, options: .atomic) }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    /// A stored extension file must be a single filename inside our Extensions folder;
    /// never let a tampered list point outside the sandbox.
    private static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
            && name == (name as NSString).lastPathComponent
    }

    private func activate(_ record: InstalledExtension) async {
        guard Self.isSafeFileName(record.file) else {
            NSLog("Feather: ignoring extension with unsafe path: \(record.file)")
            return
        }
        do {
            let ext = try await WKWebExtension(resourceBaseURL: folder.appendingPathComponent(record.file))
            let context = WKWebExtensionContext(for: ext)
            context.uniqueIdentifier = record.id
            context.hasAccessToPrivateData = false
            // The user approved these when installing.
            for p in ext.requestedPermissions { context.setPermissionStatus(.grantedExplicitly, for: p) }
            for m in ext.allRequestedMatchPatterns { context.setPermissionStatus(.grantedExplicitly, for: m) }
            for p in record.extraPermissions { context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.Permission(rawValue: p)) }
            for s in record.extraPatterns {
                if let m = try? WKWebExtension.MatchPattern(string: s) { context.setPermissionStatus(.grantedExplicitly, for: m) }
            }
            try controller.load(context)
            contexts[record.id] = context
            NotificationCenter.default.post(name: Self.changed, object: nil)
        } catch {
            NSLog("Feather: couldn't load extension \(record.name): \(error.localizedDescription)")
        }
    }

    private func deactivate(_ id: String) {
        if let context = contexts.removeValue(forKey: id) { try? controller.unload(context) }
    }

    // MARK: Install / remove

    /// Installs a .xpi / .zip file or an unpacked extension folder, after asking the user.
    func install(from source: URL, window: NSWindow?) async {
        let id = UUID().uuidString
        let isFolder = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let file = isFolder ? id : "\(id).xpi"
        let dest = folder.appendingPathComponent(file)
        do {
            try FileManager.default.copyItem(at: source, to: dest)
            let ext = try await WKWebExtension(resourceBaseURL: dest)
            let name = ext.displayName ?? source.deletingPathExtension().lastPathComponent
            guard await confirmInstall(ext, name: name, window: window) else {
                try? FileManager.default.removeItem(at: dest)
                return
            }
            // Installing a new version of something already installed replaces it.
            for old in installed where old.name == name { remove(old.id, deleteFiles: true) }
            let record = InstalledExtension(id: id, file: file, name: name, enabled: true)
            installed.append(record)
            save()
            await activate(record)
        } catch {
            try? FileManager.default.removeItem(at: dest)
            Self.alert("Couldn't install this extension", error.localizedDescription, window)
        }
    }

    /// Downloads an add-on from a URL (an .xpi link) and installs it.
    func install(fromWeb url: URL, window: NSWindow?) async {
        do {
            let (temp, _) = try await URLSession.shared.download(from: url)
            let local = folder.appendingPathComponent("download-\(UUID().uuidString).xpi")
            try FileManager.default.moveItem(at: temp, to: local)
            await install(from: local, window: window)
            try? FileManager.default.removeItem(at: local)
        } catch {
            Self.alert("Couldn't download the add-on", error.localizedDescription, window)
        }
    }

    /// On addons.mozilla.org, turns the "Download Firefox and get the extension" button into
    /// "Add to Feather", pointing at the add-on's .xpi (which Feather intercepts and installs).
    /// The site is a single-page app, so it re-checks whenever the page changes.
    static let addonsSiteScript = #"""
    (() => {
      if (location.hostname !== 'addons.mozilla.org') return;
      const xpi = () => document.querySelector('.InstallButtonWrapper-download-link')?.href;
      const fix = () => {
        const button = document.querySelector('.GetFirefoxButton-button');
        const href = xpi();
        if (!button || !href) return;
        if (button.getAttribute('href') !== href) button.setAttribute('href', href);
        if (button.textContent !== 'Add to Feather') button.textContent = 'Add to Feather';
        if (button.target) button.removeAttribute('target');
        if (!button.dataset.feather) {
          button.dataset.feather = '1';
          button.addEventListener('click', e => {
            e.preventDefault();
            e.stopImmediatePropagation();
            const target = xpi();
            if (target) location.href = target;
          }, true);
        }
        const extra = document.querySelector('.InstallButtonWrapper-download');
        if (extra && extra.style.display !== 'none') extra.style.display = 'none';
      };
      new MutationObserver(fix).observe(document.documentElement, { childList: true, subtree: true });
      fix();
    })();
    """#

    /// The add-on's slug when `url` is a Firefox Add-ons (addons.mozilla.org) listing page.
    static func addonSlug(_ url: URL?) -> String? {
        guard let url, url.host == "addons.mozilla.org" else { return nil }
        let parts = url.pathComponents
        guard let i = parts.firstIndex(of: "addon"), i > 0, parts[i - 1] == "firefox", i + 1 < parts.count else { return nil }
        return parts[i + 1]
    }

    /// Looks up the add-on's current .xpi through the public addons.mozilla.org API and installs it.
    func install(addonSlug slug: String, window: NSWindow?) async {
        guard let api = URL(string: "https://addons.mozilla.org/api/v5/addons/addon/\(slug)/") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: api)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let version = json?["current_version"] as? [String: Any]
            let file = version?["file"] as? [String: Any]
            guard let link = file?["url"] as? String, let url = URL(string: link) else {
                return Self.alert("This add-on can't be installed", "Firefox Add-ons didn't provide a download.", window)
            }
            await install(fromWeb: url, window: window)
        } catch {
            Self.alert("Couldn't reach Firefox Add-ons", error.localizedDescription, window)
        }
    }

    func remove(_ id: String, deleteFiles: Bool) {
        // Delete the extension's saved storage while it is still loaded.
        if let context = contexts[id] {
            let controller = self.controller
            controller.fetchDataRecord(ofTypes: WKWebExtensionController.allExtensionDataTypes, for: context) { record in
                if let record {
                    controller.removeData(ofTypes: WKWebExtensionController.allExtensionDataTypes, from: [record]) {}
                }
            }
        }
        deactivate(id)
        if let record = installed.first(where: { $0.id == id }), deleteFiles,
           Self.isSafeFileName(record.file) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(record.file))
        }
        installed.removeAll { $0.id == id }
        save()
    }

    func setPinned(_ id: String, _ pinned: Bool) {
        guard let i = installed.firstIndex(where: { $0.id == id }) else { return }
        installed[i].pinned = pinned
        save()
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        guard let i = installed.firstIndex(where: { $0.id == id }) else { return }
        installed[i].enabled = enabled
        save()
        if enabled { Task { await activate(installed[i]) } } else { deactivate(id) }
    }

    // MARK: Prompts

    private static let permissionText: [WKWebExtension.Permission: String] = [
        .tabs: "See your open tabs and their addresses",
        .cookies: "Read and change cookies on sites it can access",
        .webRequest: "Watch your web traffic",
        .webNavigation: "See which pages you visit",
        .declarativeNetRequest: "Block content on web pages",
        .declarativeNetRequestWithHostAccess: "Block or change content on web pages",
        .scripting: "Run scripts on web pages",
        .clipboardWrite: "Write to your clipboard",
        .nativeMessaging: "Talk to other apps on your Mac",
    ]

    private static func describe(_ permissions: Set<WKWebExtension.Permission>,
                                 _ patterns: Set<WKWebExtension.MatchPattern>) -> [String] {
        var lines = permissions.compactMap { permissionText[$0] }.sorted()
        if patterns.contains(where: { $0.matchesAllURLs || $0.matchesAllHosts }) {
            lines.insert("Read and change your data on all websites", at: 0)
        } else {
            let hosts = Set(patterns.compactMap(\.host)).sorted()
            if !hosts.isEmpty {
                let shown = hosts.prefix(5).joined(separator: ", ") + (hosts.count > 5 ? " and \(hosts.count - 5) more" : "")
                lines.insert("Read and change your data on: \(shown)", at: 0)
            }
        }
        return lines
    }

    private func confirmInstall(_ ext: WKWebExtension, name: String, window: NSWindow?) async -> Bool {
        let lines = Self.describe(ext.requestedPermissions, ext.allRequestedMatchPatterns)
        let alert = NSAlert()
        alert.messageText = "Add “\(name)”?"
        var info = lines.isEmpty ? "It doesn't ask for any special access."
                                 : "It will be able to:\n• " + lines.joined(separator: "\n• ")
        info += "\n\nOnly install extensions you trust. Extensions never run in private windows."
        alert.informativeText = info
        if let icon = ext.icon(for: CGSize(width: 64, height: 64)) { alert.icon = icon }
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        return await Self.run(alert, window) == .alertFirstButtonReturn
    }

    private func ask(_ context: WKWebExtensionContext, _ lines: [String]) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "“\(context.webExtension.displayName ?? "An extension")” wants more access"
        alert.informativeText = "It's asking to:\n• " + lines.joined(separator: "\n• ")
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don't Allow")
        return await Self.run(alert, NSApp.keyWindow) == .alertFirstButtonReturn
    }

    private func remember(_ context: WKWebExtensionContext, permissions: [String] = [], patterns: [String] = []) {
        guard let i = installed.firstIndex(where: { $0.id == context.uniqueIdentifier }) else { return }
        installed[i].extraPermissions = Array(Set(installed[i].extraPermissions + permissions))
        installed[i].extraPatterns = Array(Set(installed[i].extraPatterns + patterns))
        save()
    }

    private static func run(_ alert: NSAlert, _ window: NSWindow?) async -> NSApplication.ModalResponse {
        guard let window, window.isVisible else { return alert.runModal() }
        return await withCheckedContinuation { cont in
            alert.beginSheetModal(for: window) { cont.resume(returning: $0) }
        }
    }

    static func alert(_ title: String, _ detail: String, _ window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        Task { _ = await run(alert, window) }
    }

    // MARK: WKWebExtensionControllerDelegate

    private var normalTabs: [BrowserWindowController] {
        NSApp.orderedWindows.compactMap { $0.windowController as? BrowserWindowController }.filter { !$0.isPrivate }
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        var seen = Set<ObjectIdentifier>()
        return normalTabs.compactMap { tab in
            let window = ExtensionWindow.for(tab)
            return seen.insert(ObjectIdentifier(window)).inserted ? window : nil
        }
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        BrowserWindowController.frontmost(isPrivate: false).map(ExtensionWindow.for)
    }

    func webExtensionController(_ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                                for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void) {
        let host = (configuration.window as? ExtensionWindow)?.activeTab?.window
            ?? BrowserWindowController.frontmost(isPrivate: false)?.window
        let tab = openTab(configuration.url, inTabOf: host, background: !configuration.shouldBeActive)
        completionHandler(tab, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
                                for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void) {
        let urls = configuration.tabURLs.isEmpty ? [nil] : configuration.tabURLs.map(Optional.some)
        let first = openTab(urls[0], inTabOf: nil, background: false)
        for url in urls.dropFirst() { openTab(url, inTabOf: first.window, background: true) }
        completionHandler(ExtensionWindow.for(first), nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, openOptionsPageFor extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any Error)?) -> Void) {
        openTab(extensionContext.optionsPageURL, inTabOf: BrowserWindowController.frontmost(isPrivate: false)?.window, background: false)
        completionHandler(nil)
    }

    /// Extension pages (options, new-tab pages) need the extension's own web view configuration.
    @discardableResult
    private func openTab(_ url: URL?, inTabOf host: NSWindow?, background: Bool) -> BrowserWindowController {
        let config = url.flatMap { controller.extensionContext(for: $0)?.webViewConfiguration }
        return BrowserWindowController.open(url: url, inTabOf: host, configuration: config, background: background)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void) {
        let lines = Self.describe(permissions, [])
        guard !lines.isEmpty else {
            remember(extensionContext, permissions: permissions.map(\.rawValue))
            return completionHandler(permissions, nil)
        }
        Task {
            let ok = await ask(extensionContext, lines)
            if ok { remember(extensionContext, permissions: permissions.map(\.rawValue)) }
            completionHandler(ok ? permissions : [], nil)
        }
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<URL>, Date?) -> Void) {
        let hosts = Set(urls.compactMap(\.host)).sorted().joined(separator: ", ")
        Task {
            let ok = await ask(extensionContext, ["Read and change your data on: \(hosts)"])
            completionHandler(ok ? urls : [], nil)
        }
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void) {
        Task {
            let ok = await ask(extensionContext, Self.describe([], matchPatterns))
            if ok { remember(extensionContext, patterns: matchPatterns.map(\.string)) }
            completionHandler(ok ? matchPatterns : [], nil)
        }
    }

    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action,
                                for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        guard let popover = action.popupPopover,
              let anchor = popupAnchor ?? BrowserWindowController.frontmost(isPrivate: false)?.window?.contentView else {
            return completionHandler(nil)
        }
        popover.behavior = .transient
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        completionHandler(nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, didUpdate action: WKWebExtension.Action,
                                forExtensionContext context: WKWebExtensionContext) {
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}

/// Presents a native tab group to extensions as one browser window.
final class ExtensionWindow: NSObject, WKWebExtensionWindow {
    private static let table = NSMapTable<AnyObject, ExtensionWindow>.weakToStrongObjects()
    private weak var key: AnyObject?
    private weak var fallback: NSWindow?

    static func `for`(_ tab: BrowserWindowController) -> ExtensionWindow {
        let key: AnyObject = tab.window?.tabGroup ?? tab
        if let existing = table.object(forKey: key) { return existing }
        let window = ExtensionWindow()
        window.key = key
        window.fallback = tab.window
        table.setObject(window, forKey: key)
        return window
    }

    private var windows: [NSWindow] {
        if let group = key as? NSWindowTabGroup { return group.windows }
        return fallback.map { [$0] } ?? []
    }

    var tabs: [BrowserWindowController] { windows.compactMap { $0.windowController as? BrowserWindowController } }

    var activeTab: BrowserWindowController? {
        ((key as? NSWindowTabGroup)?.selectedWindow ?? fallback)?.windowController as? BrowserWindowController
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { tabs }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { activeTab }
    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }
    func isPrivate(for context: WKWebExtensionContext) -> Bool { activeTab?.isPrivate ?? false }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let w = activeTab?.window else { return .normal }
        if w.styleMask.contains(.fullScreen) { return .fullscreen }
        if w.isMiniaturized { return .minimized }
        return .normal
    }

    func frame(for context: WKWebExtensionContext) -> CGRect { activeTab?.window?.frame ?? .null }
    func screenFrame(for context: WKWebExtensionContext) -> CGRect { activeTab?.window?.screen?.frame ?? .null }

    func focus(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        activeTab?.window?.makeKeyAndOrderFront(nil)
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        windows.forEach { $0.close() }
        completionHandler(nil)
    }
}
