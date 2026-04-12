# REVV

REVV is a Flutter driving companion centered on three flows:

- discover a good driving route
- drive with a focused HUD and optional telemetry
- save and review the run afterward

This repository is in MVP stabilization mode. The current backend target is Supabase for route data, run sync, saved routes, and rankings.

## Current MVP Scope

- app boot and loading flow
- route browse/select flow
- cruise, drive, and sprint driving flows
- run save and history view
- optional OBD, AI, and Supabase cloud features that must fail safely

## Temporarily Reduced Areas

- detailed analysis screen
- richer route preview expansion
- elevation enrichment stays lightweight and non-blocking

These areas are kept build-safe so they do not block the main user flow.

## Setup

### Requirements

- Flutter SDK
- a valid Mapbox access token configured in the project
- a Supabase project if cloud features should be enabled

### Install

```bash
flutter pub get
```

### Supabase Configuration

Cloud features stay disabled unless these Dart defines are provided:

```bash
--dart-define=SUPABASE_URL=...
--dart-define=SUPABASE_ANON_KEY=...
```

### Run

```bash
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

### Verify

```bash
flutter analyze
flutter test
python -m unittest discover -s test -p "curvature_pipeline_test.py"
```

## Key Project Areas

- `lib/main.dart`: app bootstrap and provider wiring
- `lib/services/supabase_service.dart`: Supabase auth, runs, saved routes, rankings, curvy road RPC access
- `lib/services/route_service.dart`: local cache + Supabase-first route loading + Overpass enrichment fallback
- `lib/models/`: route, run, and telemetry contracts
- `tools/curvature_pipeline/`: KMZ to Supabase preprocessing pipeline
- `tools/supabase_migrations/`: PostGIS schema and RPC setup

## Stability Rules For This Phase

- OBD must remain optional
- AI failures must fall back locally
- Supabase failures must not block local save/use
- missing or incomplete expansion features should degrade gracefully instead of breaking build/runtime
