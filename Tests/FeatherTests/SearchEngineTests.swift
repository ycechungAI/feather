import Foundation
import Testing
@testable import Feather

struct SearchEngineTests {
    @Test func encodesQuery() {
        let url = SearchEngine.url(for: "cats & dogs?", prefix: "https://duckduckgo.com/?q=")
        #expect(url?.absoluteString == "https://duckduckgo.com/?q=cats%20%26%20dogs%3F")
    }

    @Test func plusAndHashAreEncoded() {
        let url = SearchEngine.url(for: "c++ #1", prefix: "https://www.google.com/search?q=")
        #expect(url?.absoluteString == "https://www.google.com/search?q=c%2B%2B%20%231")
    }

    @Test func presetsAreHTTPSAndDistinct() {
        #expect(SearchEngine.all.allSatisfy { $0.searchURL.hasPrefix("https://") && $0.homeURL.hasPrefix("https://") })
        #expect(Set(SearchEngine.all.map(\.searchURL)).count == SearchEngine.all.count)
        #expect(SearchEngine.all.compactMap(\.suggestURL).allSatisfy { $0.hasPrefix("https://") })
    }

    @Test func matchingFindsPresetOrNil() {
        #expect(SearchEngine.matching(searchURL: "https://duckduckgo.com/?q=")?.name == "DuckDuckGo")
        #expect(SearchEngine.matching(searchURL: "https://example.com/?q=") == nil)
    }

    @Test func everyPresetBuildsAValidURL() {
        for engine in SearchEngine.all {
            let url = SearchEngine.url(for: "hello world", prefix: engine.searchURL)
            #expect(url?.host != nil, "\(engine.name)")
        }
    }
}
