alter function public.find_curvy_roads(
  double precision, double precision, integer, double precision, integer
) rename to find_curvy_roads_unbounded_internal;

revoke all on function public.find_curvy_roads_unbounded_internal(
  double precision, double precision, integer, double precision, integer
) from public, anon, authenticated;

create function public.find_curvy_roads(
  user_lat double precision,
  user_lng double precision,
  radius_m integer default 50000,
  min_score double precision default 0,
  max_results integer default 30
)
returns table (
  id text, name text, center_lat double precision, center_lng double precision,
  nodes jsonb, distance_km double precision, curvature_score double precision,
  winding_score double precision, star_rating smallint,
  sharp_curve_count integer, tight_curve_km double precision,
  medium_curve_km double precision, max_continuous_km double precision,
  is_loop boolean, elevation_delta double precision, geohash4 text,
  region text, source text, run_count integer, published_by uuid,
  created_at timestamptz, stop_sign_count integer,
  traffic_signal_count integer, stop_control_density double precision,
  flow_score double precision, fun_score double precision,
  driveability_penalty double precision, road_class_bucket text,
  is_named boolean, is_facility_like boolean, is_bridge_like boolean,
  is_connector_like boolean, is_major_road_like boolean,
  is_private_like boolean, residential_ratio double precision,
  service_ratio double precision, local_road_ratio double precision,
  intersection_density double precision, building_density double precision,
  housing_proximity_score double precision, urban_friction_score double precision,
  residential_penalty double precision, residential_version text,
  residential_enriched_at timestamptz, quality_label text,
  quality_reject_reason text, route_character text, primary_reason text,
  caution_note text, quality_version text, quality_enriched_at timestamptz,
  elevation_profile jsonb, road_names jsonb, surface_summary text,
  speed_limit_summary text, nearby_pois jsonb, route_context jsonb,
  context_version text, context_enriched_at timestamptz,
  distance_from_user_km double precision, route_rank_score double precision
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
set statement_timeout = '8s'
as $$
begin
  if (select auth.uid()) is null and coalesce((select auth.role()), '') <> 'service_role' then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if user_lat is null
     or user_lng is null
     or user_lat not between -90 and 90
     or user_lng not between -180 and 180 then
    raise exception 'invalid coordinates' using errcode = '22023';
  end if;

  return query
  select *
    from public.find_curvy_roads_unbounded_internal(
      user_lat,
      user_lng,
      least(greatest(coalesce(radius_m, 50000), 1000), 160000),
      greatest(coalesce(min_score, 0), 0),
      least(greatest(coalesce(max_results, 30), 1), 120)
    );
end;
$$;

revoke all on function public.find_curvy_roads(
  double precision, double precision, integer, double precision, integer
) from public, anon;
grant execute on function public.find_curvy_roads(
  double precision, double precision, integer, double precision, integer
) to authenticated, service_role;

drop policy if exists crew_channels_owner_insert on public.crew_channels;
revoke insert on public.crew_channels from authenticated;

alter table public.curvy_roads
  add constraint curvy_roads_nodes_release_bound
  check (
    jsonb_typeof(nodes) = 'array'
    and jsonb_array_length(nodes) between 2 and 1200
    and pg_column_size(nodes) <= 1048576
  ) not valid;

notify pgrst, 'reload schema';
