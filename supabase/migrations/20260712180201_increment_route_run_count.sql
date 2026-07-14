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

REVOKE ALL ON FUNCTION public.increment_route_run_count(TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_route_run_count(TEXT)
  TO authenticated, service_role;;
