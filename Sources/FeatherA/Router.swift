import Foundation

/// What handles a request. Chosen by the small decision model (`routerModel`), not the answer model.
enum Route: String, CaseIterable, Equatable {
    case pageQA = "page_qa"
    case search
    case schedule
    case nothing = "none"
}

struct RouteDecision: Equatable {
    let choice: String
    let confidence: Double
}

enum RouteResult: Equatable {
    case routed(Route)
    /// Low confidence or an unknown label: ask the user instead of guessing.
    case unsure
}

/// Picks a route with the decision model through Ollama's `/v1/systemone`, the same call noskill
/// makes (noskill `internal/decide/jev.go`). Everything stays on this Mac.
struct Router {
    let config: ServicesConfig

    static let threshold = 0.4

    static let instructions = "Which action should handle the request? A page may be open in the browser."
    static let criteria: [String: String] = [
        "page_qa": "Answer a question about the open page",
        "search": "Search the web for something new",
        "schedule": "Create a task that runs on a schedule",
        "none": "Nothing needs doing",
    ]

    func decisionRequest(request text: String, pageOpen: Bool) throws -> URLRequest {
        guard let base = URL(string: config.ollama), LocalModel.isLocal(base) else {
            throw LocalModelError.notLocalhost(config.ollama)
        }
        var urlRequest = URLRequest(url: base.appendingPathComponent("v1/systemone"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": config.routerModel,
            "keep_alive": -1,
            "state": ["request": text, "page_open": pageOpen],
            "questions": [
                "route": [
                    "type": "choice",
                    "instructions": Self.instructions,
                    "criteria": Self.criteria,
                ],
            ],
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    static func decision(from data: Data) throws -> RouteDecision {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalModelError.badResponse
        }
        if let message = object["error"] as? String {
            throw LocalModelError.modelError(message)
        }
        guard let answers = object["answers"] as? [String: Any],
              let route = answers["route"] as? [String: Any],
              let choice = route["choice"] as? String,
              let confidence = route["confidence"] as? Double else {
            throw LocalModelError.badResponse
        }
        return RouteDecision(choice: choice, confidence: confidence)
    }

    static func result(for decision: RouteDecision) -> RouteResult {
        guard decision.confidence >= threshold, let route = Route(rawValue: decision.choice) else {
            return .unsure
        }
        return .routed(route)
    }

    func route(_ text: String, pageOpen: Bool) async throws -> RouteResult {
        let request = try decisionRequest(request: text, pageOpen: pageOpen)
        let (data, _) = try await URLSession.shared.data(for: request)
        return Self.result(for: try Self.decision(from: data))
    }
}
