import Foundation

enum ClaudeVibeError: LocalizedError {
    case missingAPIKey
    case network(Error)
    case badStatus(Int, String)
    case unparsableResponse
    case noMatchingSongs

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your Anthropic API key first."
        case .network(let error):
            return "Couldn't reach Claude: \(error.localizedDescription)"
        case .badStatus(let code, let message):
            return "Claude API error (\(code)): \(message)"
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
/// This is a real network call to Anthropic's API using the key the person enters
/// themselves (stored in the Keychain, never shipped with the app) -- Sift has no
/// server of its own and no key of its own.
enum ClaudeVibeService {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-haiku-4-5-20251001"

    static func curatePlaylist(request: String, from songs: [SiftSong]) async throws -> ClaudeVibeResult {
        guard let apiKey = AnthropicAPIKeyStore.load(), !apiKey.isEmpty else {
            throw ClaudeVibeError.missingAPIKey
        }

        let songList = songs
            .map { "\($0.libraryID)\t\($0.title) — \($0.artist) (\($0.genre))" }
            .joined(separator: "\n")

        let systemPrompt = """
        You curate playlists inside Sift, a macOS Apple Music companion app. You're given \
        a person's existing playlist as a list of songs (id, title, artist, genre) and a \
        free-text request describing the playlist they want made from it.

        Select songs from that list ONLY -- never invent a song, artist, or id that isn't \
        in the list. Favor precision: if the request names specific artists, prioritize \
        their songs; broaden to similar/complementary songs already in the list only when \
        the request asks for more than those artists alone provide. Choose a reasonable \
        number of songs for the request (don't include the whole library unless asked).

        Respond with ONLY a single JSON object and nothing else -- no prose, no markdown \
        fences -- in exactly this shape:
        {"name": "Short Playlist Name", "songLibraryIDs": ["id1", "id2", ...]}
        """

        let userMessage = """
        Request: \(request)

        Songs in this playlist (id<TAB>title — artist (genre)), one per line:
        \(songList)
        """

        let body = ClaudeRequest(
            model: model,
            maxTokens: 8192,
            system: systemPrompt,
            messages: [.init(role: "user", content: userMessage)]
        )

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw ClaudeVibeError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeVibeError.unparsableResponse
        }
        guard httpResponse.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(ClaudeErrorEnvelope.self, from: data))?.error.message
                ?? String(data: data, encoding: .utf8)
                ?? "Unknown error"
            throw ClaudeVibeError.badStatus(httpResponse.statusCode, message)
        }

        guard
            let decoded = try? JSONDecoder().decode(ClaudeResponse.self, from: data),
            let text = decoded.content.first(where: { $0.type == "text" })?.text
        else {
            throw ClaudeVibeError.unparsableResponse
        }

        guard let curated = parseCuratedPlaylist(from: text) else {
            throw ClaudeVibeError.unparsableResponse
        }

        let validIDs = Set(songs.map(\.libraryID))
        let matchedIDs = curated.songLibraryIDs.filter { validIDs.contains($0) }
        guard !matchedIDs.isEmpty else { throw ClaudeVibeError.noMatchingSongs }

        return ClaudeVibeResult(name: curated.name, songLibraryIDs: matchedIDs)
    }

    /// Claude is instructed to respond with only JSON, but strips a stray markdown code
    /// fence defensively in case it wraps the response in one anyway.
    private static func parseCuratedPlaylist(from text: String) -> ClaudeVibeResult? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            trimmed = trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        guard let raw = try? JSONDecoder().decode(RawCuratedPlaylist.self, from: data) else { return nil }
        return ClaudeVibeResult(name: raw.name, songLibraryIDs: raw.songLibraryIDs)
    }
}

private struct RawCuratedPlaylist: Decodable {
    let name: String
    let songLibraryIDs: [String]
}

private struct ClaudeRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [ClaudeMessage]

    enum CodingKeys: String, CodingKey {
        case model, system, messages
        case maxTokens = "max_tokens"
    }
}

private struct ClaudeMessage: Encodable {
    let role: String
    let content: String
}

private struct ClaudeResponse: Decodable {
    let content: [ClaudeContentBlock]
}

private struct ClaudeContentBlock: Decodable {
    let type: String
    let text: String?
}

private struct ClaudeErrorEnvelope: Decodable {
    let error: ClaudeErrorDetail
}

private struct ClaudeErrorDetail: Decodable {
    let message: String
}
