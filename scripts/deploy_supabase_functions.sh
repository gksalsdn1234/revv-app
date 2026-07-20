#!/usr/bin/env bash
set -euo pipefail

PROJECT_REF="${SUPABASE_PROJECT_REF:-zvwgnduuumksuqazpvsf}"
FUNCTIONS=(
  call-ai
  get-weather
  list-google-tts-voices
  synthesize-tts
  delete-account
)

if ! command -v supabase >/dev/null 2>&1; then
  echo "supabase CLI not found. Install it or put it on PATH first." >&2
  exit 1
fi

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "SUPABASE_ACCESS_TOKEN is required for non-interactive deploy." >&2
  echo "Create one in Supabase dashboard, then run:" >&2
  echo "  export SUPABASE_ACCESS_TOKEN=..." >&2
  exit 1
fi

for fn in "${FUNCTIONS[@]}"; do
  echo "Deploying $fn to $PROJECT_REF..."
  supabase functions deploy "$fn" --project-ref "$PROJECT_REF" --use-api
done

echo "Done. Remember to set Edge Function secrets if not already configured:"
echo "  supabase secrets set AI_API_KEY=... WEATHER_API_KEY=... GOOGLE_TTS_API_KEY=... --project-ref $PROJECT_REF"
