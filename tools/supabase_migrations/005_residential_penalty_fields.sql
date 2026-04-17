ALTER TABLE curvy_roads
ADD COLUMN IF NOT EXISTS residential_ratio DOUBLE PRECISION DEFAULT 0,
ADD COLUMN IF NOT EXISTS service_ratio DOUBLE PRECISION DEFAULT 0,
ADD COLUMN IF NOT EXISTS local_road_ratio DOUBLE PRECISION DEFAULT 0,
ADD COLUMN IF NOT EXISTS intersection_density DOUBLE PRECISION DEFAULT 0,
ADD COLUMN IF NOT EXISTS building_density DOUBLE PRECISION DEFAULT 0,
ADD COLUMN IF NOT EXISTS housing_proximity_score DOUBLE PRECISION DEFAULT 0,
ADD COLUMN IF NOT EXISTS urban_friction_score DOUBLE PRECISION DEFAULT 0,
ADD COLUMN IF NOT EXISTS residential_penalty DOUBLE PRECISION DEFAULT 1.0,
ADD COLUMN IF NOT EXISTS residential_version TEXT DEFAULT '',
ADD COLUMN IF NOT EXISTS residential_enriched_at TIMESTAMPTZ;

COMMENT ON COLUMN curvy_roads.residential_ratio IS
  'Estimated proportion of the route corridor composed of residential roads.';
COMMENT ON COLUMN curvy_roads.service_ratio IS
  'Estimated proportion of service-road segments inside the route corridor.';
COMMENT ON COLUMN curvy_roads.local_road_ratio IS
  'Estimated proportion of local-road segments, including residential, service, and living street classes.';
COMMENT ON COLUMN curvy_roads.intersection_density IS
  'Estimated count of intersections per km along the route corridor.';
COMMENT ON COLUMN curvy_roads.building_density IS
  'Estimated density of building footprints near the route corridor.';
COMMENT ON COLUMN curvy_roads.housing_proximity_score IS
  '0.0-1.0 score for how strongly the route overlaps housing-heavy areas.';
COMMENT ON COLUMN curvy_roads.urban_friction_score IS
  '0.0-1.0 score combining residential ratio, intersections, and stop-control into an urban-friction signal.';
COMMENT ON COLUMN curvy_roads.residential_penalty IS
  '0.0-1.0 penalty factor that reduces ranking for housing-heavy routes with broken driving flow.';
COMMENT ON COLUMN curvy_roads.residential_version IS
  'Version tag for the residential-penalty enrichment logic.';
COMMENT ON COLUMN curvy_roads.residential_enriched_at IS
  'Timestamp when residential-penalty metadata was last computed.';

CREATE INDEX IF NOT EXISTS idx_curvy_roads_residential_version
  ON curvy_roads(residential_version);
