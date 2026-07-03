CREATE TABLE IF NOT EXISTS public.region_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  grid_key TEXT NOT NULL,
  lat_rounded NUMERIC(4,1) NOT NULL,
  lng_rounded NUMERIC(4,1) NOT NULL,
  locale TEXT NOT NULL DEFAULT 'en',
  CONSTRAINT region_requests_lat_rounded_range
    CHECK (lat_rounded BETWEEN -90.0 AND 90.0),
  CONSTRAINT region_requests_lng_rounded_range
    CHECK (lng_rounded BETWEEN -180.0 AND 180.0),
  CONSTRAINT region_requests_locale_known
    CHECK (locale IN ('ko', 'en', 'fr'))
);

CREATE INDEX IF NOT EXISTS idx_region_requests_grid_created
  ON public.region_requests(grid_key, created_at DESC);

ALTER TABLE public.region_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS region_requests_anon_insert ON public.region_requests;
CREATE POLICY region_requests_anon_insert ON public.region_requests
  FOR INSERT
  TO anon
  WITH CHECK (true);

REVOKE ALL ON public.region_requests FROM PUBLIC, anon, authenticated;
GRANT INSERT ON public.region_requests TO anon;
