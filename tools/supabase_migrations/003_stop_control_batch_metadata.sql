ALTER TABLE curvy_roads
ADD COLUMN IF NOT EXISTS stop_control_enriched_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS stop_control_version TEXT DEFAULT '',
ADD COLUMN IF NOT EXISTS stop_control_source TEXT DEFAULT '';

COMMENT ON COLUMN curvy_roads.stop_control_enriched_at IS
  'Timestamp when stop-control enrichment last completed for this route.';
COMMENT ON COLUMN curvy_roads.stop_control_version IS
  'Version tag for the stop-control enrichment logic.';
COMMENT ON COLUMN curvy_roads.stop_control_source IS
  'Source strategy used for stop-control enrichment, such as overpass_tile_cache.';

CREATE INDEX IF NOT EXISTS idx_curvy_roads_stop_control_version
  ON curvy_roads(stop_control_version);
