# REVV

REVV is a Flutter driving companion centered on one lean MVP flow:

- discover a good driving route
- drive with a focused map HUD
- save the run afterward

The `lean_mvp` branch intentionally removes non-essential product experiments. `main` remains the full experimental app; this branch is the clean core used to rebuild product quality.

## Current MVP Scope

- `LoadingScreen` asks only for location permission.
- `LeanHomeScreen` exposes one primary action: route finding.
- `LeanRouteFinderScreen` shows the map, nearby route candidates, and a compact route ticket.
- `LeanDriveScreen` tracks current location, route progress, next curve, speed, and G meter.
- `LeanRunSummaryScreen` saves `RunSummary` and `RunTelemetryDetail`.
- Supabase remains the route/run backend and must fail safely.

## Removed From Lean MVP

- Garage, rankings, saved-route management, route editor, route wizard, trip planner, and advanced history UI.
- OBD UI/service, AI review, Google TTS, STT, always-listening, weather briefing, loop builder, chain extension, and advanced route preview.
- Legacy large route cards, bottom sheets, and HUD-heavy screens.

## Setup

### Requirements

- Flutter SDK
- a valid Mapbox access token provided through Dart defines
- a Supabase project if cloud features should be enabled

### Install

```bash
flutter pub get
```

### Supabase Configuration

Cloud features stay disabled unless these Dart defines are provided:

```bash
SUPABASE_URL=...
SUPABASE_ANON_KEY=...
MAPBOX_ACCESS_TOKEN=...
```

Supabase Edge Functions may still exist in the project, but the lean app path does not depend on AI, Google TTS, or speech functions. Weather must fail safely and is not a TestFlight blocker.

### Run

```bash
flutter run --dart-define-from-file=.env
```

### Verify

```bash
flutter analyze
flutter test
flutter build ios --release --no-codesign --dart-define-from-file=.env
```

For a TestFlight candidate, keep the marketing version and increment the build number:

```bash
flutter build ipa --release --dart-define-from-file=.env --build-name=1.38.0 --build-number=41
```

## Key Project Areas

- `lib/main.dart`: app bootstrap and provider wiring
- `lib/screens/lean_home_screen.dart`: lean start hub
- `lib/screens/lean_route_finder_screen.dart`: map-first route selection
- `lib/screens/lean_drive_screen.dart`: route drive HUD
- `lib/screens/lean_run_summary_screen.dart`: run save confirmation
- `lib/services/route_service.dart`: Supabase-first route loading, cache, selection, node hydration
- `lib/services/supabase_service.dart`: Supabase auth, runs, run details, curvy road RPC access
- `lib/models/`: route, run, OBD summary, and telemetry contracts
- `tools/curvature_pipeline/`: KMZ to Supabase preprocessing pipeline
- `tools/supabase_migrations/`: PostGIS schema and RPC setup

## Stability Rules For This Phase

- Keep the app path to `Loading → Home → RouteFinder → Drive → RunSummary`.
- Do not reintroduce legacy screens into the lean flow.
- Supabase failures must not block app startup or local run saving.
- RouteFinder must stay map-first and avoid large overlapping cards.
- Drive UI must keep only essential controls: next curve, speed, G meter, and end run.
- iOS permission metadata must match the lean app: location When-In-Use only.
