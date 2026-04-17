# REVV UI Backlog

Last updated: 2026-04-17

## Scope
This document turns the benchmark decisions from [`2026-04-16-revv-ux-benchmark.md`](C:/Users/gksal/Documents/GitHub/revv-app/docs/competitive-research/2026-04-16-revv-ux-benchmark.md) into an implementation-ready backlog.

The backlog assumes:
- discovery structure follows `Calimoto`
- ride-time UX follows `Scenic`
- advanced shaping follows `Kurviger`
- save/library framing lightly references `REVER`
- REVV differentiates on `fun + flow + residential` and `quality / character / explanation`

## Delivery Principle
- V1 should optimize for `good route selection -> confident preview -> reliable ride start/rejoin`
- V1 should not optimize for full power-user planner controls
- V1 should not optimize for community features

---

## Epic 1: Routes

### Benchmark
- Primary benchmark: `Calimoto`

### Product Goal
- Make route selection feel like `pick a good ride now`
- Avoid making the first screen feel like a planner or debug surface

### REVV Differentiation
- Route cards must expose:
  - `quality label`
  - `route character`
  - `primary reason`
  - lightweight `caution note` when needed

### Stories
1. Rework the top of Routes so the primary action is discovery, not filtering overload.
2. Make round-trip framing visible in the entry flow.
3. Simplify route cards to a stable structure:
   - name
   - distance / duration
   - character tag
   - primary reason
   - caution note
4. Keep advanced shaping controls out of the default view.
5. Make route list ordering clearly quality-first:
   - `keep` before `maybe`
   - sort by `route_rank_score`
6. Expose the current search radius and refresh state without blocking the screen.

### Acceptance Criteria
- The screen reads as route discovery, not route configuration.
- A new user can understand why route A is above route B without opening a debug panel.
- Route cards do not expose internal scoring jargon directly.
- `reject` routes never appear in the visible list.
- `maybe` routes only appear when `keep` supply is insufficient.

### Dependencies
- Stable `quality_label`, `route_character`, `primary_reason`, `caution_note`
- Existing route ranking pipeline

---

## Epic 2: Route Detail

### Benchmark
- Primary benchmark: `Calimoto`

### Product Goal
- Turn a selected route into a lightweight decision screen
- Explain why the route is worth riding and what tradeoffs it has

### REVV Differentiation
- Route Detail is where REVV’s explanation layer becomes explicit

### Stories
1. Create a route detail surface separate from the list card density.
2. Show:
   - route character
   - primary reason
   - caution note
   - quality state
3. Add a `why this route` section using plain language, not raw telemetry.
4. Add a `watch for` section only when there is a real caution.
5. Show chain recommendations below the main route decision area.
6. Keep planner controls hidden from the default detail screen.

### Acceptance Criteria
- The detail screen makes the route feel intentionally chosen.
- `primary_reason` is visible above the fold.
- `caution_note` is omitted when empty.
- Chain candidates do not overpower the main route decision.
- The screen remains selection-oriented, not configuration-heavy.

### Dependencies
- Route explanation metadata
- Chain candidate pipeline

---

## Epic 3: Preview

### Benchmark
- Hybrid: `Calimoto` structure + `Scenic` execution confidence

### Product Goal
- Answer one question before ride start: `can I trust this route and start smoothly from where I am?`

### REVV Differentiation
- Preview should expose whether a route is strong enough to trust and whether chaining hurts flow

### Stories
1. Make route start behavior explicit:
   - start from beginning
   - guide to route start
   - join route from current position
2. Show route quality summary in preview:
   - quality
   - character
   - primary reason
3. For composite routes, show segment breakdown and connector impact.
4. Show if the route is `keep` or `maybe`.
5. Show whether route chaining improved or degraded the route flow.

### Acceptance Criteria
- A user can tell how the ride will begin before tapping `GO`.
- Composite route preview is materially different from single-route preview.
- Rejoin/start behavior is explicit, not implicit.
- Preview reduces uncertainty rather than acting as a duplicate of Route Detail.

### Dependencies
- Navigation entry modes
- Composite route metadata
- Route quality metadata

---

## Epic 4: Ride

### Benchmark
- Primary benchmark: `Scenic`

### Product Goal
- Make ride-time navigation reliable, legible, and low-friction

### REVV Differentiation
- Keep the ride surface clean, but make route-aware recovery smarter

### Stories
1. Improve route start behavior to support:
   - route start guidance
   - mid-route join
   - chain-aware segment start
2. Improve off-route handling:
   - detect deviation
   - show clear rejoin state
   - avoid confusing silent recalculations
3. Add route-aware reroute hints:
   - preserve route quality when possible
   - tell the user when reroute quality drops
4. Keep the ride map visually simple.
5. Expose only ride-relevant context:
   - next action
   - route rejoin state
   - chain segment state
   - detour impact when necessary

### Acceptance Criteria
- Missed-turn handling is explicit.
- A user can understand whether they are rejoining or fully rerouting.
- Ride-time UI does not expose planner controls.
- Composite routes remain understandable during active navigation.

### Dependencies
- Navigation engine behavior
- Route rejoin logic
- Composite route support

---

## Epic 5: Saved

### Benchmark
- Light reference: `REVER`

### Product Goal
- Give users a clean route library without dragging V1 into full community product scope

### REVV Differentiation
- Saved routes should stay route-centric, not social-first

### Stories
1. Define a simple saved route library:
   - saved route cards
   - recents
   - optionally saved composites
2. Show route metadata consistently:
   - character
   - primary reason
   - saved date or last ridden
3. Keep sharing basic in V1.
4. Do not build public route community flows into the main saved screen yet.

### Acceptance Criteria
- Users can reliably re-open routes they care about.
- Saved routes look like route objects, not activity feed items.
- Saved does not introduce community complexity into V1.

### Dependencies
- Stable route serialization for single and composite routes

---

## Epic 6: Audit

### Benchmark
- REVV-native internal tooling

### Product Goal
- Keep route quality inspection and pipeline verification out of user-facing route selection

### Stories
1. Keep route audit as internal tooling.
2. Continue exposing:
   - quality
   - character
   - flow
   - residential
   - stop-control
3. Make audit useful for validating ranking and route explanation logic.

### Acceptance Criteria
- Internal audit can validate route recommendation decisions.
- User-facing route screens are not cluttered with audit-only data.

### Dependencies
- Supabase direct-read and route audit tooling

---

## Cross-Cutting Stories

1. Standardize route metadata language across list, detail, preview, saved, and audit.
2. Use the same source-of-truth fields across app and web:
   - `quality_label`
   - `route_character`
   - `primary_reason`
   - `caution_note`
   - `route_rank_score`
3. Keep advanced routing controls behind a secondary layer.
4. Preserve chain candidate UX without letting it dominate first-route selection.

---

## Recommended V1 Launch Order

1. `Routes`
- This is the first impression and determines whether the recommendation engine is legible.

2. `Route Detail`
- REVV differentiation is wasted if the explanation layer is hidden.

3. `Preview`
- Route confidence before ride start is the next biggest leverage point.

4. `Ride`
- Critical, but should follow the decision flow cleanup first.

5. `Saved`
- Important, but not the first blocker for route recommendation quality.

6. `Audit`
- Keep improving in parallel, but do not let it drive V1 user-facing priorities.

---

## Immediate Ticket Cut

### Batch A: Discovery Foundation
1. Rework Routes card structure around `character + primary reason`.
2. Remove default planner-heavy affordances from Routes.
3. Make list ordering strictly quality-first.

### Batch B: Explanation Layer
1. Create Route Detail screen structure.
2. Add `why this route`.
3. Add `watch for`.
4. Add chain candidate section below the main route explanation.

### Batch C: Start Confidence
1. Add explicit route start/join choices in Preview.
2. Add composite route preview breakdown.
3. Show keep/maybe state in preview.

### Batch D: Ride Reliability
1. Improve off-route and rejoin state messaging.
2. Add chain-aware ride state.
3. Add route-quality-aware reroute hints.

### Batch E: Saved Cleanup
1. Define a basic saved route library.
2. Keep sharing minimal.
3. Keep community out of V1.

---

## Out of Scope for V1
- Full Kurviger-style planner surface
- REVER-style community feed
- Public route ecosystem
- Social discovery or events
- Overly detailed debug metrics in user-facing screens
