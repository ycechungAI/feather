import Foundation
import Testing
import WebKit
@testable import Feather

struct ShieldsAllowlistTests {
    @Test func exactHost() {
        #expect(Shields.isAllowlisted(host: "example.com", in: ["example.com"]))
    }

    @Test func subdomainsAreCovered() {
        #expect(Shields.isAllowlisted(host: "www.example.com", in: ["example.com"]))
        #expect(Shields.isAllowlisted(host: "a.b.example.com", in: ["example.com"]))
    }

    @Test func lookalikeDomainsAreNot() {
        #expect(!Shields.isAllowlisted(host: "notexample.com", in: ["example.com"]))
        #expect(!Shields.isAllowlisted(host: "example.com.evil.net", in: ["example.com"]))
    }

    @Test func parentIsNotCoveredBySubdomainEntry() {
        #expect(!Shields.isAllowlisted(host: "example.com", in: ["shop.example.com"]))
    }

    @Test func caseAndTrailingDot() {
        #expect(Shields.isAllowlisted(host: "WWW.Example.COM.", in: ["example.com"]))
        #expect(Shields.isAllowlisted(host: "example.com", in: ["Example.com"]))
    }

    @Test func missingHost() {
        #expect(!Shields.isAllowlisted(host: nil, in: ["example.com"]))
        #expect(!Shields.isAllowlisted(host: "", in: ["example.com"]))
        #expect(!Shields.isAllowlisted(host: "example.com", in: []))
    }

    @Test func exceptionHostDropsWWW() {
        #expect(Shields.exceptionHost(for: "www.YouTube.com") == "youtube.com")
        #expect(Shields.exceptionHost(for: "m.youtube.com") == "m.youtube.com")
    }

    /// WebKit rejects the whole list if one rule is invalid, which would silently keep old rules.
    @Test @MainActor func rulesCompile() async throws {
        let json = Shields.rulesJSON(domains: Blocklist.domains)
        let store = WKContentRuleListStore.default()!
        let list = try await store.compileContentRuleList(forIdentifier: "feather-test", encodedContentRuleList: json)
        #expect(list != nil)
        try? await store.removeContentRuleList(forIdentifier: "feather-test")
    }

    @Test func twitchMayReachAmazonAdServers() throws {
        let rules = try JSONSerialization.jsonObject(with: Data(Shields.rulesJSON(domains: Blocklist.domains).utf8)) as! [[String: Any]]
        let blockAt = rules.firstIndex { ($0["trigger"] as? [String: Any])?["url-filter"] as? String == #"^https?://([^/]+\.)?amazon-adsystem\.com[:/]"# }
        let allowAt = rules.firstIndex { ($0["action"] as? [String: Any])?["type"] as? String == "ignore-previous-rules" }
        let allow = try #require(allowAt)
        #expect(try #require(blockAt) < allow)
        #expect((rules[allow]["trigger"] as? [String: Any])?["if-domain"] as? [String] == ["*twitch.tv"])
    }
}
