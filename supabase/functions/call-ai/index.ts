import { consumeRateLimit } from "../_shared/security.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const allowedModels = new Set([
  "claude-haiku-4-5-20251001",
  "claude-sonnet-4-6",
]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ text: "", error: "method_not_allowed" }, 405);
  }
  if (!(await consumeRateLimit(req, "call-ai", 20, 60))) {
    return json({ text: "", error: "rate_limited" }, 429);
  }

  try {
    const apiKey = Deno.env.get("AI_API_KEY") ??
      Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      return json({ text: "", error: "ai_config_missing" }, 200);
    }

    const body = await req.json();
    const requestedModel = String(body.model ?? "claude-haiku-4-5-20251001");
    const model = allowedModels.has(requestedModel)
      ? requestedModel
      : "claude-haiku-4-5-20251001";
    const system = truncate(String(body.system ?? ""), 800);
    const messages = sanitizeMessages(body.messages);
    if (messages.length === 0) {
      return json({ text: "", error: "empty_messages" }, 400);
    }
    const maxTokens = clamp(Number(body.maxTokens ?? 200), 40, 350);

    const upstream = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model,
        system,
        messages,
        max_tokens: maxTokens,
      }),
    });

    if (!upstream.ok) {
      return json({ text: "", error: "ai_upstream_failed" }, 200);
    }

    const data = await upstream.json();
    const text = (data.content ?? [])
      .map((part: { type?: string; text?: string }) =>
        part.type === "text" ? part.text ?? "" : ""
      )
      .join("")
      .trim();
    return json({ text });
  } catch {
    return json({ text: "", error: "ai_request_failed" }, 200);
  }
});

function sanitizeMessages(value: unknown) {
  if (!Array.isArray(value)) return [];
  return value.slice(0, 6).flatMap((item) => {
    if (!item || typeof item !== "object") return [];
    const record = item as Record<string, unknown>;
    const role = record.role === "assistant" ? "assistant" : "user";
    const content = truncate(String(record.content ?? ""), 1200);
    return content.trim().length === 0 ? [] : [{ role, content }];
  });
}

function truncate(value: string, maxLength: number) {
  return value.length <= maxLength ? value : value.slice(0, maxLength);
}

function clamp(value: number, min: number, max: number) {
  if (!Number.isFinite(value)) return min;
  return Math.min(max, Math.max(min, Math.round(value)));
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}
