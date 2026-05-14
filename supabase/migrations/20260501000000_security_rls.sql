-- REVV security baseline and bootstrap schema.
-- This file must be enough for a fresh Supabase project to reach the later
-- route-context migrations without relying on older tool-only SQL files.

CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS public.curvy_roads (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  center_lat DOUBLE PRECISION NOT NULL,
  center_lng DOUBLE PRECISION NOT NULL,
  center_point GEOGRAPHY(POINT, 4326) NOT NULL,
  route_line GEOGRAPHY(LINESTRING, 4326),
  nodes JSONB NOT NULL DEFAULT '[]'::jsonb,
  distance_km DOUBLE PRECISION NOT NULL DEFAULT 0,
  curvature_score DOUBLE PRECISION NOT NULL DEFAULT 0,
  winding_score DOUBLE PRECISION NOT NULL DEFAULT 0,
  star_rating SMALLINT NOT NULL DEFAULT 1,
  sharp_curve_count INTEGER NOT NULL DEFAULT 0,
  tight_curve_km DOUBLE PRECISION NOT NULL DEFAULT 0,
  medium_curve_km DOUBLE PRECISION NOT NULL DEFAULT 0,
  max_continuous_km DOUBLE PRECISION NOT NULL DEFAULT 0,
  is_loop BOOLEAN NOT NULL DEFAULT FALSE,
  elevation_delta DOUBLE PRECISION NOT NULL DEFAULT 0,
  geohash4 TEXT,
  region TEXT,
  source TEXT NOT NULL DEFAULT 'roadcurvature',
  run_count INTEGER NOT NULL DEFAULT 0,
  published_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  stop_sign_count INTEGER NOT NULL DEFAULT 0,
  traffic_signal_count INTEGER NOT NULL DEFAULT 0,
  stop_control_density DOUBLE PRECISION NOT NULL DEFAULT 0,
  flow_score DOUBLE PRECISION NOT NULL DEFAULT 0,
  fun_score DOUBLE PRECISION NOT NULL DEFAULT 0,
  driveability_penalty DOUBLE PRECISION NOT NULL DEFAULT 0,
  road_class_bucket TEXT NOT NULL DEFAULT '',
  is_named BOOLEAN NOT NULL DEFAULT TRUE,
  is_facility_like BOOLEAN NOT NULL DEFAULT FALSE,
  is_bridge_like BOOLEAN NOT NULL DEFAULT FALSE,
  is_connector_like BOOLEAN NOT NULL DEFAULT FALSE,
  is_major_road_like BOOLEAN NOT NULL DEFAULT FALSE,
  is_private_like BOOLEAN NOT NULL DEFAULT FALSE,
  residential_ratio DOUBLE PRECISION NOT NULL DEFAULT 0,
  service_ratio DOUBLE PRECISION NOT NULL DEFAULT 0,
  local_road_ratio DOUBLE PRECISION NOT NULL DEFAULT 0,
  intersection_density DOUBLE PRECISION NOT NULL DEFAULT 0,
  building_density DOUBLE PRECISION NOT NULL DEFAULT 0,
  housing_proximity_score DOUBLE PRECISION NOT NULL DEFAULT 0,
  urban_friction_score DOUBLE PRECISION NOT NULL DEFAULT 0,
  residential_penalty DOUBLE PRECISION NOT NULL DEFAULT 1,
  residential_version TEXT NOT NULL DEFAULT '',
  residential_enriched_at TIMESTAMPTZ,
  quality_label TEXT NOT NULL DEFAULT '',
  quality_reject_reason TEXT,
  route_character TEXT NOT NULL DEFAULT '',
  primary_reason TEXT,
  caution_note TEXT,
  quality_version TEXT NOT NULL DEFAULT '',
  quality_enriched_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_curvy_roads_center
  ON public.curvy_roads USING GIST(center_point);
CREATE INDEX IF NOT EXISTS idx_curvy_roads_score
  ON public.curvy_roads(winding_score DESC);
CREATE INDEX IF NOT EXISTS idx_curvy_roads_geohash4
  ON public.curvy_roads(geohash4);
CREATE INDEX IF NOT EXISTS idx_curvy_roads_region
  ON public.curvy_roads(region);
CREATE INDEX IF NOT EXISTS idx_curvy_roads_quality
  ON public.curvy_roads(quality_reject_reason, winding_score DESC);

CREATE OR REPLACE FUNCTION public.set_curvy_roads_geometries()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  line GEOGRAPHY;
BEGIN
  NEW.center_point :=
    ST_SetSRID(ST_MakePoint(NEW.center_lng, NEW.center_lat), 4326)::geography;

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
      FROM jsonb_array_elements(NEW.nodes) WITH ORDINALITY AS e(node, ord)
      WHERE node ? 'lat'
        AND node ? 'lng';
    NEW.route_line := line;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_curvy_roads_geometries ON public.curvy_roads;
CREATE TRIGGER trg_curvy_roads_geometries
BEFORE INSERT OR UPDATE ON public.curvy_roads
FOR EACH ROW
EXECUTE FUNCTION public.set_curvy_roads_geometries();

CREATE OR REPLACE FUNCTION public.increment_route_run_count(route_id_input TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.curvy_roads
  SET run_count = COALESCE(run_count, 0) + 1
  WHERE id = route_id_input;
END;
$$;

CREATE TABLE IF NOT EXISTS public.runs (
  id TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  date TIMESTAMPTZ NOT NULL,
  distance_km DOUBLE PRECISION NOT NULL,
  duration_seconds INTEGER NOT NULL,
  max_speed_kmh DOUBLE PRECISION,
  avg_speed_kmh DOUBLE PRECISION,
  route_name TEXT NOT NULL DEFAULT '',
  route_id TEXT,
  weather_emoji TEXT NOT NULL DEFAULT '',
  temp_display TEXT NOT NULL DEFAULT '',
  max_lateral_g DOUBLE PRECISION,
  sharp_corners_count INTEGER NOT NULL DEFAULT 0,
  start_lat DOUBLE PRECISION,
  start_lng DOUBLE PRECISION,
  end_lat DOUBLE PRECISION,
  end_lng DOUBLE PRECISION,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_runs_user
  ON public.runs(user_id, date DESC);

CREATE TABLE IF NOT EXISTS public.run_details (
  run_id TEXT PRIMARY KEY REFERENCES public.runs(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  detail_version INTEGER NOT NULL DEFAULT 1,
  telemetry_json JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_run_details_user
  ON public.run_details(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.route_records (
  user_id UUID NOT NULL REFERENCES auth.users(id),
  route_id TEXT NOT NULL,
  best_time_seconds INTEGER,
  best_max_g DOUBLE PRECISION,
  run_count INTEGER NOT NULL DEFAULT 0,
  last_run_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, route_id)
);

CREATE TABLE IF NOT EXISTS public.route_feedback (
  id TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  run_id TEXT,
  route_id TEXT,
  route_name TEXT NOT NULL DEFAULT '',
  feedback_type TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_route_feedback_user
  ON public.route_feedback(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_route_feedback_route
  ON public.route_feedback(route_id, feedback_type);

CREATE TABLE IF NOT EXISTS public.saved_routes (
  user_id UUID NOT NULL REFERENCES auth.users(id),
  route_id TEXT NOT NULL,
  route_data JSONB NOT NULL,
  saved_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, route_id)
);

CREATE TABLE IF NOT EXISTS public.discovered_routes (
  user_id UUID NOT NULL REFERENCES auth.users(id),
  route_id TEXT NOT NULL,
  route_data JSONB NOT NULL,
  saved_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, route_id)
);

ALTER TABLE public.curvy_roads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.run_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.route_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.route_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discovered_routes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS curvy_public_read ON public.curvy_roads;
CREATE POLICY curvy_public_read ON public.curvy_roads
  FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS runs_owner ON public.runs;
CREATE POLICY runs_owner ON public.runs
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS run_details_owner ON public.run_details;
CREATE POLICY run_details_owner ON public.run_details
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS records_owner ON public.route_records;
CREATE POLICY records_owner ON public.route_records
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS route_feedback_owner ON public.route_feedback;
CREATE POLICY route_feedback_owner ON public.route_feedback
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS saved_owner ON public.saved_routes;
CREATE POLICY saved_owner ON public.saved_routes
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS discovered_owner ON public.discovered_routes;
CREATE POLICY discovered_owner ON public.discovered_routes
  FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT SELECT ON public.curvy_roads TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.runs,
     public.run_details,
     public.route_records,
     public.route_feedback,
     public.saved_routes,
     public.discovered_routes
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.increment_route_run_count(TEXT)
  TO authenticated, service_role;
