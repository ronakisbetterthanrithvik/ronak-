import Foundation

/// Sift's own first-party listening signal, keyed by a song's stable library ID.
///
/// Apple doesn't hand a third-party app a user's pre-existing Apple Music history —
/// per the PRD, Smart Control has to build this up from what happens *through this app*
/// going forward. This starts empty for every song and fills in as you play/skip through Sift.
@MainActor
final class ListeningHistoryStore {
    static let shared = ListeningHistoryStore()

    struct Entry: Codable {
        var plays: Int = 0
        var skips: Int = 0
        var repeatsInSession: Int = 0
        var totalSecondsListened: Double = 0
        var lastPlayedAt: Date?
    }

    private(set) var entries: [String: Entry] = [:]
    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sift", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("listening-history.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        }
    }

    func entry(for libraryID: String) -> Entry {
        entries[libraryID] ?? Entry()
    }

    func recordSkip(libraryID: String) {
        var entry = entries[libraryID] ?? Entry()
        entry.skips += 1
        entries[libraryID] = entry
        persist()
    }

    func recordPlay(libraryID: String, seconds: Double) {
        var entry = entries[libraryID] ?? Entry()
        entry.plays += 1
        entry.totalSecondsListened += seconds
        if let last = entry.lastPlayedAt, Date().timeIntervalSince(last) < 30 * 60 {
            entry.repeatsInSession += 1
        }
        entry.lastPlayedAt = Date()
        entries[libraryID] = entry
        persist()
    }

    private func persist() {
        let snapshot = entries
        let url = fileURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
