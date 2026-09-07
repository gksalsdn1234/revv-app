-- Additive overview transport. Existing full-detail RPCs remain unchanged.
-- All public wrappers delegate publication/auth checks to the existing v2 RPCs.
create or replace function revv_private.route_overview_nodes(input_nodes jsonb)
returns jsonb language sql immutable strict
set search_path = pg_catalog, extensions, public, pg_temp
as $$
  with line as (
    select st_makeline(st_makepoint((node->>'lng')::double precision,
                                   (node->>'lat')::double precision) order by ord) as geom
    from jsonb_array_elements(input_nodes) with ordinality as points(node, ord)
  ), simplified as (
    -- ~44m latitude tolerance for map browsing; original endpoints/order retained.
    select st_simplifypreservetopology(geom, 0.0004) as geom from line
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'lat', st_y(point.geom), 'lng', st_x(point.geom)) order by point.path), '[]'::jsonb)
  from simplified cross join lateral st_dumppoints(simplified.geom) as point;
$$;
revoke all on function revv_private.route_overview_nodes(jsonb) from public, anon, authenticated;

create or replace function public.find_curvy_roads_overview_v2(
  user_lat double precision, user_lng double precision,
  radius_m integer default 50000, min_score double precision default 0,
  max_results integer default 30
) returns setof jsonb language plpgsql stable security definer
set search_path = pg_catalog, pg_temp
set statement_timeout = '8s'
as $$
begin
  if (select auth.uid()) is null and coalesce((select auth.jwt()->>'role'),'') <> 'service_role' then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  return query
  select to_jsonb(visible) || jsonb_build_object(
    'nodes', revv_private.route_overview_nodes(visible.nodes),
    'geometry_detail', 'overview')
  from public.find_curvy_roads_v2(user_lat, user_lng, radius_m, min_score, max_results) visible;
end;
$$;
revoke all on function public.find_curvy_roads_overview_v2(double precision,double precision,integer,double precision,integer) from public, anon;
grant execute on function public.find_curvy_roads_overview_v2(double precision,double precision,integer,double precision,integer) to authenticated, service_role;

create or replace function public.get_route_overview_v2(route_ids_input text[])
returns setof jsonb language plpgsql stable security definer
set search_path = pg_catalog, pg_temp
set statement_timeout = '8s'
as $$
begin
  if (select auth.uid()) is null and coalesce((select auth.jwt()->>'role'),'') <> 'service_role' then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  return query
  select jsonb_build_object(
    'id', visible.id, 'name', road.name,
    'nodes', revv_private.route_overview_nodes(visible.nodes),
    'geometry_detail', 'overview',
    'distance_km', road.distance_km, 'center_lat', road.center_lat, 'center_lng', road.center_lng,
    'winding_score', road.winding_score, 'star_rating', road.star_rating,
    'sharp_curve_count', road.sharp_curve_count,
    'tight_curve_km', road.tight_curve_km, 'medium_curve_km', road.medium_curve_km,
    'max_continuous_km', road.max_continuous_km, 'is_loop', road.is_loop,
    'elevation_delta', road.elevation_delta,
    'is_generated', visible.is_generated, 'activated_at', visible.activated_at,
    'province_code', visible.province_code, 'catalog_epoch', visible.catalog_epoch)
  from public.get_route_nodes_v2(route_ids_input) visible
  join public.curvy_roads road on road.id = visible.id
  order by array_position(route_ids_input, visible.id);
end;
$$;
revoke all on function public.get_route_overview_v2(text[]) from public, anon;
grant execute on function public.get_route_overview_v2(text[]) to authenticated, service_role;
