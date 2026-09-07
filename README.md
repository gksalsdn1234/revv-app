# REVV

REVV is a Flutter driving companion centered on one lean MVP flow:

- discover a good driving route
- drive with a focused map HUD
- save the run afterward

## Current status — 2026-09-07

Active worktree: `/Users/minwoohan/Documents/revv-app-release-integration`, branch `codex/revv-guideline4-language`. Older worktrees and `codex/revv-unified-workspace` are preserved history; follow [COLLABORATION.md](COLLABORATION.md) before editing.

See [today’s work and remaining tasks](docs/2026-09-07-work-log.md) and [route delivery measurements](docs/2026-09-07-route-delivery-performance.md). Both September 7 route API migrations are deployed. Updated client geometry delivery and the restored iOS icon are verified locally; no September 7 app upload occurred. Source version remains `1.38.0+63`.

## Current MVP Scope

- `main.dart` opens `LeanAppShellScreen`, with map-based route discovery, history and settings.
- `LeanRouteFinderScreen` shows nearby routes, the route list and selection preview. Nearby/catalog limits remain 120/650.
- Display geometry is lightweight; selected and active routes resolve authoritative full geometry before use.
- `LeanDriveScreen` tracks location and route progress with a focused HUD; route chains preserve their source geometry.
- Run summaries and detailed telemetry are saved locally with optional cloud sync. Open lifecycle/recovery findings are recorded in the work log.
- Supabase remains the route/run backend and must fail safely.

## Removed From Lean MVP

- Garage, rankings, saved-route management, route editor, route wizard, trip planner, and advanced history UI.
- OBD UI/service, AI review, Google TTS, STT, always-listening, weather briefing, loop builder, and advanced route preview.
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

This release-integration worktree intentionally has no `.env`; use the existing gitignored REVV environment file:

```bash
flutter run --dart-define-from-file=/Users/minwoohan/Documents/revv-app/.env
```

### Verify

```bash
flutter analyze
flutter test
flutter build ios --release --no-codesign --dart-define-from-file=/Users/minwoohan/Documents/revv-app/.env
```

Build 63 was already uploaded on September 1. Choose an unused build number after checking App Store Connect before a new upload; do not reuse older build-55/59 commands. A GitHub push does not release the updated app or icon.

The App Store candidate keeps `REVV_EXPLORATION_FOG` and `REVV_WALKIE_LAB` disabled. Apply and verify the exploration migration before a later build enables that visual feature.

## Key Project Areas

- `lib/main.dart`: app bootstrap and provider wiring
- `lib/screens/lean_app_shell_screen.dart`: current app shell and map-first entry
- `lib/screens/lean_route_finder_screen.dart`: map-first route selection
- `lib/screens/lean_drive_screen.dart`: route drive HUD
- `lib/screens/lean_run_summary_screen.dart`: run save confirmation
- `lib/services/route_service.dart`: Supabase-first route loading, cache, selection, node hydration
- `lib/services/supabase_service.dart`: Supabase auth, runs, run details, curvy road RPC access
- `lib/models/`: route, run, OBD summary, and telemetry contracts
- `tools/curvature_pipeline/`: KMZ to Supabase preprocessing pipeline
- `supabase/migrations/`: versioned production SQL migrations
- `supabase/tests/`: rollback-based SQL contract fixtures
- `tools/supabase_migrations/`: historical schema/setup tooling

## Stability Rules For This Phase

- Keep the active flow centered on `LeanAppShell → RouteFinder → Drive → RunSummary`.
- Do not reintroduce legacy screens into the lean flow.
- Supabase failures must not block app startup or local run saving.
- RouteFinder must stay map-first and avoid large overlapping cards.
- Drive UI must keep only essential controls: next curve, speed, G meter, and end run.
- iOS permission metadata and localized native copy must match actual features. Current declarations cover location When-In-Use, microphone and motion; speech recognition is absent.
