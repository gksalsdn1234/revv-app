import { consumeRateLimit } from "../_shared/security.ts";
import {
  readJsonWithLimit,
  RequestBodyTooLargeError,
} from "../_shared/bounded_json.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const allowedVoices = new Set([
  "ko-KR-Chirp3-HD-Leda",
  "ko-KR-Chirp3-HD-Autonoe",
  "ko-KR-Chirp3-HD-Aoede",
  "ko-KR-Chirp3-HD-Charon",
  "ko-KR-Wavenet-D",
]);
const maxRequestBytes = 8 * 1024;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ audioContent: "", error: "method_not_allowed" }, 405);
  }
  if (!(await consumeRateLimit(req, "synthesize-tts", 25, 60))) {
    return json({ audioContent: "", error: "rate_limited" }, 429);
  }

  try {
    const apiKey = Deno.env.get("GOOGLE_TTS_API_KEY");
    if (!apiKey) {
      return json({ audioContent: "", error: "tts_config_missing" });
    }

    const body = await readJsonWithLimit(req, maxRequestBytes);
    if (body === null || typeof body !== "object") {
      return json({ audioContent: "", error: "invalid_request" }, 400);
    }
    const { text, voiceName } = body as Record<string, unknown>;
    const trimmed = String(text ?? "").trim().slice(0, 500);
    if (!trimmed) return json({ audioContent: "" });
    const selectedVoice = allowedVoices.has(String(voiceName))
      ? String(voiceName)
      : "ko-KR-Chirp3-HD-Leda";

    const upstream = await fetch(
      `https://texttospeech.googleapis.com/v1/text:synthesize?key=${apiKey}`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          input: { text: trimmed },
          voice: {
            languageCode: "ko-KR",
            name: selectedVoice,
          },
          audioConfig: {
            audioEncoding: "MP3",
            speakingRate: 0.92,
            pitch: -1.0,
          },
        }),
      },
    );

    if (!upstream.ok) {
      return json({ audioContent: "", error: "tts_upstream_failed" });
    }
    const data = await upstream.json();
    return json({ audioContent: data.audioContent ?? "" });
  } catch (error) {
    if (error instanceof RequestBodyTooLargeError) {
      return json({ audioContent: "", error: "request_too_large" }, 413);
    }
    if (error instanceof SyntaxError) {
      return json({ audioContent: "", error: "invalid_request" }, 400);
    }
    return json({ audioContent: "", error: "tts_request_failed" });
  }
});

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}
