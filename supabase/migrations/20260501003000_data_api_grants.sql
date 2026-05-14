ALTER TABLE public.runs
  ADD COLUMN IF NOT EXISTS max_speed_kmh DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS avg_speed_kmh DOUBLE PRECISION;

CREATE TABLE IF NOT EXISTS public.run_details (
  run_id TEXT PRIMARY KEY REFERENCES public.runs(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  detail_version INTEGER NOT NULL DEFAULT 1,
  telemetry_json JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_run_details_user
  ON public.run_details(user_id, created_at DESC);

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

ALTER TABLE public.run_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.route_feedback ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS run_details_owner ON public.run_details;
CREATE POLICY run_details_owner ON public.run_details
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

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

GRANT SELECT ON public.curvy_roads
  TO anon, authenticated, service_role;

GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.runs,
     public.run_details,
     public.route_records,
     public.route_feedback,
     public.saved_routes,
     public.discovered_routes
  TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.find_curvy_roads(
  DOUBLE PRECISION,
  DOUBLE PRECISION,
  INTEGER,
  DOUBLE PRECISION,
  INTEGER
) TO anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.increment_route_run_count(TEXT)
  TO authenticated, service_role;
