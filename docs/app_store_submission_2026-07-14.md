# REVV App Store submission packet — 2026-07-14

Release candidate: `1.38.0 (55)`
Bundle ID: `com.revv.revvApp`
Release flags: no `REVV_EXPLORATION_FOG`, no `REVV_WALKIE_LAB`

## App information

- Name: `REVV`
- Primary category: `Navigation`
- Secondary category: `Travel`
- Korean subtitle: `드라이브 루트와 기록`
- English subtitle: `Curvy routes & drive logs`
- Content rights: no third-party licensed media is bundled. The previous beep asset and player dependency were removed.
- Age rating recommendation: answer the questionnaire from actual app behavior. The app has no gambling, sexual, horror, drug, profanity, user-generated public feed, or unrestricted web browsing content. Driving/navigation functionality must still be declared accurately.

## Version copy

### Korean promotional text

캐나다 전역 지도에서 이용 가능한 커브 루트를 발견하고, 주행 흐름부터 기록까지 한곳에서 확인하세요.

### English promotional text

Discover available curvy routes on a Canada-wide map, preview the flow, and keep each drive in one focused log.

Use the full descriptions, keywords, privacy mapping, and release notes from `docs/store_assets_draft.md`.

## Review notes

REVV uses When-In-Use location to search routes, show the driver's position, and save a route log. If the reviewer explicitly chooses navigation to a route start, REVV arms that single route and begins the same record only after two accurate moving fixes within the start zone. The app does not monitor every route.

No demo account is needed. REVV creates an anonymous Supabase session automatically. The reviewer can allow location access, choose an available route, open route details, select Start drive, and use Test drive from here to exercise the drive and summary flow without physically driving.

Cloud drive storage is opt-in in Settings. The same screen provides deletion controls. The App Store build keeps exploration fog and the walkie-talkie lab disabled.

## App Privacy answers

Declare these as collected and linked to the app's anonymous User ID, used for App Functionality unless App Store Connect requires a more specific purpose:

- Precise Location: route search, current-position map, route logs, optional cloud recovery.
- User ID: Supabase anonymous account boundary and deletion/restoration.
- Product Interaction: route feedback, bookmarks, route-run count, recommendation choice.
- Other Data: drive duration/distance, route samples, motion summaries, corner events.

Declare:

- Tracking: No.
- Contact Info: No.
- Purchases/Financial Info: No.
- Diagnostics: No for this candidate; no release Sentry DSN is configured.

## Screenshot package

Apple accepts 1–10 screenshots. Prepare clean portrait PNGs without simulator chrome:

1. Route map with multiple visible routes and no selected-card overlap.
2. Selected route preview with Mapbox attribution unobscured.
3. Route detail with curve mix and Start drive.
4. Drive screen with next-curve guidance and unobscured Mapbox ornaments.
5. Post-drive summary/history.
6. Settings with cloud storage and privacy controls.

Required set for the current phone-first Xcode target:

- iPhone 6.9-inch: use an accepted portrait size such as `1320 × 2868`.

Final files belong under `store_assets/screenshots/final/iphone_6_9/`. iPad was removed from the release target because this safety-first driving interface was designed and reviewed as a phone surface; this also avoids shipping an unreviewed landscape/tablet layout.

Current capture status (2026-07-13):

- The native launch screen was captured for implementation QA, but launch/loading images are not part of the App Store product screenshot set.
- The previous map capture is retained only under `store_assets/screenshots/drafts/iphone_6_9/01_route_map_needs_retake.png`; it must not be submitted because it predates the scale-bar/race fixes and the downtown viewport does not visibly show route lines.
- The final folder contains all six current-build screenshots: route map, selected route preview, route detail, drive HUD, history, and settings.
- Every final image is a portrait `1320 × 2868` RGB PNG with no alpha channel. The set was recaptured after the route preview, detail CTA, drive HUD, history metrics, and settings storage-state fixes.
- Manual visual QA confirmed unobscured Mapbox attribution/information controls, no scale bar, no selected-card/tab-bar collisions, centered action/navigation icons, no duplicated drive cue, and no simulator chrome. The draft and launch/loading images remain non-submission evidence only.

## Build and upload

```sh
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build ipa --release --dart-define-from-file=/Users/minwoohan/Documents/revv-app/.env --build-name=1.38.0 --build-number=55
```

The assigned integration worktree intentionally has no `.env`. The command above reads the existing gitignored REVV environment file without copying secrets into this worktree. Do not add exploration-fog or walkie-lab defines.

### Verified release state (2026-07-13)

- `flutter analyze`: passed with no issues.
- `flutter test`: 533 passed; 2 live-environment tests skipped by design.
- iOS Release archive: rebuilt after all source and visual fixes at `build/ios/archive/Runner.xcarchive` (`1.38.0 (55)`, arm64, iPhone-only, iOS 15 minimum); deep code-sign verification passed and no app source is newer than the archive.
- IPA export/upload: blocked on this Mac because Xcode has no usable Apple Distribution certificate/account, even though a development-signed archive was created.
- Physical iPhone: the final archive app was installed and launched successfully on device `00008120-000621623E90A01E` after the final HUD and screenshot pass.
- Production Supabase: release boundary migrations through `20260713120000_bound_route_search_and_canonical_geometry.sql` applied and remote/local migration history aligned.
- Production Edge Functions: `call-ai`, `get-weather`, `list-google-tts-voices`, and `synthesize-tts` deployed with bounded request handling and rate controls.
- Live backend smoke: unauthenticated route RPC rejected with `401`; authenticated guest route RPC succeeded and clamped an excessive request to `120` rows; direct authenticated crew-channel insert rejected with `403`. Earlier owned-write, duplicate, and invalid-run-receipt checks also passed.
- iOS simulator runtime: upgraded the transitive `objective_c` package to `9.4.1`, removing the official FFI loader crash; a clean launch completed Canada-wide loading without `DOBJC`, unhandled, or Mapbox `PlatformException` logs.
- Voice briefing runtime: the start greeting is silent; short straight segments below 1 km are omitted from both speech and the next-maneuver banner; each navigation event speaks once; plain-language curve calls such as `우측 급커브`, `좌측 급회전`, and `좌우 커브 4개` are serialized so a new call cannot start over the current one; intermediate Mapbox leg arrivals are ignored and completion appears only at the real route end. The completed HUD now displays `0m` remaining instead of falling back to the route's total distance.

## Manual fields that still require the owner

- Add the Apple Developer account to Xcode and install/refresh an Apple Distribution certificate plus App Store provisioning profile, then export/upload build `55`.
- Verify the public Privacy Policy URL configured in `/Users/minwoohan/Documents/revv-app/.env` opens and contains a real contact email; the draft still has a placeholder.
- Supply and verify a public Support URL with contact information.
- Enter the App Review contact name, phone, and email.
- Confirm agreements, tax, banking, DSA/trader status, price, countries, and release option in App Store Connect.
- Upload/select build `55`, attach screenshots, choose `Add for Review`, then `Submit for Review`.

## Apple references

- Screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- App privacy: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- Required fields: https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties/
- Submission flow: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app
