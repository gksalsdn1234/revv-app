CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS curvy_roads (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  center_lat DOUBLE PRECISION NOT NULL,
  center_lng DOUBLE PRECISION NOT NULL,
  center_point GEOGRAPHY(POINT, 4326) NOT NULL,
  route_line GEOGRAPHY(LINESTRING, 4326),
  nodes JSONB NOT NULL,
  distance_km DOUBLE PRECISION NOT NULL,
  curvature_score DOUBLE PRECISION NOT NULL,
  winding_score DOUBLE PRECISION NOT NULL,
  star_rating SMALLINT NOT NULL,
  sharp_curve_count INTEGER DEFAULT 0,
  tight_curve_km DOUBLE PRECISION DEFAULT 0,
  medium_curve_km DOUBLE PRECISION DEFAULT 0,
  max_continuous_km DOUBLE PRECISION DEFAULT 0,
  is_loop BOOLEAN DEFAULT FALSE,
  elevation_delta DOUBLE PRECISION DEFAULT 0,
  geohash4 TEXT,
  region TEXT,
  source TEXT DEFAULT 'roadcurvature',
  run_count INTEGER DEFAULT 0,
  published_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_curvy_roads_center ON curvy_roads USING GIST(center_point);
CREATE INDEX IF NOT EXISTS idx_curvy_roads_score ON curvy_roads(winding_score DESC);
CREATE INDEX IF NOT EXISTS idx_curvy_roads_geohash4 ON curvy_roads(geohash4);
CREATE INDEX IF NOT EXISTS idx_curvy_roads_region ON curvy_roads(region);

CREATE OR REPLACE FUNCTION set_curvy_roads_geometries()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  line geography;
BEGIN
  NEW.center_point := ST_SetSRID(ST_MakePoint(NEW.center_lng, NEW.center_lat), 4326)::geography;

  IF NEW.nodes IS NOT NULL
     AND jsonb_typeof(NEW.nodes) = 'array'
     AND jsonb_array_length(NEW.nodes) >= 2 THEN
    SELECT ST_MakeLine(
             ARRAY_AGG(
               ST_SetSRID(
                 ST_MakePoint(
                   (node->>'lng')::double precision,
                   (node->>'lat')::double precision
                 ),
                 4326
               )
               ORDER BY ord
             )
           )::geography
      INTO line
      FROM jsonb_array_elements(NEW.nodes) WITH ORDINALITY AS e(node, ord);
    NEW.route_line := line;
  ELSE
    NEW.route_line := NULL;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_curvy_roads_geometries ON curvy_roads;
CREATE TRIGGER trg_curvy_roads_geometries
BEFORE INSERT OR UPDATE ON curvy_roads
FOR EACH ROW
EXECUTE FUNCTION set_curvy_roads_geometries();

CREATE OR REPLACE FUNCTION find_curvy_roads(
  user_lat DOUBLE PRECISION,
  user_lng DOUBLE PRECISION,
  radius_m INTEGER DEFAULT 50000,
  min_score DOUBLE PRECISION DEFAULT 0,
  max_results INTEGER DEFAULT 30
)
RETURNS TABLE (
  id TEXT,
  name TEXT,
  center_lat DOUBLE PRECISION,
  center_lng DOUBLE PRECISION,
  center_point GEOGRAPHY(POINT, 4326),
  route_line GEOGRAPHY(LINESTRING, 4326),
  nodes JSONB,
  distance_km DOUBLE PRECISION,
  curvature_score DOUBLE PRECISION,
  winding_score DOUBLE PRECISION,
  star_rating SMALLINT,
  sharp_curve_count INTEGER,
  tight_curve_km DOUBLE PRECISION,
  medium_curve_km DOUBLE PRECISION,
  max_continuous_km DOUBLE PRECISION,
  is_loop BOOLEAN,
  elevation_delta DOUBLE PRECISION,
  geohash4 TEXT,
  region TEXT,
  source TEXT,
  run_count INTEGER,
  published_by UUID,
  created_at TIMESTAMPTZ,
  distance_from_user_km DOUBLE PRECISION
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    curvy_roads.*,
    ST_Distance(
      center_point,
      ST_SetSRID(ST_MakePoint(user_lng, user_lat), 4326)::geography
    ) / 1000.0 AS distance_from_user_km
  FROM curvy_roads
  WHERE ST_DWithin(
          center_point,
          ST_SetSRID(ST_MakePoint(user_lng, user_lat), 4326)::geography,
          radius_m
        )
    AND winding_score >= min_score
    AND distance_km >= 4.0
  ORDER BY (
      winding_score
      * LEAST(GREATEST(distance_km, 4.0) / 6.0, 3.0)
      * CASE
          WHEN name ~* '\m(kart|karting|drift|circuit|raceway|speedway|motorsport|autocross|pit\s?lane|paddock|test\s?track|trackday)\M' THEN 0.05
          WHEN name ~* '\m(pont|bridge|viaduct|causeway)\M' THEN 0.08
          WHEN name ~* '\m(sortie|exit|ramp|bretelle|interchange|junction|connector)\M' THEN 0.15
          WHEN name ~* '\m(boulevard|autoroute|highway)\M' THEN 0.35
          WHEN name ~ '^[\d\-\s_]+$' THEN 0.25
          ELSE 1.0
        END
    ) DESC,
    distance_from_user_km ASC
  LIMIT max_results;
$$;

CREATE OR REPLACE FUNCTION increment_route_run_count(route_id_input TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE curvy_roads
  SET run_count = COALESCE(run_count, 0) + 1
  WHERE id = route_id_input;
END;
$$;

CREATE TABLE IF NOT EXISTS runs (
  id TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  date TIMESTAMPTZ NOT NULL,
  distance_km DOUBLE PRECISION NOT NULL,
  duration_seconds INTEGER NOT NULL,
  max_speed_kmh DOUBLE PRECISION,
  avg_speed_kmh DOUBLE PRECISION,
  route_name TEXT NOT NULL,
  route_id TEXT,
  weather_emoji TEXT DEFAULT '',
  temp_display TEXT DEFAULT '',
  max_lateral_g DOUBLE PRECISION,
  sharp_corners_count INTEGER DEFAULT 0,
  start_lat DOUBLE PRECISION,
  start_lng DOUBLE PRECISION,
  end_lat DOUBLE PRECISION,
  end_lng DOUBLE PRECISION,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_runs_user ON runs(user_id, date DESC);

ALTER TABLE runs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS runs_owner ON runs;
CREATE POLICY runs_owner ON runs
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS run_details (
  run_id TEXT PRIMARY KEY REFERENCES runs(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  detail_version INTEGER NOT NULL DEFAULT 1,
  telemetry_json JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_run_details_user ON run_details(user_id, created_at DESC);

ALTER TABLE run_details ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS run_details_owner ON run_details;
CREATE POLICY run_details_owner ON run_details
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS route_records (
  user_id UUID NOT NULL REFERENCES auth.users(id),
  route_id TEXT NOT NULL,
  best_time_seconds INTEGER,
  best_max_g DOUBLE PRECISION,
  run_count INTEGER DEFAULT 0,
  last_run_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, route_id)
);

ALTER TABLE route_records ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS records_owner ON route_records;
CREATE POLICY records_owner ON route_records
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS route_feedback (
  id TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  run_id TEXT,
  route_id TEXT,
  route_name TEXT NOT NULL,
  feedback_type TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_route_feedback_user ON route_feedback(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_route_feedback_route ON route_feedback(route_id, feedback_type);

ALTER TABLE route_feedback ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS route_feedback_owner ON route_feedback;
CREATE POLICY route_feedback_owner ON route_feedback
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS saved_routes (
  user_id UUID NOT NULL REFERENCES auth.users(id),
  route_id TEXT NOT NULL,
  route_data JSONB NOT NULL,
  saved_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, route_id)
);

ALTER TABLE saved_routes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS saved_owner ON saved_routes;
CREATE POLICY saved_owner ON saved_routes
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS discovered_routes (
  user_id UUID NOT NULL REFERENCES auth.users(id),
  route_id TEXT NOT NULL,
  route_data JSONB NOT NULL,
  saved_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, route_id)
);

ALTER TABLE discovered_routes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS discovered_owner ON discovered_routes;
CREATE POLICY discovered_owner ON discovered_routes
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

ALTER TABLE curvy_roads ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS curvy_public_read ON curvy_roads;
CREATE POLICY curvy_public_read ON curvy_roads
  FOR SELECT
  TO authenticated, anon
  USING (true);

DROP POLICY IF EXISTS curvy_authenticated_write ON curvy_roads;
DROP POLICY IF EXISTS curvy_authenticated_update ON curvy_roads;
