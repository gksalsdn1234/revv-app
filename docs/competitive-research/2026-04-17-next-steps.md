# REVV Next Steps

Last updated: 2026-04-17

## Current Product Direction

### Benchmark split
- `Calimoto`
  - primary benchmark for `route discovery`
  - copy:
    - discovery-first structure
    - round-trip framing
    - quick route selection feel
- `Scenic`
  - primary benchmark for `ride-time UX`
  - copy:
    - start/join behavior
    - detour / rejoin handling
    - active navigation clarity
- `Kurviger`
  - benchmark for `advanced routing controls`
  - copy:
    - route shaping controls
    - curvy intensity / explicit generation controls
  - note:
    - keep behind an advanced layer, not in V1 default flow
- `REVER`
  - reference only for `saved route / library / light community framing`
  - do not use as primary benchmark for navigation UX

### REVV differentiation
- `fun + flow + residential` recommendation engine
- `quality / character / explanation` metadata
- route chain recommendation

## What Is Already Done

### Research
- Competitive summaries written for:
  - [`Calimoto`](C:/Users/gksal/Documents/GitHub/revv-app/docs/competitive-research/2026-04-16-calimoto-summary.md)
  - [`Scenic`](C:/Users/gksal/Documents/GitHub/revv-app/docs/competitive-research/2026-04-16-scenic-summary.md)
  - [`Kurviger`](C:/Users/gksal/Documents/GitHub/revv-app/docs/competitive-research/2026-04-16-kurviger-summary.md)
  - [`REVER`](C:/Users/gksal/Documents/GitHub/revv-app/docs/competitive-research/2026-04-16-rever-summary.md)
- Comparison matrix written:
  - [`competitive matrix`](C:/Users/gksal/Documents/GitHub/revv-app/docs/competitive-research/2026-04-16-competitive-matrix.md)
- Product benchmark decision written:
  - [`REVV UX benchmark`](C:/Users/gksal/Documents/GitHub/revv-app/docs/competitive-research/2026-04-16-revv-ux-benchmark.md)

### Backlog
- Implementation-facing backlog written:
  - [`REVV UI backlog`](C:/Users/gksal/Documents/GitHub/revv-app/docs/competitive-research/2026-04-17-revv-ui-backlog.md)

### Data / recommendation work already in repo
- stop-control enrichment pipeline
- residential penalty pipeline
- quality / character / explanation metadata path
- route-audit support docs

## What To Do Next

### Immediate next implementation target
1. `Routes`
- This is the first screen and the highest leverage area.
- Goal:
  - make it feel discovery-first, not planner-first
  - show `character + primary reason` clearly
  - remove or demote noisy planner/debug affordances

### After Routes
2. `Route Detail`
- Make explanation explicit:
  - why this route
  - watch for
  - chain candidate section

3. `Preview`
- Add explicit:
  - start from beginning
  - guide to route start
  - join route from current position
- show composite breakdown and keep/maybe confidence

4. `Ride`
- Improve:
  - off-route state
  - rejoin state
  - route-quality-aware reroute hints

5. `Saved`
- keep route-centric
- do not add community complexity in V1

## V1 Constraints
- do not bring full Kurviger control surface into default flow
- do not bring REVER-style community feed into V1
- do not expose audit/debug metrics in user-facing route selection

## Working Rule For Future Decisions
- if the question is about `discovery`, compare against `Calimoto`
- if the question is about `ride-time navigation`, compare against `Scenic`
- if the question is about `advanced route shaping`, compare against `Kurviger`
- if the question is about `saved/public route library`, compare lightly against `REVER`
- if the question is about `why this route is good`, use REVV’s own metadata, not competitor wording

## Index
- [`Competitive research index`](C:/Users/gksal/Documents/GitHub/revv-app/docs/competitive-research/README.md)
