create or replace function public.find_curvy_map_segments(
  user_lat double precision,
  user_lng double precision,
  radius_m integer default 50000,
  min_distance_km double precision default 0.3,
  max_results integer default 30
)
returns table (
  id text,
  name text,
  center_lat double precision,
  center_lng double precision,
  nodes jsonb,
  distance_km double precision,
  winding_score double precision,
  star_rating smallint,
  sharp_curve_count integer,
  tight_curve_km double precision,
  medium_curve_km double precision,
  max_continuous_km double precision,
  is_loop boolean,
  elevation_delta double precision,
  region text,
  source text,
  run_count integer,
  published_by uuid,
  stop_sign_count integer,
  traffic_signal_count integer,
  stop_control_density double precision,
  flow_score double precision,
  fun_score double precision,
  driveability_penalty double precision,
  road_class_bucket text,
  is_named boolean,
  is_facility_like boolean,
  is_bridge_like boolean,
  is_connector_like boolean,
  is_major_road_like boolean,
  is_private_like boolean,
  quality_label text,
  quality_reject_reason text,
  route_character text,
  primary_reason text,
  caution_note text,
  road_names jsonb,
  surface_summary text,
  speed_limit_summary text,
  nearby_pois jsonb,
  elevation_profile jsonb,
  distance_from_user_km double precision,
  route_rank_score double precision
)
language plpgsql
stable
set search_path = public, extensions, pg_temp
set statement_timeout = '8s'
as $$
declare
  bounded_radius integer :=
    least(greatest(coalesce(radius_m, 50000), 1000), 160000);
  bounded_min_distance double precision :=
    least(greatest(coalesce(min_distance_km, 0.3), 0.3), 4.0);
  bounded_results integer :=
    least(greatest(coalesce(max_results, 30), 1), 60);
begin
  if (select auth.uid()) is null
     and coalesce((select auth.role()), '') <> 'service_role' then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if user_lat is null
     or user_lng is null
     or user_lat not between -90 and 90
     or user_lng not between -180 and 180 then
    raise exception 'invalid coordinates' using errcode = '22023';
  end if;

  return query
  with nearby as (
    select
      road.*,
      st_distance(
        road.center_point,
        st_setsrid(st_makepoint(user_lng, user_lat), 4326)::geography
      ) / 1000.0 as user_distance_km,
      coalesce(
        nullif(road.geohash4, ''),
        st_geohash(road.center_point::geometry, 4)
      ) as spatial_cell
    from public.curvy_roads as road
    where st_dwithin(
            road.center_point,
            st_setsrid(st_makepoint(user_lng, user_lat), 4326)::geography,
            bounded_radius
          )
      and road.distance_km >= bounded_min_distance
      and road.distance_km < 4.0
      and jsonb_typeof(road.nodes) = 'array'
      and jsonb_array_length(road.nodes) between 2 and 1200
      and pg_column_size(road.nodes) <= 1048576
      and not coalesce(road.is_facility_like, false)
      and not coalesce(road.is_connector_like, false)
      and not coalesce(road.is_private_like, false)
  ),
  diversified as (
    select
      nearby.*,
      row_number() over (
        partition by nearby.spatial_cell
        order by
          nearby.winding_score desc,
          nearby.distance_km desc,
          nearby.user_distance_km asc,
          nearby.id
      ) as cell_rank
    from nearby
  )
  select
    diversified.id,
    diversified.name,
    diversified.center_lat,
    diversified.center_lng,
    diversified.nodes,
    diversified.distance_km,
    diversified.winding_score,
    diversified.star_rating,
    diversified.sharp_curve_count,
    diversified.tight_curve_km,
    diversified.medium_curve_km,
    diversified.max_continuous_km,
    diversified.is_loop,
    diversified.elevation_delta,
    diversified.region,
    diversified.source,
    diversified.run_count,
    diversified.published_by,
    diversified.stop_sign_count,
    diversified.traffic_signal_count,
    diversified.stop_control_density,
    diversified.flow_score,
    diversified.fun_score,
    diversified.driveability_penalty,
    diversified.road_class_bucket,
    diversified.is_named,
    diversified.is_facility_like,
    diversified.is_bridge_like,
    diversified.is_connector_like,
    diversified.is_major_road_like,
    diversified.is_private_like,
    diversified.quality_label,
    diversified.quality_reject_reason,
    diversified.route_character,
    diversified.primary_reason,
    diversified.caution_note,
    diversified.road_names,
    diversified.surface_summary,
    diversified.speed_limit_summary,
    diversified.nearby_pois,
    diversified.elevation_profile,
    diversified.user_distance_km,
    coalesce(
      nullif(diversified.fun_score, 0),
      diversified.winding_score
    ) as route_rank_score
  from diversified
  where diversified.cell_rank <= 3
  order by
    diversified.cell_rank asc,
    diversified.user_distance_km asc,
    diversified.winding_score desc
  limit bounded_results;
end;
$$;

revoke all on function public.find_curvy_map_segments(
  double precision, double precision, integer, double precision, integer
) from public, anon;
grant execute on function public.find_curvy_map_segments(
  double precision, double precision, integer, double precision, integer
) to authenticated, service_role;

notify pgrst, 'reload schema';
