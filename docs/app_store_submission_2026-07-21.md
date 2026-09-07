# REVV App Store submission packet — 2026-07-21

> Historical build-59 submission packet. Current development/deployment status is in [2026-09-07 work log](2026-09-07-work-log.md). Build 63 was uploaded and resubmitted September 1; the July candidate, commands and draft state below are historical and must not be reused for a new upload. No September 7 app upload occurred.

## Candidate identity and local evidence

| Field | Prepared value / evidence |
| --- | --- |
| App | REVV |
| Bundle ID | `com.revv.revvApp` |
| Candidate | `1.38.0 (59)` |
| Source | `edd5b23f9be0c33109326fc2d43af212ebf4da95` on `codex/revv-unified-workspace` |
| Target | iPhone-only (`TARGETED_DEVICE_FAMILY = 1`) |
| Build flags | No `REVV_EXPLORATION_FOG`, no `REVV_WALKIE_LAB`, no `SENTRY_DSN` |
| Encryption | `ITSAppUsesNonExemptEncryption = false` |
| Local validation, 2026-07-21 | `flutter analyze` clean; `flutter test -r compact`: 633 passed, 2 intentional live-environment skips; release `--no-codesign` iOS app built successfully and reports `1.38.0 (59)` |
| Distribution build, 2026-07-22 | Signed IPA uploaded and selected in App Store Connect as `1.38.0 (59)`; SHA-256 `8908d903375d2612639edd837fc87fce4d64fa410d416439fda9c0c03ccd38cc` |
| Submission state, 2026-07-22 | Draft is **Ready for Review** and the final **Submit for Review** button is enabled; it has intentionally not been pressed |

The environment file has non-empty Supabase and Mapbox values and is never
copied into this worktree. Build from the exact frozen source revision:

```sh
flutter build ipa --release \
  --dart-define-from-file=/Users/minwoohan/Documents/revv-app/.env \
  --build-name=1.38.0 --build-number=59
```

Do not add feature defines to the submission build. The signed archive was
exported with Apple Distribution identity `BMG2X5W7V9` and the App Store
provisioning profile for `com.revv.revvApp`. The profile expires 2027-05-12.
The upload completed successfully; Xcode reported non-blocking missing-dSYM
warnings for MapboxCommon, MapboxCoreMaps, and objective_c.

## Store copy ready to paste

### Korean

**Subtitle**

드라이브 루트와 기록

**Promotional text**

캐나다 전역 지도에서 이용 가능한 커브 루트를 발견하고, 주행 흐름부터 기록까지 한곳에서 확인하세요.

**Description**

캐나다 전역 지도에서 이용 가능한 굽이진 길을 발견하세요. 커브 수, 흐름, 거리로 오늘의 드라이브를 설계하고, 주행 후에는 경로와 여정을 기록으로 남기세요.

REVV는 주말 드라이브를 준비하고 복기하기 위한 앱입니다. 현재 위치나 지도에서 선택한 어느 지역이든 검색하고, 이용 가능한 루트의 커브 밀도와 형태를 비교할 수 있습니다. 루트 상세 화면에서 거리, 예상 시간, 흐름, 코파일럿 브리핑, 턴 플랜 미리보기를 확인할 수 있습니다.

주행 중에는 지도, 진행률, 다음 커브 안내, 종료 버튼만 중심으로 보여줍니다. 주행 후에는 지도 리플레이, 거리와 시간, 코너 이벤트, 메모, 공유 카드 초안을 확인합니다. 클라우드 기록 저장은 설정에서 켜고 끌 수 있으며, 익명 세션으로 개인 기록을 분리합니다.

### English

**Subtitle**

Curvy routes & drive logs

**Promotional text**

Discover available curvy routes on a Canada-wide map, preview the flow, and keep each drive in one focused log.

**Description**

Discover available curved roads on a Canada-wide map. Shape today’s drive with curve count, flow, and distance, then keep the route and journey in your log.

REVV helps you prepare and review weekend drives. Search near your current location or any area you choose on the map, compare available route shape and curve density, then review distance, estimated time, flow notes, a copilot briefing, and a turn-plan preview.

During a drive, the screen focuses on the map, progress, next-curve guidance, and a clear end control. Afterwards, review a map replay, distance and duration, corner events, notes, and a share-card draft. Cloud drive storage is opt-in and anonymous sessions separate personal history.

**Keywords**

`route planner,scenic drive,curvy roads,drive log,road trip,Canada,car routes`

## App Review notes ready to paste

REVV uses When-In-Use location to search routes, show the driver’s position,
and save a route log. If the reviewer explicitly chooses navigation to a route
start, REVV arms that one selected route and begins the same record only after
two accurate moving fixes within the start zone. It does not monitor every
route.

No demo account is needed. REVV automatically creates an anonymous Supabase
session. Allow location, choose an available route, open its details, select
Start drive, and use Test drive from that screen to exercise the drive and
summary flow without physically driving.

Cloud drive storage is opt-in in Settings, which also offers deletion controls.
The App Store build keeps exploration fog and the walkie-talkie lab disabled.
Route choice, sharing, settings, and deletion are intended for use before or
after driving.

## App Privacy answers prepared

Tracking is set to **No**. App Store Connect now declares the following eight
data types. The first six are linked to the anonymous app User ID; the two
Mapbox diagnostics types are not linked:

| Apple data type | Purpose |
| --- | --- |
| Precise Location | App Functionality: route search, position display, route logs, optional cloud recovery |
| Coarse Location | Analytics and Product Personalization: coarse recommendation origin bucket |
| User ID | App Functionality, Analytics, and Product Personalization: anonymous account boundary and recommendation learning |
| Product Interaction | Analytics and Product Personalization: recommendation impressions and choices |
| Other Usage Data | App Functionality: drive activity and summary data |
| Other Data | App Functionality: route samples, motion summaries, and corner events |
| Performance Data | App Functionality and Analytics: Mapbox SDK telemetry; not linked and not used for tracking |
| Other Diagnostic Data | App Functionality and Analytics: Mapbox SDK telemetry; not linked and not used for tracking |

Do not declare Contact Info, Financial Information, or Crash Data for this
candidate. The release has no Sentry DSN, so Sentry crash reporting is disabled.
However, the embedded Mapbox SDK declares Performance Data and Other Diagnostic
Data; App Store Connect published the two rows above on 2026-08-05. The
privacy manifest and the App Store response must be reviewed again before any
later release enables Sentry or a currently disabled experimental feature.

The configured policy/support URL returns HTTPS 200. The public Notion page was
updated and connector-verified on 2026-07-22 with account-deletion details,
public support instructions, and `gksalsdn1234559@gmail.com`. The same URL is
saved as both the Privacy Policy URL and Support URL. The App Privacy answers
were published by MinWoo Han on 2026-07-22 and republished on 2026-08-05 after
the Mapbox diagnostics correction.

## Screenshot package

Upload the six English marketing files in numeric order from
`store_assets/screenshots/marketing/en/iphone_6_9/`. Each is a PNG,
`1320 × 2868`, portrait, RGB, and has no alpha channel. This matches a
currently accepted 6.9-inch iPhone size. The marketing frames use only English
headline/subhead copy and preserve the verified app UI unchanged.

The verified source captures remain at
`store_assets/screenshots/final/iphone_6_9/`: `01_route_map`,
`02_route_preview`, `03_route_detail`, `04_drive`, `05_history`, and
`06_settings`. The renderer, source-to-output mapping, and SHA-256 values are
recorded in `store_assets/screenshots/marketing/en/manifest.json`.

All six were recaptured on 2026-07-21 from the build-59 source/configuration on
an iPhone 17 Pro Max simulator. Flutter does not support release mode on iOS
Simulator, so the capture binary is debug with the same production environment
and submission feature flags disabled. No debug banner or simulator chrome is
present. Visual review confirmed the previously rejected route preview is no
longer occluded, Mapbox attribution is visible on all map frames, the drive
frame shows next-curve guidance, and Settings visibly reports build 59. The
capture record contains the final SHA-256 hashes.

Upload order and English message:

1. **Find roads worth driving** — zoomed-out real Laurentians route field with dozens of visible routes.
2. **Know the road before you go** — selected route preview.
3. **Every curve, before the first turn** — route detail and curve mix.
4. **The next curve, right on time** — focused in-drive guidance.
5. **Every drive becomes part of the story** — season history.
6. **Your drives. Your controls.** — storage, deletion, and privacy controls.

All six marketing files were uploaded to the 6.9-inch slot on 2026-07-22 and
verified in App Store Connect in exact numeric order. The 6.5-inch product-page
slot inherits the 6.9-inch set.

## Blocking checklist

- [x] Candidate version, bundle identifier, iPhone-only target, privacy
  manifest, opaque App Store icon, and encryption declaration verified.
- [x] Static analysis, full Flutter suite, and unsigned device release build
  verified for `1.38.0 (59)`.
- [x] Korean/English product copy, review notes, privacy mapping, and
  screenshot capture plan prepared.
- [x] Apple Distribution signing and the App Store provisioning profile were
  resolved through Xcode automatic signing. Signed IPA build 59 was produced.
- [x] Exported/uploaded signed build 59, waited for processing, and selected
  that exact build in App Store Connect.
- [x] Published and verified the privacy/support page with the public contact
  email and support instructions; saved the URL in App Store Connect.
- [x] Deployed `delete-account` version 1 with `verify_jwt=true` to the linked
  `Revv` production project on 2026-07-22. Live verification created a fresh
  disposable anonymous account, confirmed its authenticated user lookup
  returned 200, invoked deletion successfully (`200`, `deleted=true`), and
  confirmed the deleted user token could no longer fetch the user (`403`). An
  unauthenticated function request returned `401`.
- [ ] Run the physical iPhone upgrade plus 10-minute foreground/background
  drive smoke on the signed build 59.
- [x] Recapture and visually approve all six build-59 screenshots; verify
  1320×2868 RGB PNG output with no alpha channel.
- [x] App Store Connect: Navigation / Travel, age rating 4+, Free, Canada-only,
  manual release, Mac/Vision distribution off, content rights confirmed, and
  App Review contact entered. DSA is not applicable to Canada-only release.
- [x] Entered English-only store copy, uploaded six ordered screenshots,
  selected build 59, and used Add for Review.
- [x] Updated and published App Privacy on 2026-08-05: Mapbox Performance Data
  and Other Diagnostic Data are not linked, not tracking, and used for App
  Functionality and Analytics. Review draft remains unsubmitted.
- [ ] Press **Submit for Review** only after owner confirmation. App Store
  Connect currently shows `1.38.0 (59)` as Ready for Review and the final
  submission button is enabled.

## Confirmed owner values

- Public privacy/support contact: `gksalsdn1234559@gmail.com`
- App Review contact: MinWoo Han, `+1 514 829 6974`,
  `gksalsdn1234559@gmail.com`
- Availability and price: Canada only, Free
- Categories: Navigation / Travel
- Release: manual
- Store copy: English only, entered in the existing Korean default
  localization because App Store Connect does not allow changing that default

## Official references checked 2026-07-21

- Apple accepts 1–10 JPEG/JPG/PNG screenshots with no alpha; `1320 × 2868` is
  an accepted portrait 6.9-inch iPhone size.
- A privacy policy URL and App Privacy disclosure are required for iOS apps.
- Submission requires required metadata and a selected build before Add for
  Review and Submit for Review.

See Apple’s [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications), [App Privacy guide](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy), and [submission flow](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app).
