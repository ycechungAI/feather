import AppKit
import WebKit

/// What to do with a navigation, decided from the request alone so the rules can be tested.
/// BrowserWindowController carries the decision out.
enum NavigationPolicy: Equatable {
    case allow
    case download
    case installAddon
    case openInNewTab(background: Bool)
    case cancel
    /// Hand the URL to the app that handles it (mailto:, facetime:, app links).
    case openExternally
    /// Cancel and load this URL instead: tracking parameters removed, or upgraded to HTTPS.
    case load(URL, upgradedHost: String?)

    struct Request {
        var url: URL
        var method: String? = "GET"
        /// nil when the navigation opens a new window (target=_blank, window.open).
        var isMainFrame: Bool? = true
        var navigationType: WKNavigationType = .other
        var modifiers: NSEvent.ModifierFlags = []
        var buttonNumber = 0
        var shouldDownload = false
        var isPrivate = false
        var isExtensionPage = false
        var httpsOnly = true
        var insecureAllowed: Set<String> = []
    }

    static let webSchemes: Set<String> = ["http", "https", "about", "file", "data", "blob"]

    static func decide(_ r: Request) -> NavigationPolicy {
        if r.shouldDownload { return .download }

        // Firefox add-on files open the install prompt instead of downloading.
        if r.url.pathExtension.lowercased() == "xpi", !r.isPrivate { return .installAddon }
        // Extension pages (settings, popups opened as tabs) load inside WebKit.
        if r.isExtensionPage { return .allow }

        // ⌘-click or middle-click opens a new tab.
        if r.navigationType == .linkActivated, r.modifiers.contains(.command) || r.buttonNumber == 2 {
            return .openInNewTab(background: !r.modifiers.contains(.shift))
        }

        // `javascript:` must never be honoured as a navigation: a page that manages to
        // steer one here could otherwise run script outside its own origin.
        let scheme = r.url.scheme?.lowercased() ?? ""
        if scheme == "javascript" { return .cancel }

        // Hand mailto:, facetime:, app links etc. to the system, but only for a real
        // user click so a page can't silently launch other apps.
        if !webSchemes.contains(scheme) {
            return r.navigationType == .linkActivated ? .openExternally : .cancel
        }

        if r.isMainFrame == true {
            if r.method == "GET", let clean = URLTools.stripTracking(r.url) { return .load(clean, upgradedHost: nil) }
            if r.httpsOnly, let host = r.url.host?.lowercased(), !r.insecureAllowed.contains(host),
               let secure = URLTools.httpsUpgrade(r.url) {
                return .load(secure, upgradedHost: host)
            }
        }
        return .allow
    }
}
