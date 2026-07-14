import { z, ZodError } from "npm:zod@4.1.12";
import {
  readJsonWithLimit,
  RequestBodyTooLargeError,
} from "../_shared/bounded_json.ts";
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
const maxRequestBytes = 64 * 1024;
const requestSchema = z.object({
  model: z.string().default("claude-haiku-4-5-20251001"),
  system: z.string().default(""),
  messages: z.array(
    z.object({
      role: z.enum(["user", "assistant"]),
      content: z.string().min(1),
    }),
  ).min(1).max(6),
  maxTokens: z.number().finite().default(200),
});
const upstreamSchema = z.object({
  content: z.array(
    z.object({
      type: z.string(),
      text: z.string().optional(),
    }),
  ).default([]),
});

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

    const body = requestSchema.parse(
      await readJsonWithLimit(req, maxRequestBytes),
    );
    const requestedModel = body.model;
    const model = allowedModels.has(requestedModel)
      ? requestedModel
      : "claude-haiku-4-5-20251001";
    const system = truncate(body.system, 800);
    const messages = body.messages.map((message) => ({
      role: message.role,
      content: truncate(message.content, 1200),
    }));
    const maxTokens = clamp(body.maxTokens, 40, 350);

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

    const data = upstreamSchema.parse(await upstream.json());
    const text = data.content
      .map((part) => part.type === "text" ? part.text ?? "" : "")
      .join("")
      .trim();
    return json({ text });
  } catch (error) {
    if (
      error instanceof RequestBodyTooLargeError ||
      error instanceof SyntaxError ||
      error instanceof ZodError
    ) {
      return json({ text: "", error: "invalid_request" }, 400);
    }
    return json({ text: "", error: "ai_request_failed" }, 200);
  }
});

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
