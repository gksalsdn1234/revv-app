# Route delivery performance — 2026-09-07

**Current status (2026-09-07):** Both `20260907120251_route_lightweight_overview` and `20260907131716_route_catalog_ordinal_lookup` are deployed to REVV `zvwgnduuumksuqazpvsf`. Final catalog measurements succeeded 3/3 at 1.558 / 2.573 / 1.524 s; nearby lookup still varies from 2.545 to 7.960 s. Client changes and the restored icon are verified in the simulator, but no new App Store upload occurred. See [today’s work log and next steps](2026-09-07-work-log.md). Earlier sections retain their checkpoint-specific evidence.

The map continues to expose many routes. Nearby requests retain the 120-route cap and the catalog retains the 650-route cap. This implementation separates display geometry from navigation geometry rather than reducing those route counts.

## Changes

- `RouteTimingClient` records headers received, consumed response-body bytes and body completion for route RPCs. It excludes URL queries, request/response contents, coordinates, user IDs and credentials. These are consumed body bytes, not compressed bytes on the wire. Location permission/fix, catalog epoch, model conversion, nearby fetch, cache persistence, source application and the following rendered frame have separate measurements. Enable `[REVV][RoutePerf]` output in Debug or with `--dart-define=REVV_ROUTE_PERF=true` for Profile. The post-source frame event is a rendering milestone, not proof that every map tile has loaded.
- New `get_route_overview_v2` and `find_curvy_roads_overview_v2` RPCs simplify only the transmitted display geometry (0.0004 degree tolerance). The stored coordinates, route distances, ranking fields and existing detail RPC remain authoritative. Endpoints and line order are preserved. Server auth, active-publication filtering, ID bounds and epoch validation remain in effect. The helper is private and RPC execution is restricted to authenticated/service roles.
- A persisted `geometryIsOverview` marker prevents a short-looking display polyline from being mistaken for complete route geometry. Selection resolves nodes through the authoritative v2 detail endpoint; concurrent preview/start requests share their work. Detail/start and selected-route planning reject an unresolved overview. Generated routes never use the legacy direct-table fallback. Client-composed budget routes retain their source parts and hydrate each part before rebuilding their full geometry.
- Epoch and nearby requests start concurrently, but generated routes are published only after matching epoch validation. The initial field notifies the UI before its cache write finishes. Existing generated-cache validation remains intentionally unchanged.
- Difficulty sources/layers survive map updates; only their GeoJSON is replaced, and removed groups receive empty data. Identical data is skipped. A latest-state queue discards intermediate pending draws; style reloads invalidate source state. Four difficulty groups are still used.

## Local SQL result

A disposable, network-isolated Postgres 17.6/PostGIS container used the repository's route schema and v2 publication migration. The historical crew-only permission statements were irrelevant to this route-only fixture; auth identity helpers were provided for the local test roles. No production DB was accessed.

The curved synthetic fixture contained **120 routes × 1,200 coordinates**. Catalog JSON fell from **6,476,412 bytes to 203,424 bytes (96.86%)**, with **120 routes before and after**. The local warm overview query took about **99 ms**. These are synthetic JSON payload and local database figures, not measured production/mobile latency; real reduction depends on route geometry and transport compression. Server simplification adds work, so compare its execution time with the full-detail query on production-like data before rollout.

`supabase/tests/route_lightweight_overview.sql` verifies size/count, endpoint and original-detail preservation, nearby response geometry, metadata, permissions and authentication/bounds errors, then rolls back its fixture.

## App verification at the initial local checkpoint

The focused delivery suite passed 14 tests. The full Flutter suite passed 672 tests with two existing intentional skips. Final `flutter analyze --no-pub` found no issues, and `git diff --check` passed. `flutter build ios --simulator --debug --no-pub` also succeeded (Runner.app); no simulator launch or physical-device timing is claimed. These tests cover transport fallback/error boundaries, overview persistence and detail hydration (including composites), concurrent detail deduplication, epoch ordering, and retained-source/latest-state behavior. They do not exercise the native map on a physical phone.

## Current rollout and remaining validation

1. Both scoped route migrations are deployed and recorded in production migration history. Their SQL fixtures, live response/security checks and simulator remeasurements are complete; see the deployment sections below. Do not replay the deployment scripts or push unrelated local migrations.
2. Investigate remaining nearby query variability. Catalog improvement does not establish fast overall startup.
3. On a physical iPhone Profile build with `REVV_ROUTE_PERF=true`, measure empty cache, warm cache, map pan, route selection and start. Separate permission/GPS delay from RPC body time and source/frame time; verify useful visible routes, not only nonempty map data.
4. Release the updated client and icon separately with a new unused build number. Existing released clients do not automatically receive the new overview transport from a server-only deployment; the updated full-detail endpoint does apply to callers of that endpoint.

The initial local checkpoint preceded deployment; the following baseline and first-deployment sections describe historical measurements. The final section records the catalog fix and supersedes its earlier unresolved status. Physical-phone testing remains outstanding.

## Simulator measurement against the configured live backend

Measured on 2026-09-07, iPhone 16e simulator / iOS 26.3, Debug build with the existing environment definitions. Synthetic simulator location was fixed to downtown Montreal. Location permission was pregranted to exclude human dialog delay. The app was absent from this simulator before installation; the first run therefore had no REVV route cache. Two subsequent process relaunches retained the cache/session. No production migration was applied.

| Measurement | Fresh install | Cached relaunch 1 | Cached relaunch 2 |
|---|---:|---:|---:|
| Launch request to first frame after nonempty route source application | ~14.74 s | 3.52 s | 3.25 s |
| Nearby field fetch, including missing-overview fallback | 9.445 s | 4.617 s | 6.047 s |
| Existing nearby RPC: headers received | 7.725 s | 3.233 s | 3.826 s |
| Existing nearby RPC: body fully consumed | 8.297 s | 3.776 s | 4.418 s |
| Nearby response body | 1,200,754 B | 1,200,754 B | 1,200,754 B |
| Nearby model conversion | 41.3 ms | 22.0 ms | 24.4 ms |
| Initial nonempty map source application | 83.6 ms | 79.2 ms | 99.7 ms |
| Initial source content | 120 routes / 23,504 vertices | same | same |

The first fresh-install field request through post-source frame took about 9.62 s. Remaining launch time includes process/Flutter initialization, session setup and location readiness; those startup components were not separately timed. The fresh-install launch timestamp is inferred from the wall-clock native console line and its monotonic offset (approximate); subsequent launch timestamps were recorded directly. Cached source application precedes background refresh.

Both overview RPCs returned HTTP 404 because the new migration is absent. Nearby endpoint probing added 0.76–1.54 s per process before the legacy-compatible v2 endpoint. This is measured current-code behavior against an unmigrated server, not a before/after comparison or a measurement of the overview implementation.

The full catalog detail request returned HTTP 500 after 9.014 s and 8.796 s in the first two runs. It succeeded on the third in 7.733 s with a 3,283,708-byte body; the map then received 220 routes / 37,755 vertices (~13.11 s after launch). The HTTP status is confirmed; the precise server-side reason is unverified and must not be labeled a SQL timeout without server evidence.

These results point to the remote request/response path as the largest measured wait, rather than Dart model conversion or native source application. Header timing includes network/server processing and does not isolate SQL execution. The additive overview functions still delegate to existing v2 queries, so smaller payloads alone cannot be assumed to fix long server waits or intermittent 500s. Next investigate the intended project's query plan, endpoint errors and response-generation time before measuring the deployed overview version.

The post-source frame is a milestone, not pixel-proof that a colored winding route is visible. The observed initial camera remained tightly zoomed on downtown Montreal, where the screenshot showed city streets and a ready Route list button but no colored winding routes. Data readiness and first useful route visibility are distinct; actual first-route discovery also depends on the initial camera/selection flow. These simulator/Debug results are neither physical-iPhone release performance nor statistically robust latency percentiles.

Evidence (local): `/private/tmp/revv-sim-oslog.log`, `/private/tmp/revv-sim-metrics-final.log`, `/private/tmp/revv-sim-warm-starts.jsonl`, `/private/tmp/revv-sim-cold.log`, `/private/tmp/revv-sim-loaded.png`. Metrics were retrieved from iOS unified logs because Flutter logs were not consistently forwarded by `simctl --console`; a temporary Flutter attach session is not used as the timing clock.

UI follow-through after icon-only rebuild: opened Route list and selected its first item, Route Promenade (57.0 km). The preview card, Start drive button and cyan winding route with surrounding red route lines appeared. This confirms usable loaded route data and selected-route rendering; no drive was started and the UI automation duration is not treated as a latency benchmark.

## Latest icon restoration

User requested the previously completed latest icon. Found clean `revv-consolidate` commit `ac99fc171d157d1a50e12e46f155e9dd24a564c3` (2026-08-09), documented in that checkout's `docs/handoff_20260810_submission_and_after.md`. Copied only its 15 iOS AppIcon PNGs into the active release worktree. The design is a white perspective road beneath a red tachometer arc on black. Version/build remains 1.38.0+63.

All 15 PNGs match that commit byte-for-byte, are opaque RGB and match every Contents.json size/scale entry. The iOS Debug simulator build succeeded and installation completed. Computer Use visually confirmed the new icon on the simulator home screen and launched it successfully. No image generation or redesign, broad branch merge, Android/desktop icon change or App Store upload was performed.

## Authorized production deployment and remeasurement

The owner explicitly requested deployment and remeasurement. The configured app host and linked CLI project both matched `zvwgnduuumksuqazpvsf` (Revv, us-east-2, active). The MCP connection still exposed only an unrelated project; the existing CLI login had REVV access. Live function signatures/PostGIS placement and migration history were checked before deployment. Later unrelated migrations already on production were preserved.

Applied **only** the prepared migration through the linked Management API using `supabase db query --linked`, in one transaction with its `supabase_migrations.schema_migrations` record and a PostgREST schema reload notification. This avoided pushing unrelated local migration history. Guards required the new functions and version to be absent before execution. SQL SHA-256: `1ce0b9647f2fdae1a28022a02146701449294a3d06ddb2e47c6ccb876c276288`. A rollback script was prepared at `/private/tmp/revv-overview-rollback.sql` and was **not executed**. All three preexisting route function definitions exactly match the saved preflight definitions after deployment.

Live validation retained 120 matched route IDs and endpoints, and marked every response as overview. Vertices fell from 23,504 to 2,754. Distance equality was initially checked with exact floating-point equality, which flagged 59 values; a follow-up showed a maximum JSON-roundtrip difference of only 4.97e-14 km (all below 1e-10 km), with no actual route-distance modification. Anonymous execution is denied for both RPCs; authenticated execution is enabled; the helper remains inaccessible to authenticated clients. Missing authentication and empty IDs produce their expected errors.

Security advisors: 36 preexisting notices and two new notices for the intentional authenticated SECURITY DEFINER RPCs. Both new functions have explicit identity checks, pinned search paths, denied anon/PUBLIC execution and delegate visibility to the existing APIs. No broad permission changes were made. The two notices were reviewed, not misreported as a clean advisor pass. [Advisor explanation](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

### Post-deployment simulator results

Same iPhone 16e / iOS 26.3 Debug app, existing environment configuration and synthetic Montreal location. The first post-deployment run removed only the route field cache and overview-cache file after backing them up; login/session/settings were retained. The failed initial `simctl defaults delete` did not clear the app's sandbox preference domain, so the known cache key was removed from the stopped app's plist directly. The absence of cached routes was verified by empty map sources until the HTTP result arrived. The two subsequent relaunches retained the newly fetched caches.

| Measurement | Route-cache empty | Cached relaunch 1 | Cached relaunch 2 |
|---|---:|---:|---:|
| Launch to first post-source frame | 5.455 s | 2.192 s | 3.335 s |
| Nearby field fetch | 2.645 s | 2.379 s | 7.852 s |
| Nearby overview RPC headers | 2.220 s | 1.927 s | 7.435 s |
| Nearby overview RPC body complete | 2.584 s | 2.330 s | 7.801 s |
| Nearby response body | 415,062 B | 415,062 B | 415,062 B |
| First nonempty source application | 30.8 ms | 174.3 ms | 55.3 ms |
| Catalog overview response | HTTP 500 / 9.313 s | HTTP 200 / 7.491 s | HTTP 500 / 9.727 s |

The nearby body is **65.4% smaller** than the measured pre-deployment 1,200,754 bytes while retaining 120 routes. The successful catalog response is **817,859 bytes**, versus the earlier full response's 3,283,708 bytes (75.1% smaller). Both new endpoints are reachable; no missing-function fallback occurred. The fresh-cache field fetch improved in the first observed comparison from 9.445 to 2.645 s, but the third run still took 7.852 s. This is a real transfer reduction with unresolved latency variability, not a consistently fast endpoint. The earlier 14.74-second fresh installation and current 5.455-second route-cache-empty launch differ in retained auth/platform caches and must not be presented as a controlled startup-speed comparison. Three sequential runs do not establish latency percentiles or causal speedup independently of network/server warmth.

The catalog still failed in two of three runs. A read-only live EXPLAIN ANALYZE under the authenticated role and an eight-second statement limit reproduced SQLSTATE **57014: canceling statement due to statement timeout**. Repeating with JIT disabled only within that transaction also timed out; its error context identifies the preexisting **get_route_nodes_v2 bulk-node SELECT**, called by the new catalog overview wrapper. JIT alone is therefore not an established remedy. A non-executing plan confirms the ID lookup has a primary-key index path; it is insufficient to attribute the timeout to a missing index, locks, I/O or serialization. No production timeout, JIT, index, stored route or legacy API setting was changed. The precise lower-level cause still needs a dedicated investigation.

After timing, Computer Use selected Route Promenade from the real list. The authoritative `get_route_nodes_v2` single-route request succeeded in **430 ms / 11,792 bytes**, and its detailed route page rendered correctly. No drive or invitation was started. The simulator is left open on that route detail for review.

Evidence: `/private/tmp/revv-overview-deploy-result.json`, `/private/tmp/revv-overview-live-check.json`, `/private/tmp/revv-overview-distance-check.json`, `/private/tmp/revv-overview-post-definitions.json`, `/private/tmp/revv-advisors-before.json`, `/private/tmp/revv-advisors-after.json`, `/private/tmp/revv-sim-post-starts.jsonl`, `/private/tmp/revv-sim-post-metrics-final.log`, `/private/tmp/revv-overview-plan.err`, `/private/tmp/revv-overview-plan-jit-off.err`, `/private/tmp/revv-post-catalog-plan-readonly.json`. Production API deployment is complete; catalog latency/error remediation and physical-device release validation remain open.

## Follow-up: authorized catalog timeout fix

The owner asked to fix the remaining bulk catalog query. A read-only actual plan for the original ID-array lookup and `array_position` ordering returned 650 rows in **1,585.958 ms** with **268,004 shared-buffer hits and zero shared reads**. Rewriting the same lookup to expand IDs and their input ordinality once returned the same 650 rows in **8.163 ms / 2,687 shared-buffer hits**. These are the direct lookup subquery measurements, not the entire HTTP request. Repeated processing of the large input array was an evidenced query bottleneck; this was not a missing-index diagnosis.

Migration `20260907131716_route_catalog_ordinal_lookup.sql` changes only `get_route_nodes_v2(text[])` and `get_route_overview_v2(text[])`. Each materializes `unnest(... WITH ORDINALITY)` once, groups duplicate IDs using their first ordinal, joins by route primary key and sorts by the saved ordinal. This preserves existing ANY-style de-duplication and first-input-order behavior without rescanning the array per row. The overview API now directly projects lightweight route metadata/geometry from the same visibility-filtered join, eliminating its intermediate full-node RPC result and second route-table join. Auth checks, 1–650 exact-ID validation, active-generated/legacy visibility, epoch and eight-second limits are preserved. No new index, global setting or stored route rewrite was used.

Verification before deployment:

- Relevant Flutter catalog/transport/migration security suites: **68 passed**. No app code changed in this follow-up, so a new iOS build was unnecessary.
- `tools/build_catalog_ordinal_fixture.py --output <temporary.sql>` generates a runnable version of `supabase/tests/route_catalog_ordinal_lookup.sql` from the actual migration function definitions. It remaps both functions and all route/batch/catalog tables into `pg_temp`, inserts only transaction-local synthetic rows and rolls back. The fixture passed auth denial, malformed/empty/oversized inputs, 650 reversed IDs, duplicates, absent IDs, active/inactive/orphan generated batches, malformed legacy visibility, full geometry and overview metadata/endpoints. Production tables/functions were not written by the fixture.
- An ephemeral candidate overview function against actual 650-route production data completed in **836.873 ms** under the existing eight-second limit. This includes the overview construction and differs from the 8.163 ms direct-lookup benchmark.

Deployment used the existing authorized REVV CLI link and one transaction containing the new migration plus its history record. It required exact MD5 matches of the two previously inspected function definitions before mutation and rejected an already recorded migration version. SQL SHA-256: `b079cad76e07dbe7e13a603bc51fdabc57c01b9fdf641ff2466d337ca5cb0368`. A rollback script was prepared at `/private/tmp/revv-catalog-fix-rollback.sql` and not run. Read-back verified only the intended two function definitions changed; their eight-second limits remain. Security advisor notices remained the same **38**, including the already-reviewed intentional definer notices.

Evidence: `/private/tmp/revv-catalog-direct-plan.json`, `/private/tmp/revv-catalog-ordinal-plan.json`, `/private/tmp/revv-catalog-fixture-result.json`, `/private/tmp/revv-catalog-candidate-live-plan.json`, `/private/tmp/revv-catalog-fix-tests.log`, `/private/tmp/revv-catalog-fix-deploy.json`, `/private/tmp/revv-catalog-fixed-definitions.json`, `/private/tmp/revv-catalog-advisors-after.json`.

### Catalog fix: final simulator verification

The same iPhone 16e / iOS 26.3 Debug build was launched three times against the deployed migration. The first launch cleared only backed-up route caches while retaining login/settings; subsequent launches retained caches. Synthetic location remained Montreal.

| Measurement | Route-cache empty | Cached relaunch 1 | Cached relaunch 2 |
|---|---:|---:|---:|
| Catalog overview HTTP status | 200 | 200 | 200 |
| Catalog request to body complete | 1.558 s | 2.573 s | 1.524 s |
| Catalog response body | 817,859 B | 817,859 B | 817,859 B |
| Nearby field fetch | 7.960 s | 4.820 s | 2.545 s |
| Launch to first post-source frame | 10.768 s | 3.071 s | 2.870 s |

All three catalog requests succeeded, compared with two timeouts in the preceding three-run measurement. The catalog retained 650 routes and the nearby response retained 120; the eight-second function timeout was not raised. Three samples establish observed success, not a production latency percentile or a guarantee against future timeouts.

Nearby latency remains variable and explains the slow route-cache-empty first frame in this run. This follow-up fixes the evidenced catalog bottleneck; it does not establish consistently fast overall startup. The post-source frame is still a data/render milestone, not pixel-proof of a useful route at the initial downtown camera. After measurement, Computer Use opened Route Promenade from the route list and confirmed the detailed route page, geometry, 57 km distance and 89 min duration. No drive or invitation was started; the simulator remains on route detail.

Final evidence: `/private/tmp/revv-sim-fixed-starts.jsonl`, `/private/tmp/revv-sim-fixed-metrics-final.log`, `/private/tmp/revv-sim-fixed-summary.json`. Migration `20260907131716` is deployed and the requested catalog fix/retest is complete. Nearby query optimization, physical-device validation and any App Store release remain separate work.
