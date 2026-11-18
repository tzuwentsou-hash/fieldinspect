export interface Env {
  GEMINI_API_KEY: string;
  /** Optional shared token. When set, requests must send a matching `X-FieldInspect-Token` header. */
  APP_CLIENT_TOKEN?: string;
}

/** Gemini rejects inline request payloads above ~20 MB; refuse earlier with a clear error. */
const MAX_BODY_BYTES = 20 * 1024 * 1024;

interface ProxyRequestBody {
  model?: string;
  systemInstruction?: unknown;
  contents?: unknown;
  generationConfig?: unknown;
}

interface GeminiApiResponse {
  candidates?: Array<{
    content?: {
      parts?: Array<{
        text?: string;
        thought?: boolean;
      }>;
    };
  }>;
  error?: {
    code?: number;
    message?: string;
  };
}

const ALLOWED_MODELS = new Set(["gemini-2.5-flash", "gemini-2.5-pro"]);

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return Response.json({ ok: true, service: "fieldinspect-gemini-proxy" });
    }

    if (request.method !== "POST" || url.pathname !== "/v1/analyze-defect") {
      return Response.json({ error: "Not Found" }, { status: 404 });
    }

    // Without a client check this endpoint is an open relay that anyone can use to spend your Gemini quota.
    if (env.APP_CLIENT_TOKEN && request.headers.get("X-FieldInspect-Token") !== env.APP_CLIENT_TOKEN) {
      return Response.json({ error: "Unauthorized" }, { status: 401 });
    }

    const contentLength = Number(request.headers.get("Content-Length") ?? "0");
    if (contentLength > MAX_BODY_BYTES) {
      return Response.json({ error: "Request body too large" }, { status: 413 });
    }

    if (!env.GEMINI_API_KEY) {
      return Response.json(
        { error: "Server configuration error: missing GEMINI_API_KEY" },
        { status: 500 }
      );
    }

    let body: ProxyRequestBody;
    try {
      body = (await request.json()) as ProxyRequestBody;
    } catch {
      return Response.json({ error: "Invalid JSON request body" }, { status: 400 });
    }

    const model = body.model && ALLOWED_MODELS.has(body.model)
      ? body.model
      : "gemini-2.5-flash";

    if (!Array.isArray(body.contents) || body.contents.length === 0) {
      return Response.json(
        { error: "Missing multimodal contents array" },
        { status: 400 }
      );
    }

    const upstreamUrl = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;

    let upstreamResponse: Response;
    try {
      upstreamResponse = await fetch(upstreamUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": env.GEMINI_API_KEY,
        },
        body: JSON.stringify({
          systemInstruction: body.systemInstruction,
          contents: body.contents,
          generationConfig: body.generationConfig,
        }),
      });
    } catch {
      return Response.json({ error: "Failed to reach Gemini API" }, { status: 502 });
    }

    const upstreamText = await upstreamResponse.text();
    if (!upstreamResponse.ok) {
      return new Response(upstreamText, {
        status: upstreamResponse.status,
        headers: { "Content-Type": "application/json" },
      });
    }

    try {
      const parsed = JSON.parse(upstreamText) as GeminiApiResponse;
      // Skip any "thought" parts and join the answer text (it may be split across parts).
      const jsonText = (parsed.candidates?.[0]?.content?.parts ?? [])
        .filter((part) => !part.thought && typeof part.text === "string")
        .map((part) => part.text)
        .join("");
      if (jsonText) {
        return new Response(jsonText, {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      }
      return new Response(upstreamText, {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    } catch {
      return Response.json(
        { error: "Failed to parse upstream Gemini response" },
        { status: 502 }
      );
    }
  },
};
