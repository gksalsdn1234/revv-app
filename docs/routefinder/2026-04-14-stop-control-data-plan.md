# Stop Control Data Plan

## Goal
- Remove routes that look curvy but break driving flow because of dense stop signs or traffic lights.
- Move this logic out of UI heuristics and into the data layer.

## New Data Fields
Add these fields to `curvy_roads`:

- `stop_sign_count`
  - Count of stop-sign-controlled intersections within a route corridor.
- `traffic_signal_count`
  - Count of signalized intersections within a route corridor.
- `stop_control_density`
  - Weighted stop control count per km.
  - Proposed formula:
    - `(stop_sign_count + traffic_signal_count * 1.5) / distance_km`
- `flow_score`
  - Normalized 0.0-1.0 uninterrupted-flow score.
  - Higher is better.

## Pipeline Changes
Extend `tools/curvature_pipeline` in three stages.

### 1. Corridor generation
- Keep the existing route line from `nodes`.
- Build a route corridor polygon with a narrow buffer.
- Suggested starting width:
  - rural roads: 40m
  - mixed regions: 30m

### 2. Traffic control enrichment
- Query OSM features intersecting the corridor:
  - `highway=stop`
  - `highway=traffic_signals`
- Map each matched feature to the nearest segment on the route line.
- De-duplicate nearby controls to avoid overcounting clustered nodes.

### 3. Flow scoring
- Compute:
  - `stop_sign_count`
  - `traffic_signal_count`
  - `stop_control_density`
  - `flow_score`
- Proposed first-pass formula:

```text
weighted_stop_count = stop_sign_count + traffic_signal_count * 1.5
stop_control_density = weighted_stop_count / max(distance_km, 1.0)
flow_score = clamp(1.0 - stop_control_density * 0.35, 0.15, 1.0)
```

## RPC Ranking Changes
`find_curvy_roads()` should use these values directly in ranking.

### Hard rejection candidates
- `stop_sign_count >= 5 AND distance_km < 12`
- `stop_control_density >= 0.65 AND max_continuous_km < 1.2`

### Score penalty
- Multiply existing route score by:
  - `GREATEST(flow_score, 0.15)`

This keeps the current winding-first logic but prevents short broken-flow routes from dominating.

## Web Audit Changes
The web audit currently uses `stop-heavy estimate` as a proxy based on:
- short overall distance
- low continuous run
- low total curvy distance
- not a bridge/ramp/major-road candidate

Once real stop-control data is present:
- replace `stop-heavy estimate` with actual values
- show:
  - `stop_sign_count`
  - `traffic_signal_count`
  - `stop_control_density`
  - `flow_score`
- keep the heuristic only as a fallback for older rows

## Validation Plan
Use Montreal first.

### Audit sample
- top 200 routes within 100km
- compare current labels vs new ranking

### Success criteria
- bridge/ramp/connector routes stay suppressed
- obvious city stop-grid routes drop out of top 20
- `keep` candidates dominate top 10
- no strong regression in rural winding coverage

## File Map
- SQL draft:
  - `tools/supabase_migrations/002_stop_control_fields.sql`
- Current audit heuristic:
  - `apps/web/lib/route-audit.ts`
- Web review UI:
  - `apps/web/pages/route-audit.tsx`
