const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const fallbackVoices = [
  { name: "ko-KR-Chirp3-HD-Leda", locale: "ko-KR", label: "Leda · Premium HD" },
  {
    name: "ko-KR-Chirp3-HD-Autonoe",
    locale: "ko-KR",
    label: "Autonoe · Premium HD",
  },
  {
    name: "ko-KR-Chirp3-HD-Aoede",
    locale: "ko-KR",
    label: "Aoede · Premium HD",
  },
  {
    name: "ko-KR-Chirp3-HD-Charon",
    locale: "ko-KR",
    label: "Charon · Premium HD",
  },
  { name: "ko-KR-Wavenet-D", locale: "ko-KR", label: "Wavenet-D · Classic" },
];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const apiKey = Deno.env.get("GOOGLE_TTS_API_KEY");
  if (!apiKey) {
    return json({
      voices: fallbackVoices,
      error: "GOOGLE_TTS_API_KEY missing",
    });
  }

  try {
    const upstream = await fetch(
      `https://texttospeech.googleapis.com/v1/voices?languageCode=ko-KR&key=${apiKey}`,
    );
    if (!upstream.ok) {
      return json({ voices: fallbackVoices, error: await upstream.text() });
    }
    const data = await upstream.json();
    const voices = (data.voices ?? [])
      .map((voice: { name?: string; languageCodes?: string[] }) => ({
        name: voice.name ?? "",
        locale: voice.languageCodes?.[0] ?? "ko-KR",
        label: voice.name ?? "Google Korean Voice",
      }))
      .filter((voice: { name: string }) => voice.name.length > 0);
    return json({ voices: voices.length > 0 ? voices : fallbackVoices });
  } catch (error) {
    return json({ voices: fallbackVoices, error: String(error) });
  }
});

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}
