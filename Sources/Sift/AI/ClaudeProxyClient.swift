import Foundation

enum ClaudeProxyError: LocalizedError {
    case network(Error)
    case badStatus(Int, String)
    case unparsableResponse

    var errorDescription: String? {
        switch self {
        case .network(let error):
            return "Couldn't reach Claude: \(error.localizedDescription)"
        case .badStatus(let code, let message):
            return "Claude API error (\(code)): \(message)"
        case .unparsableResponse:
            return "Claude's response wasn't in the expected format."
        }
    }
}

/// Talks to Sift's own Cloudflare Worker proxy (see `CloudflareWorker/vibe-proxy.js`),
/// which holds the real Anthropic API key privately server-side so it's never shipped
/// inside the app. Shared by every Claude-powered feature in Sift -- Auto-Sort's Vibe
/// tab and the AI Playlist Generator both just supply their own system/user prompt and
/// parse the returned text differently; this is the one place that knows the proxy's
/// URL, headers, and request/response shape.
enum ClaudeProxyClient {
    /// Deployed `CloudflareWorker/vibe-proxy.js`.
    private static let proxyEndpoint = URL(string: "https://sift-vibe-proxy.ronakvus.workers.dev")!
    /// Must match `SIFT_CLIENT_HEADER_VALUE` in `CloudflareWorker/vibe-proxy.js` -- see
    /// that file's security notes for what this header is (and isn't) protecting against.
    private static let clientHeaderValue = "sift-macos-app-v1"

    /// Sends one system+user message turn through the proxy and returns Claude's own
    /// text response. Callers are expected to instruct Claude (via `system`) to respond
    /// with only the exact text/JSON shape they need, then parse `content` themselves --
    /// this layer only handles the network round trip, not what's inside the message.
    static func sendMessage(system: String, userMessage: String, maxTokens: Int = 8192) async throws -> String {
        // No `model` field -- the proxy pins its own model server-side rather than
        // trusting a client-supplied one.
        let body = ClaudeRequest(
            maxTokens: maxTokens,
            system: system,
            messages: [.init(role: "user", content: userMessage)]
        )

        var urlRequest = URLRequest(url: proxyEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(clientHeaderValue, forHTTPHeaderField: "X-Sift-Client")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONEncoder().encode(body)
        // URLSession's default request timeout is 60s -- too short once the prompt gets
        // large (a whole playlist's song list, or a big suggested song list), and
        // Claude's own processing time scales with it too.
        urlRequest.timeoutInterval = 180

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw ClaudeProxyError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeProxyError.unparsableResponse
        }
        guard httpResponse.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(ClaudeErrorEnvelope.self, from: data))?.error.message
                ?? String(data: data, encoding: .utf8)
                ?? "Unknown error"
            throw ClaudeProxyError.badStatus(httpResponse.statusCode, message)
        }

        guard
            let decoded = try? JSONDecoder().decode(ClaudeResponse.self, from: data),
            let text = decoded.content.first(where: { $0.type == "text" })?.text
        else {
            throw ClaudeProxyError.unparsableResponse
        }

        return text
    }

    /// Claude is instructed to respond with only JSON, but strips a stray markdown code
    /// fence defensively in case it wraps the response in one anyway. Shared here since
    /// every caller of `sendMessage` asks Claude for a JSON-only response.
    static func stripMarkdownFence(from text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            trimmed = trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
}

private struct ClaudeRequest: Encodable {
    let maxTokens: Int
    let system: String
    let messages: [ClaudeMessage]

    enum CodingKeys: String, CodingKey {
        case system, messages
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
