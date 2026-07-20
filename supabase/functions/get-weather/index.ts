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
const maxRequestBytes = 4 * 1024;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json(defaultWeather("method_not_allowed"), 405);
  }
  if (!(await consumeRateLimit(req, "get-weather", 60, 60))) {
    return json(defaultWeather("rate_limited"), 429);
  }

  try {
    const apiKey = Deno.env.get("WEATHER_API_KEY") ??
      Deno.env.get("OPENWEATHER_API_KEY");
    if (!apiKey) {
      return json(defaultWeather("weather_config_missing"));
    }

    const body = await readJsonWithLimit(req, maxRequestBytes);
    if (body === null || typeof body !== "object") {
      return json(defaultWeather("invalid_request"), 400);
    }
    const { lat, lng } = body as Record<string, unknown>;
    const latitude = Number(lat);
    const longitude = Number(lng);
    if (
      !Number.isFinite(latitude) ||
      !Number.isFinite(longitude) ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180
    ) {
      return json(defaultWeather("invalid_coordinates"), 400);
    }
    const url = new URL("https://api.openweathermap.org/data/2.5/weather");
    url.searchParams.set("lat", latitude.toFixed(5));
    url.searchParams.set("lon", longitude.toFixed(5));
    url.searchParams.set("appid", apiKey);
    url.searchParams.set("units", "metric");
    url.searchParams.set("lang", "kr");

    const upstream = await fetch(url);
    if (!upstream.ok) {
      return json(defaultWeather("weather_upstream_failed"));
    }
    const data = await upstream.json();
    return json({
      weather: data.weather ?? [{ id: 800, description: "맑음", icon: "01d" }],
      main: data.main ?? { temp: 0 },
    });
  } catch (error) {
    if (error instanceof RequestBodyTooLargeError) {
      return json(defaultWeather("request_too_large"), 413);
    }
    if (error instanceof SyntaxError) {
      return json(defaultWeather("invalid_request"), 400);
    }
    return json(defaultWeather("weather_request_failed"));
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
