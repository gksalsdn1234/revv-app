# REVV Security Hardening Plan

## Scope

This document tracks the security and privacy work needed before a wider beta. The first pass closes the issues that can block TestFlight or cause misleading privacy behavior. Larger storage refactors are kept as follow-up work so the release branch stays stable.

## Completed In Current Patch

- Added defensive iOS purpose strings for Speech Recognition and Always Location references that can be pulled in by permission libraries.
- Guarded route usage uploads behind the same `cloudRunStorageEnabled` preference used for run summaries and telemetry details.
- Changed run data deletion so local data is not cleared when cloud deletion fails.
- Added local pending upload purge when cloud run storage is disabled from the home screen.
- Wrapped Mapbox/route debug logs behind `kDebugMode` and removed raw exception text from release logs.
- Moved pending `RunTelemetryDetail` payloads out of plain `SharedPreferences` into secure string storage with legacy migration and corrupt-payload cleanup.
- Added 14-day TTL cleanup for stale pending telemetry details at app history load and pending retry time.
- Added active Supabase core schema migrations and explicit Data API grants for route/run tables and RPC functions.
- Added static migration security tests and a Supabase verification runbook for staging/production checks.
- Added Supabase Security Advisor cleanup migration for app-owned function `search_path` and public execute grants.
- Applied linked Supabase remote migrations through `20260501005000_revoke_anon_user_data.sql`; `anon` can still discover routes but cannot read user run/history tables.

## Next Required Block

- If long-session telemetry payloads grow beyond comfortable Keychain/secure-storage limits, move pending detail payloads to encrypted files with a Keychain-stored key and `NSFileProtectionCompleteUntilFirstUserAuthentication`.
- Keep cloud storage opt-out behavior strict: no new detail upload, no permanent local detail retention, and legacy pending payloads purged on opt-out.

## Supabase Required Block

- Active migrations now include the production bootstrap schema and explicit grants:
  - `runs`
  - `run_details`
  - `route_feedback`
  - `route_records`
  - `saved_routes`
  - `discovered_routes`
  - read-only route tables/RPCs such as `curvy_roads` and `find_curvy_roads`
- Keep RLS owner policies on user data tables.
- Verify new Supabase project bootstrap with `supabase db reset` or a staging project before external beta.
- Follow `docs/supabase_security_verification.md` before opening a wider TestFlight group.
- Current linked project has been migrated and privilege-checked. Re-run the verification runbook before every new external beta build.
- Current known non-blocking advisor warnings: PostGIS public extension objects, anonymous beta auth posture, password/MFA warnings for login flows not exposed in MVP.

## Edge Function Required Block

- Require a verified Supabase JWT for paid/proxy functions.
- Keep IP fallback only for non-costly public functions, if any.
- Return stable error codes to the app and avoid raw upstream error strings.

## Release Checklist Reminder

- Bump build number for every App Store Connect upload.
- Clean iOS pods/archive after permission or Podfile changes.
- Re-run:
  - `flutter analyze`
  - `flutter test`
  - `flutter build ios --release --no-codesign --dart-define-from-file=.env`
