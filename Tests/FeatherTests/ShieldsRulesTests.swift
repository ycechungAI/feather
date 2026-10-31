import Foundation
import Testing
@testable import Feather

/// Evaluates Feather's content rules the way WebKit does for an ordinary (non-ping) request:
/// rules apply in order, and "ignore-previous-rules" undoes earlier blocks for matching pages.
private struct RuleEvaluator {
    private struct Rule {
        let filter: NSRegularExpression
        let ifDomain: [String]?
        let resourceTypes: [String]?
        let action: String
    }
    private let rules: [Rule]

    init(domains: [String] = Blocklist.domains) throws {
        let json = try JSONSerialization.jsonObject(with: Data(Shields.rulesJSON(domains: domains).utf8)) as! [[String: Any]]
        rules = try json.map { rule in
            let trigger = rule["trigger"] as! [String: Any]
            let action = (rule["action"] as! [String: Any])["type"] as! String
            return Rule(filter: try NSRegularExpression(pattern: trigger["url-filter"] as! String),
                        ifDomain: trigger["if-domain"] as? [String],
                        resourceTypes: trigger["resource-type"] as? [String], action: action)
        }
    }

    func isBlocked(_ url: String, on page: String) -> Bool {
        let host = URL(string: page)?.host ?? ""
        var blocked = false
        for rule in rules where rule.resourceTypes == nil {
            guard rule.filter.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil else { continue }
            if let domains = rule.ifDomain, !domains.contains(where: { pageMatches(host, $0) }) { continue }
            switch rule.action {
            case "block": blocked = true
            case "ignore-previous-rules": blocked = false
            default: break
            }
        }
        return blocked
    }

    /// "*twitch.tv" covers twitch.tv and its subdomains; a plain entry is that host only.
    private func pageMatches(_ host: String, _ entry: String) -> Bool {
        guard entry.hasPrefix("*") else { return host == entry }
        let domain = String(entry.dropFirst())
        return host == domain || host.hasSuffix("." + domain)
    }
}

struct ShieldsRulesTests {
    /// Sites and their own resources that must keep working with Shields on.
    @Test(arguments: [
        ("https://www.amazon.ca/gp/cart/view.html?ref_=nav_cart", "https://www.amazon.ca/"),
        ("https://www.amazon.ca/cart/add-to-cart/ref=dp_start-bbf_1_glance", "https://www.amazon.ca/"),
        ("https://m.media-amazon.com/images/S/sash/A1msX0A1d1IcYGM.html", "https://www.amazon.ca/"),
        ("https://www.amazon.ca/checkout/entry/cart?proceedToCheckout=1", "https://www.amazon.ca/"),
        ("https://www.youtube.com/watch?v=dHj-vxDCw3g", "https://www.youtube.com/"),
        ("https://rr3---sn-abc.googlevideo.com/videoplayback?id=1", "https://www.youtube.com/"),
        ("https://www.youtube.com/live_chat_replay?continuation=x", "https://www.youtube.com/"),
        ("https://accounts.google.com/RotateCookiesPage", "https://www.google.com/"),
        ("https://www.google.com/search?q=amazon.ca", "https://www.google.com/"),
        ("https://github.com/ycechungAI/feather", "https://github.com/"),
        ("https://usher.ttvnw.net/api/channel/hls/x.m3u8", "https://www.twitch.tv/"),
        ("https://en.wikipedia.org/wiki/Feather", "https://en.wikipedia.org/"),
    ])
    func siteKeepsWorking(url: String, page: String) throws {
        #expect(try !RuleEvaluator().isBlocked(url, on: page))
    }

    @Test(arguments: [
        "https://securepubads.g.doubleclick.net/gampad/ads?x=1",
        "https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js",
        "https://www.google-analytics.com/analytics.js",
        "https://www.googletagmanager.com/gtm.js?id=GTM-X",
        "https://aax-us-east.amazon-adsystem.com/e/dtb/bid",
        "https://connect.facebook.net/en_US/fbevents.js",
        "https://www.facebook.com/tr?id=1&ev=PageView",
        "https://www.youtube.com/pagead/viewthroughconversion/1",
        "https://www.youtube.com/api/stats/ads?ver=2",
        "https://cdn.taboola.com/libtrc/loader.js",
        "http://ad.doubleclick.net:443/x",
    ])
    func adsAndTrackersAreBlocked(url: String) throws {
        #expect(try RuleEvaluator().isBlocked(url, on: "https://news.example.com/"))
    }

    /// A blocked domain covers its subdomains, never a different site that merely contains it.
    @Test func lookalikeDomainsAreNotBlocked() throws {
        let rules = try RuleEvaluator()
        #expect(!rules.isBlocked("https://notdoubleclick.net/a", on: "https://a.com/"))
        #expect(!rules.isBlocked("https://doubleclick.net.example.com/a", on: "https://a.com/"))
        #expect(!rules.isBlocked("https://example.com/?u=https://doubleclick.net/", on: "https://a.com/"))
        #expect(!rules.isBlocked("https://myclarity.ms.example.org/", on: "https://a.com/"))
    }

    @Test func twitchExceptionIsOnlyForTwitch() throws {
        let rules = try RuleEvaluator()
        let ad = "https://aax-us-east.amazon-adsystem.com/e/dtb/bid"
        #expect(!rules.isBlocked(ad, on: "https://www.twitch.tv/somechannel"))
        #expect(!rules.isBlocked(ad, on: "https://twitch.tv/"))
        #expect(rules.isBlocked(ad, on: "https://www.amazon.ca/"))
        #expect(rules.isBlocked(ad, on: "https://nottwitch.tv/"))
        // Other ad networks stay blocked on Twitch.
        #expect(rules.isBlocked("https://securepubads.g.doubleclick.net/x", on: "https://www.twitch.tv/"))
    }

    @Test func userBlocklistDomainsAreBlocked() throws {
        let rules = try RuleEvaluator(domains: Blocklist.domains + ["tracker.example"])
        #expect(rules.isBlocked("https://cdn.tracker.example/p.js", on: "https://a.com/"))
    }

    @Test func duplicateDomainsMakeOneRule() throws {
        let json = Shields.rulesJSON(domains: ["a.example", "a.example", "b.example"])
        let rules = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [[String: Any]]
        let filters = rules.compactMap { ($0["trigger"] as? [String: Any])?["url-filter"] as? String }
        #expect(filters.filter { $0.contains("a\\.example") }.count == 1)
    }

    /// WebKit rejects a list over 150,000 rules, which would leave the old rules in force.
    @Test func hugeListsStayUnderWebKitsLimit() throws {
        let domains = (0..<200_000).map { "d\($0).example" }
        let rules = try JSONSerialization.jsonObject(with: Data(Shields.rulesJSON(domains: domains).utf8)) as! [Any]
        #expect(rules.count < 150_000)
    }

    @Test func thirdPartyPingsAreBlocked() throws {
        let rules = try JSONSerialization.jsonObject(with: Data(Shields.rulesJSON(domains: []).utf8)) as! [[String: Any]]
        let ping = rules.first { (($0["trigger"] as? [String: Any])?["resource-type"] as? [String]) == ["ping"] }
        let trigger = try #require(ping?["trigger"] as? [String: Any])
        #expect(trigger["load-type"] as? [String] == ["third-party"])
    }

    /// Hiding ad boxes must come after every block rule and its exceptions.
    @Test func cosmeticRuleIsLast() throws {
        let rules = try JSONSerialization.jsonObject(with: Data(Shields.rulesJSON(domains: Blocklist.domains).utf8)) as! [[String: Any]]
        #expect((rules.last?["action"] as? [String: Any])?["type"] as? String == "css-display-none")
    }

    @Test func builtInListHasNoDuplicatesOrBadEntries() {
        #expect(Set(Blocklist.domains).count == Blocklist.domains.count)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        #expect(Blocklist.domains.allSatisfy { $0.contains(".") && $0.unicodeScalars.allSatisfy(allowed.contains) })
    }

    @Test func urlFiltersCompileAsRegexes() {
        for filter in Blocklist.urlFilters {
            #expect((try? NSRegularExpression(pattern: filter)) != nil, "\(filter)")
            #expect(!filter.contains("|"), "WebKit content rules have no | alternation: \(filter)")
        }
    }
}

struct BlocklistFileTests {
    @Test func readsPlainDomainLists() {
        #expect(Shields.domains(inList: "ads.example.com\ntracker.example.net\n") == ["ads.example.com", "tracker.example.net"])
    }

    @Test func readsHostsFiles() {
        let text = """
            # Hosts file
            127.0.0.1 localhost
            ::1 localhost
            255.255.255.255 broadcasthost
            0.0.0.0 0.0.0.0
            0.0.0.0 ads.example.com
            127.0.0.1\tpixel.example.org   # trailing comment
            """
        #expect(Shields.domains(inList: text) == ["ads.example.com", "pixel.example.org"])
    }

    @Test func lowercasesAndSkipsJunk() {
        let text = "ADS.Example.COM\n\n   \nnodot\n||adblock.syntax^\nbad host!.com\nwindows.crlf.example\r\n"
        #expect(Shields.domains(inList: text) == ["ads.example.com", "windows.crlf.example"])
    }

    @Test func commentsAreIgnored() {
        #expect(Shields.domains(inList: "#ads.example.com\n# 0.0.0.0 x.example\nkeep.example # why").sorted() == ["keep.example"])
    }
}
