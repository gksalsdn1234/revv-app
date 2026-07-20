# REVV App Store screenshot capture plan

Final target: `final/iphone_6_9/`, portrait PNG, `1320 × 2868`, no simulator chrome.

Capture and approve these six files in order:

1. `01_route_map.png` — multiple visible red routes, no selected-card overlap.
2. `02_route_preview.png` — selected route preview, Mapbox attribution unobscured.
3. `03_route_detail.png` — curve mix and Start drive action.
4. `04_drive.png` — next-curve guidance, end control, Mapbox ornaments unobscured.
5. `05_history.png` — post-drive summary or history detail.
6. `06_settings.png` — cloud storage, deletion, and privacy controls.

The six existing files were captured from the older build-55 source and are not final evidence for the current uncommitted SQLite/bug-fix candidate. Independent QA rejected `02_route_preview.png` because its header is fragmented/occluded and Mapbox attribution is absent. After the source is frozen, retake screenshot 02 and re-review all six files against the exact new archive before upload.

The image under `drafts/iphone_6_9/` is QA evidence only and must not be submitted.
