import MusicKit
import Foundation

struct LibraryPlaylistSummary: Identifiable, Hashable {
    let id: String
    let name: String
}

enum MusicLibraryError: LocalizedError {
    case playlistNotFound
    case noSongsToCreatePlaylistFrom

    var errorDescription: String? {
        switch self {
        case .playlistNotFound:
            return "That playlist couldn't be found in your library anymore."
        case .noSongsToCreatePlaylistFrom:
            return "None of those songs were found in your library."
        }
    }
}

/// Talks to the real Apple Music library through MusicKit. Requires the MusicKit
/// capability + an authorized `MusicAuthorization.Status` before any call here succeeds.
@MainActor
final class MusicLibraryService {
    static let shared = MusicLibraryService()

    /// MusicKit's own `Song` objects, cached by library ID after a playlist load, so
    /// Auto-Sort can hand real songs back to `MusicLibrary` when creating playlists
    /// without re-querying the library.
    private var songCache: [String: Song] = [:]

    func fetchPlaylists() async throws -> [LibraryPlaylistSummary] {
        var request = MusicLibraryRequest<Playlist>()
        request.limit = 100
        let response = try await request.response()
        return response.items.map { LibraryPlaylistSummary(id: $0.id.rawValue, name: $0.name) }
    }

    func loadPlaylist(id: String) async throws -> SiftPlaylist {
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: MusicItemID(id))
        let response = try await request.response()

        guard let basePlaylist = response.items.first else {
            throw MusicLibraryError.playlistNotFound
        }

        let detailed = try await basePlaylist.with(.tracks)
        let tracks = detailed.tracks ?? []

        var songs: [SiftSong] = []
        songs.reserveCapacity(tracks.count)

        for track in tracks {
            guard case let .song(song) = track else { continue }
            songCache[song.id.rawValue] = song
            songs.append(
                SiftSong(
                    libraryID: song.id.rawValue,
                    title: song.title,
                    artist: song.artistName,
                    album: song.albumTitle ?? "",
                    genre: song.genreNames.first ?? "Unknown",
                    duration: song.duration ?? 0
                )
            )
        }

        let genres = Array(Set(songs.map(\.genre))).sorted()
        let artistCounts = Dictionary(grouping: songs, by: \.artist).mapValues(\.count)
        let topArtists = artistCounts.sorted { $0.value > $1.value }.prefix(4).map(\.key)
        let allArtists = Array(artistCounts.keys).sorted()
        let totalDuration = songs.reduce(0) { $0 + $1.duration }

        return SiftPlaylist(
            libraryID: id,
            name: detailed.name,
            ownerName: "Your Library",
            songCount: songs.count,
            totalDuration: totalDuration,
            songs: songs,
            genresPresent: genres,
            topArtists: Array(topArtists),
            allArtists: allArtists
        )
    }

    /// Creates a real playlist in the connected Apple Music library.
    ///
    /// - Note: `MusicLibrary`'s playlist-creation surface has shifted across recent
    ///   SDKs. If `createPlaylist` doesn't match this signature in your Xcode version,
    ///   autocomplete on `MusicLibrary.shared.` will show the current overload — the
    ///   intent (a new library playlist containing these songs) stays the same.
    func createPlaylist(name: String, songLibraryIDs: [String]) async throws {
        let songs = songLibraryIDs.compactMap { songCache[$0] }
        guard !songs.isEmpty else { throw MusicLibraryError.noSongsToCreatePlaylistFrom }
        _ = try await MusicLibrary.shared.createPlaylist(name: name, items: songs)
    }

    /// The real MusicKit `Song` behind a library ID, if it's been seen since launch
    /// (populated by `loadPlaylist`). Used by `PlaybackService` to actually play songs.
    func song(for libraryID: String) -> Song? {
        songCache[libraryID]
    }
}
