import Foundation

enum CatalogPlaylistGeneratorError: LocalizedError {
    case proxy(ClaudeProxyError)
    case unparsableResponse
    case noSongsFound

    var errorDescription: String? {
        switch self {
        case .proxy(let error):
            return error.errorDescription
        case .unparsableResponse:
            return "Claude's response wasn't in the expected format. Try rephrasing your request."
        case .noSongsFound:
            return "None of Claude's suggestions matched a real song on Apple Music. Try rephrasing your request."
        }
    }
}

struct CatalogPlaylistGeneratorResult {
    let name: String
    let songs: [SiftSong]
}

/// The "AI Playlist Generator" -- unlike Auto-Sort's Vibe tab, which only ever curates
/// from a playlist you already have open, this builds a brand new playlist from
/// anywhere in Apple Music's catalog based on a free-text request alone.
///
/// Claude can't browse Apple Music's catalog itself, so this is a suggest-then-verify
/// pipeline: Claude suggests real songs from its own knowledge, and
/// `MusicLibraryService.resolveCatalogSongs` searches the actual catalog for each one
/// to confirm it's real and pull its real metadata/artwork. A suggestion Claude got
/// wrong (misremembered, misspelled, or simply not on Apple Music) just doesn't resolve
/// and is dropped, rather than appearing as a broken song.
enum CatalogPlaylistGeneratorService {
    static func generate(request: String) async throws -> CatalogPlaylistGeneratorResult {
        let systemPrompt = """
        You build playlists inside Sift, a macOS Apple Music companion app, from a \
        person's free-text description of what they want. Unlike a normal playlist \
        curator, you are NOT given an existing list of songs to choose from -- suggest \
        real, specific songs from your own knowledge of music that best fit the request.

        Suggest between 15 and 30 songs, real and specific (a real title and the real \
        artist who recorded it -- never a made-up or paraphrased title). Favor well-known \
        recordings you're confident actually exist over obscure guesses. If the request \
        names specific artists, prioritize their songs; broaden to similar/complementary \
        artists only when the request asks for more than those artists alone would provide \
        (e.g. "and similar artists," a broad mood/genre, an activity).

        Respond with ONLY a single JSON object and nothing else -- no prose, no markdown \
        fences -- in exactly this shape:
        {"name": "Short Playlist Name", "songs": [{"title": "Song Title", "artist": "Artist Name"}, ...]}
        """

        return try await requestAndResolve(systemPrompt: systemPrompt, userMessage: request)
    }

    /// Applies a follow-up free-text change ("add more Travis Scott," "swap out the
    /// slow songs") to a playlist this service already built, rather than starting over.
    /// Claude is handed the *current* song list as context so it knows what's already
    /// there, but still can't browse the catalog itself -- same suggest-then-verify
    /// pipeline as `generate`, just given one playlist's worth of existing context first.
    static func refine(currentName: String, currentSongs: [SiftSong], editRequest: String) async throws -> CatalogPlaylistGeneratorResult {
        let songList = currentSongs.map { "\($0.displayTitle) — \($0.displayArtist)" }.joined(separator: "\n")
        let systemPrompt = """
        You build and edit playlists inside Sift, a macOS Apple Music companion app. You \
        already built a playlist for this person from an earlier request, and they now \
        want a change made to it. You are still NOT given an existing list of songs to \
        choose replacements from -- suggest real, specific songs from your own knowledge, \
        same as building a playlist from scratch.

        The playlist is currently called "\(currentName)" and has these songs (title — \
        artist), one per line:
        \(songList)

        Apply the person's requested change below to this playlist, then respond with \
        the FULL updated song list, not just what changed -- keep every song the request \
        doesn't call for changing, drop whichever songs it asks to remove, and add \
        whichever songs it asks to add, real and specific (a real title and the real \
        artist who recorded it -- never a made-up or paraphrased title). Keep the same \
        playlist name unless the request implies a new one fits better.

        Respond with ONLY a single JSON object and nothing else -- no prose, no markdown \
        fences -- in exactly this shape:
        {"name": "Short Playlist Name", "songs": [{"title": "Song Title", "artist": "Artist Name"}, ...]}
        """

        return try await requestAndResolve(systemPrompt: systemPrompt, userMessage: editRequest)
    }

    private static func requestAndResolve(systemPrompt: String, userMessage: String) async throws -> CatalogPlaylistGeneratorResult {
        let text: String
        do {
            text = try await ClaudeProxyClient.sendMessage(system: systemPrompt, userMessage: userMessage)
        } catch let error as ClaudeProxyError {
            throw CatalogPlaylistGeneratorError.proxy(error)
        }

        guard let suggested = parseSuggestedPlaylist(from: text), !suggested.songs.isEmpty else {
            throw CatalogPlaylistGeneratorError.unparsableResponse
        }

        let suggestions = suggested.songs.map {
            MusicLibraryService.CatalogSongSuggestion(title: $0.title, artist: $0.artist)
        }
        let resolvedSongs = await MusicLibraryService.shared.resolveCatalogSongs(for: suggestions)
        guard !resolvedSongs.isEmpty else {
            throw CatalogPlaylistGeneratorError.noSongsFound
        }

        return CatalogPlaylistGeneratorResult(name: suggested.name, songs: resolvedSongs)
    }

    private static func parseSuggestedPlaylist(from text: String) -> RawSuggestedPlaylist? {
        let stripped = ClaudeProxyClient.stripMarkdownFence(from: text)
        guard let data = stripped.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RawSuggestedPlaylist.self, from: data)
    }
}

private struct RawSuggestedPlaylist: Decodable {
    let name: String
    let songs: [RawSuggestedSong]
}

private struct RawSuggestedSong: Decodable {
    let title: String
    let artist: String
}
