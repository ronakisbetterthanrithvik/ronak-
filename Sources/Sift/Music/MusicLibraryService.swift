import MusicKit
import Foundation

struct LibraryPlaylistSummary: Identifiable, Hashable {
    let id: String
    let name: String
    let artworkURL: URL?
}

enum MusicLibraryError: LocalizedError {
    case playlistNotFound
    case noSongsToCreatePlaylistFrom
    case playlistCreationUnsupportedOnMac

    var errorDescription: String? {
        switch self {
        case .playlistNotFound:
            return "That playlist couldn't be found in your library anymore."
        case .noSongsToCreatePlaylistFrom:
            return "None of those songs were found in your library."
        case .playlistCreationUnsupportedOnMac:
            return "Apple's on-device MusicKit doesn't support creating playlists on Mac yet (iOS/iPadOS only) — this is a real Apple platform limitation, not a Sift bug."
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
        return response.items.map {
            LibraryPlaylistSummary(id: $0.id.rawValue, name: $0.name, artworkURL: $0.artwork?.url(width: 300, height: 300))
        }
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
        var mosaicURLs: [URL] = []

        for track in tracks {
            guard case let .song(song) = track else { continue }
            songCache[song.id.rawValue] = song
            // Requested well above the ~40pt row size it renders at, so it stays sharp
            // on Retina displays instead of upscaling a too-small source image.
            let songArtworkURL = song.artwork?.url(width: 200, height: 200)
            songs.append(
                SiftSong(
                    libraryID: song.id.rawValue,
                    title: song.title,
                    artist: song.artistName,
                    album: song.albumTitle ?? "",
                    genre: song.genreNames.first ?? "Unknown",
                    duration: song.duration ?? 0,
                    artworkURL: songArtworkURL
                )
            )
            if mosaicURLs.count < 4, let url = song.artwork?.url(width: 400, height: 400) {
                mosaicURLs.append(url)
            }
        }

        let genres = Array(Set(songs.map(\.genre))).sorted()
        var artistCounts: [String: Int] = [:]
        for song in songs {
            for artistName in song.artist.splitArtistCredits() {
                artistCounts[artistName, default: 0] += 1
            }
        }
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
            allArtists: allArtists,
            artworkURL: detailed.artwork?.url(width: 600, height: 600),
            mosaicArtworkURLs: mosaicURLs
        )
    }

    /// Would create a real playlist in the connected Apple Music library.
    ///
    /// - Important: `MusicLibrary.createPlaylist(name:description:authorDisplayName:items:)`
    ///   is explicitly marked unavailable on macOS in MusicKit's current SDK — confirmed
    ///   directly from Xcode's own compiler error, not assumed. Apple's on-device
    ///   playlist-creation API is iOS/iPadOS only right now. The PRD's own Technical
    ///   Architecture section anticipated this gap and named AppleScript automation as
    ///   the Mac-specific workaround (driving Music.app directly) — that's a real,
    ///   separate piece of work this doesn't attempt yet, so this throws a clear error
    ///   instead of silently failing or refusing to compile.
    func createPlaylist(name: String, songLibraryIDs: [String]) async throws {
        let songs = songLibraryIDs.compactMap { songCache[$0] }
        guard !songs.isEmpty else { throw MusicLibraryError.noSongsToCreatePlaylistFrom }
        throw MusicLibraryError.playlistCreationUnsupportedOnMac
    }

    /// The real MusicKit `Song` behind a library ID, if it's been seen since launch
    /// (populated by `loadPlaylist`). Used by `PlaybackService` to actually play songs.
    func song(for libraryID: String) -> Song? {
        songCache[libraryID]
    }
}
