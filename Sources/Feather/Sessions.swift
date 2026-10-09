import Foundation

/// One saved session: a name plus the tabs' URLs.
struct Session: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var urls: [URL]
    var created: Date
}

/// Named tab sessions, stored as JSON in the app's support folder.
final class Sessions {
    static let shared = Sessions()
    static let changed = Notification.Name("FeatherSessionsChanged")

    private(set) var sessions: [Session] = []
    private let file: URL

    private convenience init() {
        self.init(storeURL: Settings.supportDirectory.appendingPathComponent("sessions.json"))
    }

    /// Loads from (and saves to) the given file instead of the app's support folder,
    /// so tests don't touch the real sessions or the shared singleton.
    init(storeURL: URL) {
        file = storeURL
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode([Session].self, from: data) {
            sessions = decoded
        }
    }

    var all: [Session] { sessions }

    func session(id: UUID) -> Session? {
        sessions.first { $0.id == id }
    }

    /// Saves the URLs as a new session and returns it.
    @discardableResult
    func save(name: String, urls: [URL]) -> Session {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = Session(id: UUID(),
                              name: clean.isEmpty ? "Untitled Session" : clean,
                              urls: urls,
                              created: Date())
        sessions.append(session)
        persist()
        return session
    }

    func rename(_ id: UUID, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].name = clean
        persist()
    }

    func delete(_ id: UUID) {
        let before = sessions.count
        sessions.removeAll { $0.id == id }
        if sessions.count != before { persist() }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sessions) {
            try? data.write(to: file, options: .atomic)
        }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}
