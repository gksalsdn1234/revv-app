# Montreal Route Audit

Date: 2026-04-13

## Scope
- Search center: `45.4627167, -73.62658`
- Radius: `50km`
- Candidate set: top `200` rows ranked with the current Supabase route score
- Source query: [`tools/route_audit/montreal_candidate_audit.sql`](/C:/Users/gksal/Documents/GitHub/revv-app/tools/route_audit/montreal_candidate_audit.sql)
- Exported sample: [`docs/routefinder/montreal_route_audit_top200.csv`](/C:/Users/gksal/Documents/GitHub/revv-app/docs/routefinder/montreal_route_audit_top200.csv)

## What The Data Says
- `keep / keep_candidate`: `41`
- `maybe / major_road_like`: `26`
- `maybe / bridge_like`: `1`
- `reject / too_short`: `46`
- `reject / track_or_facility`: `2`

The old problem was dominated by extremely short segments. After the RPC ranking change, the top of the list is now mostly real roads, but there is still a large `major_road_like` bucket and one bridge candidate.

## Top 20 Snapshot
- `1` `Rang de la Rivière Nord (339)` `19.96km` `keep`
- `2` `Boulevard Perrot` `17.05km` `maybe major_road_like`
- `3` `Chemin De Val-des-Lacs` `12.94km` `keep`
- `4` `Chemin de la Petite-Côte` `11.98km` `keep`
- `5` `Rue Main` `12.63km` `keep`
- `6` `Boulevard Gouin Ouest` `12.50km` `maybe major_road_like`
- `7` `Pont Victoria (112)` `7.93km` `maybe bridge_like`
- `8` `Chemin du Fleuve` `18.06km` `keep`
- `9` `Chemin du Lac-Saint-Louis` `7.31km` `keep`
- `10` `Chemin Saint-Charles (344)` `9.18km` `keep`

## Immediate Conclusions
1. The shortest-segment noise is the first cleanup target and is already reduced by the `distance_km >= 4.0` RPC filter.
2. `major_road_like` routes still exist, but after the second ranking pass they no longer dominate the top 10.
3. Bridge and connector candidates need aggressive penalties. After the latest ranking change, `Pont Victoria (112)` dropped out of the top 15.

## Recommended Next Rules
1. Keep the current bridge and major-road penalties in the RPC ranking:
   - `bridge/pont/viaduct/causeway`: `0.08`
   - `boulevard/autoroute/highway`: `0.35`
2. Split `maybe` routes into two groups:
   - `major_road_like`
   - `bridge_or_connector`
3. Exclude `bridge_or_connector` rows from the top 20 unless there are fewer than `8` keep candidates.
4. Keep the CSV review loop:
   - regenerate top 200
   - relabel false positives
   - tighten SQL ranking before adding more app-side filters

## Regenerate
```powershell
npx supabase db query --linked --file "C:/Users/gksal/Documents/GitHub/revv-app/tools/route_audit/montreal_candidate_audit.sql" --output csv --agent=no `
  | Set-Content -LiteralPath "C:/Users/gksal/Documents/GitHub/revv-app/docs/routefinder/montreal_route_audit_top200.csv"
```
