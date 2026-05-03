# REVV Supabase Edge Functions

These functions provide the app's optional cloud helper layer. They are optional
cloud helpers: if a secret is missing or an upstream API fails, the Flutter app
falls back to local/default behavior.

## Functions

- `call-ai`: Anthropic-compatible AI proxy. Returns `{ "text": "..." }`.
- `get-weather`: OpenWeather proxy. Returns a minimal OpenWeather-compatible
  `{ weather, main }` shape.
- `list-google-tts-voices`: Google TTS voices proxy. Returns
  `{ voices: [...] }`.
- `synthesize-tts`: Google TTS synthesis proxy. Returns `{ audioContent }` as
  base64 MP3.

## Required Secrets

```sh
supabase secrets set AI_API_KEY=...
supabase secrets set WEATHER_API_KEY=...
supabase secrets set GOOGLE_TTS_API_KEY=...
```

`AI_API_KEY` may also be provided as `ANTHROPIC_API_KEY`, and `WEATHER_API_KEY`
may also be provided as `OPENWEATHER_API_KEY`.

## Deploy

```sh
export SUPABASE_ACCESS_TOKEN=...
export SUPABASE_PROJECT_REF=zvwgnduuumksuqazpvsf
bash scripts/deploy_supabase_functions.sh
```

The deploy script uses `--use-api`, so it does not require Docker.

## Smoke Checks

```sh
supabase functions invoke call-ai --body '{"model":"claude-haiku-4-5-20251001","system":"Reply briefly.","messages":[{"role":"user","content":"ping"}],"maxTokens":20}'
supabase functions invoke get-weather --body '{"lat":45.5,"lng":-73.57}'
supabase functions invoke list-google-tts-voices --body '{}'
supabase functions invoke synthesize-tts --body '{"text":"안녕하세요","voiceName":"ko-KR-Chirp3-HD-Leda"}'
```

If a secret is missing, the function should still return JSON and the app should
continue with fallback UI/audio.
