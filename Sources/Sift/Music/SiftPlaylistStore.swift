import Foundation

/// A playlist that exists only inside Sift, never in Apple Music itself.
///
/// `MusicLibrary.createPlaylist(...)` is unavailable on macOS (see
/// `MusicLibraryService.createPlaylist`), so anything Sift proposes -- Auto-Sort's
/// Genre/Artist/Vibe splits included -- can't actually be written back to a person's
/// real library. Rather than always failing that real API call, Sift keeps its own
/// proposals here instead: playable from within Sift, persisted across launches, just
/// not visible in Music.app.
struct SiftOwnedPlaylist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var songLibraryIDs: [String]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, songLibraryIDs: [String], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.songLibraryIDs = songLibraryIDs
        self.createdAt = createdAt
    }
}

@MainActor
final class SiftPlaylistStore: ObservableObject {
    static let shared = SiftPlaylistStore()

    @Published private(set) var playlists: [SiftOwnedPlaylist] = []
    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sift", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("sift-playlists.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([SiftOwnedPlaylist].self, from: data) {
            playlists = decoded.sorted { $0.createdAt > $1.createdAt }
        }
    }

    @discardableResult
    func create(name: String, songLibraryIDs: [String]) -> SiftOwnedPlaylist {
        let playlist = SiftOwnedPlaylist(name: name, songLibraryIDs: songLibraryIDs)
        playlists.insert(playlist, at: 0)
        persist()
        return playlist
    }

    func delete(id: UUID) {
        playlists.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        let snapshot = playlists
        let url = fileURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
