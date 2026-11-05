import Foundation

/// Locates the bundled Orcastrator (Research) web UI.
/// Research is web-based and powered by a Swift native bridge (no runtime Python).
enum OrcastratorService {
    static let port: Int = 8400
    static let baseURL = URL(string: "http://127.0.0.1:8400/")!

    /// Bundled static UI (loaded in a FeatherA tab with the native API bridge).
    static func bundledUIURL() -> URL? {
        let fm = FileManager.default
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("Orcastrator/orcastrator/static/index.html")
            if fm.fileExists(atPath: bundled.path) { return bundled }
        }
        // Dev fallback: resolve relative to this source file's repo.
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dev = repo.appendingPathComponent("Resources/Orcastrator/orcastrator/static/index.html")
        if fm.fileExists(atPath: dev.path) { return dev }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let rel = cwd.appendingPathComponent("Resources/Orcastrator/orcastrator/static/index.html")
        if fm.fileExists(atPath: rel.path) { return rel }
        return nil
    }

    /// Back-compat: no runtime Python process needed (Swift bridge handles APIs).
    @MainActor static func ensureRunningIfEnabled() async -> Bool { bundledUIURL() != nil }
    @MainActor static var lastError: String? { nil }
}
