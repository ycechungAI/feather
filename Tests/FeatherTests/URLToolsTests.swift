import Foundation
import Testing
@testable import Feather

struct URLToolsResolveTests {
    private func resolve(_ text: String) -> String? { URLTools.resolve(text)?.absoluteString }
    private func search(_ text: String) -> String? { SearchEngine.url(for: text, prefix: Settings.searchURL)?.absoluteString }

    @Test func fullURLsPassThrough() {
        #expect(resolve("https://example.com/a?b=1#c") == "https://example.com/a?b=1#c")
        #expect(resolve("http://example.com") == "http://example.com")
    }

    @Test func bareDomainsGetHTTPS() {
        #expect(resolve("example.com") == "https://example.com")
        #expect(resolve("en.wikipedia.org/wiki/Feather") == "https://en.wikipedia.org/wiki/Feather")
    }

    @Test func whitespaceIsTrimmed() {
        #expect(resolve("  example.com \n") == "https://example.com")
    }

    @Test func emptyInputIsNothing() {
        #expect(resolve("") == nil)
        #expect(resolve("   ") == nil)
    }

    @Test func localDevelopmentUsesHTTP() {
        #expect(resolve("localhost:3000") == "http://localhost:3000")
        #expect(resolve("127.0.0.1:8080/x") == "http://127.0.0.1:8080/x")
    }

    /// Routers, printers and NAS boxes rarely serve HTTPS; typing their address must not fail.
    @Test func privateNetworkAddressesUseHTTP() {
        #expect(resolve("192.168.1.1") == "http://192.168.1.1")
        #expect(resolve("10.0.0.2:8080") == "http://10.0.0.2:8080")
        #expect(resolve("printer.local") == "http://printer.local")
    }

    @Test func wordsAreSearched() {
        #expect(resolve("hello world") == search("hello world"))
        #expect(resolve("feather") == search("feather"))
    }

    @Test func aboutAndFileURLsAreKept() {
        #expect(resolve("about:blank") == "about:blank")
        #expect(resolve("file:///tmp/a.html") == "file:///tmp/a.html")
    }

    /// Typing (or pasting) a javascript: URL must never turn into script running in a page.
    @Test func javascriptURLsAreNeverLoaded() {
        for text in ["javascript:alert(1)", "javascript:alert(document.domain)", "JavaScript:void(0)"] {
            #expect(URLTools.resolve(text)?.scheme?.lowercased() != "javascript", "\(text)")
        }
    }

    @Test func otherSchemesAreNotOpened() {
        #expect(URLTools.resolve("data:text/html,<script>alert(1)</script>")?.scheme != "data")
    }
}

struct URLToolsTrackingTests {
    private func strip(_ s: String) -> String? { URLTools.stripTracking(URL(string: s)!)?.absoluteString }

    @Test func removesTrackingKeepsTheRest() {
        #expect(strip("https://a.com/p?id=1&utm_source=x&utm_medium=y") == "https://a.com/p?id=1")
    }

    @Test func dropsQueryWhenOnlyTrackingRemains() {
        #expect(strip("https://a.com/p?fbclid=abc") == "https://a.com/p")
    }

    @Test func untouchedURLsGiveNil() {
        #expect(strip("https://a.com/p?id=1") == nil)
        #expect(strip("https://a.com/p") == nil)
    }

    @Test func namesAreCaseInsensitive() {
        #expect(strip("https://a.com/?UTM_Source=x&GCLID=1&q=2") == "https://a.com/?q=2")
    }

    @Test func fragmentSurvives() {
        #expect(strip("https://a.com/p?gclid=1#section") == "https://a.com/p#section")
    }

    /// The rest of the query must reach the site byte for byte: "%2B" is a plus sign, while a
    /// bare "+" means a space to most servers.
    @Test func otherParametersKeepTheirEncoding() {
        #expect(strip("https://a.com/s?q=c%2B%2B&utm_source=x") == "https://a.com/s?q=c%2B%2B")
        #expect(strip("https://a.com/s?q=a+b&fbclid=1") == "https://a.com/s?q=a+b")
        #expect(strip("https://a.com/s?next=%2Fhome%3Fa%3D1&gclid=1") == "https://a.com/s?next=%2Fhome%3Fa%3D1")
    }

    @Test func repeatedAndEmptyParametersSurvive() {
        #expect(strip("https://a.com/?tag=a&tag=b&flag&utm_id=1") == "https://a.com/?tag=a&tag=b&flag")
    }

    @Test func everyKnownTrackerIsRemoved() {
        for name in ["utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id", "fbclid",
                     "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid", "mc_cid",
                     "mc_eid", "igshid", "_hsenc", "_hsmi", "oly_anon_id", "oly_enc_id"] {
            #expect(strip("https://a.com/?\(name)=1&keep=2") == "https://a.com/?keep=2", "\(name)")
        }
    }

    /// Amazon's own "ref" and affiliate "tag" are not click trackers and must stay.
    @Test func siteParametersThatLookLikeTrackersStay() {
        #expect(strip("https://www.amazon.ca/gp/cart/view.html?ref_=nav_cart") == nil)
        #expect(strip("https://www.amazon.ca/?tag=x-20&ref=pd") == nil)
    }
}

struct URLToolsHTTPSTests {
    private func upgrade(_ s: String) -> String? { URLTools.httpsUpgrade(URL(string: s)!)?.absoluteString }

    @Test func upgradesPublicHTTP() {
        #expect(upgrade("http://example.com/a?b=1#c") == "https://example.com/a?b=1#c")
    }

    @Test func dropsTheDefaultHTTPPort() {
        #expect(upgrade("http://example.com:80/x") == "https://example.com/x")
    }

    @Test func leavesHTTPSAlone() {
        #expect(upgrade("https://example.com") == nil)
    }

    @Test func neverUpgradesLocalHosts() {
        for s in ["http://localhost:3000", "http://127.0.0.1/", "http://192.168.0.10", "http://[::1]:8080/",
                  "http://router.local", "http://app.test", "http://dev.localhost", "http://localhost./"] {
            #expect(upgrade(s) == nil, "\(s)")
        }
    }
}

struct URLToolsLocalTests {
    @Test(arguments: ["localhost", "LOCALHOST", "localhost.", "a.localhost", "printer.local", "site.test",
                      "127.0.0.1", "127.255.255.254", "0.0.0.0", "10.1.2.3", "192.168.1.1", "172.16.0.1",
                      "172.31.255.255", "169.254.10.20", "::1", "[::1]", "fe80::1", "fd12:3456::1", "fc00::1",
                      "::ffff:127.0.0.1", "::ffff:192.168.1.1"])
    func local(_ host: String) {
        #expect(URLTools.isLocal(host))
    }

    @Test(arguments: ["example.com", "8.8.8.8", "172.15.0.1", "172.32.0.1", "192.169.0.1", "11.0.0.1",
                      "256.1.1.1", "1.2.3", "2001:db8::1", "fcm.googleapis.com", "fdsa.com", "local",
                      "notlocalhost", "localhost.example.com", "::ffff:8.8.8.8"])
    func notLocal(_ host: String) {
        #expect(!URLTools.isLocal(host))
    }
}
