import AppKit
import Foundation
import Testing
import WebKit
@testable import Feather

struct NavigationPolicyTests {
    private func decide(_ url: String, _ change: (inout NavigationPolicy.Request) -> Void = { _ in }) -> NavigationPolicy {
        var r = NavigationPolicy.Request(url: URL(string: url)!)
        change(&r)
        return NavigationPolicy.decide(r)
    }

    @Test func ordinaryPagesLoad() {
        #expect(decide("https://www.amazon.ca/gp/cart/view.html?ref_=nav_cart") == .allow)
        #expect(decide("https://www.youtube.com/watch?v=1") { $0.navigationType = .linkActivated } == .allow)
    }

    @Test func javascriptURLsAreAlwaysCancelled() {
        for type in [WKNavigationType.linkActivated, .other, .formSubmitted] {
            #expect(decide("javascript:alert(document.cookie)") { $0.navigationType = type } == .cancel)
            #expect(decide("JavaScript:void(0)") { $0.navigationType = type; $0.isMainFrame = false } == .cancel)
        }
    }

    /// Other apps open only when you click a link, never because a page redirected or scripted it.
    @Test func otherAppsOpenOnlyOnAClick() {
        #expect(decide("mailto:a@example.com") { $0.navigationType = .linkActivated } == .openExternally)
        #expect(decide("facetime://a@example.com") { $0.navigationType = .linkActivated } == .openExternally)
        #expect(decide("mailto:a@example.com") == .cancel)
        #expect(decide("zoommtg://join?x=1") { $0.isMainFrame = false } == .cancel)
        #expect(decide("itms-apps://apps.apple.com/app/1") { $0.navigationType = .formSubmitted } == .cancel)
    }

    @Test func commandAndMiddleClickOpenNewTabs() {
        #expect(decide("https://a.com/") { $0.navigationType = .linkActivated; $0.modifiers = .command } == .openInNewTab(background: true))
        #expect(decide("https://a.com/") { $0.navigationType = .linkActivated; $0.modifiers = [.command, .shift] } == .openInNewTab(background: false))
        #expect(decide("https://a.com/") { $0.navigationType = .linkActivated; $0.buttonNumber = 2 } == .openInNewTab(background: true))
        // A script navigating while ⌘ happens to be held is not a click.
        #expect(decide("https://a.com/") { $0.modifiers = .command } == .allow)
    }

    @Test func trackingIsRemovedFromPageLoads() {
        #expect(decide("https://a.com/p?id=1&utm_source=x") == .load(URL(string: "https://a.com/p?id=1")!, upgradedHost: nil))
    }

    /// Changing a form POST, a subframe or a new-window request would break it; only main-frame GETs.
    @Test func trackingIsLeftAloneOutsideMainFrameGETs() {
        #expect(decide("https://a.com/p?utm_source=x") { $0.method = "POST" } == .allow)
        #expect(decide("https://a.com/p?utm_source=x") { $0.isMainFrame = false } == .allow)
        #expect(decide("https://a.com/p?utm_source=x") { $0.isMainFrame = nil } == .allow)
    }

    @Test func httpIsUpgraded() {
        #expect(decide("http://example.com/a") == .load(URL(string: "https://example.com/a")!, upgradedHost: "example.com"))
    }

    @Test func httpStaysWhenAllowedOrOff() {
        #expect(decide("http://example.com/") { $0.insecureAllowed = ["example.com"] } == .allow)
        #expect(decide("http://example.com/") { $0.httpsOnly = false } == .allow)
        #expect(decide("http://localhost:3000/") == .allow)
        #expect(decide("http://192.168.1.1/") == .allow)
    }

    @Test func trackingIsRemovedBeforeUpgrading() {
        // Removing tracking reloads the page, and that reload is then upgraded.
        let first = decide("http://example.com/?gclid=1")
        #expect(first == .load(URL(string: "http://example.com/")!, upgradedHost: nil))
        #expect(decide("http://example.com/") == .load(URL(string: "https://example.com/")!, upgradedHost: "example.com"))
    }

    @Test func downloadsWin() {
        #expect(decide("https://a.com/file.zip") { $0.shouldDownload = true } == .download)
    }

    @Test func addonsInstallExceptInPrivateWindows() {
        #expect(decide("https://addons.mozilla.org/firefox/downloads/file/1/ublock.xpi") == .installAddon)
        #expect(decide("https://addons.mozilla.org/firefox/downloads/file/1/ublock.XPI") == .installAddon)
        #expect(decide("https://addons.mozilla.org/firefox/downloads/file/1/ublock.xpi") { $0.isPrivate = true } == .allow)
    }

    @Test func extensionPagesLoadAsTheyAre() {
        #expect(decide("webkit-extension://abc/options.html") { $0.isExtensionPage = true } == .allow)
        #expect(decide("webkit-extension://abc/options.html") == .cancel)
    }

    @Test func webSchemesInSubframesLoad() {
        for url in ["about:blank", "about:srcdoc", "blob:https://a.com/1", "data:text/plain,hi"] {
            #expect(decide(url) { $0.isMainFrame = false } == .allow, "\(url)")
        }
    }
}
