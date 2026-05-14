ALTER FUNCTION public.find_curvy_roads(
  DOUBLE PRECISION,
  DOUBLE PRECISION,
  INTEGER,
  DOUBLE PRECISION,
  INTEGER
) SET search_path = public;

ALTER FUNCTION public.set_curvy_roads_geometries()
  SET search_path = public;

ALTER FUNCTION public.increment_route_run_count(TEXT)
  SET search_path = public;

REVOKE ALL ON FUNCTION public.increment_route_run_count(TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_route_run_count(TEXT)
  TO authenticated, service_role;

DO $$
BEGIN
  IF to_regprocedure('public.rls_auto_enable()') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.rls_auto_enable()
      FROM PUBLIC, anon, authenticated;
  END IF;
END $$;
