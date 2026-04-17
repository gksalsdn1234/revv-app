# Residential Penalty Plan

## Goal
- Reduce routes that are technically curvy but function like neighborhood cut-throughs.
- Preserve scenic connectors and mixed touring roads when residential exposure is limited.
- Add a `residential_penalty` layer on top of `fun + flow + access`.

## Why This Exists
Current ranking already suppresses:
- track/facility routes
- bridge/connector-heavy routes
- stop-heavy routes

What still leaks through:
- short to mid-length residential roads
- local grids with frequent access points
- neighborhood roads that have enough curvature to score well but do not drive well

The missing signal is not curvature. It is residential friction.

## New Fields
Add these fields to `curvy_roads`:

- `residential_ratio`
  - corridor share classified as `highway=residential`
- `service_ratio`
  - corridor share classified as `highway=service`
- `local_road_ratio`
  - combined share of residential, service, living street, and comparable local-only segments
- `intersection_density`
  - intersections per km
- `building_density`
  - nearby building-footprint density
- `housing_proximity_score`
  - normalized 0.0-1.0 route overlap with housing-heavy areas
- `urban_friction_score`
  - normalized 0.0-1.0 friction score from local-road and neighborhood signals
- `residential_penalty`
  - 0.0-1.0 multiplier applied to final ranking
- `residential_version`
- `residential_enriched_at`

## Pipeline Input Sources
Use OSM corridor enrichment.

### Road class enrichment
- `highway=residential`
- `highway=service`
- `highway=living_street`
- `highway=unclassified`
- `highway=tertiary`

Map them into:
- residential
- service
- local
- through-road

### Built-environment enrichment
- building footprints near the corridor
- optional landuse hints:
  - `landuse=residential`
  - `place=neighbourhood`

### Flow interaction
Reuse:
- `stop_control_density`
- `max_continuous_km`

Residential risk should never be computed in isolation from flow.

## Scoring Model
Recommended first pass:

```text
urban_friction_score =
  residential_ratio * 0.35
  + service_ratio * 0.15
  + local_road_ratio * 0.20
  + normalized(intersection_density) * 0.15
  + building_density * 0.05
  + housing_proximity_score * 0.10
  + normalized(stop_control_density) * 0.20

continuity_relief =
  0.12 when max_continuous_km >= 2.0
  0.06 when max_continuous_km >= 1.2
  0 otherwise

residential_penalty =
  clamp(1.0 - urban_friction_score + continuity_relief, 0.15, 1.0)
```

Interpretation:
- high residential exposure alone is not enough to kill a route
- high residential exposure plus broken flow is a strong negative signal
- long continuous runs can partially offset residential exposure when the route is still drivable

## Hard Reject Rules
Use only for clearly bad candidates:

- `residential_ratio >= 0.60`
- `max_continuous_km < 1.0`
- `stop_control_density >= 0.50`

If all three are true:
- mark `quality_label = reject`
- set `quality_reject_reason = '주거지 구간 비중이 높고 흐름이 자주 끊김'`

Everything else should prefer a penalty over a hard reject.

## Ranking Change
Current shape:

```text
route_rank_score = fun_score * flow_score * driveability_penalty * context_adjustment
```

Target shape:

```text
route_rank_score =
  fun_score
  * flow_score
  * driveability_penalty
  * residential_penalty
  * context_adjustment
```

This should happen in the data layer first, with app heuristics kept only as fallback.

## Explanation Layer
Residential data should feed explanation, not just ranking.

### Positive examples
- `주거지 구간이 적어 흐름이 좋은 루트예요.`
- `로컬 접근도로 비중이 낮아 몰입감이 유지되는 코스예요.`

### Caution examples
- `초반 주거지 구간이 있어 흐름이 잠깐 끊길 수 있음`
- `주거지 연결구간이 일부 섞여 있어 완전한 와인딩 전용 루트는 아님`

## Suggested Rollout
1. Add fields via `005_residential_penalty_fields.sql`
2. Extend batch runner to compute residential metadata
3. Run on Montreal top-N first
4. Verify top 20 quality shift
5. Expand to Toronto/Vancouver

## Validation
Check these after rollout:
- fewer neighborhood grid routes in top 20
- scenic connectors can still survive as `maybe`
- stop-heavy residential routes fall sharply
- strong rural roads remain `keep`
