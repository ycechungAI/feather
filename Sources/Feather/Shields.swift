import Foundation
import WebKit

/// Ad & tracker blocking built on WebKit content rules. Rules are compiled once into
/// native bytecode and enforced inside the engine, so blocking costs almost no CPU or RAM.
final class Shields {
    static let shared = Shields()

    private(set) var ruleList: WKContentRuleList?
    private var compiledID: String?
    private let store = WKContentRuleListStore.default()!

    /// Compiles (or loads the cached) rule list, then calls `done`.
    func prepare(force: Bool = false, _ done: @escaping () -> Void) {
        let json = Self.rulesJSON(domains: Blocklist.domains + Self.userDomains())
        let id = "feather-\(Self.fnv1a(json))"
        if id == compiledID, !force { done(); return }

        store.lookUpContentRuleList(forIdentifier: id) { [weak self] cached, _ in
            guard let self else { return }
            if let cached {
                self.finish(cached, id, done)
                return
            }
            self.store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) { list, error in
                if let error { NSLog("Feather: blocklist compile failed: \(error)") }
                self.finish(list, id, done)
            }
        }
    }

    private func finish(_ list: WKContentRuleList?, _ id: String, _ done: () -> Void) {
        ruleList = list
        compiledID = id
        // Drop stale compiled lists from previous blocklist versions.
        store.getAvailableContentRuleListIdentifiers { ids in
            for old in ids ?? [] where old.hasPrefix("feather-") && old != id {
                self.store.removeContentRuleList(forIdentifier: old) { _ in }
            }
        }
        done()
    }

    /// Applies or removes blocking on a web view's content controller.
    /// `addonInstalls` adds the "Add to Feather" button on addons.mozilla.org (off in private windows).
    func apply(to controller: WKUserContentController, addonInstalls: Bool) {
        controller.removeAllContentRuleLists()
        controller.removeAllUserScripts()
        if addonInstalls {
            controller.addUserScript(WKUserScript(source: ExtensionManager.addonsSiteScript,
                                                  injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        guard Settings.shieldsEnabled else { return }
        if let ruleList { controller.add(ruleList) }
        controller.addUserScript(WKUserScript(source: Blocklist.youtubeScript,
                                              injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }

    // MARK: Rule building

    /// Reads every `*.txt` in the blocklist folder. Accepts plain domain lists and hosts files
    /// (e.g. "0.0.0.0 ads.example.com").
    private static func userDomains() -> [String] {
        let dir = Settings.supportDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var out: [String] = []
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-_")
        let skip: Set<String> = ["localhost", "localhost.localdomain", "local", "broadcasthost", "0.0.0.0"]
        for file in files where file.pathExtension == "txt" {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for raw in text.split(whereSeparator: \.isNewline) {
                let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                guard let host = line.split(whereSeparator: \.isWhitespace).last?.lowercased(),
                      host.contains("."), !skip.contains(host),
                      host.unicodeScalars.allSatisfy(allowed.contains) else { continue }
                out.append(host)
            }
        }
        return out
    }

    static func rulesJSON(domains: [String]) -> String {
        var rules: [[String: Any]] = []
        // WebKit caps a single list at 150k rules.
        for domain in Array(Set(domains)).sorted().prefix(140_000) {
            let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
            rules.append(block("^https?://([^/]+\\.)?\(escaped)[:/]"))
        }
        for filter in Blocklist.urlFilters {
            rules.append(block(filter))
        }
        // Tracking pings (<a ping>, navigator.sendBeacon) to third parties.
        rules.append(["trigger": ["url-filter": ".*", "resource-type": ["ping"], "load-type": ["third-party"]],
                      "action": ["type": "block"]])
        rules.append(["trigger": ["url-filter": ".*"],
                      "action": ["type": "css-display-none", "selector": Blocklist.cosmeticSelectors.joined(separator: ", ")]])
        let data = try! JSONSerialization.data(withJSONObject: rules)
        return String(decoding: data, as: UTF8.self)
    }

    private static func block(_ filter: String) -> [String: Any] {
        ["trigger": ["url-filter": filter], "action": ["type": "block"]]
    }

    /// Stable hash, so the compiled list is cached across launches.
    private static func fnv1a(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 16)
    }
}
