import Foundation
import WebKit

/// Shared Swift-native bridge for the bundled Orcastrator/Research web UI (no runtime Python).
/// Handles /api/models, /api/chat (streaming), /api/research (SSE-like progress/report), /api/pull.
@MainActor
enum ResearchBridge {
    static let handlerName = "featheraResearch"

    static let bridgeJS: String = BrowserWindowController.researchBridgeJS // reuse script; defined below fallback not needed

    static func handle(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let id = body["id"] as? Int,
              let type = body["type"] as? String else { return }
        let webView = message.webView
        switch type {
        case "models":
            Task { let data = await researchModels(); push(to: webView, id: id, kind: "resolve", payload: data) }
        case "chat":
            let payload = body["body"] as? [String: Any] ?? [:]
            Task { await researchChat(id: id, webView: webView, body: payload) }
        case "research":
            let url = body["url"] as? String ?? ""
            Task { await researchRun(id: id, webView: webView, url: url) }
        case "pull", "pull_stream":
            let payload = body["body"] as? [String: Any] ?? [:]
            Task { await researchPull(id: id, webView: webView, body: payload) }
        case "research_close":
            break
        default:
            break
        }
    }

    nonisolated static func push(to webView: WKWebView?, id: Int, kind: String, payload: Any) {
        guard let webView else { return }
        let safePayload: Any
        if JSONSerialization.isValidJSONObject(payload) {
            safePayload = payload
        } else if let d = payload as? [String: Any] {
            safePayload = d.mapValues { v -> Any in
                if v is NSNull || v is String || v is NSNumber || v is Bool { return v }
                if JSONSerialization.isValidJSONObject(v) { return v }
                return String(describing: v)
            }
        } else {
            safePayload = ["value": String(describing: payload)]
        }
        let data = (try? JSONSerialization.data(withJSONObject: safePayload, options: []))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let escaped = data
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\r")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        let js = "window.__featheraResearchPush && window.__featheraResearchPush(\(id), '\(kind)', '\(escaped)')"
        DispatchQueue.main.async { webView.evaluateJavaScript(js, completionHandler: nil) }
    }

    nonisolated static func pushSSE(to webView: WKWebView?, id: Int, event: String, data: Any) {
        push(to: webView, id: id, kind: "sse", payload: ["event": event, "data": data])
    }

    static func researchModels() async -> [String: Any] {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else {
            return ["models": [], "cloud_models": [], "error": "bad ollama url"]
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                return ["models": [], "cloud_models": [], "error": "Could not reach Ollama at http://127.0.0.1:11434"]
            }
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = obj["models"] as? [[String: Any]] {
                let names = models.compactMap { ($0["name"] as? String) ?? ($0["model"] as? String) }
                return ["models": names, "cloud_models": [] as [String], "error": NSNull()]
            }
        } catch {
            return ["models": [], "cloud_models": [], "error": "Could not reach Ollama at http://127.0.0.1:11434: \(error.localizedDescription)"]
        }
        return ["models": [], "cloud_models": [], "error": "no models"]
    }

    static func researchChat(id: Int, webView: WKWebView?, body: [String: Any]) async {
        let model = (body["model"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "granite4:3b"
        let messages = body["messages"] as? [[String: Any]] ?? []
        guard let url = URL(string: "http://127.0.0.1:11434/api/chat") else {
            push(to: webView, id: id, kind: "reject", payload: ["message": "bad ollama url"])
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = TimeInterval((body["timeout"] as? Double) ?? (body["timeout"] as? Int).map(Double.init) ?? 300)
        let payload: [String: Any] = ["model": model, "messages": messages, "stream": true]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                push(to: webView, id: id, kind: "reject", payload: ["message": "Ollama chat error (is Ollama running / model available?)"])
                return
            }
            for try await line in bytes.lines {
                guard let d = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                if let err = obj["error"] as? String { push(to: webView, id: id, kind: "reject", payload: ["message": err]); return }
                if let msg = obj["message"] as? [String: Any], let content = msg["content"] as? String, !content.isEmpty {
                    push(to: webView, id: id, kind: "chat_chunk", payload: ["text": content])
                }
                if (obj["done"] as? Bool) == true { break }
            }
            push(to: webView, id: id, kind: "chat_done", payload: [:] as [String: Any])
        } catch {
            push(to: webView, id: id, kind: "reject", payload: ["message": error.localizedDescription])
        }
    }

    static func researchRun(id: Int, webView: WKWebView?, url urlString: String) async {
        guard let comps = URLComponents(string: urlString) else {
            pushSSE(to: webView, id: id, event: "error", data: "Invalid research URL"); return
        }
        func q(_ name: String) -> String? { comps.queryItems?.first(where: {$0.name==name})?.value }
        let topic = (q("topic") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty else { pushSSE(to: webView, id: id, event: "error", data: "Missing topic"); return }
        var model = (q("model") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if model.isEmpty { model = "granite4:3b" }
        // Enforce: never auto-select a 1B model.
        if model.range(of: #"(^|[^0-9])1b([^0-9]|$)"#, options: [.regularExpression, .caseInsensitive]) != nil { model = "granite4:3b" }
        let preset = (q("preset") ?? "fast").trimmingCharacters(in: .whitespacesAndNewlines)
        let useWeb = (q("use_web") ?? "true") != "false"
        let citations = (q("citations") ?? "true") != "false"
        let host = (q("host") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hostURL = host.isEmpty ? "http://127.0.0.1:11434" : host
        let timeout = TimeInterval(Int(q("timeout") ?? "") ?? 300)
        let retries = Int(q("retries") ?? "") ?? 1
        let sourcesRaw = (q("sources") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let enabledSources: [String]? = sourcesRaw.isEmpty ? nil : sourcesRaw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        let orch = StormOrchestrator(topic: topic, model: model, host: hostURL, preset: preset, useWeb: useWeb, inlineCitations: citations, enabledSources: enabledSources, timeout: max(30, timeout), retries: retries, sseID: id, webViewProvider: { [weak webView] in webView })
        await orch.run()
    }

    static func ollamaGenerate(model: String, prompt: String, timeout: TimeInterval) async -> (String, String?) {
        guard let url = URL(string: "http://127.0.0.1:11434/api/generate") else { return ("", "Bad Ollama URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeout
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "prompt": prompt, "stream": false])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if let err = obj?["error"] as? String, !err.isEmpty {
                if err.localizedCaseInsensitiveContains("not found") {
                    return ("", "Model '\(model)' is not installed in Ollama. Install it (e.g. `ollama pull \(model)`) or select another model.")
                }
                return ("", "Ollama error: \(err)")
            }
            guard status == 200, let response = obj?["response"] as? String else {
                return ("", "Could not reach Ollama or model '\(model)' unavailable (status \(status)). Is Ollama running?")
            }
            return (response, nil)
        } catch {
            return ("", "Could not reach Ollama at http://127.0.0.1:11434. Is Ollama running? \(error.localizedDescription)")
        }
    }

    static func basicWebContext(topic: String) async -> String {
        let q = topic.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? topic
        guard let url = URL(string: "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=\(q)&format=json&srlimit=3&utf8=1") else { return "" }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("FeatherA/1.0 (local research)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let query = obj["query"] as? [String: Any],
                  let search = query["search"] as? [[String: Any]], !search.isEmpty else { return "" }
            var lines: [String] = []
            for (i, item) in search.prefix(3).enumerated() {
                let title = (item["title"] as? String) ?? "Source"
                let snippet = ((item["snippet"] as? String) ?? "").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                let page = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
                lines.append("[\(i+1)] \(title) - https://en.wikipedia.org/wiki/\(page)\n\(snippet)")
            }
            return lines.joined(separator: "\n\n")
        } catch { return "" }
    }

    static func researchPull(id: Int, webView: WKWebView?, body: [String: Any]) async {
        var names: [String] = []
        if let n = body["name"] as? String, !n.isEmpty { names = [n] }
        if let arr = body["names"] as? [String] { names = arr.filter { !$0.isEmpty } }
        if names.isEmpty { names = ["tev1:0.8b", "granite4:3b"] }
        if let vurl = URL(string: "http://127.0.0.1:11434/api/version") {
            var vreq = URLRequest(url: vurl); vreq.timeoutInterval = 2
            if (try? await URLSession.shared.data(for: vreq)) == nil {
                push(to: webView, id: id, kind: "pull_err", payload: ["message": "Ollama is not running. Start Ollama, then press Pull again. (Run scripts/setup.sh for non-admin setup + auto-pull.)"])
                return
            }
        }
        for (idx, name) in names.enumerated() {
            push(to: webView, id: id, kind: "pull_progress", payload: ["status": "Pulling \(name) (\(idx+1)/\(names.count))…"])
            let err = await ollamaPullModel(name: name, webView: webView, id: id)
            if let err {
                push(to: webView, id: id, kind: "pull_err", payload: ["message": "Failed pulling \(name): \(err)"])
                return
            }
        }
        push(to: webView, id: id, kind: "pull_done", payload: ["status": "Done: pulled \(names.joined(separator: ", "))"])
    }

    static func ollamaPullModel(name: String, webView: WKWebView?, id: Int) async -> String? {
        guard let url = URL(string: "http://127.0.0.1:11434/api/pull") else { return "Bad Ollama URL" }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 7200
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name, "stream": true])
        do {
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status != 200 {
                for try await line in bytes.lines.prefix(2) {
                    if let d = line.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let e = obj["error"] as? String { return e }
                }
                return "Ollama returned status \(status). Is Ollama running?"
            }
            for try await line in bytes.lines {
                guard let d = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                if let e = obj["error"] as? String, !e.isEmpty { return e }
                let st = (obj["status"] as? String) ?? "pulling…"
                if let completed = obj["completed"] as? Double, let total = obj["total"] as? Double, total > 0 {
                    let pct = Int((completed / total) * 100)
                    let mb = Int(completed / 1_048_576), mbt = Int(total / 1_048_576)
                    push(to: webView, id: id, kind: "pull_progress", payload: ["status": "\(name): \(st) (\(pct)% • \(mb)/\(mbt) MB)"])
                } else {
                    push(to: webView, id: id, kind: "pull_progress", payload: ["status": "\(name): \(st)"])
                }
                if st == "success" { break }
            }
            return nil
        } catch {
            return "Could not reach Ollama (is it running?). \(error.localizedDescription)"
        }
    }
}
