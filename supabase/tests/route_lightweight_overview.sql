\set ON_ERROR_STOP on
begin;
select set_config('request.jwt.claims','{"role":"service_role"}',true);

-- Dense, curved fixture; no production routes or users are read or changed.
insert into public.curvy_roads (
 id,name,center_lat,center_lng,center_point,nodes,distance_km,
 curvature_score,winding_score,star_rating,sharp_curve_count,region,province_code
)
select 'overview-perf-'||n, 'Overview fixture '||n,45.02,-73,
 st_setsrid(st_makepoint(-73,45.02),4326)::geography,
 (select jsonb_agg(jsonb_build_object('lat',45+i*0.00004,
   'lng',-73+0.005*sin(i/40.0)) order by i) from generate_series(0,1199) i),
 8,50,50,4,12,'quebec','QC'
from generate_series(1,120) n;

create temp table overview_measurement as
with full_rows as (
 select jsonb_agg(to_jsonb(f)) payload from public.get_route_nodes_v2(
   array(select 'overview-perf-'||n from generate_series(1,120) n)) f
), overview_rows as (
 select jsonb_agg(f) payload from public.get_route_overview_v2(
   array(select 'overview-perf-'||n from generate_series(1,120) n)) f
)
select octet_length(full_rows.payload::text) full_json_bytes,
 octet_length(overview_rows.payload::text) overview_json_bytes,
 jsonb_array_length(full_rows.payload) full_count,
 jsonb_array_length(overview_rows.payload) overview_count
from full_rows,overview_rows;

select *,round(100.0*(1-overview_json_bytes::numeric/full_json_bytes),2) as byte_reduction_percent
from overview_measurement;

do $$
declare full_nodes jsonb; overview jsonb; near_row jsonb;
begin
 select nodes into full_nodes from public.get_route_nodes_v2(array['overview-perf-1']);
 select row into overview from public.get_route_overview_v2(array['overview-perf-1']) row;
 if jsonb_array_length(full_nodes) <> 1200 then raise exception 'full geometry mutated'; end if;
 if jsonb_array_length(overview->'nodes') >= 300 then raise exception 'overview still too dense'; end if;
 if full_nodes->0 <> overview->'nodes'->0 or full_nodes->-1 <> overview->'nodes'->-1
 then raise exception 'endpoints changed'; end if;
 if overview->>'geometry_detail' <> 'overview' or (overview->>'distance_km')::numeric <> 8
 then raise exception 'overview metadata changed'; end if;
 if exists(select 1 from overview_measurement where overview_count <> full_count or overview_json_bytes >= full_json_bytes/2)
 then raise exception 'overview must preserve route count and cut dense fixture bytes by half'; end if;
 select row into near_row from public.find_curvy_roads_overview_v2(45.02,-73,160000,0,120) row
 where row->>'id'='overview-perf-1';
 if near_row is null or near_row->>'geometry_detail'<>'overview' or near_row->'nodes' <> overview->'nodes'
 then raise exception 'nearby endpoint did not return display geometry'; end if;
 if has_function_privilege('anon','public.get_route_overview_v2(text[])','execute')
 or has_function_privilege('anon','public.find_curvy_roads_overview_v2(double precision,double precision,integer,double precision,integer)','execute')
 or has_function_privilege('authenticated','revv_private.route_overview_nodes(jsonb)','execute')
 then raise exception 'overview permissions too broad'; end if;
 perform set_config('request.jwt.claims','{}',true);
 begin
   perform public.get_route_overview_v2(array['overview-perf-1']);
   raise exception 'missing authentication was accepted';
 exception when sqlstate '28000' then null;
 end;
 begin
   perform public.find_curvy_roads_overview_v2(45,-73);
   raise exception 'missing nearby authentication was accepted';
 exception when sqlstate '28000' then null;
 end;
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 begin
   perform public.get_route_overview_v2(array[]::text[]);
   raise exception 'empty route ids accepted';
 exception when sqlstate '22023' then null;
 end;
end $$;

explain (analyze, buffers, format text)
select * from public.get_route_overview_v2(array(select 'overview-perf-'||n from generate_series(1,120) n));
rollback;
