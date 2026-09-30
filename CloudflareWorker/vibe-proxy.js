/**
 * Sift's Vibe proxy -- sits between the app and Anthropic's API so the app never ships
 * with a real Anthropic API key. The key lives only here, as an encrypted Worker
 * secret (ANTHROPIC_API_KEY), set in the Cloudflare dashboard, never committed to git
 * and never sent to the app.
 *
 * Deploy via the Cloudflare dashboard (Workers & Pages -> Create -> paste this in the
 * online editor) -- see the chat walkthrough for the full click-by-click steps,
 * including creating the ANTHROPIC_API_KEY secret and the SIFT_RATE_LIMIT KV binding
 * this script expects.
 *
 * Security notes:
 * - The X-Sift-Client header check below is friction, not real security -- anyone who
 *   decompiles the app can find that constant. The actual protection against someone
 *   burning through your Anthropic budget is the per-IP rate limit further down, plus
 *   whatever spend alerts/limits you set on the Anthropic account itself.
 * - This only ever forwards `system`, `messages`, and `max_tokens` to Anthropic --
 *   never the whole client-supplied body -- so a request can't smuggle in a different
 *   model or other fields.
 */

const SIFT_CLIENT_HEADER_VALUE = "sift-macos-app-v1";
const RATE_LIMIT_WINDOW_SECONDS = 60;
const RATE_LIMIT_MAX_REQUESTS = 10;
const ANTHROPIC_MODEL = "claude-haiku-4-5-20251001";
const ANTHROPIC_VERSION = "2023-06-01";

function jsonResponse(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" }
  });
}

function anthropicStyleError(message, status) {
  return jsonResponse({ error: { message } }, status);
}

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return anthropicStyleError("Method not allowed", 405);
    }

    if (request.headers.get("X-Sift-Client") !== SIFT_CLIENT_HEADER_VALUE) {
      return anthropicStyleError("Missing or invalid client header", 401);
    }

    const ip = request.headers.get("CF-Connecting-IP") || "unknown";
    const rateLimitKey = `ratelimit:${ip}`;
    const current = await env.SIFT_RATE_LIMIT.get(rateLimitKey);
    const count = current ? parseInt(current, 10) : 0;
    if (count >= RATE_LIMIT_MAX_REQUESTS) {
      return anthropicStyleError("Too many requests -- please wait a minute and try again.", 429);
    }
    await env.SIFT_RATE_LIMIT.put(rateLimitKey, String(count + 1), {
      expirationTtl: RATE_LIMIT_WINDOW_SECONDS
    });

    let body;
    try {
      body = await request.json();
    } catch {
      return anthropicStyleError("Invalid JSON body", 400);
    }

    const { system, messages, max_tokens } = body;
    if (typeof system !== "string" || !Array.isArray(messages)) {
      return anthropicStyleError("Missing system or messages", 400);
    }

    let anthropicResponse;
    try {
      anthropicResponse = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": env.ANTHROPIC_API_KEY,
          "anthropic-version": ANTHROPIC_VERSION
        },
        body: JSON.stringify({
          model: ANTHROPIC_MODEL,
          max_tokens: typeof max_tokens === "number" ? max_tokens : 8192,
          system,
          messages
        })
      });
    } catch (error) {
      return anthropicStyleError(`Couldn't reach Anthropic: ${error}`, 502);
    }

    const responseBody = await anthropicResponse.text();
    return new Response(responseBody, {
      status: anthropicResponse.status,
      headers: { "Content-Type": "application/json" }
    });
  }
};
