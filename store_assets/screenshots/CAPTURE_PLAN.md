# REVV App Store screenshot capture record — build 59

> Current submission authority: `docs/app_store_submission_2026-07-21.md`.
> All six final files were recaptured and approved on 2026-07-21 from the
> build-59 source/configuration on an iPhone 17 Pro Max simulator. Flutter does
> not support release mode on iOS Simulator, so the screenshots use the debug
> simulator binary with the same production environment and with
> `REVV_EXPLORATION_FOG`, `REVV_WALKIE_LAB`, and `SENTRY_DSN` disabled. No
> debug banner or simulator chrome is present.

Final target: `final/iphone_6_9/`, portrait PNG, `1320 × 2868`, no simulator chrome.

Approved files:

1. `01_route_map.png` — actually zoomed-out Ottawa–Montreal/Laurentians viewport with dozens of visible red route segments and no list/preview overlay.
2. `02_route_preview.png` — compact loop route at a legible scale with preview card and Mapbox attribution unobscured.
3. `03_route_detail.png` — curve mix and Start drive action.
4. `04_drive.png` — next-curve guidance, end control, Mapbox ornaments unobscured.
5. `05_history.png` — post-drive summary or history detail.
6. `06_settings.png` — cloud storage, deletion, and privacy controls.

The prior build-55 files are preserved under
`archive/pre_build59_20260721/iphone_6_9/`. The replacement set was visually
reviewed as a contact sheet plus full-resolution route-preview and drive
frames. Screenshots 01 and 02 were strengthened again on 2026-07-22: discovery
now shows an actually zoomed-out real Laurentians route field with dozens of
red route segments, and
preview shows the compact Chemin du Lac Sylvère loop at a much more legible
scale. Screenshot 02 retains an unoccluded
title/card and visible Mapbox attribution; screenshot 04 shows live simulated
next-curve guidance; screenshot 06 visibly reports `REVV · BUILD 1.38.0+59`.

Every final file is a portrait `1320 × 2868` RGB PNG with no alpha channel.
SHA-256:

- `01_route_map.png`: `928d6646772cc494d7c1dd70c806f74462c68149bad925e257ea63bbdcd40396`
- `02_route_preview.png`: `7a66a7403817072a9c83e2fa76b4df927efa157d55477c075ddb498a364a458a`
- `03_route_detail.png`: `f3ecf68b71fed1080e4b5b653be3bd6d48b53d59baef6bb78aeb0e1161fd390e`
- `04_drive.png`: `ebc096a2e9f7e7c2f10fc89ad862ce1d899464ee10267ea61b9a2368721030aa`
- `05_history.png`: `2d1e789a6a16187026a1a7b8babd943c17cda1ff5e641cc6447472d28a8902fd`
- `06_settings.png`: `aaeee63e60be3cf1f83f661cc1f8c78dd365232f70f1a877c0464c74f15b32b7`

The image under `drafts/iphone_6_9/` is QA evidence only and must not be submitted.
