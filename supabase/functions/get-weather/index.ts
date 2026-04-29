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
    const apiKey = Deno.env.get("WEATHER_API_KEY") ??
      Deno.env.get("OPENWEATHER_API_KEY");
    if (!apiKey) {
      return json(defaultWeather("WEATHER_API_KEY missing"));
    }

    const { lat, lng } = await req.json();
    const url = new URL("https://api.openweathermap.org/data/2.5/weather");
    url.searchParams.set("lat", String(lat));
    url.searchParams.set("lon", String(lng));
    url.searchParams.set("appid", apiKey);
    url.searchParams.set("units", "metric");
    url.searchParams.set("lang", "kr");

    const upstream = await fetch(url);
    if (!upstream.ok) {
      return json(defaultWeather(await upstream.text()));
    }
    const data = await upstream.json();
    return json({
      weather: data.weather ?? [{ id: 800, description: "맑음", icon: "01d" }],
      main: data.main ?? { temp: 0 },
    });
  } catch (error) {
    return json(defaultWeather(String(error)));
  }
});

function defaultWeather(error: string) {
  return {
    weather: [{ id: 800, description: "맑음", icon: "01d" }],
    main: { temp: 0 },
    error,
  };
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}
