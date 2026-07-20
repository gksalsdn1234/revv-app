\set ON_ERROR_STOP on

begin;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);

insert into public.curvy_roads (
  id, name, center_lat, center_lng, center_point, nodes,
  distance_km, winding_score, region, province_code
) values (
  'fixture-legacy', 'Fixture Legacy', 51.0, -114.0,
  st_setsrid(st_makepoint(-114.0, 51.0), 4326)::geography,
  '[{"lat":51.0,"lng":-114.0},{"lat":51.01,"lng":-114.01}]'::jsonb,
  6.0, 40.0, 'alberta', 'AB'
);

insert into public.curvy_roads (
  id, name, center_lat, center_lng, center_point, nodes,
  distance_km, winding_score, region, province_code
) values (
  'fixture-map-legacy', 'Fixture Map Legacy', 51.0, -114.0,
  st_setsrid(st_makepoint(-114.0, 51.0), 4326)::geography,
  '[{"lat":51.0,"lng":-114.0},{"lat":51.001,"lng":-114.001}]'::jsonb,
  1.0, 45.0, 'alberta', 'AB'
);

do $$
declare
  pilot_ids_sha256 text;
  expansion_ids_sha256 text;
begin
  select encode(
    extensions.digest(string_agg(
      length('fixture-pilot-' || to_char(n, 'FM00'))::text || ':' ||
        'fixture-pilot-' || to_char(n, 'FM00'), E'\n' order by n
    ), 'sha256'),
    'hex'
  ) into pilot_ids_sha256
  from generate_series(1, 24) as n;

  select encode(
    extensions.digest(string_agg(
      length('fixture-expansion-' || to_char(n, 'FM000'))::text || ':' ||
        'fixture-expansion-' || to_char(n, 'FM000'), E'\n' order by n
    ), 'sha256'),
    'hex'
  ) into expansion_ids_sha256
  from generate_series(1, 96) as n;

  perform public.admin_register_route_generation_batch(
    'fixture-pilot-20260716',
    'pilot',
    'fixture-v1',
    repeat('1', 64),
    pilot_ids_sha256,
    24,
    '{"fixture":"pilot"}'::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'hub_id', 'calgary',
        'province_code', 'AB',
        'source_pbf_sha256', repeat('a', 64),
        'source_graph_sha256', repeat('b', 64),
        'source_snapshot', 'fixture-ab-2026-07-16'
      ),
      jsonb_build_object(
        'hub_id', 'kananaskis',
        'province_code', 'AB',
        'source_pbf_sha256', repeat('a', 64),
        'source_graph_sha256', repeat('9', 64),
        'source_snapshot', 'fixture-ab-2026-07-16'
      )
    )
  );

  perform public.admin_register_route_generation_batch(
    'fixture-expansion-20260716',
    'expansion',
    'fixture-v1',
    repeat('2', 64),
    expansion_ids_sha256,
    96,
    '{"fixture":"expansion"}'::jsonb,
    jsonb_build_array(jsonb_build_object(
        'hub_id', 'drumheller',
        'province_code', 'AB',
        'source_pbf_sha256', repeat('d', 64),
      'source_graph_sha256', repeat('e', 64),
      'source_snapshot', 'fixture-sk-2026-07-16'
    ))
  );

  perform public.admin_register_route_generation_batch(
    'fixture-partial-20260716',
    'pilot',
    'fixture-v1',
    repeat('3', 64),
    repeat('4', 64),
    24,
    '{"fixture":"partial-cohort"}'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'hub_id', 'edmonton',
      'province_code', 'AB',
      'source_pbf_sha256', repeat('5', 64),
      'source_graph_sha256', repeat('6', 64),
      'source_snapshot', 'fixture-ab-2026-07-16'
    ))
  );

  perform public.admin_register_route_generation_batch(
    'fixture-hash-mismatch-20260716',
    'pilot',
    'fixture-v1',
    repeat('7', 64),
    repeat('8', 64),
    24,
    '{"fixture":"same-count-hash-mismatch"}'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'hub_id', 'red-deer',
      'province_code', 'AB',
      'source_pbf_sha256', repeat('5', 64),
      'source_graph_sha256', repeat('7', 64),
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
  'fixture-pilot-' || to_char(n, 'FM00'),
  'Fixture Pilot ' || to_char(n, 'FM00'),
  51.0 + n / 10000.0,
  -114.0 - n / 10000.0,
  st_setsrid(st_makepoint(-114.0 - n / 10000.0, 51.0 + n / 10000.0), 4326)::geography,
  jsonb_build_array(
    jsonb_build_object('lat', 51.0 + n / 10000.0, 'lng', -114.0 - n / 10000.0),
    jsonb_build_object('lat', 51.01 + n / 10000.0, 'lng', -114.01 - n / 10000.0)
  ),
  20.0,
  80.0 - n / 100.0,
  'alberta',
  'osm_generated',
  'p' || lpad(to_hex(n), 3, '0'),
  'AB',
  'osm_generated',
  'fixture-pilot-20260716',
  repeat('a', 64),
  case when n <= 12 then 'calgary' else 'kananaskis' end,
  case when n <= 12 then repeat('b', 64) else repeat('9', 64) end,
  jsonb_build_object(
    'province_codes', jsonb_build_array('AB'),
    'source_hub_id', case when n <= 12 then 'calgary' else 'kananaskis' end,
    'directed_edge_ids', jsonb_build_array('edge-' || n),
    'source_seed_ids', jsonb_build_array('seed-' || n),
    'guidance_receipt_sha256', repeat('c', 64)
  )
from generate_series(1, 24) as n;

insert into public.curvy_roads (
  id, name, center_lat, center_lng, center_point, nodes,
  distance_km, winding_score, region, source, geohash4, province_code,
  publication_kind, generation_batch_id, source_pbf_sha256,
  source_hub_id, source_graph_sha256, generation_provenance
)
select
  'fixture-expansion-' || to_char(n, 'FM000'),
  'Fixture Expansion ' || to_char(n, 'FM000'),
  51.0 + n / 10000.0,
  -114.0 - n / 10000.0,
  st_setsrid(st_makepoint(-114.0 - n / 10000.0, 51.0 + n / 10000.0), 4326)::geography,
  jsonb_build_array(
    jsonb_build_object('lat', 51.0 + n / 10000.0, 'lng', -114.0 - n / 10000.0),
    jsonb_build_object('lat', 51.01 + n / 10000.0, 'lng', -114.01 - n / 10000.0)
  ),
  25.0,
  70.0 - n / 1000.0,
  'alberta',
  'osm_generated',
  'e' || lpad(to_hex(n), 3, '0'),
  'AB',
  'osm_generated',
  'fixture-expansion-20260716',
  repeat('d', 64),
  'drumheller',
  repeat('e', 64),
  jsonb_build_object(
    'province_codes', jsonb_build_array('AB'),
    'source_hub_id', 'drumheller',
    'directed_edge_ids', jsonb_build_array('edge-' || n),
    'source_seed_ids', jsonb_build_array('seed-' || n),
    'guidance_receipt_sha256', repeat('f', 64)
  )
from generate_series(1, 96) as n;

insert into public.curvy_roads (
  id, name, center_lat, center_lng, center_point, nodes,
  distance_km, winding_score, region, source, geohash4, province_code,
  publication_kind, generation_batch_id, source_pbf_sha256,
  source_hub_id, source_graph_sha256, generation_provenance
)
select
  'fixture-hash-' || to_char(n, 'FM00'),
  'Fixture Hash ' || to_char(n, 'FM00'),
  51.0 + n / 10000.0,
  -114.0 - n / 10000.0,
  st_setsrid(st_makepoint(-114.0 - n / 10000.0, 51.0 + n / 10000.0), 4326)::geography,
  jsonb_build_array(
    jsonb_build_object('lat', 51.0 + n / 10000.0, 'lng', -114.0 - n / 10000.0),
    jsonb_build_object('lat', 51.01 + n / 10000.0, 'lng', -114.01 - n / 10000.0)
  ),
  20.0,
  90.0 - n / 100.0,
  'alberta',
  'osm_generated',
  'x' || lpad(to_hex(n), 3, '0'),
  'AB',
  'osm_generated',
  'fixture-hash-mismatch-20260716',
  repeat('5', 64),
  'red-deer',
  repeat('7', 64),
  jsonb_build_object(
    'province_codes', jsonb_build_array('AB'),
    'source_hub_id', 'red-deer',
    'directed_edge_ids', jsonb_build_array('edge-' || n),
    'source_seed_ids', jsonb_build_array('seed-' || n),
    'guidance_receipt_sha256', repeat('8', 64)
  )
from generate_series(1, 24) as n;

do $$
begin
  if (select count(*) from public.curvy_roads where publication_kind = 'osm_generated') <> 144 then
    raise exception 'fixture shadow import count mismatch';
  end if;
  if (
    select count(*) from public.route_generation_sources
    where batch_id = 'fixture-pilot-20260716' and province_code = 'AB'
  ) <> 2 then
    raise exception 'same-province per-hub graph sources were collapsed';
  end if;
  if (
    select count(distinct source_hub_id) from public.curvy_roads
    where generation_batch_id = 'fixture-pilot-20260716'
  ) <> 2 then
    raise exception 'generated routes did not retain per-hub graph identity';
  end if;
  if (select cardinality(route_ids) from public.route_catalog_state where singleton_key) <> 0 then
    raise exception 'shadow routes leaked into initial catalog';
  end if;
  if has_table_privilege('authenticated', 'public.route_generation_batches', 'SELECT')
     or has_table_privilege('authenticated', 'public.route_catalog_state', 'SELECT')
     or has_function_privilege(
       'authenticated',
       'public.admin_transition_route_batch(text,text,text)',
       'EXECUTE'
     ) then
    raise exception 'client admin or direct catalog privilege leaked';
  end if;
end;
$$;

select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000001"}',
  true
);
set local role authenticated;

do $$
begin
  if (select count(*) from public.curvy_roads where publication_kind = 'osm_generated') <> 0 then
    raise exception 'shadow routes leaked through direct RLS';
  end if;
  if (
    select count(*) from public.find_curvy_roads(51.0, -114.0, 160000, 0, 120)
    where source = 'osm_generated'
  ) <> 0 then
    raise exception 'shadow routes leaked through legacy recommendation RPC';
  end if;
  if not exists (
    select 1 from public.find_curvy_roads(51.0, -114.0, 160000, 0, 120)
    where id = 'fixture-legacy'
  ) then
    raise exception 'shadow cohort suppressed the visible legacy recommendation';
  end if;
  if (
    select count(*) from public.find_curvy_map_segments(51.0, -114.0, 160000, 0.3, 60)
    where source = 'osm_generated'
  ) <> 0 then
    raise exception 'shadow routes leaked through legacy map RPC';
  end if;
  if not exists (
    select 1 from public.find_curvy_map_segments(51.0, -114.0, 160000, 0.3, 60)
    where id = 'fixture-map-legacy'
  ) then
    raise exception 'legacy map segment was suppressed by generated cohorts';
  end if;
  if (
    select count(*) from public.find_curvy_roads_v2(51.0, -114.0, 160000, 0, 120)
    where is_generated
  ) <> 0 then
    raise exception 'shadow routes leaked through v2 RPC';
  end if;
  if has_function_privilege(
    current_user,
    'public.admin_transition_route_batch(text,text,text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated client activation unexpectedly succeeded';
  end if;
  begin
    perform 1 from public.route_catalog_state;
    raise exception 'authenticated direct catalog SELECT unexpectedly succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select * from public.admin_transition_route_batch(
  'fixture-pilot-20260716', repeat('1', 64), 'active'
);

do $$
begin
  if (select epoch from public.route_catalog_state where singleton_key) <> 1 then
    raise exception 'pilot activation did not increment epoch once';
  end if;
  if (
    select count(*)
    from unnest((select route_ids from public.route_catalog_state where singleton_key)) as route_id
    where route_id like 'fixture-pilot-%'
  ) <> 24 then
    raise exception 'active pilot catalog is incomplete';
  end if;
  if (
    select count(*)
    from unnest((select route_ids from public.route_catalog_state where singleton_key)) as route_id
    where route_id like 'fixture-expansion-%'
  ) <> 0 then
    raise exception 'shadow expansion leaked after pilot activation';
  end if;
  if (select count(*) from public.route_batch_transition_receipts) <> 1 then
    raise exception 'activation receipt missing';
  end if;
end;
$$;

select * from public.admin_transition_route_batch(
  'fixture-pilot-20260716', repeat('1', 64), 'active'
);

do $$
begin
  if (select epoch from public.route_catalog_state where singleton_key) <> 1
     or (select count(*) from public.route_batch_transition_receipts) <> 1 then
    raise exception 'same-state active transition was not an epoch-stable no-op';
  end if;
end;
$$;

select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000001"}',
  true
);
set local role authenticated;

do $$
begin
  if (select count(*) from public.curvy_roads where publication_kind = 'osm_generated') <> 0 then
    raise exception 'active generated routes leaked through direct legacy RLS';
  end if;
  if (
    select count(*) from public.find_curvy_roads(51.0, -114.0, 160000, 0, 120)
    where source = 'osm_generated'
  ) <> 0 then
    raise exception 'active generated routes leaked through legacy recommendation RPC';
  end if;
  if not exists (
    select 1 from public.find_curvy_roads(51.0, -114.0, 160000, 0, 120)
    where id = 'fixture-legacy'
  ) then
    raise exception 'active/shadow generated cohorts suppressed the legacy recommendation';
  end if;
  if (
    select count(*) from public.find_curvy_map_segments(51.0, -114.0, 160000, 0.3, 60)
    where source = 'osm_generated'
  ) <> 0 then
    raise exception 'active generated routes leaked through legacy map RPC';
  end if;
  if (
    select count(*) from public.find_curvy_roads_v2(51.0, -114.0, 160000, 0, 120)
    where is_generated
  ) <> 24 then
    raise exception 'active pilot missing from v2 recommendation RPC';
  end if;
  if (
    select count(*) from public.get_route_nodes_v2(
      array(select 'fixture-pilot-' || to_char(n, 'FM00') from generate_series(1, 24) as n)
    ) where is_generated
  ) <> 24 then
    raise exception 'active pilot missing from v2 node RPC';
  end if;
  if (
    select count(*)
    from unnest((select route_ids from public.get_route_catalog_v2())) as route_id
    where route_id like 'fixture-pilot-%'
  ) <> 24 then
    raise exception 'active pilot missing from authenticated catalog RPC';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

do $$
begin
  if not (
    select route_ids_match and actual_route_count = 24 and catalog_route_count = 24
    from public.admin_audit_route_generation_batch('fixture-pilot-20260716')
  ) then
    raise exception 'service publication audit did not reconcile active pilot';
  end if;
  begin
    perform public.admin_transition_route_batch(
      'fixture-pilot-20260716', repeat('1', 64), 'shadow'
    );
    raise exception 'active to shadow unexpectedly succeeded';
  exception when sqlstate '22023' then
    null;
  end;
  begin
    perform public.admin_transition_route_batch(
      'fixture-%', repeat('1', 64), 'disabled'
    );
    raise exception 'wildcard batch unexpectedly succeeded';
  exception when sqlstate '22023' then
    null;
  end;
  begin
    perform public.admin_transition_route_batch(
      'fixture-pilot-20260716', repeat('0', 64), 'disabled'
    );
    raise exception 'wrong manifest checksum unexpectedly succeeded';
  exception when sqlstate '23514' then
    null;
  end;
  begin
    perform public.admin_transition_route_batch(
      'fixture-expansion-20260716', repeat('2', 64), 'disabled'
    );
    raise exception 'shadow to disabled unexpectedly succeeded';
  exception when sqlstate '23514' then
    null;
  end;
  begin
    perform public.admin_transition_route_batch(
      'fixture-partial-20260716', repeat('3', 64), 'active'
    );
    raise exception 'partial cohort unexpectedly activated';
  exception when sqlstate '23514' then
    null;
  end;
  begin
    perform public.admin_transition_route_batch(
      'fixture-hash-mismatch-20260716', repeat('7', 64), 'active'
    );
    raise exception 'same-count route id hash mismatch unexpectedly activated';
  exception when sqlstate '23514' then
    null;
  end;
  begin
    insert into public.curvy_roads (
      id, name, center_lat, center_lng, center_point, nodes,
      distance_km, region, source, province_code, publication_kind,
      generation_batch_id, source_hub_id, source_pbf_sha256, source_graph_sha256,
      generation_provenance
    ) values (
      'fixture-source-mismatch', 'Mismatch', 51.0, -114.0,
      st_setsrid(st_makepoint(-114.0, 51.0), 4326)::geography,
      '[{"lat":51.0,"lng":-114.0},{"lat":51.01,"lng":-114.01}]'::jsonb,
      20.0, 'alberta', 'osm_generated', 'AB', 'osm_generated',
      'fixture-expansion-20260716', 'calgary', repeat('a', 64), repeat('b', 64),
      jsonb_build_object(
        'province_codes', jsonb_build_array('AB'),
        'source_hub_id', 'calgary',
        'directed_edge_ids', jsonb_build_array('edge'),
        'source_seed_ids', jsonb_build_array('seed'),
        'guidance_receipt_sha256', repeat('c', 64)
      )
    );
    raise exception 'source graph/code mismatch unexpectedly succeeded';
  exception when integrity_constraint_violation then
    null;
  end;
  begin
    insert into public.curvy_roads (
      id, name, center_lat, center_lng, center_point, nodes,
      distance_km, region, source, province_code, publication_kind,
      generation_batch_id, source_hub_id, source_pbf_sha256, source_graph_sha256,
      generation_provenance
    ) values (
      'fixture-multi-province', 'Multi province', 51.0, -114.0,
      st_setsrid(st_makepoint(-114.0, 51.0), 4326)::geography,
      '[{"lat":51.0,"lng":-114.0},{"lat":51.01,"lng":-114.01}]'::jsonb,
      20.0, 'alberta', 'osm_generated', 'AB', 'osm_generated',
      'fixture-expansion-20260716', 'drumheller', repeat('d', 64), repeat('e', 64),
      jsonb_build_object(
        'province_codes', jsonb_build_array('AB', 'BC'),
        'source_hub_id', 'drumheller',
        'directed_edge_ids', jsonb_build_array('edge'),
        'source_seed_ids', jsonb_build_array('seed'),
        'guidance_receipt_sha256', repeat('f', 64)
      )
    );
    raise exception 'multi-province provenance unexpectedly succeeded';
  exception when sqlstate '23514' then
    null;
  end;
  begin
    insert into public.curvy_roads (
      id, name, center_lat, center_lng, center_point, nodes,
      distance_km, region, source, province_code, publication_kind,
      generation_batch_id, source_hub_id, source_pbf_sha256, source_graph_sha256,
      generation_provenance
    ) values (
      E'fixture\nbad-id', 'Malformed ID', 51.0, -114.0,
      st_setsrid(st_makepoint(-114.0, 51.0), 4326)::geography,
      '[{"lat":51.0,"lng":-114.0},{"lat":51.01,"lng":-114.01}]'::jsonb,
      20.0, 'alberta', 'osm_generated', 'AB', 'osm_generated',
      'fixture-expansion-20260716', 'drumheller', repeat('d', 64), repeat('e', 64),
      jsonb_build_object(
        'province_codes', jsonb_build_array('AB'),
        'source_hub_id', 'drumheller',
        'directed_edge_ids', jsonb_build_array('edge'),
        'source_seed_ids', jsonb_build_array('seed'),
        'guidance_receipt_sha256', repeat('f', 64)
      )
    );
    raise exception 'malformed generated id unexpectedly succeeded';
  exception when sqlstate '23514' then
    null;
  end;
  begin
    perform * from public.get_route_nodes_v2(array['fixture-*']);
    raise exception 'wildcard route id unexpectedly succeeded';
  exception when sqlstate '22023' then
    null;
  end;
  begin
    perform * from public.get_route_nodes_v2(array[E'fixture\nbad']);
    raise exception 'control-character route id unexpectedly succeeded';
  exception when sqlstate '22023' then
    null;
  end;
end;
$$;

select * from public.admin_transition_route_batch(
  'fixture-pilot-20260716', repeat('1', 64), 'disabled'
);

select * from public.admin_transition_route_batch(
  'fixture-pilot-20260716', repeat('1', 64), 'disabled'
);

do $$
begin
  if (select epoch from public.route_catalog_state where singleton_key) <> 2 then
    raise exception 'soft-disable did not increment epoch once';
  end if;
  if (select count(*) from public.route_batch_transition_receipts) <> 2 then
    raise exception 'same-state disabled transition was not an epoch-stable no-op';
  end if;
  if (
    select count(*)
    from unnest((select route_ids from public.route_catalog_state where singleton_key)) as route_id
    where route_id like 'fixture-pilot-%'
  ) <> 0 then
    raise exception 'disabled pilot leaked into catalog';
  end if;
  if (select count(*) from public.curvy_roads where generation_batch_id = 'fixture-pilot-20260716') <> 24 then
    raise exception 'soft-disable deleted pilot routes';
  end if;
  if (
    select status from public.route_generation_batches
    where batch_id = 'fixture-expansion-20260716'
  ) <> 'shadow' then
    raise exception 'pilot transition changed expansion state';
  end if;
  if (select count(*) from public.route_batch_transition_receipts) <> 2 then
    raise exception 'soft-disable receipt missing';
  end if;
  begin
    perform public.admin_transition_route_batch(
      'fixture-pilot-20260716', repeat('1', 64), 'active'
    );
    raise exception 'disabled to active unexpectedly succeeded';
  exception when sqlstate '23514' then
    null;
  end;
  begin
    update public.curvy_roads set name = 'Mutated'
    where id = 'fixture-pilot-01';
    raise exception 'disabled payload mutation unexpectedly succeeded';
  exception when sqlstate '23514' then
    null;
  end;
  begin
    delete from public.route_generation_batches
    where batch_id = 'fixture-pilot-20260716';
    raise exception 'batch delete unexpectedly succeeded';
  exception when sqlstate '23514' then
    null;
  end;
  begin
    delete from public.route_generation_sources
    where batch_id = 'fixture-pilot-20260716' and hub_id = 'calgary';
    raise exception 'source provenance delete unexpectedly succeeded';
  exception when sqlstate '23514' then
    null;
  end;
  begin
    delete from public.curvy_roads where id = 'fixture-pilot-01';
    raise exception 'generated route delete unexpectedly succeeded';
  exception when sqlstate '23514' then
    null;
  end;
  begin
    delete from public.route_batch_transition_receipts
    where batch_id = 'fixture-pilot-20260716' and to_state = 'active';
    raise exception 'transition receipt delete unexpectedly succeeded';
  exception when sqlstate '23514' then
    null;
  end;
  begin
    update public.route_catalog_state
    set route_ids = array(select 'overflow-' || n from generate_series(1, 651) as n)
    where singleton_key;
    raise exception 'catalog overflow unexpectedly succeeded';
  exception when sqlstate '23514' then
    null;
  end;
end;
$$;

select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000001"}',
  true
);
set local role authenticated;

do $$
begin
  if (select count(*) from public.curvy_roads where publication_kind = 'osm_generated') <> 0 then
    raise exception 'disabled routes leaked through direct RLS';
  end if;
  if (
    select count(*) from public.find_curvy_roads_v2(51.0, -114.0, 160000, 0, 120)
    where is_generated
  ) <> 0 then
    raise exception 'disabled routes leaked through v2 RPC';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

explain (costs off)
select road.id
from public.curvy_roads as road
left join public.route_generation_batches as batch
  on batch.batch_id = road.generation_batch_id
where road.distance_km >= 4.0
  and (
    (road.publication_kind = 'legacy' and road.generation_batch_id is null)
    or (road.publication_kind = 'osm_generated' and batch.status = 'active')
  )
order by road.province_code, road.geohash4, road.winding_score desc, road.id
limit 650;

explain (costs off)
select 1
from public.route_generation_sources
where batch_id = 'fixture-pilot-20260716'
  and hub_id = 'calgary'
  and province_code = 'AB'
  and source_pbf_sha256 = repeat('a', 64)
  and source_graph_sha256 = repeat('b', 64);

explain (costs off)
select *
from revv_private.find_visible_curvy_roads(
  51.0, -114.0, 160000, 0, 120, true
);

rollback;
