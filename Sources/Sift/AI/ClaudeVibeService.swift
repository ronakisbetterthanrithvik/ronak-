import Foundation

enum ClaudeVibeError: LocalizedError {
    case proxy(ClaudeProxyError)
    case unparsableResponse
    case noMatchingSongs

    var errorDescription: String? {
        switch self {
        case .proxy(let error):
            return error.errorDescription
        case .unparsableResponse:
            return "Claude's response wasn't in the expected format. Try rephrasing your request."
        case .noMatchingSongs:
            return "Claude didn't find any songs in this playlist that matched that request."
        }
    }
}

struct ClaudeVibeResult {
    let name: String
    let songLibraryIDs: [String]
}

/// Sends a free-text "vibe" request plus this playlist's own song list to Claude, and
/// gets back a curated subset with a suggested name -- the actual engine behind
/// Auto-Sort's Vibe tab. Nothing here is invented by Sift itself: Claude only ever picks
/// from the exact songs it's given, never songs it makes up.
///
/// This only ever selects from the current playlist's own songs. For a playlist built
/// from anywhere in Apple Music's catalog instead, see `CatalogPlaylistGeneratorService`.
enum ClaudeVibeService {
    static func curatePlaylist(request: String, from songs: [SiftSong]) async throws -> ClaudeVibeResult {
        let songList = songs
            .map { "\($0.libraryID)\t\($0.title) — \($0.artist) (\($0.genre))" }
            .joined(separator: "\n")

        let systemPrompt = """
        You curate playlists inside Sift, a macOS Apple Music companion app. You're given \
        a person's existing playlist as a list of songs (id, title, artist, genre) and a \
        free-text request describing the playlist they want made from it.

        Select songs from that list ONLY -- never invent a song, artist, or id that isn't \
        in the list. Favor precision: if the request names one or more specific artists \
        (e.g. "all the Drake songs," "a playlist of just X"), include ONLY songs credited \
        to exactly those artists -- never a collaborator, a featured artist, or a \
        similar/associated artist, even one closely linked to the artist named. Only \
        include other artists' songs when the request itself explicitly asks for more \
        than the named artist(s) alone (e.g. "and similar artists," a mood/genre/activity \
        that isn't artist-specific). Choose a reasonable number of songs for the request \
        (don't include the whole library unless asked).

        Respond with ONLY a single JSON object and nothing else -- no prose, no markdown \
        fences -- in exactly this shape:
        {"name": "Short Playlist Name", "songLibraryIDs": ["id1", "id2", ...]}
        """

        let userMessage = """
        Request: \(request)

        Songs in this playlist (id<TAB>title — artist (genre)), one per line:
        \(songList)
        """

        let text: String
        do {
            text = try await ClaudeProxyClient.sendMessage(system: systemPrompt, userMessage: userMessage)
        } catch let error as ClaudeProxyError {
            throw ClaudeVibeError.proxy(error)
        }

        guard let curated = parseCuratedPlaylist(from: text) else {
            throw ClaudeVibeError.unparsableResponse
        }

        let validIDs = Set(songs.map(\.libraryID))
        let matchedIDs = curated.songLibraryIDs.filter { validIDs.contains($0) }
        guard !matchedIDs.isEmpty else { throw ClaudeVibeError.noMatchingSongs }

        return ClaudeVibeResult(name: curated.name, songLibraryIDs: matchedIDs)
    }

    private static func parseCuratedPlaylist(from text: String) -> ClaudeVibeResult? {
        let stripped = ClaudeProxyClient.stripMarkdownFence(from: text)
        guard let data = stripped.data(using: .utf8) else { return nil }
        guard let raw = try? JSONDecoder().decode(RawCuratedPlaylist.self, from: data) else { return nil }
        return ClaudeVibeResult(name: raw.name, songLibraryIDs: raw.songLibraryIDs)
    }
}

private struct RawCuratedPlaylist: Decodable {
    let name: String
    let songLibraryIDs: [String]
}
