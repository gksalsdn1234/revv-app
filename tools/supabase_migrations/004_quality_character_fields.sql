ALTER TABLE curvy_roads
ADD COLUMN IF NOT EXISTS quality_label TEXT DEFAULT '',
ADD COLUMN IF NOT EXISTS quality_reject_reason TEXT,
ADD COLUMN IF NOT EXISTS route_character TEXT DEFAULT '',
ADD COLUMN IF NOT EXISTS primary_reason TEXT,
ADD COLUMN IF NOT EXISTS caution_note TEXT,
ADD COLUMN IF NOT EXISTS quality_version TEXT DEFAULT '',
ADD COLUMN IF NOT EXISTS quality_enriched_at TIMESTAMPTZ;

COMMENT ON COLUMN curvy_roads.quality_label IS
  'Recommendation quality bucket: keep, maybe, or reject.';
COMMENT ON COLUMN curvy_roads.quality_reject_reason IS
  'Human-readable reason for rejecting a route from primary recommendations.';
COMMENT ON COLUMN curvy_roads.route_character IS
  'Route style classification such as tight_technical, fast_sweeper, rhythmic_flow, hill_climb, mixed_touring.';
COMMENT ON COLUMN curvy_roads.primary_reason IS
  'Primary explanation shown to users for why the route is recommended.';
COMMENT ON COLUMN curvy_roads.caution_note IS
  'Short cautionary note about interruptions or road character.';
COMMENT ON COLUMN curvy_roads.quality_version IS
  'Version tag for the quality/character/explanation logic.';
COMMENT ON COLUMN curvy_roads.quality_enriched_at IS
  'Timestamp when quality/character/explanation metadata was last computed.';

CREATE INDEX IF NOT EXISTS idx_curvy_roads_quality_version
  ON curvy_roads(quality_version);
