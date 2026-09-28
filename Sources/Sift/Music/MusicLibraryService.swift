import MusicKit
import Foundation

extension Song {
    /// A library song's plain `genreNames` property consistently comes back empty --
    /// the real genre data lives behind the separate `genres` *relationship*, which
    /// only has a value once explicitly fetched via `.with(.genres)` (see
    /// `MusicLibraryService.fetchFullSongs`). Prefers that relationship's data, falls
    /// back to `genreNames` in case a particular `Song` value was never enriched that
    /// way, and only actually reports "Unknown" once both come up empty.
    ///
    /// - Note: `genres` returning a `MusicItemCollection<Genre>?` with a `.name` on
    ///   each `Genre` is my best recollection of this MusicKit API; if the shape
    ///   differs in your SDK, Xcode's autocomplete on `self.genres?.first?.` will show
    ///   the current form.
    var genreName: String {
        genres?.first?.name ?? genreNames.first ?? "Unknown"
    }
}

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

    /// "title|artist" -> looked-up catalog genre (or nil if the search found nothing),
    /// so re-opening the same playlist's Genre tab never re-searches the same song twice.
    private var catalogGenreCache: [String: String?] = [:]

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

        // `genreNames` (a plain property on the `Song` a playlist's own `.tracks`
        // relationship hands back) consistently comes back empty -- the real genre data
        // lives behind the separate `genres` *relationship*, which, like a playlist's
        // own `.tracks`, has to be fetched explicitly via `.with(...)` rather than
        // coming back for free. `fetchFullSongs` re-fetches these same songs by id and
        // does that `.with(.genres)` fetch.
        let orderedIDs = tracks.compactMap { track -> String? in
            guard case let .song(song) = track else { return nil }
            return song.id.rawValue
        }
        let fullSongsByID = await fetchFullSongs(forLibraryIDs: orderedIDs)

        var songs: [SiftSong] = []
        songs.reserveCapacity(tracks.count)
        var mosaicArtwork: [Artwork] = []

        for track in tracks {
            guard case let .song(trackSong) = track else { continue }
            let song = fullSongsByID[trackSong.id.rawValue] ?? trackSong
            songCache[song.id.rawValue] = song
            songs.append(
                SiftSong(
                    libraryID: song.id.rawValue,
                    title: song.title,
                    artist: song.artistName,
                    album: song.albumTitle ?? "",
                    genre: song.genreName,
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
            print("Sift DEBUG: loadPlaylist — \(unknownGenreCount)/\(songs.count) songs in \(detailed.name) had no genre even after fetching the genres relationship")
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
            let fetched = await fetchFullSongs(forLibraryIDs: uncachedIDs)
            for (id, song) in fetched {
                songCache[id] = song
            }
        }

        return ids.compactMap { id in
            guard let song = songCache[id] else { return nil }
            return SiftSong(
                libraryID: song.id.rawValue,
                title: song.title,
                artist: song.artistName,
                album: song.albumTitle ?? "",
                genre: song.genreName,
                duration: song.duration ?? 0,
                artwork: song.artwork
            )
        }
    }

    /// A direct top-level fetch of `Song`s by library id, with each song's `genres`
    /// relationship also fetched (see `Song.genreName` below). Used by both
    /// `loadPlaylist` and `resolveSongs`.
    ///
    /// Chunked at the request level because a single `.filter(matching:memberOf:)` call
    /// carrying 1,000+ ids (an entire large playlist) risks hitting a request-size
    /// limit; those chunk requests run concurrently. The follow-up `.with(.genres)` per
    /// song is bounded to a modest number at a time instead (`mapConcurrently`) rather
    /// than firing everything at once, since that's a separate network call per song.
    /// A chunk or an individual `.with()` call that fails just leaves that song without
    /// enriched genre data (falling back to its plain, usually-empty `genreNames`)
    /// rather than failing the whole fetch.
    private func fetchFullSongs(forLibraryIDs ids: [String]) async -> [String: Song] {
        guard !ids.isEmpty else { return [:] }
        let chunkSize = 100
        let chunks = stride(from: 0, to: ids.count, by: chunkSize).map {
            Array(ids[$0..<min($0 + chunkSize, ids.count)])
        }

        var baseSongs: [Song] = []
        await withTaskGroup(of: [Song].self) { group in
            for chunk in chunks {
                group.addTask {
                    var request = MusicLibraryRequest<Song>()
                    request.filter(matching: \.id, memberOf: chunk.map { MusicItemID($0) })
                    guard let response = try? await request.response() else { return [] }
                    return Array(response.items)
                }
            }
            for await songs in group {
                baseSongs.append(contentsOf: songs)
            }
        }

        let enrichedSongs = await mapConcurrently(baseSongs, maxConcurrent: 20) { song in
            (try? await song.with(.genres)) ?? song
        }

        var result: [String: Song] = [:]
        for song in enrichedSongs {
            result[song.id.rawValue] = song
        }
        return result
    }

    /// Runs `transform` over `items` with at most `maxConcurrent` in flight at once,
    /// rather than either fully sequential (slow for 1,000+ songs, one network round
    /// trip at a time) or fully unbounded (firing 1,000+ requests simultaneously).
    private func mapConcurrently<T: Sendable, R: Sendable>(_ items: [T], maxConcurrent: Int, transform: @escaping @Sendable (T) async -> R) async -> [R] {
        var result: [R] = []
        result.reserveCapacity(items.count)
        var index = 0
        while index < items.count {
            let end = min(index + maxConcurrent, items.count)
            let batch = Array(items[index..<end])
            await withTaskGroup(of: R.self) { group in
                for item in batch {
                    group.addTask { await transform(item) }
                }
                for await value in group {
                    result.append(value)
                }
            }
            index = end
        }
        return result
    }

    /// A library song's catalog counterpart's genre, found by searching the catalog for
    /// its own title + artist -- for when `Song.genreName` comes up empty even after the
    /// `.with(.genres)` fetch, i.e. Apple Music's library APIs genuinely have no genre
    /// data for that song (only its catalog counterpart does). This is the same catalog
    /// search endpoint `lookupArtistArtwork` already uses; if this app is hitting the
    /// `.developerTokenRequestFailed` issue that's affected artist photos, this will
    /// fail the same way for the same reason.
    ///
    /// - Note: `MusicCatalogSearchRequest(term:types:)` returning a response with a
    ///   `.songs` collection is my best recollection of this MusicKit API; if it differs
    ///   in your SDK, Xcode's autocomplete on `response.` will show the current form.
    func lookupCatalogGenre(title: String, artist: String) async -> String? {
        let key = "\(title)|\(artist)"
        if let cached = catalogGenreCache[key] { return cached }
        var request = MusicCatalogSearchRequest(term: "\(title) \(artist)", types: [Song.self])
        request.limit = 1
        do {
            let response = try await request.response()
            let genre = response.songs.first?.genreNames.first
            // `updateValue`, not subscript assignment -- see the same note on
            // `artistArtworkCache` above; a `cache[key] = nil` here would delete the
            // entry instead of caching "searched, found nothing."
            catalogGenreCache.updateValue(genre, forKey: key)
            return genre
        } catch {
            print("Sift DEBUG: lookupCatalogGenre — search failed for \"\(title)\" by \"\(artist)\" — \(error)")
            catalogGenreCache.updateValue(nil, forKey: key)
            return nil
        }
    }

    /// Batch version of `lookupCatalogGenre` for every song in a playlist -- used by
    /// Auto-Sort's Genre tab as a fallback only when the library itself has no genre
    /// data for any song in the playlist at all. Bounded concurrency, same reasoning as
    /// `fetchFullSongs`'s `.with(.genres)` step: one network call per song, so a
    /// 1,000+ song playlist can't fire all of them at once.
    func catalogGenres(for songs: [SiftSong]) async -> [String: String] {
        let results = await mapConcurrently(songs, maxConcurrent: 20) { song -> (String, String)? in
            guard let genre = await self.lookupCatalogGenre(title: song.title, artist: song.artist) else { return nil }
            return (song.libraryID, genre)
        }
        var byLibraryID: [String: String] = [:]
        for case let (libraryID, genre)? in results {
            byLibraryID[libraryID] = genre
        }
        return byLibraryID
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
        do {
            let response = try await request.response()
            guard let matched = response.artists.first else {
                print("Sift DEBUG: lookupArtistArtwork — catalog search for \"\(name)\" returned no artists")
                // `updateValue`, not subscript assignment -- `cache[name] = nil` on a
                // `[String: Artwork?]` deletes the entry instead of storing a cached
                // "looked this up, found nothing" result, so every reappearance of this
                // card (every scroll) would silently retry the same failing request.
                artistArtworkCache.updateValue(nil, forKey: name)
                return nil
            }
            if matched.artwork == nil {
                print("Sift DEBUG: lookupArtistArtwork — matched \"\(matched.name)\" for \"\(name)\" but it has no artwork")
            }
            artistArtworkCache.updateValue(matched.artwork, forKey: name)
            return matched.artwork
        } catch {
            print("Sift DEBUG: lookupArtistArtwork — search failed for \"\(name)\" — \(error)")
            artistArtworkCache.updateValue(nil, forKey: name)
            return nil
        }
    }
}
