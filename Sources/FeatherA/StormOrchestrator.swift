import Foundation
import WebKit

// MARK: - Full STORM multi-agent research pipeline (Swift-native, no runtime Python).
// Parity target: Orcastrator orchestrator/agents/retrieval semantics + UI SSE progress protocol.

struct StormSource: Codable {
    var title: String
    var url: String
    var content: String
    var verified: Bool
}

enum StormPresets {
    struct Config {
        var maxQuestions: Int
        var useCritic: Bool
        var answerTokens: Int? // nil = unlimited
        var extended: Bool
    }
    static func config(preset: String) -> Config {
        switch preset {
        case "fast": return .init(maxQuestions: 4, useCritic: false, answerTokens: 300, extended: false)
        case "balanced": return .init(maxQuestions: 6, useCritic: true, answerTokens: 500, extended: false)
        case "thorough": return .init(maxQuestions: 10, useCritic: true, answerTokens: nil, extended: false)
        case "extended": return .init(maxQuestions: 8, useCritic: true, answerTokens: 600, extended: true)
        default: return .init(maxQuestions: 6, useCritic: true, answerTokens: 500, extended: false)
        }
    }
}

enum StormText {
    static let writerCharBudget = 12_000
    static let extractChars = 2500
    static let maxRevisions = 1

    static func parseQuestions(_ raw: String) -> [String] {
        var out: [String] = []
        for lineSub in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(lineSub).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            line = line.replacingOccurrences(of: "^[\\d]+[.)]\\s*", with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: "^[-*]\\s*", with: "", options: .regularExpression)
            if !line.isEmpty { out.append(line) }
        }
        return out
    }

    static func sourcesBlock(_ sources: [StormSource]) -> String {
        sources.enumerated().map { i, s in "[\(i+1)] \(s.title) (\(s.url)):\n\(s.content)" }.joined(separator: "\n\n")
    }

    static func renumberCitations(_ text: String, offset: Int, nSources: Int) -> String {
        guard let re = try? NSRegularExpression(pattern: "\\[(\\d+)\\]") else { return text }
        let ns = text as NSString
        var result = text
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed()
        for m in matches {
            guard m.numberOfRanges >= 2 else { continue }
            let k = Int(ns.substring(with: m.range(at: 1))) ?? 0
            if k >= 1 && k <= nSources {
                let rep = "[\(k + offset)]"
                result = (result as NSString).replacingCharacters(in: m.range, with: rep)
            }
        }
        return result
    }

    static func linkifyCitations(_ text: String, references: [StormSource]) -> String {
        guard let re = try? NSRegularExpression(pattern: "\\[(\\d+)\\]") else { return text }
        let ns = text as NSString
        var result = text
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed()
        for m in matches {
            guard m.numberOfRanges >= 2 else { continue }
            let k = Int(ns.substring(with: m.range(at: 1))) ?? 0
            if k >= 1 && k <= references.count {
                let url = references[k - 1].url
                let rep = "[[\(k)]](\(url))"
                result = (result as NSString).replacingCharacters(in: m.range, with: rep)
            }
        }
        return result
    }

    static func stripCitations(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s*\\[\\d+\\]", with: "", options: .regularExpression)
    }

    static func budgetSections(_ sections: [String], budget: Int = writerCharBudget) -> String {
        let joined = sections.joined(separator: "\n\n")
        if joined.count <= budget { return joined }
        // Proportional truncation (simple but effective).
        let per = max(200, budget / max(1, sections.count) - 50)
        return sections.map { s in
            if s.count <= per { return s }
            let idx = s.index(s.startIndex, offsetBy: per)
            let cut = String(s[..<idx])
            if let sp = cut.lastIndex(of: " ") { return String(cut[..<sp]) + " […]" }
            return cut + " […]"
        }.joined(separator: "\n\n")
    }

    static func cleanStockQuery(_ query: String) -> String {
        let filler: Set<String> = ["what","whats","how","much","is","are","the","a","an","current","currently","latest","today","todays","right","now","please","stock","stocks","share","shares","price","prices","of","for","trading","at","value","doing","on","market","quote","quotes","worth","cost","costs","and","in","to","does"]
        let stripped = query.replacingOccurrences(of: "[?!.,]", with: "", options: .regularExpression).replacingOccurrences(of: "’", with: "'")
        let kept = stripped.split(separator: " ").compactMap { tok -> String? in
            var bare = String(tok)
            if bare.lowercased().hasSuffix("'s") { bare = String(bare.dropLast(2)) }
            return filler.contains(bare.lowercased()) ? nil : bare
        }
        return kept.isEmpty ? query : kept.joined(separator: " ")
    }

    static func stripHTML(_ text: String) -> String {
        let noTags = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return noTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func truncateExtract(_ text: String, limit: Int = extractChars) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= limit { return t }
        let idx = t.index(t.startIndex, offsetBy: limit)
        let cut = String(t[..<idx])
        if let sp = cut.lastIndex(of: " ") { return String(cut[..<sp]) + " […]" }
        return cut + " […]"
    }
}

// MARK: - Ollama agent

struct StormAgent {
    var role: String
    var systemPrompt: String
    var model: String
    var host: String = "http://127.0.0.1:11434"
    var retries: Int = 1
    var numPredict: Int?
    var think: Bool? // nil = default; false disables hidden reasoning on thinking models
    var timeout: TimeInterval = 300

    func generate(_ prompt: String) async throws -> String {
        var lastErr: Error?
        let attempts = max(1, retries + 1)
        for attempt in 0..<attempts {
            do {
                return try await call(prompt: prompt)
            } catch {
                lastErr = error
                if attempt + 1 < attempts {
                    let delay = UInt64(pow(2.0, Double(attempt)) * 500_000_000) // 0.5s,1s
                    try? await Task.sleep(nanoseconds: delay)
                    continue
                }
            }
        }
        throw lastErr ?? NSError(domain: "StormAgent", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(role) failed"])
    }

    private func call(prompt: String) async throws -> String {
        guard let url = URL(string: host + "/api/generate") else { throw NSError(domain: "StormAgent", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bad Ollama URL"]) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeout
        var body: [String: Any] = ["model": model, "system": systemPrompt, "prompt": prompt, "stream": false]
        var options: [String: Any] = [:]
        if let np = numPredict { options["num_predict"] = np }
        if !options.isEmpty { body["options"] = options }
        if let think { body["think"] = think }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let err = obj?["error"] as? String, !err.isEmpty { throw NSError(domain: "Ollama", code: status, userInfo: [NSLocalizedDescriptionKey: err]) }
        guard status == 200 else { throw NSError(domain: "Ollama", code: status, userInfo: [NSLocalizedDescriptionKey: "HTTP \(status)"]) }
        var text = (obj?["response"] as? String) ?? ""
        // If a thinking model spent its budget in hidden reasoning and returned empty, retry once uncapped without think.
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (numPredict != nil || think == false) {
            var body2 = body; body2.removeValue(forKey: "options"); body2["think"] = false
            req.httpBody = try? JSONSerialization.data(withJSONObject: body2)
            if let (d2, r2) = try? await URLSession.shared.data(for: req), (r2 as? HTTPURLResponse)?.statusCode == 200,
               let o2 = (try? JSONSerialization.jsonObject(with: d2)) as? [String: Any], let t2 = o2["response"] as? String, !t2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = t2
            }
        }
        return text
    }
}

// MARK: - Retrieval engines

protocol StormRetrievalEngine {
    var name: String { get }
    func search(query: String) async -> [StormSource]
}

enum StormHTTP {
    static let ua = "FeatherA-Orcastrator/1.0 (local research)"
    static func client(timeout: TimeInterval = 15) -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }
    static func getJSON(session: URLSession, url: String, headers: [String: String] = [:]) async -> Any? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        for (k,v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        guard let (data, resp) = try? await session.data(for: req), (resp as? HTTPURLResponse).map({(200..<400).contains($0.statusCode)}) ?? false else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
    static func getText(session: URLSession, url: String, headers: [String: String] = [:]) async -> String? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        for (k,v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        guard let (data, resp) = try? await session.data(for: req), (resp as? HTTPURLResponse).map({(200..<400).contains($0.statusCode)}) ?? false else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
    static func alive(session: URLSession, url: String) async -> Bool {
        guard let u = URL(string: url) else { return false }
        var req = URLRequest(url: u); req.httpMethod = "HEAD"; req.timeoutInterval = 6
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        do {
            let (_, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return code < 400 || code == 405
        } catch { return false }
    }
}

struct WikipediaEngine: StormRetrievalEngine {
    let name = "wikipedia"
    func search(query: String) async -> [StormSource] {
        let session = StormHTTP.client(timeout: 15)
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        // Use search REST to get keys/ids, then extracts via action API (exintro, batched)
        guard let searchObj = await StormHTTP.getJSON(session: session, url: "https://en.wikipedia.org/w/rest.php/v1/search/page?q=\(q)&limit=3") as? [String: Any],
              let pages = searchObj["pages"] as? [[String: Any]], !pages.isEmpty else { return [] }
        let ids = pages.compactMap { $0["id"] as? Int }
        guard !ids.isEmpty else { return [] }
        let idStr = ids.map(String.init).joined(separator: "|")
        guard let exObj = await StormHTTP.getJSON(session: session, url: "https://en.wikipedia.org/w/api.php?action=query&prop=extracts&explaintext=1&exintro=1&exlimit=max&format=json&pageids=\(idStr)") as? [String: Any],
              let query = exObj["query"] as? [String: Any], let pageMap = query["pages"] as? [String: Any] else { return [] }
        var extracts: [String: String] = [:]
        for (pid, pv) in pageMap {
            if let p = pv as? [String: Any], let ex = (p["extract"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !ex.isEmpty {
                extracts[pid] = StormText.truncateExtract(ex)
            }
        }
        var out: [StormSource] = []
        for p in pages {
            guard let id = p["id"] as? Int, let key = p["key"] as? String, let content = extracts[String(id)] else { continue }
            let title = (p["title"] as? String) ?? key
            let page = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
            out.append(StormSource(title: title, url: "https://en.wikipedia.org/wiki/\(page)", content: content, verified: true))
        }
        return out
    }
}

struct OpenAlexEngine: StormRetrievalEngine {
    let name = "openalex"
    func search(query: String) async -> [StormSource] {
        let session = StormHTTP.client(timeout: 15)
        let clean = query.replacingOccurrences(of: "[^\\w\\s]", with: " ", options: .regularExpression).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        let q = clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clean
        guard let obj = await StormHTTP.getJSON(session: session, url: "https://api.openalex.org/works?search=\(q)&per-page=2&filter=has_abstract:true") as? [String: Any],
              let works = obj["results"] as? [[String: Any]] else { return [] }
        var out: [StormSource] = []
        for w in works {
            var abstract = ""
            if let inv = w["abstract_inverted_index"] as? [String: [Int]] {
                var slots: [Int: String] = [:]
                for (word, positions) in inv { for pos in positions { slots[pos] = word } }
                abstract = slots.keys.sorted().compactMap { slots[$0] }.joined(separator: " ")
            }
            if abstract.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            abstract = StormText.truncateExtract(abstract)
            var url = (w["doi"] as? String) ?? (w["id"] as? String)
            if url == nil { continue }
            if !(await StormHTTP.alive(session: session, url: url!)) { url = w["id"] as? String }
            guard let finalURL = url, await StormHTTP.alive(session: session, url: finalURL) else { continue }
            var title = (w["title"] as? String) ?? "Untitled"
            if let year = w["publication_year"] { title = "\(title) (\(year))" }
            out.append(StormSource(title: title, url: finalURL, content: abstract, verified: true))
        }
        return out
    }
}

struct InstantAnswerEngine: StormRetrievalEngine {
    let name = "instant"
    func search(query: String) async -> [StormSource] {
        let session = StormHTTP.client(timeout: 10)
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let obj = await StormHTTP.getJSON(session: session, url: "https://api.duckduckgo.com/?q=\(q)&format=json&no_html=1&skip_disambig=1") as? [String: Any],
              let text = obj["AbstractText"] as? String, !text.isEmpty,
              let url = obj["AbstractURL"] as? String, !url.isEmpty else { return [] }
        guard await StormHTTP.alive(session: session, url: url) else { return [] }
        var title = (obj["Heading"] as? String) ?? "Instant answer"
        if let src = obj["AbstractSource"] as? String, !src.isEmpty { title = "\(title) — \(src)" }
        return [StormSource(title: title, url: url, content: StormText.truncateExtract(text), verified: true)]
    }
}

struct DDGWebEngine: StormRetrievalEngine {
    let name = "ddg"
    func search(query: String) async -> [StormSource] {
        let session = StormHTTP.client(timeout: 15)
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let html = await StormHTTP.getText(session: session, url: "https://html.duckduckgo.com/html/?q=\(q)") else { return [] }
        // Parse result blocks roughly (HTML structure can change; best-effort).
        var out: [StormSource] = []
        let parts = html.components(separatedBy: "class=\"result__a\"")
        for block in parts.dropFirst() {
            if out.count >= 3 { break }
            guard let hrefRange = block.range(of: "href=\"([^\"]+)\"", options: .regularExpression) else { continue }
            let hrefMatch = String(block[hrefRange])
            let href = hrefMatch.replacingOccurrences(of: "href=\"", with: "").replacingOccurrences(of: "\"", with: "")
            var realURL: String? = nil
            if href.contains("uddg="), let comps = URLComponents(string: "https://x\(href.hasPrefix("/") ? href : "/"+href)"), let uddg = comps.queryItems?.first(where: {$0.name=="uddg"})?.value {
                realURL = uddg.removingPercentEncoding ?? uddg
            }
            guard let url = realURL, !url.isEmpty else { continue }
            var title = url
            if let tRange = block.range(of: ">(.*?)</a>", options: .regularExpression) {
                title = StormText.stripHTML(String(block[tRange]).replacingOccurrences(of: ">", with: "", options: []).replacingOccurrences(of: "</a>", with: "", options: []))
            }
            var snippet = ""
            if let sRange = block.range(of: "class=\"result__snippet\"[^>]*>(.*?)(?:</a>|</td>)", options: [.regularExpression, .caseInsensitive]) {
                snippet = StormText.stripHTML(String(block[sRange]))
            }
            guard await StormHTTP.alive(session: session, url: url) else { continue }
            out.append(StormSource(title: title.isEmpty ? url : title, url: url, content: StormText.truncateExtract(snippet.isEmpty ? title : snippet), verified: true))
        }
        return out
    }
}

struct ArxivEngine: StormRetrievalEngine {
    let name = "arxiv"
    func search(query: String) async -> [StormSource] {
        let session = StormHTTP.client(timeout: 15)
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let xml = await StormHTTP.getText(session: session, url: "http://export.arxiv.org/api/query?search_query=all:\(q)&start=0&max_results=2") else { return [] }
        // Minimal Atom parsing via regex (no XMLParser dependency hassle in a quick implementation).
        var out: [StormSource] = []
        let entries = xml.components(separatedBy: "<entry>")
        for entry in entries.dropFirst() {
            func tag(_ name: String) -> String {
                guard let r = entry.range(of: "<\(name)[^>]*>([\\s\\S]*?)</\(name)>", options: .regularExpression) else { return "" }
                let raw = String(entry[r])
                return StormText.stripHTML(raw.replacingOccurrences(of: "<\(name)[^>]*>", with: "", options: .regularExpression).replacingOccurrences(of: "</\(name)>", with: ""))
            }
            let title = tag("title").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = StormText.truncateExtract(tag("summary").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression))
            let id = tag("id")
            if title.isEmpty || id.isEmpty { continue }
            out.append(StormSource(title: title, url: id, content: summary, verified: true))
        }
        return out
    }
}

struct SemanticScholarEngine: StormRetrievalEngine {
    let name = "s2"
    func search(query: String) async -> [StormSource] {
        let session = StormHTTP.client(timeout: 15)
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = "https://api.semanticscholar.org/graph/v1/paper/search?query=\(q)&limit=2&fields=title,abstract,url,year,paperId"
        for attempt in 0..<3 {
            guard let u = URL(string: url) else { return [] }
            var req = URLRequest(url: u); req.setValue(StormHTTP.ua, forHTTPHeaderField: "User-Agent")
            guard let (data, resp) = try? await session.data(for: req) else { return [] }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 429 { try? await Task.sleep(nanoseconds: UInt64((min(2.0 * Double(attempt), 10.0)) * 1_000_000_000)); continue }
            if code >= 500 { return [] }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let papers = obj["data"] as? [[String: Any]] else { return [] }
            var out: [StormSource] = []
            for p in papers {
                var title = (p["title"] as? String) ?? "Untitled"
                guard let abstract = (p["abstract"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !abstract.isEmpty else { continue }
                let url = (p["url"] as? String) ?? ((p["paperId"] as? String).map { "https://www.semanticscholar.org/paper/\($0)" })
                guard let finalURL = url else { continue }
                if let year = p["year"] { title = "\(title) (\(year))" }
                out.append(StormSource(title: title, url: finalURL, content: StormText.truncateExtract(abstract), verified: true))
            }
            return out
        }
        return []
    }
}

struct StackExchangeEngine: StormRetrievalEngine {
    let name = "stackex"
    func search(query: String) async -> [StormSource] {
        let session = StormHTTP.client(timeout: 15)
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let obj = await StormHTTP.getJSON(session: session, url: "https://api.stackexchange.com/2.3/search/advanced?order=desc&sort=relevance&site=stackoverflow&q=\(q)&pagesize=2") as? [String: Any],
              let items = obj["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let title = (item["title"] as? String).map(StormText.stripHTML), !title.isEmpty, let link = item["link"] as? String else { return nil }
            let excerpt = StormText.stripHTML((item["excerpt"] as? String) ?? "")
            return StormSource(title: title, url: link, content: StormText.truncateExtract(excerpt.isEmpty ? title : excerpt), verified: true)
        }
    }
}

struct HackerNewsEngine: StormRetrievalEngine {
    let name = "hn"
    func search(query: String) async -> [StormSource] {
        let session = StormHTTP.client(timeout: 15)
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let obj = await StormHTTP.getJSON(session: session, url: "https://hn.algolia.com/api/v1/search?query=\(q)&tags=story&hitsPerPage=2") as? [String: Any],
              let hits = obj["hits"] as? [[String: Any]] else { return [] }
        return hits.compactMap { hit in
            guard let title = (hit["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                  let url = hit["url"] as? String, !url.isEmpty else { return nil }
            let body = StormText.stripHTML((hit["story_text"] as? String) ?? "")
            return StormSource(title: title, url: url, content: StormText.truncateExtract(body.isEmpty ? title : body), verified: true)
        }
    }
}

struct StockQuoteEngine: StormRetrievalEngine {
    let name = "stock"
    func search(query: String) async -> [StormSource] {
        let session = StormHTTP.client(timeout: 10)
        let cleaned = StormText.cleanStockQuery(query)
        let q = cleaned.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleaned
        guard let sobj = await StormHTTP.getJSON(session: session, url: "https://query1.finance.yahoo.com/v1/finance/search?q=\(q)") as? [String: Any],
              let quotes = sobj["quotes"] as? [[String: Any]] else { return [] }
        let okTypes: Set<String> = ["EQUITY","ETF","INDEX","CRYPTOCURRENCY","MUTUALFUND","CURRENCY"]
        guard let match = quotes.first(where: { okTypes.contains(($0["quoteType"] as? String) ?? "") }),
              let symbol = match["symbol"] as? String else { return [] }
        guard let cobj = await StormHTTP.getJSON(session: session, url: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)") as? [String: Any],
              let chart = cobj["chart"] as? [String: Any], let result = (chart["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any], let price = meta["regularMarketPrice"] else { return [] }
        let name = (match["longname"] as? String) ?? (match["shortname"] as? String) ?? symbol
        let currency = (meta["currency"] as? String) ?? ""
        var asOf = "unknown time"
        if let t = meta["regularMarketTime"] as? Double {
            let d = Date(timeIntervalSince1970: t)
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"; f.timeZone = TimeZone(secondsFromGMT: 0)
            asOf = f.string(from: d)
        }
        var parts = ["\(name) (\(symbol)): \(price) \(currency) as of \(asOf)."]
        if let lo = meta["regularMarketDayLow"], let hi = meta["regularMarketDayHigh"] { parts.append("Day range: \(lo)-\(hi).") }
        if let pc = meta["previousClose"] { parts.append("Previous close: \(pc).") }
        return [StormSource(title: "\(name) (\(symbol)) stock quote", url: "https://finance.yahoo.com/quote/\(symbol)", content: parts.joined(separator: " "), verified: true)]
    }
}

struct StormMultiRetriever {
    static let allEngines = ["wikipedia","openalex","instant","ddg","stock","arxiv","s2","stackex","hn"]
    static let maxSources = 5
    var enabled: [String]
    init(enabled: [String]? = nil) {
        let list = enabled?.filter { !$0.isEmpty } ?? Self.allEngines
        self.enabled = list.isEmpty ? Self.allEngines : list
    }
    func makeEngines() -> [StormRetrievalEngine] {
        enabled.compactMap { name in
            switch name {
            case "wikipedia": return WikipediaEngine()
            case "openalex": return OpenAlexEngine()
            case "instant": return InstantAnswerEngine()
            case "ddg": return DDGWebEngine()
            case "stock": return StockQuoteEngine()
            case "arxiv": return ArxivEngine()
            case "s2": return SemanticScholarEngine()
            case "stackex": return StackExchangeEngine()
            case "hn": return HackerNewsEngine()
            default: return nil
            }
        }
    }
    func search(query: String) async -> [StormSource] {
        let engines = makeEngines()
        if engines.isEmpty { return [] }
        var groups: [[StormSource]] = Array(repeating: [], count: engines.count)
        await withTaskGroup(of: (Int, [StormSource]).self) { group in
            for (i, e) in engines.enumerated() {
                group.addTask { (i, await e.search(query: query)) }
            }
            for await (i, res) in group { groups[i] = res }
        }
        // Round-robin merge, dedup by URL.
        var merged: [StormSource] = []
        var seen: Set<String> = []
        let maxLen = groups.map(\.count).max() ?? 0
        for round in 0..<maxLen {
            for g in groups {
                if round >= g.count { continue }
                let s = g[round]
                if seen.contains(s.url) { continue }
                seen.insert(s.url)
                merged.append(s)
                if merged.count >= Self.maxSources { return merged }
            }
        }
        return merged
    }
}

// MARK: - Orchestrator

final class StormOrchestrator {
    let topic: String
    let model: String
    let host: String
    let preset: String
    let useWeb: Bool
    let inlineCitations: Bool
    let enabledSources: [String]?
    let timeout: TimeInterval
    let retries: Int
    let weakWebView: () -> WKWebView?
    let sseID: Int

    private let cfg: StormPresets.Config
    private var stateQuestions: [String] = []
    private var stateSources: [[StormSource]] = []

    init(topic: String, model: String, host: String = "http://127.0.0.1:11434", preset: String, useWeb: Bool, inlineCitations: Bool, enabledSources: [String]?, timeout: TimeInterval, retries: Int, sseID: Int, webViewProvider: @escaping () -> WKWebView?) {
        self.topic = topic
        self.model = model.isEmpty ? "granite4:3b" : model
        self.host = host
        self.preset = preset
        self.cfg = StormPresets.config(preset: preset)
        self.useWeb = useWeb
        self.inlineCitations = inlineCitations
        self.enabledSources = enabledSources
        self.timeout = timeout
        self.retries = max(0, retries)
        self.sseID = sseID
        self.weakWebView = webViewProvider
    }

    private func pushProgress(_ data: Any) {
        ResearchBridge.pushSSE(to: weakWebView(), id: sseID, event: "progress", data: data)
    }
    private func emit(_ kind: String, _ message: String, extra: [String: Any] = [:]) {
        var d: [String: Any] = ["kind": kind, "message": message]
        for (k,v) in extra { d[k]=v }
        pushProgress(d)
    }
    private func log(_ message: String) { pushProgress(message) }
    private func err(_ message: String) { ResearchBridge.pushSSE(to: weakWebView(), id: sseID, event: "error", data: message) }
    private func report(_ text: String) { ResearchBridge.pushSSE(to: weakWebView(), id: sseID, event: "report", data: text) }

    private func makeAgent(role: String, system: String, numPredict: Int? = nil, think: Bool? = false) -> StormAgent {
        StormAgent(role: role, systemPrompt: system, model: model, host: host, retries: retries, numPredict: numPredict, think: think, timeout: timeout)
    }

    func run() async {
        let t0 = Date()
        // Verify Ollama
        if let vurl = URL(string: host + "/api/version") {
            var req = URLRequest(url: vurl); req.timeoutInterval = 4
            if (try? await URLSession.shared.data(for: req)) == nil {
                err("Could not reach Ollama at \(host). Is Ollama running? (scripts/setup.sh can install/start it.)")
                return
            }
        }

        // Announce stages (extended = 5 stages).
        var stagePlan: [[String: String]] = [["key":"planning","label":"Plan"],["key":"researching","label":"Research"]]
        if cfg.extended {
            stagePlan += [["key":"drafting","label":"Draft"],["key":"reviewing","label":"Review"],["key":"rewriting","label":"Rewrite"]]
        } else {
            stagePlan += [["key":"writing","label":"Write"]]
        }
        emit("stage", "Breaking '\(topic)' into research questions…", extra: ["stage":"planning","stages":stagePlan])
        log("STORM multi-agent (Swift-native, no Python) • model=\(model) • preset=\(preset)\(cfg.extended ? " (extended)" : "") • web=\(useWeb) • citations=\(inlineCitations)")

        // Planner
        let planner = makeAgent(role: "Planner", system: "Break a topic into 3-10 clear, specific research questions. Return a numbered list only.")
        var planRaw: String
        do { planRaw = try await planner.generate("Break down the topic: \(topic)") }
        catch { err("Planning failed: \(error.localizedDescription). Is model '\(model)' available in Ollama?"); return }
        var questions = StormText.parseQuestions(planRaw)
        if questions.isEmpty { err("Planner returned no research questions. Try a clearer topic or a different model."); return }
        if questions.count > cfg.maxQuestions { questions = Array(questions.prefix(cfg.maxQuestions)) }
        stateQuestions = questions

        // Concurrency (conservative default; local Ollama benefits from modest fan-out)
        let concurrency = max(1, min(4, questions.count))
        let criticNote = cfg.useCritic ? " (each answered, then reviewed by the critic)" : ""
        emit("stage", "Researching \(questions.count) questions\(criticNote)…", extra: ["stage":"researching","questions":questions,"use_critic":cfg.useCritic])
        emit("info", "Running \(concurrency) research task\(concurrency>1 ? "s":"") at a time")

        let researcher = makeAgent(role: "Researcher", system: "You are an expert research analyst. Give thorough, factual, well-structured answers.", numPredict: cfg.answerTokens)
        let critic = makeAgent(role: "Critic", system: "Evaluate a research answer for accuracy, completeness, and clarity. Reply with 'APPROVED: <refined answer>' if the answer is good, or 'REVISE: <reason>' if the researcher should try again.", numPredict: cfg.answerTokens)
        let writer = makeAgent(role: "Writer", system: "Synthesize validated research into a cohesive, structured, Wikipedia-style article with clear headings.")
        let challenger = makeAgent(role: "Critic", system: "Cross-examine a research answer: name its 2-3 weakest claims, missing perspectives, or likely errors, briefly and specifically. Do not rewrite the answer yourself.", numPredict: cfg.answerTokens)
        let reviewer = makeAgent(role: "Reviewing Editor", system: "Review a draft report for factual gaps, contradictions, redundancy, and unclear structure. Reply with a short numbered list of concrete improvements. Do not rewrite the report yourself.")

        // Parallel bounded research (each returns answer + sources for its index)
        var results: [String?] = Array(repeating: nil, count: questions.count)
        var allSources: [[StormSource]] = Array(repeating: [], count: questions.count)
        let retriever = useWeb ? StormMultiRetriever(enabled: enabledSources) : nil
        await withTaskGroup(of: (Int, String, [StormSource]).self) { group in
            var next = 0
            func submit(_ i: Int) {
                let q = questions[i]
                group.addTask { [self] in
                    let (ans, srcs) = await self.researchAndValidate(index: i, question: q, retriever: retriever, researcher: researcher, critic: critic, challenger: challenger)
                    return (i, ans, srcs)
                }
            }
            while next < min(concurrency, questions.count) { submit(next); next += 1 }
            while let (i, ans, srcs) = await group.next() {
                results[i] = ans
                allSources[i] = srcs
                if next < questions.count { submit(next); next += 1 }
            }
        }

        // Merge citations / sections
        var references: [StormSource] = []
        var sections: [String] = []
        for i in 0..<questions.count {
            let q = questions[i]
            var res = results[i] ?? "[unverified] No answer produced."
            let srcs = allSources[i]
            if !srcs.isEmpty {
                res = StormText.renumberCitations(res, offset: references.count, nSources: srcs.count)
                references.append(contentsOf: srcs)
            } else if useWeb {
                res += "\n\n*(No sources found — this section is unsourced model knowledge.)*"
            }
            sections.append("## \(q)\n\(res)")
        }
        let combined = StormText.budgetSections(sections)
        var referencesMD = ""
        if !references.isEmpty {
            let lines = references.enumerated().map { i, s in "- [\(i+1)] [\(s.title)](\(s.url))" }.joined(separator: "\n")
            referencesMD = "\n\n## References\n*All links were fetched and verified while researching this report.*\n\n\(lines)"
        }
        func finalize(_ body: String) -> String {
            var b = body
            if !references.isEmpty { b = inlineCitations ? StormText.linkifyCitations(b, references: references) : StormText.stripCitations(b) }
            return b + referencesMD
        }

        let doneNote = cfg.useCritic ? "All research validated" : "Research complete"
        let citeNote = references.isEmpty ? "" : " Keep the citation markers like [1] exactly where they support each claim. Do NOT write your own references, sources, or bibliography section — a verified References list is appended automatically."
        let draftPrompt = "Write a structured report on '\(topic)' using this validated research.\(citeNote)\n\n\(combined)"

        if !cfg.extended {
            emit("stage", "\(doneNote) — writing the final report…", extra: ["stage":"writing"])
            do {
                let out = try await writer.generate(draftPrompt)
                let final = finalize(out)
                let secs = Int(Date().timeIntervalSince(t0))
                log("Done in \(secs)s — report ready.")
                report(final)
            } catch { err("Writing failed: \(error.localizedDescription)") }
            return
        }

        // Extended: draft -> review -> rewrite
        emit("stage", "\(doneNote) — writing the first draft…", extra: ["stage":"drafting"])
        let draft: String
        do { draft = try await writer.generate(draftPrompt) } catch { err("Drafting failed: \(error.localizedDescription)"); return }

        emit("stage", "Draft complete — reviewing editor checking for gaps and contradictions…", extra: ["stage":"reviewing"])
        let feedback: String
        do { feedback = try await reviewer.generate("Review this draft report on '\(topic)':\n\n\(draft)") } catch { err("Review failed: \(error.localizedDescription)"); return }

        emit("stage", "Review complete — rewriting the final report…", extra: ["stage":"rewriting"])
        do {
            let out = try await writer.generate("Improve this draft report on '\(topic)' by applying the reviewer's feedback. Keep clear headings and output only the final report.\(citeNote)\n\nDraft:\n\(draft)\n\nReviewer feedback:\n\(feedback)")
            let final = finalize(out)
            let secs = Int(Date().timeIntervalSince(t0))
            log("Done in \(secs)s (extended) — report ready.")
            report(final)
        } catch { err("Rewrite failed: \(error.localizedDescription)") }
    }

    private func researchAndValidate(index: Int, question: String, retriever: StormMultiRetriever?, researcher: StormAgent, critic: StormAgent, challenger: StormAgent) async -> (String, [StormSource]) {
        func qstat(_ status: String, _ message: String) { emit("question", message, extra: ["index": index, "status": status]) }
        var sources: [StormSource] = []
        if let retriever {
            qstat("searching", "Searching the web: \(question)")
            sources = await retriever.search(query: question)
            if !sources.isEmpty { emit("info", "Found \(sources.count) verified sources for: \(question)") }
            else { emit("info", "No sources found for: \(question) — answering from model knowledge (unsourced)") }
        }

        let grounding: String
        if !sources.isEmpty {
            grounding = "\n\nAnswer using ONLY the numbered sources below. Cite the supporting source after each factual claim, like [1] or [2]. If the sources don't cover part of the question, say what's missing instead of guessing.\n\nSOURCES:\n" + StormText.sourcesBlock(sources)
        } else { grounding = "" }

        qstat("researching", "Researching: \(question)")
        var answer: String
        do { answer = try await researcher.generate("\(question)\(grounding)") } catch { qstat("unverified", "Research failed: \(question)"); return ("[unverified] \(error.localizedDescription)", sources) }

        if cfg.extended {
            qstat("challenging", "Critic challenging: \(question)")
            if let challenge = try? await challenger.generate("Question: \(question)\nAnswer: \(answer)") {
                qstat("rebutting", "Researcher rebutting: \(question)")
                if let improved = try? await researcher.generate("\(question)\n\nYour answer was:\n\(answer)\n\nA critic raised these challenges:\n\(challenge)\n\nWrite an improved answer that addresses each challenge — correct anything wrong, fill the gaps, and keep what holds up.\(grounding)") {
                    answer = improved
                }
            }
        }

        if !cfg.useCritic {
            qstat("done", "Researched: \(question)")
            return (answer, sources)
        }

        qstat("reviewing", "Critic reviewing: \(question)")
        let criticContext = sources.isEmpty ? "" : "\nSOURCES:\n" + StormText.sourcesBlock(sources)
        for _ in 0...(StormText.maxRevisions) {
            do {
                let verdict = try await critic.generate("Question: \(question)\(criticContext)\nAnswer: \(answer)")
                if verdict.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("APPROVED") {
                    qstat("approved", "Critic approved: \(question)")
                    if let colon = verdict.firstIndex(of: ":") {
                        let refined = String(verdict[verdict.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        return (refined.isEmpty ? answer : refined, sources)
                    }
                    return (answer, sources)
                }
                qstat("revising", "Critic requested a revision: \(question)")
                if let revised = try? await researcher.generate("\(question)\n\nYour previous answer was rejected for this reason: \(verdict)\nProvide a corrected, more thorough answer.\(grounding)") {
                    answer = revised
                } else { break }
            } catch { break }
        }
        qstat("unverified", "Never approved after \(StormText.maxRevisions) revision(s), keeping as [unverified]: \(question)")
        return ("[unverified] \(answer)", sources)
    }
}
