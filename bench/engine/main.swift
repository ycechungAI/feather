// bench/engine/main.swift: page loads and Speedometer in Feather's WebKit setup, for bench/bench.py.
// Built together with Sources/Feather/Blocklist.swift so the ad-blocking rules are the real ones.
// Usage: engine '{"sites": [...], "speedometer": "https://..."}'   (prints one JSON line)
import AppKit
import WebKit

final class Nav: NSObject, WKNavigationDelegate {
    var done = false
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { done = true }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { done = true }
}

/// The same rules Shields builds (Shields.rulesJSON), from the built-in lists.
func rulesJSON() -> String {
    var rules: [[String: Any]] = []
    for domain in Set(Blocklist.domains).sorted() {
        rules.append(["trigger": ["url-filter": "^https?://([^/]+\\.)?\(domain.replacingOccurrences(of: ".", with: "\\."))[:/]"],
                      "action": ["type": "block"]])
    }
    for filter in Blocklist.urlFilters { rules.append(["trigger": ["url-filter": filter], "action": ["type": "block"]]) }
    rules.append(["trigger": ["url-filter": ".*", "resource-type": ["ping"], "load-type": ["third-party"]], "action": ["type": "block"]])
    rules.append(["trigger": ["url-filter": ".*"],
                  "action": ["type": "css-display-none", "selector": Blocklist.cosmeticSelectors.joined(separator: ", ")]])
    return String(decoding: try! JSONSerialization.data(withJSONObject: rules), as: UTF8.self)
}

@MainActor
func makeWebView(window: NSWindow, rules: WKContentRuleList?) -> (WKWebView, Nav) {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent() // a cold cache for each setup
    config.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
    for (key, value) in [("usesPageCache", false), ("lowPowerVideoAudioBufferSizeEnabled", true),
                         ("hiddenPageDOMTimerThrottlingEnabled", true)] {
        config.preferences.setValue(value, forKey: key)
    }
    if let rules { config.userContentController.add(rules) }
    let webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
    webView.autoresizingMask = [.width, .height]
    window.contentView!.subviews.forEach { $0.removeFromSuperview() }
    window.contentView!.addSubview(webView)
    let nav = Nav()
    webView.navigationDelegate = nav
    return (webView, nav)
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("engine: \(message)\n".utf8))
}

@MainActor
func loadTime(_ webView: WKWebView, _ nav: Nav, _ url: String) async -> Int? {
    nav.done = false
    webView.load(URLRequest(url: URL(string: url)!))
    let metric = "const n = performance.getEntriesByType('navigation')[0]; return n && n.loadEventEnd > 0 ? n.loadEventEnd : 0"
    let end = Date().addingTimeInterval(45)
    while Date() < end {
        try? await Task.sleep(for: .milliseconds(250))
        if nav.done, let value = try? await webView.callAsyncJavaScript(metric, arguments: [:], in: nil, contentWorld: .page) as? Double, value > 0 {
            return Int(value.rounded())
        }
    }
    return nil
}

@MainActor
func run() async {
    let input = try! JSONSerialization.jsonObject(with: Data(CommandLine.arguments[1].utf8)) as! [String: Any]
    let sites = input["sites"] as! [String]
    let app = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1280, height: 860),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.title = "Feather engine benchmark"
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    app.activate(ignoringOtherApps: true)

    let store = WKContentRuleListStore.default()!
    let rules = try? await store.compileContentRuleList(forIdentifier: "feather-bench", encodedContentRuleList: rulesJSON())

    var output: [String: Any] = [:]
    for (key, list) in [("loads", rules), ("loads_no_blocker", nil)] {
        let (webView, nav) = makeWebView(window: window, rules: list)
        var loads: [String: [String: Int]] = [:]
        for kind in ["cold", "warm"] {
            for site in sites {
                let ms = await loadTime(webView, nav, site)
                log("\(key) \(kind) \(site): \(ms.map(String.init) ?? "timed out")")
                if let ms { loads[site, default: [:]][kind] = ms }
            }
        }
        output[key] = loads
    }

    let speedometer = input["speedometer"] as? String ?? ""
    let (webView, nav) = makeWebView(window: window, rules: rules)
    nav.done = false
    if !speedometer.isEmpty { webView.load(URLRequest(url: URL(string: speedometer)!)) }
    // Speedometer marks the summary "valid" (or "invalid") when the run ends.
    let result = """
        const s = document.getElementById('summary'), r = document.getElementById('result-number');
        if (s && (s.className === 'valid' || s.className === 'invalid')) return r ? r.textContent.trim() : 'Error';
        return '';
        """
    let status = "return location.hash + ' ' + document.visibilityState + ' ' + (document.querySelector('#progress-completed, #info')?.textContent || '').trim().slice(0, 40)"
    let end = Date().addingTimeInterval(speedometer.isEmpty ? 0 : 1200)
    while Date() < end {
        try? await Task.sleep(for: .seconds(5))
        if let state = try? await webView.callAsyncJavaScript(status, arguments: [:], in: nil, contentWorld: .page) {
            log("speedometer: \(state)")
        }
        if let score = try? await webView.callAsyncJavaScript(result, arguments: [:], in: nil, contentWorld: .page) as? String,
           !score.isEmpty {
            output["speedometer"] = score
            break
        }
    }
    try? await store.removeContentRuleList(forIdentifier: "feather-bench")
    let data = try! JSONSerialization.data(withJSONObject: output)
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

// A real app run loop, so the window is on screen and WebKit treats the page as visible
// (hidden pages pause animation frames, and Speedometer with them).
final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in await run() }
    }
}
let delegate = Delegate()
NSApplication.shared.setActivationPolicy(.regular)
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
