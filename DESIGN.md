# REVV Lean MVP Design System

## 1. Product Direction

REVV Lean MVP is a mobile driving companion for finding winding roads, running a drive, and reviewing the run afterward. The interface should feel like a compact race paddock instrument: decisive, mechanical, and readable while moving.

## 2. Color Tokens

- `ink`: `#14110E` for primary text on light racing panels.
- `pit-black`: `#100E0C` for app background and high-contrast panels.
- `cream`: `#F1ECE1` for primary surfaces.
- `cream-raised`: `#F8F4EB` for raised tiles.
- `cream-muted`: `#E7E1D4` for secondary route-map tiles.
- `revv-red`: `#E2231A` for primary action, active route, and race-state emphasis.
- `red-soft`: `#FBEBEA` for low-intensity red surfaces.
- `gold`: `#C9A24B` for personal-best and premium route accents.
- `success`: `#1FA85F` for synced/ready states.
- `warning`: `#FFB020` for caution states.
- `stone`: `#8A8278` for secondary text on light panels.
- `stone-muted`: `#A9A39B` for inactive labels and dividers.

## 3. Typography

- Display and race labels: Saira Condensed, uppercase, heavy weight.
- Body and route names: Archivo, medium to bold weight.
- Technical metadata: JetBrains Mono, small uppercase labels.
- Letter spacing is non-negative. Use tighter line-height for display type instead of negative tracking.

## 4. Spacing and Shape

- Base spacing is 4px.
- Screen padding: 24px on standard mobile panels, 14px for map overlays.
- Cards and tiles use 8-18px radius depending on size. Tool buttons stay compact.
- Do not nest cards. Use full screen bands, map overlays, or individual repeated list cards.

## 5. Components

- `RevvGlassCard`: dark or cream panel with thin outline, used for single repeated items or tool panels.
- `RevvPill`: compact filter/status chip.
- `RevvPrimaryButton`: red filled command button for primary driving action.
- Route ticket: selected route card with rank, route type, map glyph, distance/curves/start metrics, and primary preview/start command.
- Result metric row: two-column table with mono label and bold result value.
- History row: route glyph, route metadata, peak G/date column.

## 6. Motion and States

- Motion should be tactile but restrained. Animate opacity and transform only.
- Loading states should use racing language such as GPS lock, sensors calibrated, and route scan status.
- Empty states must explain the next route-finding action.

## 7. Implementation Notes

- All new UI colors should map to `AppColors`.
- All new text should use `AppText` helpers.
- Lean MVP has no OBD data. Do not introduce OBD labels, fields, serialization, or tests into Lean screens.
