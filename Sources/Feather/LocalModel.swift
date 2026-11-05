import Foundation

/// Where the local services are and which model answers (docs/AGENTIC.md). The file is optional:
/// without it, or with a broken one, the defaults are used.
struct ServicesConfig: Codable, Equatable {
    var ollama: String
    var model: String
    var pageCharacterLimit: Int

    init(ollama: String = "http://127.0.0.1:11434", model: String = "gemma3:1b", pageCharacterLimit: Int = 12_000) {
        self.ollama = ollama
        self.model = model
        self.pageCharacterLimit = pageCharacterLimit
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ServicesConfig()
        ollama = try values.decodeIfPresent(String.self, forKey: .ollama) ?? defaults.ollama
        model = try values.decodeIfPresent(String.self, forKey: .model) ?? defaults.model
        pageCharacterLimit = try values.decodeIfPresent(Int.self, forKey: .pageCharacterLimit) ?? defaults.pageCharacterLimit
    }

    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Feather/services.json")
    }

    static func load(from url: URL = fileURL) -> ServicesConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(ServicesConfig.self, from: data) else {
            return ServicesConfig()
        }
        return config
    }
}

enum LocalModelError: Error, Equatable, LocalizedError {
    case notLocalhost(String)
    case ollamaUnavailable
    case modelError(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notLocalhost(let address):
            return "Only this Mac is allowed as the model address; \(address) isn't."
        case .ollamaUnavailable:
            return "Ollama isn't running on this Mac. Start Ollama, then try again."
        case .modelError(let message):
            return "Ollama said: \(message)"
        case .badResponse:
            return "Ollama sent an answer Feather couldn't read."
        }
    }
}

/// Asks a local Ollama model about the page the user is reading. Everything stays on this Mac.
struct LocalModel {
    let config: ServicesConfig

    static let instructions = "You answer questions about a web page the user is reading. Use only the page text. If the answer isn't in the text, say so."

    func chatRequest(question: String, pageText: String) throws -> URLRequest {
        guard let base = URL(string: config.ollama), Self.isLocal(base) else {
            throw LocalModelError.notLocalhost(config.ollama)
        }
        var request = URLRequest(url: base.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let page = Self.clip(pageText, limit: config.pageCharacterLimit)
        let body: [String: Any] = [
            "model": config.model,
            "stream": false,
            "messages": [
                ["role": "system", "content": Self.instructions],
                ["role": "user", "content": "Page text:\n\(page)\n\nQuestion: \(question)"],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func ask(question: String, pageText: String) async throws -> String {
        let request = try chatRequest(question: question, pageText: pageText)
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .cannotConnectToHost {
            throw LocalModelError.ollamaUnavailable
        }
        return try Self.answer(from: data)
    }

    static func answer(from data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalModelError.badResponse
        }
        if let message = object["error"] as? String {
            throw LocalModelError.modelError(message)
        }
        guard let message = object["message"] as? [String: Any], let content = message["content"] as? String else {
            throw LocalModelError.badResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func clip(_ text: String, limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit))
    }

    static func isLocal(_ url: URL) -> Bool {
        ["127.0.0.1", "localhost", "::1"].contains(url.host ?? "")
    }
}
