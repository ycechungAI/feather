import Foundation
import Testing
@testable import FeatherA

struct LocalModelConfigTests {
    @Test func defaultsAreLocalOllamaAndASmallModel() {
        let config = ServicesConfig()
        #expect(config.ollama == "http://127.0.0.1:11434")
        #expect(config.routerModel == "tev1:0.8b")
        #expect(config.answerModel == "granite4:3b")
        #expect(config.basicModel == "gemma3:1b")
        #expect(config.pageCharacterLimit == 12_000)
    }

    @Test func partialFileKeepsTheOtherDefaults() throws {
        let config = try JSONDecoder().decode(ServicesConfig.self, from: Data(#"{"basicModel":"llama3.2:1b"}"#.utf8))
        #expect(config.basicModel == "llama3.2:1b")
        #expect(config.ollama == "http://127.0.0.1:11434")
    }

    @Test func missingFileGivesDefaults() {
        let missing = URL(fileURLWithPath: "/nonexistent/feather/services.json")
        #expect(ServicesConfig.load(from: missing) == ServicesConfig())
    }
}

struct LocalModelRequestTests {
    @Test func bodyCarriesModelQuestionAndPageWithoutStreaming() throws {
        let request = try LocalModel(config: ServicesConfig()).chatRequest(question: "What is it?", pageText: "Hello page")
        #expect(request.url?.absoluteString == "http://127.0.0.1:11434/api/chat")
        #expect(request.httpMethod == "POST")
        let data = try #require(request.httpBody)
        let body = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["model"] as? String == "granite4:3b")
        #expect(body["stream"] as? Bool == false)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages[1]["content"]?.contains("Hello page") == true)
        #expect(messages[1]["content"]?.contains("What is it?") == true)
    }

    @Test func onlyThisMacIsAllowed() {
        var config = ServicesConfig()
        config.ollama = "https://example.com"
        #expect(throws: LocalModelError.notLocalhost("https://example.com")) {
            try LocalModel(config: config).chatRequest(question: "x", pageText: "y")
        }
    }

    @Test func versionCheckGoesToTheLocalServerWithAShortTimeout() throws {
        let request = try LocalModel(config: ServicesConfig()).versionRequest()
        #expect(request.url?.absoluteString == "http://127.0.0.1:11434/api/version")
        #expect(request.timeoutInterval == 2)
    }

    @Test func reportsNotRunningWhenNothingListens() async {
        var config = ServicesConfig()
        config.ollama = "http://127.0.0.1:1"
        #expect(await LocalModel(config: config).isRunning() == false)
    }

    @Test func versionCheckRefusesRemoteServers() {
        var config = ServicesConfig()
        config.ollama = "https://example.com"
        #expect(throws: LocalModelError.notLocalhost("https://example.com")) {
            try LocalModel(config: config).versionRequest()
        }
    }

    @Test func findsTheConfiguredModelByExactName() {
        let tags = Data(#"{"models":[{"name":"gemma3:1b"},{"name":"granite4:3b"}]}"#.utf8)
        #expect(LocalModel.hasModel(named: "gemma3:1b", inTags: tags))
        #expect(!LocalModel.hasModel(named: "gemma3", inTags: tags))
        #expect(!LocalModel.hasModel(named: "llama3.2:1b", inTags: tags))
    }

    @Test func pullAsksOllamaForTheConfiguredModelWithoutStreaming() throws {
        let request = try LocalModel(config: ServicesConfig()).pullRequest("gemma3:1b")
        #expect(request.url?.absoluteString == "http://127.0.0.1:11434/api/pull")
        #expect(request.timeoutInterval == 1800)
        let data = try #require(request.httpBody)
        let body = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["model"] as? String == "gemma3:1b")
        #expect(body["stream"] as? Bool == false)
    }

    @Test func pageTextIsClipped() {
        #expect(LocalModel.clip("abcdef", limit: 3) == "abc")
        #expect(LocalModel.clip("ab", limit: 3) == "ab")
    }
}

struct LocalModelAnswerTests {
    @Test func readsTheAnswerAndTrimsIt() throws {
        let data = Data(#"{"message":{"role":"assistant","content":" Yes. "},"done":true}"#.utf8)
        #expect(try LocalModel.answer(from: data) == "Yes.")
    }

    @Test func showsOllamaErrors() {
        let data = Data(#"{"error":"model 'x' not found"}"#.utf8)
        #expect(throws: LocalModelError.modelError("model 'x' not found")) {
            try LocalModel.answer(from: data)
        }
    }

    @Test func rejectsAnswersWithoutContent() {
        #expect(throws: LocalModelError.badResponse) {
            try LocalModel.answer(from: Data("{}".utf8))
        }
    }
}
