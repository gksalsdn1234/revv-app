# RouteFinder Debug Report

Date: 2026-04-02

## Summary
- Symptom 1: Montreal coordinate search was often stuck at 9 routes.
- Symptom 2: Some fallback candidates looked too straight and not fun enough for REVV's winding-first intent.
- Symptom 3: Overpass enrichment frequently failed with `504`, timeout, or empty payloads, so route diversity could not improve beyond the local cache.

## Reproduction
- Emulator GPS fixed to `45.4627167, -73.62658` (Montreal area).
- Opened `Routes` from the app on `emulator-5554`.
- Verified route count from UI tree and Flutter run logs.

## Evidence
- Before the latest fix, the visible route card count stayed at `1 / 9`.
- Flutter run log showed local cache filling the list first, then Overpass failing:
  - `[CloudSync] 루트 풀 저장 완료 — 9개`
  - `[RouteService] https://overpass-api.de/api/interpreter 실패: TimeoutException...`
  - `[RouteService] https://overpass.kumi.systems/api/interpreter 실패: TimeoutException...`
  - `[RouteService] https://overpass.osm.ch/api/interpreter 빈 응답 → 다음 서버 시도`
- After the final fix, the same Montreal flow showed:
  - UI tree card count: `1 / 10`
  - Flutter run log: `[CloudSync] 루트 풀 저장 완료 — 10개`

## Root Causes
1. The route count bottleneck was no longer the strict filter alone. In Montreal, the app was already relying on cached route inventory, and Overpass enrichment was not succeeding often enough to add more.
2. The quality filter had a gap: it used absolute straight-run thresholds, but it did not sufficiently reject routes whose overall shape was dominated by long straight segments relative to total distance.
3. When external enrichment failed, the app had no reliable local fallback to grow from 9 routes to the target 10+ routes.

## Fixes Applied
1. Added stage-based quality thresholds for `strict`, `balanced`, and `expanded`.
2. Added straight-dominance filtering:
   - minimum curvy distance
   - maximum straight fraction relative to total route length
3. Tightened quality scoring so long-straight candidates are penalized even if they pass basic thresholds.
4. Added non-strict cached response reuse rules for later search stages.
5. Added a local `composite winding route` fallback:
   - combines two already-valid winding routes only when the connection gap is short
   - considers multiple endpoint orientations instead of a single end-to-start pairing
   - requires minimum combined curvy fraction before the composite is accepted
   - only activates when visible route count is below the target

## Files Changed
- `lib/services/route_loading_policy.dart`
- `lib/services/route_service.dart`
- `test/route_loading_policy_test.dart`

## Verification
- `flutter test test\\route_loading_policy_test.dart` passed.
- Emulator verification passed on `emulator-5554`.
- Montreal route count now reaches `10` in the `Routes` UI even when Overpass enrichment is still failing in the background.

## Remaining Notes
- Overpass reliability is still a real external bottleneck. The app now degrades more gracefully, but upstream timeouts and empty payloads continue to limit true fresh discovery.
- The current fallback reaches the user goal of `10+` visible routes while preserving winding bias better than simply loosening all filters.
