# REVV

REVV is a Flutter driving companion focused on three core flows:

- discover an enjoyable route
- drive with a focused HUD and optional telemetry
- save the run and review coaching/summary afterward

This repository is currently in MVP stabilization mode. Core driving flows are prioritized over feature breadth.

## Current MVP Scope

- app boot and loading flow
- route browse/select flow
- cruise, drive, and sprint driving flows
- run save and history view
- optional OBD, AI, and cloud integrations that should fail safely

## Temporarily De-scoped or Placeholder Features

The following areas are intentionally reduced for stability during this phase:

- detailed analysis screen
- rich route preview expansion
- elevation data fetching uses a lightweight fallback service

These are kept build-safe so they do not block the main user flow.

## Setup

### Requirements

- Flutter SDK
- a valid Mapbox access token configured in the project
- Firebase project configuration if you want cloud and AI features fully enabled

### Install

```bash
flutter pub get
```

### Run

```bash
flutter run
```

### Verify

```bash
flutter analyze
flutter test
```

Note: `flutter analyze` currently reports warnings and infos, but MVP-blocking analyzer errors should be zero.

## Key Project Areas

- `lib/main.dart`: app bootstrap, providers, Firebase init fallback
- `lib/screens/`: user-facing flows like loading, routes, cruise, sprint, run card
- `lib/services/`: route generation, run tracking, OBD, AI, sync, settings
- `lib/models/`: route, run, and telemetry contracts

## Stability Rules for This Phase

- OBD must remain optional
- AI failures must fall back to local responses
- cloud sync failures must not block local save/use
- missing or incomplete expansion features should degrade gracefully instead of breaking build/runtime
