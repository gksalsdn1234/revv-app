-- Generate the runnable version with tools/build_catalog_ordinal_fixture.py.
-- Runs only on transaction-local fixture tables/functions. Production rows,
-- functions, schema and migration history are never modified.
begin;
set local statement_timeout='20s';
create temp table curvy_roads as select * from public.curvy_roads with no data;
create temp table route_generation_batches(batch_id text primary key,status text);
create temp table route_catalog_state(singleton_key boolean,epoch bigint);
insert into route_catalog_state values(true,42);
insert into route_generation_batches values('active-batch','active'),('hidden-batch','staging');
insert into curvy_roads(id,name,nodes,distance_km,publication_kind,province_code)
select 'fixture-'||n,'Fixture '||n,'[{"lat":45,"lng":-74},{"lat":45.01,"lng":-73.99}]'::jsonb,5,'legacy','QC'
from generate_series(1,650) n;
insert into curvy_roads(id,name,nodes,distance_km,publication_kind,generation_batch_id,province_code)
values
('active','Active','[{"lat":45,"lng":-74},{"lat":45.01,"lng":-73.99}]',5,'osm_generated','active-batch','QC'),
('hidden','Hidden','[{"lat":45,"lng":-74},{"lat":45.01,"lng":-73.99}]',5,'osm_generated','hidden-batch','QC'),
('orphan','Orphan','[{"lat":45,"lng":-74},{"lat":45.01,"lng":-73.99}]',5,'osm_generated','missing','QC'),
('bad-legacy','Bad legacy','[{"lat":45,"lng":-74},{"lat":45.01,"lng":-73.99}]',5,'legacy','active-batch','QC');
-- CANDIDATE_FUNCTIONS
select set_config('request.jwt.claims','{}',true);
do $tests$
declare ids text[]; got text[]; item jsonb; all_ids text[]; fname text;
begin
 foreach fname in array array['get_route_nodes_v2','get_route_overview_v2'] loop
  begin
   execute format('select * from pg_temp.%I($1)',fname) using array['fixture-1'];
   raise exception 'Missing auth was accepted: %',fname;
  exception when sqlstate '28000' then null; end;
 end loop;
 perform set_config('request.jwt.claims','{"role":"authenticated","sub":"00000000-0000-4000-8000-000000000001"}',true);
 ids:=array['fixture-2','hidden','active','fixture-1','fixture-2','orphan','absent','bad-legacy'];
 select array_agg(id) into got from pg_temp.get_route_nodes_v2(ids);
 if got<>array['fixture-2','active','fixture-1'] then raise exception 'Order/dedup/visibility failed: %',got; end if;
 select array_agg(x->>'id') into got from pg_temp.get_route_overview_v2(ids) x;
 if got<>array['fixture-2','active','fixture-1'] then raise exception 'Overview order/dedup/visibility failed: %',got; end if;
 if exists(select 1 from pg_temp.get_route_nodes_v2(ids) f join pg_temp.curvy_roads r on r.id=f.id where f.nodes<>r.nodes or f.catalog_epoch<>42 or f.province_code<>'QC' or f.is_generated<>(r.publication_kind='osm_generated')) then raise exception 'Full geometry/metadata changed'; end if;
 for item in select * from pg_temp.get_route_overview_v2(ids) loop
  if item->>'geometry_detail'<>'overview' or (item->>'distance_km')::numeric<>5 or (item->>'catalog_epoch')::int<>42 or item->'nodes'->0 <> '{"lat":45,"lng":-74}'::jsonb or item->'nodes'->-1 <> '{"lat":45.01,"lng":-73.99}'::jsonb then raise exception 'Overview metadata/endpoints changed'; end if;
 end loop;
 select array_agg('fixture-'||n order by n desc) into all_ids from generate_series(1,650) n;
 select array_agg(id) into got from pg_temp.get_route_nodes_v2(all_ids);
 if got<>all_ids then raise exception '650 reversed IDs did not preserve count/order'; end if;
 select array_agg(x->>'id') into got from pg_temp.get_route_overview_v2(all_ids) x;
 if got<>all_ids then raise exception '650 overview IDs did not preserve count/order'; end if;
 foreach fname in array array['get_route_nodes_v2','get_route_overview_v2'] loop
  for ids in select v from (values (null::text[]),(array[]::text[]),(array[null]::text[]),(array['']),(array['wild*']),(array[repeat('a',193)]),(array_fill('fixture-1'::text,array[651]))) q(v) loop
   begin
    execute format('select * from pg_temp.%I($1)',fname) using ids;
    raise exception 'Invalid input accepted by %',fname;
   exception when sqlstate '22023' then null; end;
  end loop;
 end loop;
end $tests$;
select 'PASS: auth, invalid inputs, 650 IDs, order, duplicates, inactive/orphan/legacy visibility, nodes, metadata, endpoints' as result;
rollback;
