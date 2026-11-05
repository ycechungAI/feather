import Foundation
import Testing
@testable import Feather

struct RouterRequestTests {
    @Test func postsTheRouteQuestionToTheDecisionModelAndKeepsItLoaded() throws {
        let request = try Router(config: ServicesConfig()).decisionRequest(request: "Find news", pageOpen: false)
        #expect(request.url?.absoluteString == "http://127.0.0.1:11434/v1/systemone")
        let data = try #require(request.httpBody)
        let body = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["model"] as? String == "tev1:0.8b")
        #expect(body["keep_alive"] as? Int == -1)
        let state = try #require(body["state"] as? [String: Any])
        #expect(state["request"] as? String == "Find news")
        #expect(state["page_open"] as? Bool == false)
        let questions = try #require(body["questions"] as? [String: Any])
        let route = try #require(questions["route"] as? [String: Any])
        #expect(route["type"] as? String == "choice")
        let criteria = try #require(route["criteria"] as? [String: String])
        #expect(Set(criteria.keys) == ["page_qa", "search", "schedule", "none"])
    }

    @Test func refusesRemoteServers() {
        var config = ServicesConfig()
        config.ollama = "https://example.com"
        #expect(throws: LocalModelError.notLocalhost("https://example.com")) {
            try Router(config: config).decisionRequest(request: "x", pageOpen: false)
        }
    }
}

struct RouterDecisionTests {
    private func response(choice: String, confidence: Double) -> Data {
        Data(#"{"answers":{"route":{"type":"choice","choice":"\#(choice)","confidence":\#(confidence)}}}"#.utf8)
    }

    @Test func readsTheChoiceAndConfidence() throws {
        let decision = try Router.decision(from: response(choice: "schedule", confidence: 0.69))
        #expect(decision == RouteDecision(choice: "schedule", confidence: 0.69))
    }

    @Test func confidentChoiceRoutes() {
        #expect(Router.result(for: RouteDecision(choice: "page_qa", confidence: 0.67)) == .routed(.pageQA))
        #expect(Router.result(for: RouteDecision(choice: "none", confidence: 0.9)) == .routed(.nothing))
    }

    @Test func lowConfidenceAsksInsteadOfGuessing() {
        #expect(Router.result(for: RouteDecision(choice: "none", confidence: 0.31)) == .unsure)
    }

    @Test func unknownLabelAsksInsteadOfGuessing() {
        #expect(Router.result(for: RouteDecision(choice: "delete_everything", confidence: 0.99)) == .unsure)
    }

    @Test func showsOllamaErrors() {
        let data = Data(#"{"error":"model 'tev1:0.8b' not found"}"#.utf8)
        #expect(throws: LocalModelError.modelError("model 'tev1:0.8b' not found")) {
            try Router.decision(from: data)
        }
    }
}
