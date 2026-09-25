import Foundation
import Combine
import AppKit

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
    /// Filename (not a full path) inside the covers directory `SiftPlaylistStore`
    /// manages -- a real Apple Music playlist can fall back to a mosaic of its songs'
    /// own artwork when it has no custom cover, but a Sift-only playlist has no such
    /// built-in fallback, so this is optional: picked by the person when they name it,
    /// or left nil for a plain gradient tile.
    var coverImageFileName: String?

    init(id: UUID = UUID(), name: String, songLibraryIDs: [String], createdAt: Date = Date(), coverImageFileName: String? = nil) {
        self.id = id
        self.name = name
        self.songLibraryIDs = songLibraryIDs
        self.createdAt = createdAt
        self.coverImageFileName = coverImageFileName
    }
}

@MainActor
final class SiftPlaylistStore: ObservableObject {
    static let shared = SiftPlaylistStore()

    @Published private(set) var playlists: [SiftOwnedPlaylist] = []
    private let fileURL: URL
    private let coversDirectory: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sift", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("sift-playlists.json")

        coversDirectory = base.appendingPathComponent("covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: coversDirectory, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([SiftOwnedPlaylist].self, from: data) {
            playlists = decoded.sorted { $0.createdAt > $1.createdAt }
        }
    }

    @discardableResult
    func create(name: String, songLibraryIDs: [String], coverImage: NSImage? = nil) -> SiftOwnedPlaylist {
        let coverFileName = coverImage.flatMap { saveCoverImage($0) }
        let playlist = SiftOwnedPlaylist(name: name, songLibraryIDs: songLibraryIDs, coverImageFileName: coverFileName)
        playlists.insert(playlist, at: 0)
        persist()
        return playlist
    }

    func delete(id: UUID) {
        guard let playlist = playlists.first(where: { $0.id == id }) else { return }
        if let fileName = playlist.coverImageFileName {
            try? FileManager.default.removeItem(at: coversDirectory.appendingPathComponent(fileName))
        }
        playlists.removeAll { $0.id == id }
        persist()
    }

    func coverImage(for playlist: SiftOwnedPlaylist) -> NSImage? {
        guard let fileName = playlist.coverImageFileName else { return nil }
        return NSImage(contentsOf: coversDirectory.appendingPathComponent(fileName))
    }

    private func saveCoverImage(_ image: NSImage) -> String? {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else { return nil }

        let fileName = "\(UUID().uuidString).png"
        let url = coversDirectory.appendingPathComponent(fileName)
        guard (try? pngData.write(to: url)) != nil else { return nil }
        return fileName
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
