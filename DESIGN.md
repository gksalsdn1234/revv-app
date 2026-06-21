# REVV Design System

## 1. Atmosphere & Identity

REVV feels like a dark precision cockpit for drivers: dense, fast to scan, and tuned for trust under motion. The signature is cyan instrumentation on layered graphite surfaces, with amber reserved for caution, route chaining, and decision emphasis.

## 2. Color

### Palette

| Role | Token | Light | Dark | Usage |
|------|-------|-------|------|-------|
| Surface/base | `AppColors.bg` | N/A | `#131314` | App background |
| Surface/lowest | `AppColors.surfaceLowest` | N/A | `#0E0E0F` | Deep panels, inputs |
| Surface/panel | `AppColors.panel` | N/A | `#1C1B1C` | Primary cards and sheets |
| Surface/panel-2 | `AppColors.panel2` | N/A | `#201F20` | Secondary cards |
| Surface/default | `AppColors.surface` | N/A | `#2A2A2B` | Raised controls |
| Surface/high | `AppColors.surfaceHigh` | N/A | `#353436` | Active/elevated controls |
| Text/primary | `AppColors.textPrimary` | N/A | `#E5E2E3` | Main copy and headings |
| Text/secondary | `AppColors.textSecondary` | N/A | `#BAC9CC` | Supporting copy |
| Text/hint | `AppColors.textHint` | N/A | `#849396` | Metadata, muted labels |
| Border/default | `AppColors.outline` | N/A | `#849396` | High-emphasis outlines |
| Border/subtle | `AppColors.outlineVariant` | N/A | `#3B494C` | Dividers, low-emphasis outlines |
| Accent/primary | `AppColors.primaryContainer` | N/A | `#00E5FF` | Primary route and focus accent |
| Accent/cyan | `AppColors.cyan` | N/A | `#00DAF3` | Telemetry and instrumentation |
| Accent/amber | `AppColors.warning` | N/A | `#FEB300` | Caution, route-chain selection |
| Status/success | `AppColors.success` | N/A | `#59D98E` | Confirmations |
| Status/error | `AppColors.danger` | N/A | `#FF6F61` | Errors and destructive states |

### Rules

- Dark mode is the primary mode.
- Cyan indicates live route, telemetry, and active focus.
- Amber is reserved for caution or Smart Chain emphasis, not decoration.
- Prefer `AppColors` tokens over raw `Color(...)` values.

## 3. Typography

### Scale

| Level | Size | Weight | Line Height | Tracking | Usage |
|-------|------|--------|-------------|----------|-------|
| Display | 56px | 800 | Contextual | -2 | Large cockpit numbers and primary display |
| H1 | 24px | 800 | Contextual | 0 | Screen-level headings |
| H2 | 18px | 800-900 | Contextual | 0 | Card headers |
| Body | 14px | 500 | Contextual | 0 | Default UI copy |
| Body/sm | 11-12px | 700-800 | Contextual | 0 | Dense labels and helper copy |
| Technical | 10-12px | 700 | Contextual | 1.6 | Machine labels, route metadata |
| Mono | 12px | 700 | Contextual | 0 | Numeric and technical readouts |

### Font Stack

- Primary: Inter with Pretendard, Apple SD Gothic Neo, and Noto Sans KR fallbacks.
- Technical: JetBrains Mono.
- Display accents: Orbitron and Rajdhani for cockpit-specific instrumentation.

### Rules

- Use `AppText.body`, `AppText.display`, `AppText.technicalLabel`, and `AppText.mono`.
- Body text in touch surfaces should not go below 11px.
- Technical labels may use letter spacing; normal body copy should not.

## 4. Spacing & Layout

### Base Unit

All spacing derives from a base of 4px.

| Token | Value | Usage |
|-------|-------|-------|
| `space-1` | 4px | Tight icon/text relationships |
| `space-2` | 8px | Compact vertical rhythm |
| `space-3` | 12px | Card and panel inner padding |
| `space-4` | 16px | Screen edge padding |
| `space-5` | 20px | Comfortable panel spacing |
| `space-6` | 24px | Major control groups |
| `space-8` | 32px | Large panel separation |

### Grid

- Mobile-first Flutter layouts with `SafeArea` and fixed cockpit overlays.
- Route Finder and Drive screens use full-screen maps with constrained overlay panels.
- Touch targets should remain stable when labels, route distances, or telemetry values update.

### Rules

- Keep map and driving surfaces full-bleed.
- Avoid nested cards; use a single glass/panel layer over the map.
- Use stable dimensions for chips, controls, and route HUD elements.

## 5. Components

### Glass Panel

- **Structure**: dark translucent panel over map or cockpit background.
- **Variants**: route card, bottom sheet, drive HUD.
- **Spacing**: 12-16px inner padding.
- **States**: default, selected, disabled/loading where applicable.
- **Accessibility**: maintain contrast against map imagery.
- **Motion**: subtle opacity/transform transitions only.

### Route Chip

- **Structure**: icon plus stacked label/detail.
- **Variants**: default and selected.
- **Spacing**: 8px gap, 12-16px horizontal padding.
- **States**: default, selected, pressed.
- **Accessibility**: selected state must not rely on color only.
- **Motion**: no layout shift when selected.

## 6. Motion & Interaction

### Timing

| Type | Duration | Easing | Usage |
|------|----------|--------|-------|
| Micro | 100-150ms | ease-out | Press and selection feedback |
| Standard | 200-300ms | ease-in-out | Sheet and panel transitions |
| Emphasis | 400-600ms | ease-out | Drive HUD emphasis changes |

### Rules

- Animate transform and opacity where possible.
- Do not animate map layout or route geometry.
- Respect stable HUD layout during drive mode.

## 7. Depth & Surface

### Strategy

Mixed: tonal-shift surfaces with subtle outlines and occasional glow for active cockpit elements.

| Level | Value | Usage |
|-------|-------|-------|
| Base | `AppColors.bg` | Full-screen background |
| Panel | `AppColors.panel` / translucent `#0F1214` family | Floating route/drive panels |
| Outline | `AppColors.outlineVariant` | Control and chip boundaries |
| Glow | Cyan or amber alpha shadows | Active route, selected Smart Chain, instrumentation focus |

Depth should support scanability without making the map dirty.
