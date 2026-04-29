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
    const apiKey = Deno.env.get("GOOGLE_TTS_API_KEY");
    if (!apiKey) {
      return json({ audioContent: "", error: "GOOGLE_TTS_API_KEY missing" });
    }

    const { text, voiceName } = await req.json();
    const trimmed = String(text ?? "").trim();
    if (!trimmed) return json({ audioContent: "" });

    const upstream = await fetch(
      `https://texttospeech.googleapis.com/v1/text:synthesize?key=${apiKey}`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          input: { text: trimmed },
          voice: {
            languageCode: "ko-KR",
            name: voiceName ?? "ko-KR-Chirp3-HD-Leda",
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
      return json({ audioContent: "", error: await upstream.text() });
    }
    const data = await upstream.json();
    return json({ audioContent: data.audioContent ?? "" });
  } catch (error) {
    return json({ audioContent: "", error: String(error) });
  }
});

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}
