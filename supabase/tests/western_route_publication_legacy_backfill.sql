\set ON_ERROR_STOP on

begin;

insert into public.curvy_roads (
  id, name, center_lat, center_lng, center_point, nodes,
  distance_km, winding_score, region
)
select
  'legacy-province-' || lower(expected_code),
  'Legacy ' || region_value,
  50.0 + ordinal / 100.0,
  -110.0 - ordinal / 100.0,
  st_setsrid(
    st_makepoint(-110.0 - ordinal / 100.0, 50.0 + ordinal / 100.0),
    4326
  )::geography,
  jsonb_build_array(
    jsonb_build_object(
      'lat', 50.0 + ordinal / 100.0,
      'lng', -110.0 - ordinal / 100.0
    ),
    jsonb_build_object(
      'lat', 50.01 + ordinal / 100.0,
      'lng', -110.01 - ordinal / 100.0
    )
  ),
  6.0,
  40.0,
  region_value
from (
  values
    (1, 'Alberta', 'AB'),
    (2, 'British Columbia', 'BC'),
    (3, 'Manitoba', 'MB'),
    (4, 'New Brunswick', 'NB'),
    (5, 'Newfoundland and Labrador', 'NL'),
    (6, 'Nova Scotia', 'NS'),
    (7, 'Northwest Territories', 'NT'),
    (8, 'Nunavut', 'NU'),
    (9, 'Ontario', 'ON'),
    (10, 'Prince Edward Island', 'PE'),
    (11, 'Quebec', 'QC'),
    (12, 'Saskatchewan', 'SK'),
    (13, 'Yukon', 'YT')
) as legacy(ordinal, region_value, expected_code);

\ir ../migrations/20260716043420_western_route_publication_v2.sql

do $$
declare
  mismatch_count integer;
  catalog_ids text[];
  expected_catalog_ids constant text[] := array[
    'legacy-province-ab',
    'legacy-province-bc',
    'legacy-province-mb',
    'legacy-province-nb',
    'legacy-province-nl',
    'legacy-province-ns',
    'legacy-province-pe',
    'legacy-province-qc',
    'legacy-province-sk'
  ];
begin
  select count(*)::integer
  into mismatch_count
  from (
    values
      ('legacy-province-ab', 'AB'),
      ('legacy-province-bc', 'BC'),
      ('legacy-province-mb', 'MB'),
      ('legacy-province-nb', 'NB'),
      ('legacy-province-nl', 'NL'),
      ('legacy-province-ns', 'NS'),
      ('legacy-province-nt', 'NT'),
      ('legacy-province-nu', 'NU'),
      ('legacy-province-on', 'ON'),
      ('legacy-province-pe', 'PE'),
      ('legacy-province-qc', 'QC'),
      ('legacy-province-sk', 'SK'),
      ('legacy-province-yt', 'YT')
  ) as expected(route_id, province_code)
  left join public.curvy_roads as road
    on road.id = expected.route_id
   and road.province_code = expected.province_code
  where road.id is null;

  if mismatch_count <> 0 then
    raise exception 'legacy 13-code province backfill mismatch for % rows', mismatch_count;
  end if;
  if (
    select count(*) from public.curvy_roads
    where province_code is null
       or province_code not in ('AB','BC','MB','NB','NL','NS','NT','NU','ON','PE','QC','SK','YT')
  ) <> 0 then
    raise exception 'legacy fixture retained an unclassified province';
  end if;

  select route_ids
  into catalog_ids
  from public.route_catalog_state
  where singleton_key;

  if catalog_ids is distinct from expected_catalog_ids then
    raise exception 'shared-geohash sparse-province catalog mismatch: %', catalog_ids;
  end if;
  if encode(
    extensions.digest(array_to_string(catalog_ids, E'\n'), 'sha256'),
    'hex'
  ) <> '201643f188802a57111825aae645ce8fc2a79ffa776cbd9ed9aac6146414ac4c' then
    raise exception 'shared-geohash sparse-province catalog digest mismatch';
  end if;
  if (
    select max(cell_count)
    from (
      select coalesce(
        nullif(road.geohash4, ''),
        public.st_geohash(road.center_point::public.geometry, 4)
      ) as effective_geohash4,
      count(*) as cell_count
      from unnest(catalog_ids) as route_id
      join public.curvy_roads as road on road.id = route_id
      group by effective_geohash4
    ) as cells
  ) > 3 then
    raise exception 'shared-geohash backfill weakened the global cell cap';
  end if;
  if (
    select max(province_count)
    from (
      select road.province_code, count(*) as province_count
      from unnest(catalog_ids) as route_id
      join public.curvy_roads as road on road.id = route_id
      group by road.province_code
    ) as provinces
  ) > 80 then
    raise exception 'shared-geohash backfill weakened the province cap';
  end if;

  perform revv_private.rebuild_route_catalog(false);
  if (
    select route_ids from public.route_catalog_state where singleton_key
  ) is distinct from expected_catalog_ids then
    raise exception 'shared-geohash sparse-province rebuild was not deterministic';
  end if;
end;
$$;

rollback;
