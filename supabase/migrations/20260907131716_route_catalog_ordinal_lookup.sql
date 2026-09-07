-- Expand each requested ID array only once; keep existing auth, visibility,
-- exact ID bounds, de-duplication, input order, full nodes and response contracts.
CREATE OR REPLACE FUNCTION public.get_route_nodes_v2(route_ids_input text[])
 RETURNS TABLE(id text, nodes jsonb, province_code text, is_generated boolean, activated_at timestamp with time zone, catalog_epoch bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
 SET statement_timeout TO '8s'
AS $function$
begin
  if (select auth.uid()) is null
     and coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if route_ids_input is null
     or cardinality(route_ids_input) < 1
     or cardinality(route_ids_input) > 650
     or exists (
       select 1 from unnest(route_ids_input) as requested_id
       where requested_id is null
          or length(requested_id) not between 1 and 192
          or requested_id ~ '[[:cntrl:]%*?]'
     ) then
    raise exception 'route ids must contain 1 to 650 exact ids' using errcode = '22023';
  end if;
  return query
  with requested as materialized (
    -- Preserve ANY's de-duplication and array_position's first-occurrence order,
    -- but expand/detoast the input array once instead of once per result row.
    select requested_id, min(ord) as ord
    from unnest(route_ids_input) with ordinality as ids(requested_id, ord)
    group by requested_id
  )
  select
    road.id,
    road.nodes,
    road.province_code,
    road.publication_kind = 'osm_generated',
    road.activated_at,
    catalog.epoch
  from requested
  join public.curvy_roads as road on road.id = requested.requested_id
  left join public.route_generation_batches as batch
    on batch.batch_id = road.generation_batch_id
  cross join public.route_catalog_state as catalog
  where catalog.singleton_key
    and (
      (road.publication_kind = 'legacy' and road.generation_batch_id is null)
      or (road.publication_kind = 'osm_generated' and batch.status = 'active')
    )
  order by requested.ord;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_route_overview_v2(route_ids_input text[])
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
 SET statement_timeout TO '8s'
AS $function$
begin
  if (select auth.uid()) is null
     and coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if route_ids_input is null
     or cardinality(route_ids_input) < 1
     or cardinality(route_ids_input) > 650
     or exists (
       select 1 from unnest(route_ids_input) as requested_id
       where requested_id is null
          or length(requested_id) not between 1 and 192
          or requested_id ~ '[[:cntrl:]%*?]'
     ) then
    raise exception 'route ids must contain 1 to 650 exact ids' using errcode = '22023';
  end if;
  return query
  with requested as materialized (
    -- Preserve ANY's de-duplication and array_position's first-occurrence order,
    -- but expand/detoast the input array once instead of once per result row.
    select requested_id, min(ord) as ord
    from unnest(route_ids_input) with ordinality as ids(requested_id, ord)
    group by requested_id
  )
  select jsonb_build_object(
    'id', road.id, 'name', road.name,
    'nodes', revv_private.route_overview_nodes(road.nodes),
    'geometry_detail', 'overview',
    'distance_km', road.distance_km, 'center_lat', road.center_lat, 'center_lng', road.center_lng,
    'winding_score', road.winding_score, 'star_rating', road.star_rating,
    'sharp_curve_count', road.sharp_curve_count,
    'tight_curve_km', road.tight_curve_km, 'medium_curve_km', road.medium_curve_km,
    'max_continuous_km', road.max_continuous_km, 'is_loop', road.is_loop,
    'elevation_delta', road.elevation_delta,
    'is_generated', road.publication_kind = 'osm_generated', 'activated_at', road.activated_at,
    'province_code', road.province_code, 'catalog_epoch', catalog.epoch)
  from requested
  join public.curvy_roads as road on road.id = requested.requested_id
  left join public.route_generation_batches as batch
    on batch.batch_id = road.generation_batch_id
  cross join public.route_catalog_state as catalog
  where catalog.singleton_key
    and (
      (road.publication_kind = 'legacy' and road.generation_batch_id is null)
      or (road.publication_kind = 'osm_generated' and batch.status = 'active')
    )
  order by requested.ord;
end;
$function$;

revoke all on function public.get_route_nodes_v2(text[]) from public, anon;
grant execute on function public.get_route_nodes_v2(text[]) to authenticated, service_role;
revoke all on function public.get_route_overview_v2(text[]) from public, anon;
grant execute on function public.get_route_overview_v2(text[]) to authenticated, service_role;
