const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const apiKey = Deno.env.get("AI_API_KEY") ??
      Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      return json({ text: "", error: "AI_API_KEY missing" }, 200);
    }

    const body = await req.json();
    const model = body.model ?? "claude-haiku-4-5-20251001";
    const system = body.system ?? "";
    const messages = Array.isArray(body.messages) ? body.messages : [];
    const maxTokens = Number(body.maxTokens ?? 200);

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
      const error = await upstream.text();
      return json({ text: "", error }, 200);
    }

    const data = await upstream.json();
    const text = (data.content ?? [])
      .map((part: { type?: string; text?: string }) =>
        part.type === "text" ? part.text ?? "" : ""
      )
      .join("")
      .trim();
    return json({ text });
  } catch (error) {
    return json({ text: "", error: String(error) }, 200);
  }
});

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}
