\set ON_ERROR_STOP on

begin;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);

do $$
declare
  route_ids_sha256 text;
begin
  select encode(
    extensions.digest(
      string_agg(
        length('allocator-hub-' || to_char(n, 'FM00'))::text || ':' ||
          'allocator-hub-' || to_char(n, 'FM00'),
        E'\n' order by n
      ),
      'sha256'
    ),
    'hex'
  )
  into route_ids_sha256
  from generate_series(1, 24) as n;

  perform public.admin_register_route_generation_batch(
    'allocator-pilot-20260716',
    'pilot',
    'allocator-fixture-v1',
    repeat('1', 64),
    route_ids_sha256,
    24,
    '{"fixture":"catalog-allocation"}'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'hub_id', 'allocator-hub',
      'province_code', 'AB',
      'source_pbf_sha256', repeat('a', 64),
      'source_graph_sha256', repeat('b', 64),
      'source_snapshot', 'fixture-ab-2026-07-16'
    ))
  );
end;
$$;

insert into public.curvy_roads (
  id, name, center_lat, center_lng, center_point, nodes,
  distance_km, winding_score, region, source, geohash4, province_code,
  publication_kind, generation_batch_id, source_pbf_sha256,
  source_hub_id, source_graph_sha256, generation_provenance
)
select
  'allocator-hub-' || to_char(n, 'FM00'),
  'Allocator Hub ' || to_char(n, 'FM00'),
  51.0 + n / 10000.0,
  -114.0 - n / 10000.0,
  st_setsrid(
    st_makepoint(-114.0 - n / 10000.0, 51.0 + n / 10000.0),
    4326
  )::geography,
  jsonb_build_array(
    jsonb_build_object('lat', 51.0 + n / 10000.0, 'lng', -114.0 - n / 10000.0),
    jsonb_build_object('lat', 51.01 + n / 10000.0, 'lng', -114.01 - n / 10000.0)
  ),
  20.0,
  1.0,
  'alberta',
  'osm_generated',
  'h' || lpad(to_hex(n), 3, '0'),
  'AB',
  'osm_generated',
  'allocator-pilot-20260716',
  repeat('a', 64),
  'allocator-hub',
  repeat('b', 64),
  jsonb_build_object(
    'province_codes', jsonb_build_array('AB'),
    'source_hub_id', 'allocator-hub',
    'directed_edge_ids', jsonb_build_array('edge-' || n),
    'source_seed_ids', jsonb_build_array('seed-' || n),
    'guidance_receipt_sha256', repeat('c', 64)
  )
from generate_series(1, 24) as n;

select *
from public.admin_transition_route_batch(
  'allocator-pilot-20260716', repeat('1', 64), 'active'
);

insert into public.curvy_roads (
  id, name, center_lat, center_lng, center_point, nodes,
  distance_km, winding_score, region, source, geohash4, province_code
)
select
  'allocator-' || lower(spec.province_code) || '-' || to_char(n, 'FM0000'),
  'Allocator ' || spec.province_code || ' ' || to_char(n, 'FM0000'),
  50.0 + n / 100000.0,
  -110.0 - n / 100000.0,
  st_setsrid(
    st_makepoint(-110.0 - n / 100000.0, 50.0 + n / 100000.0),
    4326
  )::geography,
  jsonb_build_array(
    jsonb_build_object('lat', 50.0 + n / 100000.0, 'lng', -110.0 - n / 100000.0),
    jsonb_build_object('lat', 50.01 + n / 100000.0, 'lng', -110.01 - n / 100000.0)
  ),
  case spec.route_kind when 'recommendation' then 6.0 else 1.0 end,
  50.0,
  lower(spec.province_code),
  'roadcurvature',
  lower(spec.province_code) || lpad(to_hex(((n - 1) / 3)::integer), 2, '0'),
  spec.province_code
from (
  values
    ('AB', 400, 'recommendation'),
    ('BC', 400, 'map'),
    ('MB', 10, 'recommendation'),
    ('SK', 10, 'map')
) as spec(province_code, route_count, route_kind)
cross join lateral generate_series(1, spec.route_count) as n;

insert into public.curvy_roads (
  id, name, center_lat, center_lng, center_point, nodes,
  distance_km, winding_score, region, source, geohash4, province_code
)
select
  'allocator-nb-' || to_char(n, 'FM0000'),
  'Allocator NB ' || to_char(n, 'FM0000'),
  46.0 + n / 100000.0,
  -66.0 - n / 100000.0,
  st_setsrid(
    st_makepoint(-66.0 - n / 100000.0, 46.0 + n / 100000.0),
    4326
  )::geography,
  jsonb_build_array(
    jsonb_build_object('lat', 46.0 + n / 100000.0, 'lng', -66.0 - n / 100000.0),
    jsonb_build_object('lat', 46.01 + n / 100000.0, 'lng', -66.01 - n / 100000.0)
  ),
  case when n <= 60 then 6.0 else 1.0 end,
  50.0,
  'new_brunswick',
  'roadcurvature',
  'nb' || lpad(to_hex(((n - 1) / 3)::integer), 2, '0'),
  'NB'
from generate_series(1, 120) as n;

insert into public.curvy_roads (
  id, name, center_lat, center_lng, center_point, nodes,
  distance_km, winding_score, region, source, geohash4, province_code
)
select
  'allocator-on-single-cell-' || to_char(n, 'FM000'),
  'Allocator ON Single Cell ' || to_char(n, 'FM000'),
  45.0 + n / 100000.0,
  -79.0 - n / 100000.0,
  st_setsrid(
    st_makepoint(-79.0 - n / 100000.0, 45.0 + n / 100000.0),
    4326
  )::geography,
  jsonb_build_array(
    jsonb_build_object('lat', 45.0 + n / 100000.0, 'lng', -79.0 - n / 100000.0),
    jsonb_build_object('lat', 45.01 + n / 100000.0, 'lng', -79.01 - n / 100000.0)
  ),
  6.0,
  50.0,
  'ontario',
  'roadcurvature',
  'onzz',
  'ON'
from generate_series(1, 100) as n;

select revv_private.rebuild_route_catalog(false);

create temporary table allocator_first_catalog on commit drop as
select route_ids
from public.route_catalog_state
where singleton_key;

do $$
declare
  catalog_ids text[];
  fixed_digest text;
begin
  select route_ids
  into catalog_ids
  from public.route_catalog_state
  where singleton_key;

  if cardinality(catalog_ids) <> 263 then
    raise exception 'three-phase catalog size mismatch: expected 263, got %',
      cardinality(catalog_ids);
  end if;
  if (
    select max(province_count)
    from (
      select road.province_code, count(*) as province_count
      from unnest(catalog_ids) with ordinality as selected(route_id, ordinal)
      join public.curvy_roads as road on road.id = selected.route_id
      group by road.province_code
    ) as counts
  ) > 80 then
    raise exception 'region cap 80 was exceeded';
  end if;
  if (
    select count(*) from unnest(catalog_ids) as route_id
    join public.curvy_roads as road on road.id = route_id
    where road.province_code = 'MB'
  ) <> 10 or (
    select count(*) from unnest(catalog_ids) as route_id
    join public.curvy_roads as road on road.id = route_id
    where road.province_code = 'SK'
  ) <> 10 then
    raise exception 'synthetic AB400/BC400/MB10/SK10 lost sparse-province minima';
  end if;
  if (
    select count(*) from unnest(catalog_ids) as route_id
    join public.curvy_roads as road on road.id = route_id
    where road.province_code = 'AB'
  ) <> 80 or (
    select count(*) from unnest(catalog_ids) as route_id
    join public.curvy_roads as road on road.id = route_id
    where road.province_code = 'BC'
  ) <> 80 then
    raise exception 'unused sparse-province quota did not redistribute deterministically';
  end if;
  if (
    select max(cell_count)
    from (
      select road.geohash4, count(*) as cell_count
      from unnest(catalog_ids) as route_id
      join public.curvy_roads as road on road.id = route_id
      group by road.geohash4
    ) as cells
  ) > 3 then
    raise exception 'geohash4 cap 3 was exceeded';
  end if;
  if (
    select count(*) from unnest(catalog_ids) as route_id
    join public.curvy_roads as road on road.id = route_id
    where road.geohash4 = 'onzz'
  ) <> 3 then
    raise exception 'single 100-row geohash did not clamp to 3';
  end if;
  if (
    select count(*) from unnest(catalog_ids) as route_id
    join public.curvy_roads as road on road.id = route_id
    where road.province_code = 'NB' and road.distance_km >= 4.0
  ) <> 48 or (
    select count(*) from unnest(catalog_ids) as route_id
    join public.curvy_roads as road on road.id = route_id
    where road.province_code = 'NB' and road.distance_km < 4.0
  ) <> 32 then
    raise exception 'recommendation/map 3:2 quota or fallback was not preserved';
  end if;
  if (
    select count(*)
    from unnest(catalog_ids[1:3]) as route_id
    where route_id like 'allocator-hub-%'
  ) <> 3 then
    raise exception 'western manifest hub did not reserve three distinct-cell routes first';
  end if;
  if (
    select count(distinct road.geohash4)
    from unnest(catalog_ids[1:3]) as route_id
    join public.curvy_roads as road on road.id = route_id
  ) <> 3 then
    raise exception 'western manifest hub reservation reused a geohash4 cell';
  end if;

  select encode(
    extensions.digest(array_to_string(catalog_ids, E'\n'), 'sha256'),
    'hex'
  ) into fixed_digest;
  if fixed_digest <> 'dc3279d80667b187556224af05ca68bfc87a4a6dfd9cb05a7552505fc4acbf92' then
    raise exception 'catalog byte digest mismatch: %', fixed_digest;
  end if;
end;
$$;

select revv_private.rebuild_route_catalog(false);

do $$
begin
  if (
    select route_ids from public.route_catalog_state where singleton_key
  ) is distinct from (
    select route_ids from allocator_first_catalog
  ) then
    raise exception 'identical rebuild was not byte-deterministic';
  end if;
  if has_table_privilege('authenticated', 'public.route_catalog_state', 'SELECT') then
    raise exception 'authenticated direct catalog select unexpectedly succeeded';
  end if;
end;
$$;

insert into public.curvy_roads (
  id, name, center_lat, center_lng, center_point, nodes,
  distance_km, winding_score, region, source, geohash4, province_code
)
select
  'allocator-stress-' || lower(spec.province_code) || '-' || to_char(n, 'FM0000'),
  'Allocator Stress ' || spec.province_code || ' ' || to_char(n, 'FM0000'),
  55.0 + n / 100000.0,
  -100.0 - n / 100000.0,
  st_setsrid(
    st_makepoint(-100.0 - n / 100000.0, 55.0 + n / 100000.0),
    4326
  )::geography,
  jsonb_build_array(
    jsonb_build_object('lat', 55.0 + n / 100000.0, 'lng', -100.0 - n / 100000.0),
    jsonb_build_object('lat', 55.01 + n / 100000.0, 'lng', -100.01 - n / 100000.0)
  ),
  case when mod(n - 1, 5) < 3 then 6.0 else 1.0 end,
  40.0,
  lower(spec.province_code),
  'roadcurvature',
  lower(spec.province_code) || lpad(to_hex(((n - 1) / 3)::integer), 2, '0'),
  spec.province_code
from (
  values ('NL'), ('NS'), ('NT'), ('NU'), ('PE'), ('QC'), ('YT')
) as spec(province_code)
cross join lateral generate_series(1, 240) as n;

select revv_private.rebuild_route_catalog(false);

do $$
declare
  catalog_ids text[];
begin
  select route_ids
  into catalog_ids
  from public.route_catalog_state
  where singleton_key;

  if cardinality(catalog_ids) <> 650 then
    raise exception 'route-ID-only catalog did not clamp to 650';
  end if;
  if pg_column_size(catalog_ids) >= 2097152 then
    raise exception 'route-ID-only catalog payload exceeded 2 MiB';
  end if;
  if (
    select max(province_count)
    from (
      select road.province_code, count(*) as province_count
      from unnest(catalog_ids) as route_id
      join public.curvy_roads as road on road.id = route_id
      group by road.province_code
    ) as counts
  ) > 80 then
    raise exception '650-route stress catalog exceeded the region cap';
  end if;
  if (
    select max(cell_count)
    from (
      select road.geohash4, count(*) as cell_count
      from unnest(catalog_ids) as route_id
      join public.curvy_roads as road on road.id = route_id
      group by road.geohash4
    ) as cells
  ) > 3 then
    raise exception '650-route stress catalog exceeded the geohash4 cap';
  end if;
end;
$$;

rollback;
