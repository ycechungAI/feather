import Foundation
import Testing
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
}
