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

    var errorDescription: String? {
        switch self {
        case .playlistNotFound:
            return "That playlist couldn't be found in your library anymore."
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

    /// Artist name -> looked-up artwork (or nil if the search found nothing), so
    /// scrolling Auto-Sort's Artist tab never re-searches the same artist twice.
    private var artistArtworkCache: [String: Artwork?] = [:]

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

        let unknownGenreCount = songs.filter { $0.genre == "Unknown" }.count
        if unknownGenreCount > 0 {
            print("Sift DEBUG: loadPlaylist — \(unknownGenreCount)/\(songs.count) songs in \(detailed.name) had no genreNames from MusicKit")
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

    /// The real MusicKit `Song` behind a library ID, if it's been seen since launch
    /// (populated by `loadPlaylist`). Used by `PlaybackService` to actually play songs.
    func song(for libraryID: String) -> Song? {
        songCache[libraryID]
    }

    /// Turns library IDs back into playable `SiftSong`s -- for a `SiftOwnedPlaylist`
    /// (see `SiftPlaylistStore`), whose songs might not all be in `songCache` if it was
    /// created in an earlier session (the cache is in-memory only, populated by
    /// `loadPlaylist`, and starts empty on every launch). Looks there first, then fetches
    /// anything missing directly by id.
    ///
    /// - Note: `request.filter(matching:memberOf:)` is my best recollection of how to
    ///   filter a `MusicLibraryRequest` by a set of ids; if the signature differs in your
    ///   SDK, Xcode's autocomplete on `request.filter(` will show the current form.
    func resolveSongs(forLibraryIDs ids: [String]) async -> [SiftSong] {
        let uncachedIDs = ids.filter { songCache[$0] == nil }
        if !uncachedIDs.isEmpty {
            var request = MusicLibraryRequest<Song>()
            request.filter(matching: \.id, memberOf: uncachedIDs.map { MusicItemID($0) })
            if let response = try? await request.response() {
                for song in response.items {
                    songCache[song.id.rawValue] = song
                }
            }
        }

        return ids.compactMap { id in
            guard let song = songCache[id] else { return nil }
            return SiftSong(
                libraryID: song.id.rawValue,
                title: song.title,
                artist: song.artistName,
                album: song.albumTitle ?? "",
                genre: song.genreNames.first ?? "Unknown",
                duration: song.duration ?? 0,
                artwork: song.artwork
            )
        }
    }

    /// An artist's real photo from Apple's catalog, looked up by name -- for Auto-Sort's
    /// Artist tab, whose proposal cards otherwise fall back to a plain gradient tile.
    /// This is a catalog search, not a library fetch: MusicKit doesn't expose a library
    /// song's `artists` relationship without an extra fetch per song, which isn't
    /// practical across 1,000+ songs, but an artist name search against the public
    /// catalog is cheap and works for any artist Apple Music actually has.
    ///
    /// - Note: `MusicCatalogSearchRequest(term:types:)` is my best recollection of this
    ///   MusicKit API; if the signature differs in your SDK, Xcode's autocomplete on
    ///   `MusicCatalogSearchRequest(` will show the current form.
    func lookupArtistArtwork(name: String) async -> Artwork? {
        if let cached = artistArtworkCache[name] { return cached }
        var request = MusicCatalogSearchRequest(term: name, types: [Artist.self])
        request.limit = 1
        let artwork = (try? await request.response())?.artists.first?.artwork
        artistArtworkCache[name] = artwork
        return artwork
    }
}
