import MusicKit
import Foundation

struct LibraryPlaylistSummary: Identifiable, Hashable {
    let id: String
    let name: String
}

/// A playlist's real cover -- its own custom artwork if it has one, or (for a personal
/// playlist without custom art, which is most of them) up to four of its own tracks'
/// artwork to build the same 2x2 mosaic Apple Music itself shows for that playlist. Kept
/// as MusicKit's own `Artwork` rather than a resolved `URL` -- see `SiftSong.artwork`.
struct PlaylistCoverArtwork {
    let single: Artwork?
    let mosaic: [Artwork]
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
        return response.items.map { LibraryPlaylistSummary(id: $0.id.rawValue, name: $0.name) }
    }

    /// A playlist's `artwork` on the bare items `fetchPlaylists()` returns is unreliable
    /// (often nil even when the playlist visibly has custom art in Music.app) -- that
    /// property only actually resolves once loaded via `.with(.tracks)`, exactly like
    /// `loadPlaylist` below already does when opening a playlist for real. So this always
    /// goes through that same detailed fetch rather than trusting the shallow list
    /// response, and falls back to sampling a handful of the playlist's own songs for a
    /// mosaic if it truly has no custom art. Used lazily, only for playlists the picker's
    /// carousel actually scrolls to, and cached by the caller.
    func loadPlaylistCoverArtwork(id: String) async -> PlaylistCoverArtwork {
        do {
            var request = MusicLibraryRequest<Playlist>()
            request.filter(matching: \.id, equalTo: MusicItemID(id))
            let response = try await request.response()
            guard let basePlaylist = response.items.first else {
                print("Sift DEBUG: loadPlaylistCoverArtwork — no playlist found for id \(id)")
                return PlaylistCoverArtwork(single: nil, mosaic: [])
            }

            let detailed = try await basePlaylist.with(.tracks)
            if let artwork = detailed.artwork {
                return PlaylistCoverArtwork(single: artwork, mosaic: [])
            }

            var mosaic: [Artwork] = []
            for track in (detailed.tracks ?? []).prefix(20) {
                guard case let .song(song) = track, let artwork = song.artwork else { continue }
                mosaic.append(artwork)
                if mosaic.count == 4 { break }
            }
            if mosaic.isEmpty {
                print("Sift DEBUG: loadPlaylistCoverArtwork — \(detailed.name) has no artwork and no track artwork to build a mosaic from")
            }
            return PlaylistCoverArtwork(single: nil, mosaic: mosaic)
        } catch {
            print("Sift DEBUG: loadPlaylistCoverArtwork failed for id \(id) — \(error)")
            return PlaylistCoverArtwork(single: nil, mosaic: [])
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
        var mosaicArtwork: [Artwork] = []

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
                    duration: song.duration ?? 0,
                    artwork: song.artwork
                )
            )
            if mosaicArtwork.count < 4, let artwork = song.artwork {
                mosaicArtwork.append(artwork)
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
            artwork: detailed.artwork,
            mosaicArtwork: mosaicArtwork
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
