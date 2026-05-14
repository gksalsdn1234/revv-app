REVOKE ALL
  ON public.runs,
     public.run_details,
     public.route_records,
     public.route_feedback,
     public.saved_routes,
     public.discovered_routes
  FROM PUBLIC, anon;

GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.runs,
     public.run_details,
     public.route_records,
     public.route_feedback,
     public.saved_routes,
     public.discovered_routes
  TO authenticated, service_role;
