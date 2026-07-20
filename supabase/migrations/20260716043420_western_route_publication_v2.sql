create schema if not exists revv_private;
revoke all on schema revv_private from public, anon, authenticated, service_role;

do $$
begin
  if exists (
    select 1
      from public.curvy_roads
     where lower(trim(coalesce(source, ''))) = 'osm_generated'
  ) then
    raise exception 'existing generated rows must be zero before publication migration'
      using errcode = '23514';
  end if;
end;
$$;

alter table public.curvy_roads
  add column province_code text;

update public.curvy_roads
   set province_code = case
     when trim(both '_' from regexp_replace(lower(trim(region)), '[^a-z0-9]+', '_', 'g')) = 'alberta' then 'AB'
     when trim(both '_' from regexp_replace(lower(trim(region)), '[^a-z0-9]+', '_', 'g')) = 'british_columbia' then 'BC'
     when trim(both '_' from regexp_replace(lower(trim(region)), '[^a-z0-9]+', '_', 'g')) = 'manitoba' then 'MB'
     when trim(both '_' from regexp_replace(lower(trim(region)), '[^a-z0-9]+', '_', 'g')) = 'new_brunswick' then 'NB'
     when trim(both '_' from regexp_replace(lower(trim(region)), '[^a-z0-9]+', '_', 'g')) = 'newfoundland_and_labrador' then 'NL'
     when trim(both '_' from regexp_replace(lower(trim(region)), '[^a-z0-9]+', '_', 'g')) = 'nova_scotia' then 'NS'
     when trim(both '_' from regexp_replace(lower(trim(region)), '[^a-z0-9]+', '_', 'g')) = 'northwest_territories' then 'NT'
     when trim(both '_' from regexp_replace(lower(trim(region)), '[^a-z0-9]+', '_', 'g')) = 'nunavut' then 'NU'
     when trim(both '_' from regexp_replace(lower(trim(region)), '[^a-z0-9]+', '_', 'g')) = 'ontario' then 'ON'
     when trim(both '_' from regexp_replace(lower(trim(region)), '[^a-z0-9]+', '_', 'g')) = 'prince_edward_island' then 'PE'
     when trim(both '_' from regexp_replace(lower(trim(region)), '[^a-z0-9]+', '_', 'g')) = 'quebec' then 'QC'
     when trim(both '_' from regexp_replace(lower(trim(region)), '[^a-z0-9]+', '_', 'g')) = 'saskatchewan' then 'SK'
     when trim(both '_' from regexp_replace(lower(trim(region)), '[^a-z0-9]+', '_', 'g')) = 'yukon' then 'YT'
     else null
   end;

do $$
declare
  unmapped_count bigint;
  unmapped_regions text;
begin
  select count(*), string_agg(distinct coalesce(region, '<null>'), ', ' order by coalesce(region, '<null>'))
    into unmapped_count, unmapped_regions
    from public.curvy_roads
   where province_code is null;

  if unmapped_count > 0 then
    raise exception 'legacy province mapping failed for % rows: %', unmapped_count, unmapped_regions
      using errcode = '23514';
  end if;
end;
$$;

alter table public.curvy_roads
  alter column province_code set not null;

alter table public.curvy_roads
  add constraint curvy_roads_province_code_allowed
  check (province_code in ('AB','BC','MB','NB','NL','NS','NT','NU','ON','PE','QC','SK','YT'));

create index idx_curvy_roads_province_code
  on public.curvy_roads(province_code);

create table public.route_generation_batches (
  batch_id text primary key,
  cohort_kind text not null
    check (cohort_kind in ('pilot', 'expansion')),
  status text not null default 'shadow'
    check (status in ('shadow', 'active', 'disabled')),
  generator_version text not null,
  manifest_sha256 text not null
    check (manifest_sha256 ~ '^[0-9a-f]{64}$'),
  route_ids_sha256 text not null
    check (route_ids_sha256 ~ '^[0-9a-f]{64}$'),
  expected_route_count integer not null,
  manifest jsonb not null
    check (jsonb_typeof(manifest) = 'object'),
  created_at timestamptz not null default now(),
  activated_at timestamptz,
  disabled_at timestamptz,
  constraint route_generation_batch_id_safe
    check (
      length(batch_id) between 8 and 96
      and batch_id ~ '^[a-z0-9][a-z0-9._:-]*$'
      and batch_id !~ '[%*?]'
    ),
  constraint route_generation_batch_size
    check (
      (cohort_kind = 'pilot' and expected_route_count between 24 and 50)
      or (cohort_kind = 'expansion' and expected_route_count between 96 and 200)
    ),
  constraint route_generation_batch_timestamps
    check (
      (status = 'shadow' and activated_at is null and disabled_at is null)
      or (status = 'active' and activated_at is not null and disabled_at is null)
      or (status = 'disabled' and activated_at is not null and disabled_at is not null)
    )
);

create table public.route_generation_sources (
  batch_id text not null,
  hub_id text not null,
  province_code text not null,
  source_pbf_sha256 text not null
    check (source_pbf_sha256 ~ '^[0-9a-f]{64}$'),
  source_graph_sha256 text not null
    check (source_graph_sha256 ~ '^[0-9a-f]{64}$'),
  source_snapshot text not null,
  created_at timestamptz not null default now(),
  primary key (batch_id, hub_id),
  unique (batch_id, province_code, source_graph_sha256),
  unique (batch_id, hub_id, province_code, source_pbf_sha256, source_graph_sha256),
  foreign key (batch_id)
    references public.route_generation_batches(batch_id)
    on delete restrict,
  check (province_code in ('AB','BC','MB','NB','NL','NS','NT','NU','ON','PE','QC','SK','YT')),
  check (
    length(hub_id) between 2 and 96
    and hub_id ~ '^[a-z0-9][a-z0-9._:-]*$'
    and hub_id !~ '[%*?]'
  ),
  check (length(source_snapshot) between 1 and 160)
);

create table public.route_catalog_state (
  singleton_key boolean primary key default true check (singleton_key),
  epoch bigint not null default 0 check (epoch >= 0),
  route_ids text[] not null default '{}'::text[],
  updated_at timestamptz not null default now(),
  constraint route_catalog_state_bound
    check (cardinality(route_ids) <= 650)
);

create table public.route_batch_transition_receipts (
  receipt_id bigint generated always as identity primary key,
  batch_id text not null,
  manifest_sha256 text not null,
  from_state text not null,
  to_state text not null,
  route_count integer not null,
  catalog_epoch bigint not null,
  transitioned_at timestamptz not null default now(),
  foreign key (batch_id)
    references public.route_generation_batches(batch_id)
    on delete restrict,
  unique (batch_id, to_state),
  check (from_state in ('shadow', 'active')),
  check (to_state in ('active', 'disabled')),
  check (route_count > 0),
  check (catalog_epoch > 0)
);

create index route_generation_batches_status_idx
  on public.route_generation_batches(status, cohort_kind, batch_id);
create index route_batch_transition_receipts_batch_idx
  on public.route_batch_transition_receipts(batch_id, transitioned_at desc);

alter table public.curvy_roads
  add column publication_kind text not null default 'legacy',
  add column generation_batch_id text,
  add column source_hub_id text,
  add column source_pbf_sha256 text,
  add column source_graph_sha256 text,
  add column generation_provenance jsonb not null default '{}'::jsonb,
  add column activated_at timestamptz;

alter table public.curvy_roads
  add constraint curvy_roads_publication_kind_allowed
    check (publication_kind in ('legacy', 'osm_generated')),
  add constraint curvy_roads_publication_shape
    check (
      (
        publication_kind = 'legacy'
        and generation_batch_id is null
        and source_hub_id is null
        and source_pbf_sha256 is null
        and source_graph_sha256 is null
        and generation_provenance = '{}'::jsonb
        and activated_at is null
      and lower(trim(source)) <> 'osm_generated'
      )
      or (
        publication_kind = 'osm_generated'
        and generation_batch_id is not null
        and source_hub_id is not null
        and source_pbf_sha256 ~ '^[0-9a-f]{64}$'
        and source_graph_sha256 ~ '^[0-9a-f]{64}$'
        and jsonb_typeof(generation_provenance) = 'object'
      and source = 'osm_generated'
      and id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{7,191}$'
      )
    ),
  add constraint curvy_roads_generation_source_fkey
    foreign key (
      generation_batch_id,
      source_hub_id,
      province_code,
      source_pbf_sha256,
      source_graph_sha256
    )
    references public.route_generation_sources (
      batch_id,
      hub_id,
      province_code,
      source_pbf_sha256,
      source_graph_sha256
    )
    on delete restrict;

create index idx_curvy_roads_generation_batch
  on public.curvy_roads(generation_batch_id)
  where generation_batch_id is not null;
create index idx_curvy_roads_publication_catalog
  on public.curvy_roads(
    publication_kind,
    province_code,
    geohash4,
    winding_score desc,
    id
  )
  where distance_km >= 0.3;

alter table public.route_generation_batches enable row level security;
alter table public.route_generation_sources enable row level security;
alter table public.route_catalog_state enable row level security;
alter table public.route_batch_transition_receipts enable row level security;

revoke all on table public.route_generation_batches from public, anon, authenticated, service_role;
revoke all on table public.route_generation_sources from public, anon, authenticated, service_role;
revoke all on table public.route_catalog_state from public, anon, authenticated, service_role;
revoke all on table public.route_batch_transition_receipts from public, anon, authenticated, service_role;

grant insert on table public.curvy_roads to service_role;
revoke insert, update, delete on table public.curvy_roads from public, anon, authenticated;

create function revv_private.require_service_role()
returns void
language plpgsql
stable
security invoker
set search_path = pg_catalog, pg_temp
as $$
begin
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role'
     and current_user <> 'service_role'
     and session_user <> 'service_role' then
    raise exception 'service_role required' using errcode = '42501';
  end if;
end;
$$;

revoke all on function revv_private.require_service_role() from public, anon, authenticated, service_role;

create function public.enforce_route_generation_batch_immutability()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'generation batches cannot be deleted' using errcode = '23514';
  end if;

  if old.status = 'disabled' then
    raise exception 'disabled batch is immutable' using errcode = '23514';
  end if;

  if new.batch_id is distinct from old.batch_id
     or new.cohort_kind is distinct from old.cohort_kind
     or new.generator_version is distinct from old.generator_version
     or new.manifest_sha256 is distinct from old.manifest_sha256
     or new.route_ids_sha256 is distinct from old.route_ids_sha256
     or new.expected_route_count is distinct from old.expected_route_count
     or new.manifest is distinct from old.manifest
     or new.created_at is distinct from old.created_at then
    raise exception 'generation batch manifest is immutable' using errcode = '23514';
  end if;

  if new.status = old.status then
    return new;
  end if;

  if not (
    (old.status = 'shadow' and new.status = 'active')
    or (old.status = 'active' and new.status = 'disabled')
  ) then
    raise exception 'batch state transitions are shadow->active->disabled only'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_route_generation_batch_immutability()
  from public, anon, authenticated, service_role;

create trigger route_generation_batch_immutable
before update or delete on public.route_generation_batches
for each row execute function public.enforce_route_generation_batch_immutability();

create function public.enforce_route_generation_source_immutability()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  batch_status text;
begin
  if tg_op <> 'INSERT' then
    raise exception 'generation sources are immutable' using errcode = '23514';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(
    pg_catalog.hashtextextended('revv-route-batch:' || new.batch_id, 0)
  );

  select status
    into batch_status
    from public.route_generation_batches
   where batch_id = new.batch_id;

  if batch_status is distinct from 'shadow' then
    raise exception 'generation sources require a shadow batch' using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function public.enforce_route_generation_source_immutability()
  from public, anon, authenticated, service_role;

create trigger route_generation_source_immutable
before insert or update or delete on public.route_generation_sources
for each row execute function public.enforce_route_generation_source_immutability();

create function public.enforce_route_transition_receipt_immutability()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  raise exception 'route transition receipts are immutable' using errcode = '23514';
end;
$$;

revoke all on function public.enforce_route_transition_receipt_immutability()
  from public, anon, authenticated, service_role;

create trigger route_transition_receipt_immutable
before update or delete on public.route_batch_transition_receipts
for each row execute function public.enforce_route_transition_receipt_immutability();

create function public.enforce_curvy_road_publication_integrity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  batch_status text;
  locked_batch_id text;
begin
  locked_batch_id := case
    when tg_op = 'DELETE' then old.generation_batch_id
    else new.generation_batch_id
  end;
  if locked_batch_id is not null then
    perform pg_catalog.pg_advisory_xact_lock_shared(
      pg_catalog.hashtextextended('revv-route-batch:' || locked_batch_id, 0)
    );
  end if;
  if tg_op = 'DELETE' and old.publication_kind = 'osm_generated' then
    raise exception 'generated routes cannot be deleted' using errcode = '23514';
  elsif tg_op = 'DELETE' then
    return old;
  end if;

  if tg_op = 'UPDATE'
     and new.publication_kind is distinct from old.publication_kind then
    raise exception 'route publication kind is immutable' using errcode = '23514';
  end if;

  if new.publication_kind = 'legacy' then
    return new;
  end if;

  if jsonb_typeof(new.generation_provenance -> 'province_codes') is distinct from 'array'
     or jsonb_array_length(new.generation_provenance -> 'province_codes') <> 1
     or new.generation_provenance #>> '{province_codes,0}' is distinct from new.province_code
     or new.generation_provenance ->> 'source_hub_id' is distinct from new.source_hub_id
     or jsonb_typeof(new.generation_provenance -> 'directed_edge_ids') is distinct from 'array'
     or jsonb_array_length(new.generation_provenance -> 'directed_edge_ids') < 1
     or jsonb_array_length(new.generation_provenance -> 'directed_edge_ids') > 1200
     or exists (
       select 1
       from jsonb_array_elements(new.generation_provenance -> 'directed_edge_ids') as edge_id
       where jsonb_typeof(edge_id) <> 'string'
          or length(edge_id #>> '{}') not between 1 and 160
     )
     or jsonb_typeof(new.generation_provenance -> 'source_seed_ids') is distinct from 'array'
     or jsonb_array_length(new.generation_provenance -> 'source_seed_ids') < 1
     or jsonb_array_length(new.generation_provenance -> 'source_seed_ids') > 128
     or exists (
       select 1
       from jsonb_array_elements(new.generation_provenance -> 'source_seed_ids') as seed_id
       where jsonb_typeof(seed_id) <> 'string'
          or length(seed_id #>> '{}') not between 1 and 160
     )
     or coalesce(new.generation_provenance ->> 'guidance_receipt_sha256', '') !~ '^[0-9a-f]{64}$' then
    raise exception 'generated route provenance is incomplete or multi-province'
      using errcode = '23514';
  end if;

  select batch.status
    into batch_status
    from public.route_generation_batches as batch
    join public.route_generation_sources as source_manifest
      on source_manifest.batch_id = batch.batch_id
     and source_manifest.hub_id = new.source_hub_id
     and source_manifest.province_code = new.province_code
     and source_manifest.source_pbf_sha256 = new.source_pbf_sha256
     and source_manifest.source_graph_sha256 = new.source_graph_sha256
   where batch.batch_id = new.generation_batch_id;

  if batch_status is null then
    raise exception 'generated route source graph/code mismatch' using errcode = '23514';
  end if;

  if tg_op = 'INSERT' and batch_status <> 'shadow' then
    raise exception 'generated route insert requires a shadow batch' using errcode = '23514';
  end if;

  if tg_op = 'UPDATE' then
    if new.generation_batch_id is distinct from old.generation_batch_id
       or new.source_hub_id is distinct from old.source_hub_id
       or new.province_code is distinct from old.province_code
       or new.source_pbf_sha256 is distinct from old.source_pbf_sha256
       or new.source_graph_sha256 is distinct from old.source_graph_sha256
       or new.generation_provenance is distinct from old.generation_provenance then
      raise exception 'generated route provenance is immutable' using errcode = '23514';
    end if;

    if batch_status = 'disabled' then
      raise exception 'disabled generated route payload is immutable' using errcode = '23514';
    end if;

    if batch_status = 'active'
       and (
         (to_jsonb(new) - 'run_count') is distinct from (to_jsonb(old) - 'run_count')
         or new.run_count <> old.run_count + 1
       ) then
      raise exception 'active generated route payload is immutable' using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_curvy_road_publication_integrity()
  from public, anon, authenticated, service_role;

create trigger curvy_road_publication_integrity
before insert or update or delete on public.curvy_roads
for each row execute function public.enforce_curvy_road_publication_integrity();

create function revv_private.rebuild_route_catalog(increment_epoch boolean)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
set statement_timeout = '60s'
as $$
declare
  next_route_ids text[];
  next_epoch bigint;
  selection_order integer := 0;
  preferred_kind text;
  hub_selected integer;
  hub_record record;
  region_record record;
  route_record record;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('revv-route-catalog', 0));

  insert into public.route_catalog_state(singleton_key, epoch, route_ids)
  values (true, 0, '{}'::text[])
  on conflict (singleton_key) do nothing;

  perform 1
    from public.route_catalog_state
   where singleton_key
   for update;

  if exists (
    select 1
      from public.curvy_roads as road
      left join public.route_generation_batches as batch
        on batch.batch_id = road.generation_batch_id
     where (
       (road.publication_kind = 'legacy' and road.generation_batch_id is null)
       or (road.publication_kind = 'osm_generated' and batch.status = 'active')
     )
       and (
         road.province_code is null
         or road.province_code not in ('AB','BC','MB','NB','NL','NS','NT','NU','ON','PE','QC','SK','YT')
       )
  ) then
    raise exception 'catalog contains unclassified eligible routes' using errcode = '23514';
  end if;

  drop table if exists pg_temp.revv_catalog_selected;
  drop table if exists pg_temp.revv_catalog_regions;
  drop table if exists pg_temp.revv_catalog_candidates;

  create temporary table revv_catalog_candidates (
    id text primary key,
    province_code text not null,
    geohash4 text not null,
    source_hub_id text,
    route_kind text not null check (route_kind in ('recommendation', 'map')),
    winding_score double precision not null,
    distance_km double precision not null
  ) on commit drop;

  insert into pg_temp.revv_catalog_candidates (
    id, province_code, geohash4, source_hub_id,
    route_kind, winding_score, distance_km
  )
  with eligible as (
    select
      road.id,
      road.province_code,
      coalesce(
        nullif(road.geohash4, ''),
        public.st_geohash(road.center_point::public.geometry, 4)
      ) as geohash4,
      case
        when road.publication_kind = 'osm_generated'
          and road.province_code in ('AB', 'BC', 'MB', 'SK')
        then road.source_hub_id
        else null
      end as source_hub_id,
      case when road.distance_km >= 4.0 then 'recommendation' else 'map' end
        as route_kind,
      coalesce(road.winding_score, 0) as winding_score,
      road.distance_km
    from public.curvy_roads as road
    left join public.route_generation_batches as batch
      on batch.batch_id = road.generation_batch_id
    where (
      (road.publication_kind = 'legacy' and road.generation_batch_id is null)
      or (road.publication_kind = 'osm_generated' and batch.status = 'active')
    )
      and road.distance_km >= 0.3
      and jsonb_typeof(road.nodes) = 'array'
      and jsonb_array_length(road.nodes) between 2 and 1200
      and pg_column_size(road.nodes) <= 1048576
      and not coalesce(road.is_facility_like, false)
      and not coalesce(road.is_connector_like, false)
      and not coalesce(road.is_private_like, false)
      and road.quality_reject_reason is null
  ), cell_kind_ranked as (
    select
      eligible.*,
      row_number() over (
        partition by province_code, geohash4, route_kind, source_hub_id
        order by winding_score desc, distance_km desc, id collate "C"
      ) as cell_kind_rank
    from eligible
  )
  select
    id, province_code, geohash4, source_hub_id,
    route_kind, winding_score, distance_km
  from cell_kind_ranked
  where cell_kind_rank <= 3;

  create index revv_catalog_candidates_region_kind_rank_idx
    on pg_temp.revv_catalog_candidates(
      province_code, route_kind, winding_score desc, distance_km desc, geohash4, id
    );
  create index revv_catalog_candidates_hub_rank_idx
    on pg_temp.revv_catalog_candidates(
      province_code, source_hub_id, route_kind,
      winding_score desc, distance_km desc, geohash4, id
    ) where source_hub_id is not null;

  create temporary table revv_catalog_regions (
    province_code text primary key,
    capacity integer not null check (capacity between 1 and 80),
    selected_count integer not null default 0 check (selected_count between 0 and 80),
    exhausted boolean not null default false
  ) on commit drop;

  insert into pg_temp.revv_catalog_regions(province_code, capacity)
  select province_code, least(sum(least(cell_count, 3)), 80)::integer
  from (
    select province_code, geohash4, count(*)::integer as cell_count
    from pg_temp.revv_catalog_candidates
    group by province_code, geohash4
  ) as cells
  group by province_code;

  create temporary table revv_catalog_selected (
    id text primary key,
    selection_order integer not null unique,
    province_code text not null,
    geohash4 text not null,
    source_hub_id text,
    route_kind text not null
  ) on commit drop;
  create index revv_catalog_selected_region_idx
    on pg_temp.revv_catalog_selected(province_code);
  create index revv_catalog_selected_cell_idx
    on pg_temp.revv_catalog_selected(geohash4);
  create index revv_catalog_selected_hub_cell_idx
    on pg_temp.revv_catalog_selected(province_code, source_hub_id, geohash4)
    where source_hub_id is not null;

  -- Phase 1: reserve up to three distinct cells for every active western manifest hub.
  for hub_record in
    select distinct
      province_code collate "C" as province_code,
      source_hub_id collate "C" as source_hub_id
    from pg_temp.revv_catalog_candidates
    where source_hub_id is not null
    order by province_code, source_hub_id
  loop
    hub_selected := 0;
    while hub_selected < 3 and selection_order < 650 loop
      preferred_kind := case
        when mod(hub_selected, 5) < 3 then 'recommendation'
        else 'map'
      end;
      select candidate.*
      into route_record
      from pg_temp.revv_catalog_candidates as candidate
      where candidate.province_code = hub_record.province_code
        and candidate.source_hub_id = hub_record.source_hub_id
        and not exists (
          select 1 from pg_temp.revv_catalog_selected as selected
          where selected.id = candidate.id
        )
        and not exists (
          select 1 from pg_temp.revv_catalog_selected as selected
          where selected.province_code = candidate.province_code
            and selected.source_hub_id = candidate.source_hub_id
            and selected.geohash4 = candidate.geohash4
        )
        and (
          select count(*) from pg_temp.revv_catalog_selected as selected
          where selected.geohash4 = candidate.geohash4
        ) < 3
        and (
          select selected_count from pg_temp.revv_catalog_regions as region
          where region.province_code = candidate.province_code
        ) < 80
      order by
        (candidate.route_kind <> preferred_kind),
        candidate.winding_score desc,
        candidate.distance_km desc,
        candidate.geohash4 collate "C",
        candidate.id collate "C"
      limit 1;

      exit when not found;
      selection_order := selection_order + 1;
      insert into pg_temp.revv_catalog_selected (
        id, selection_order, province_code, geohash4, source_hub_id, route_kind
      ) values (
        route_record.id, selection_order, route_record.province_code,
        route_record.geohash4, route_record.source_hub_id, route_record.route_kind
      );
      update pg_temp.revv_catalog_regions
      set selected_count = selected_count + 1
      where province_code = route_record.province_code;
      hub_selected := hub_selected + 1;
    end loop;
  end loop;

  -- Phase 2: guarantee up to twenty routes per province/territory where available.
  for region_record in
    select province_code, capacity, selected_count
    from pg_temp.revv_catalog_regions
    order by province_code collate "C"
  loop
    while region_record.selected_count < least(region_record.capacity, 20)
      and selection_order < 650
    loop
      preferred_kind := case
        when mod(region_record.selected_count, 5) < 3 then 'recommendation'
        else 'map'
      end;
      select candidate.*
      into route_record
      from pg_temp.revv_catalog_candidates as candidate
      where candidate.province_code = region_record.province_code
        and not exists (
          select 1 from pg_temp.revv_catalog_selected as selected
          where selected.id = candidate.id
        )
        and (
          select count(*) from pg_temp.revv_catalog_selected as selected
          where selected.geohash4 = candidate.geohash4
        ) < 3
      order by
        (candidate.route_kind <> preferred_kind),
        candidate.winding_score desc,
        candidate.distance_km desc,
        candidate.geohash4 collate "C",
        candidate.id collate "C"
      limit 1;

      if not found then
        update pg_temp.revv_catalog_regions
        set exhausted = true
        where province_code = region_record.province_code;
        exit;
      end if;

      selection_order := selection_order + 1;
      insert into pg_temp.revv_catalog_selected (
        id, selection_order, province_code, geohash4, source_hub_id, route_kind
      ) values (
        route_record.id, selection_order, route_record.province_code,
        route_record.geohash4, route_record.source_hub_id, route_record.route_kind
      );
      update pg_temp.revv_catalog_regions
      set selected_count = selected_count + 1
      where province_code = route_record.province_code;
      region_record.selected_count := region_record.selected_count + 1;
    end loop;
  end loop;

  -- Phase 3: redistribute remaining slots to the lowest normalized coverage.
  while selection_order < 650 loop
    select region.*
    into region_record
    from pg_temp.revv_catalog_regions as region
    where region.selected_count < region.capacity
      and not region.exhausted
    order by
      (region.capacity - region.selected_count)::numeric / region.capacity desc,
      region.province_code collate "C"
    limit 1;
    exit when not found;

    preferred_kind := case
      when mod(region_record.selected_count, 5) < 3 then 'recommendation'
      else 'map'
    end;
    select candidate.*
    into route_record
    from pg_temp.revv_catalog_candidates as candidate
    where candidate.province_code = region_record.province_code
      and not exists (
        select 1 from pg_temp.revv_catalog_selected as selected
        where selected.id = candidate.id
      )
      and (
        select count(*) from pg_temp.revv_catalog_selected as selected
        where selected.geohash4 = candidate.geohash4
      ) < 3
    order by
      (candidate.route_kind <> preferred_kind),
      candidate.winding_score desc,
      candidate.distance_km desc,
      candidate.geohash4 collate "C",
      candidate.id collate "C"
    limit 1;

    if not found then
      update pg_temp.revv_catalog_regions
      set exhausted = true
      where province_code = region_record.province_code;
      continue;
    end if;

    selection_order := selection_order + 1;
    insert into pg_temp.revv_catalog_selected (
      id, selection_order, province_code, geohash4, source_hub_id, route_kind
    ) values (
      route_record.id, selection_order, route_record.province_code,
      route_record.geohash4, route_record.source_hub_id, route_record.route_kind
    );
    update pg_temp.revv_catalog_regions
    set selected_count = selected_count + 1
    where province_code = route_record.province_code;
  end loop;

  select coalesce(
    array_agg(selected.id order by selected.selection_order),
    '{}'::text[]
  )
  into next_route_ids
  from pg_temp.revv_catalog_selected as selected;

  if cardinality(next_route_ids) > 650 then
    raise exception 'catalog exceeds 650 route ids' using errcode = '54000';
  end if;

  update public.route_catalog_state
     set route_ids = next_route_ids,
         epoch = epoch + case when increment_epoch then 1 else 0 end,
         updated_at = now()
   where singleton_key
   returning epoch into next_epoch;

  return next_epoch;
end;
$$;

revoke all on function revv_private.rebuild_route_catalog(boolean)
  from public, anon, authenticated, service_role;

create function public.admin_register_route_generation_batch(
  batch_id_input text,
  cohort_kind_input text,
  generator_version_input text,
  manifest_sha256_input text,
  route_ids_sha256_input text,
  expected_route_count_input integer,
  manifest_input jsonb,
  sources_input jsonb
)
returns void language plpgsql security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  source_row jsonb;
begin
  perform revv_private.require_service_role();
  if jsonb_typeof(sources_input) is distinct from 'array'
     or jsonb_array_length(sources_input) < 1
     or jsonb_array_length(sources_input) > 64 then
    raise exception 'batch sources must be a bounded non-empty array' using errcode = '22023';
  end if;
  insert into public.route_generation_batches (
    batch_id, cohort_kind, generator_version, manifest_sha256,
    route_ids_sha256, expected_route_count, manifest
  ) values (
    batch_id_input, cohort_kind_input, generator_version_input, manifest_sha256_input,
    route_ids_sha256_input, expected_route_count_input, manifest_input
  );
  for source_row in select value from jsonb_array_elements(sources_input)
  loop
    insert into public.route_generation_sources (
      batch_id, hub_id, province_code, source_pbf_sha256, source_graph_sha256, source_snapshot
    ) values (
      batch_id_input,
      source_row ->> 'hub_id',
      source_row ->> 'province_code',
      source_row ->> 'source_pbf_sha256',
      source_row ->> 'source_graph_sha256',
      source_row ->> 'source_snapshot'
    );
  end loop;
end;
$$;
revoke all on function public.admin_register_route_generation_batch(
  text, text, text, text, text, integer, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.admin_register_route_generation_batch(
  text, text, text, text, text, integer, jsonb, jsonb
) to service_role;

create function public.admin_transition_route_batch(
  batch_id_input text,
  manifest_sha256_input text,
  target_state_input text
)
returns table (
  batch_id text,
  previous_state text,
  current_state text,
  changed boolean,
  catalog_epoch bigint
)
language plpgsql security definer
set search_path = pg_catalog, pg_temp
set statement_timeout = '60s'
as $$
declare
  batch_record public.route_generation_batches%rowtype;
  actual_route_count integer;
  actual_route_ids_sha256 text;
  next_epoch bigint;
  transition_time timestamptz := now();
begin
  perform revv_private.require_service_role();
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('revv-route-batch:' || coalesce(batch_id_input, ''), 0)
  );
  if batch_id_input is null or batch_id_input = '' or batch_id_input ~ '[%*?]' then
    raise exception 'exact batch id required' using errcode = '22023';
  end if;
  if target_state_input not in ('active', 'disabled') then
    raise exception 'target state must be active or disabled' using errcode = '22023';
  end if;
  select * into batch_record
  from public.route_generation_batches as batch
  where batch.batch_id = batch_id_input
  for update;
  if not found then
    raise exception 'unknown generation batch' using errcode = 'P0002';
  end if;
  if batch_record.manifest_sha256 is distinct from manifest_sha256_input then
    raise exception 'batch manifest checksum mismatch' using errcode = '23514';
  end if;
  if batch_record.status = target_state_input then
    select epoch into next_epoch from public.route_catalog_state where singleton_key;
    return query
      select batch_record.batch_id, batch_record.status, batch_record.status, false, next_epoch;
    return;
  end if;
  if not (
    (batch_record.status = 'shadow' and target_state_input = 'active')
    or (batch_record.status = 'active' and target_state_input = 'disabled')
  ) then
    raise exception 'batch state transitions are shadow->active->disabled only'
      using errcode = '23514';
  end if;
  select
    count(*)::integer,
    encode(extensions.digest(
      coalesce(string_agg(length(road.id)::text || ':' || road.id, E'\n' order by road.id), ''),
      'sha256'
    ), 'hex')
  into actual_route_count, actual_route_ids_sha256
  from public.curvy_roads as road
  where road.publication_kind = 'osm_generated'
    and road.generation_batch_id = batch_record.batch_id;
  if actual_route_count <> batch_record.expected_route_count
     or actual_route_ids_sha256 is distinct from batch_record.route_ids_sha256 then
    raise exception 'route id cohort mismatch' using errcode = '23514';
  end if;
  if target_state_input = 'active' then
    update public.curvy_roads
    set activated_at = transition_time
    where publication_kind = 'osm_generated'
      and generation_batch_id = batch_record.batch_id;
    update public.route_generation_batches
    set status = 'active', activated_at = transition_time
    where route_generation_batches.batch_id = batch_record.batch_id;
  else
    update public.route_generation_batches
    set status = 'disabled', disabled_at = transition_time
    where route_generation_batches.batch_id = batch_record.batch_id;
  end if;
  next_epoch := revv_private.rebuild_route_catalog(true);
  insert into public.route_batch_transition_receipts (
    batch_id, manifest_sha256, from_state, to_state,
    route_count, catalog_epoch, transitioned_at
  ) values (
    batch_record.batch_id, batch_record.manifest_sha256, batch_record.status,
    target_state_input, actual_route_count, next_epoch, transition_time
  );
  return query
    select batch_record.batch_id, batch_record.status, target_state_input, true, next_epoch;
end;
$$;
revoke all on function public.admin_transition_route_batch(text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.admin_transition_route_batch(text, text, text)
  to service_role;

create function public.admin_audit_route_generation_batch(batch_id_input text)
returns table (
  batch_id text,
  cohort_kind text,
  status text,
  manifest_sha256 text,
  expected_route_count integer,
  actual_route_count integer,
  actual_route_ids_sha256 text,
  route_ids_match boolean,
  catalog_route_count integer,
  catalog_epoch bigint
)
language plpgsql stable security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  perform revv_private.require_service_role();
  if batch_id_input is null or batch_id_input = '' or batch_id_input ~ '[%*?]' then
    raise exception 'exact batch id required' using errcode = '22023';
  end if;
  return query
  with actual as (
    select
      count(*)::integer as route_count,
      encode(extensions.digest(
        coalesce(string_agg(length(road.id)::text || ':' || road.id, E'\n' order by road.id), ''),
        'sha256'
      ), 'hex') as ids_sha256
    from public.curvy_roads as road
    where road.publication_kind = 'osm_generated'
      and road.generation_batch_id = batch_id_input
  )
  select
    batch.batch_id,
    batch.cohort_kind,
    batch.status,
    batch.manifest_sha256,
    batch.expected_route_count,
    actual.route_count,
    actual.ids_sha256,
    actual.route_count = batch.expected_route_count
      and actual.ids_sha256 = batch.route_ids_sha256,
    (
      select count(*)::integer
      from unnest(catalog.route_ids) as catalog_route_id
      where catalog_route_id in (
        select road.id from public.curvy_roads as road
        where road.generation_batch_id = batch.batch_id
      )
    ),
    catalog.epoch
  from public.route_generation_batches as batch
  cross join actual
  cross join public.route_catalog_state as catalog
  where batch.batch_id = batch_id_input
    and catalog.singleton_key;
end;
$$;
revoke all on function public.admin_audit_route_generation_batch(text)
  from public, anon, authenticated, service_role;
grant execute on function public.admin_audit_route_generation_batch(text)
  to service_role;

drop policy if exists curvy_public_read on public.curvy_roads;
create policy curvy_public_read on public.curvy_roads
for select to anon, authenticated
using (publication_kind = 'legacy' and generation_batch_id is null);

revoke all on function public.find_curvy_roads_unbounded_internal(
  double precision, double precision, integer, double precision, integer
) from public, anon, authenticated, service_role;

create function revv_private.find_visible_curvy_roads(
  user_lat double precision,
  user_lng double precision,
  radius_m integer,
  min_score double precision,
  max_results integer,
  include_generated boolean
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
  distance_from_user_km double precision, route_rank_score double precision,
  province_code text, is_generated boolean, activated_at timestamptz,
  catalog_epoch bigint
)
language sql stable security definer
set search_path = pg_catalog, extensions, public, pg_temp
set statement_timeout = '8s'
as $$
  with base_routes as (
    select
      road.*,
      st_distance(
        road.center_point,
        st_setsrid(st_makepoint(user_lng, user_lat), 4326)::geography
      ) / 1000.0 as distance_from_user_km,
      coalesce(
        nullif(road.fun_score, 0),
        road.winding_score
        * (1.0 + least((road.tight_curve_km + road.medium_curve_km) / greatest(road.distance_km, 1.0), 0.45))
        * (1.0 + least(road.max_continuous_km / 12.0, 0.18))
        * case when road.is_loop then 1.05 else 1.0 end
        * case when road.elevation_delta >= 40 then least(1.0 + road.elevation_delta / 250.0, 1.14) else 1.0 end
      ) as computed_fun_score,
      coalesce(
        nullif(road.flow_score, 0),
        greatest(
          0.15,
          least(
            1.0,
            1.0 - (
              (coalesce(road.stop_sign_count, 0) + coalesce(road.traffic_signal_count, 0) * 1.5)
              / greatest(road.distance_km, 1.0)
            ) * 0.35
            + case when road.max_continuous_km >= 1.5 then 0.08 else 0.0 end
          )
        )
      ) as computed_flow_score,
      coalesce(
        nullif(road.driveability_penalty, 0),
        greatest(
          0.05,
          least(
            1.0,
            case when coalesce(road.is_named, true) then 1.0 else 0.78 end
            * case when coalesce(road.is_facility_like, false) then 0.08 else 1.0 end
            * case when coalesce(road.is_connector_like, false) then 0.18 else 1.0 end
            * case when coalesce(road.is_bridge_like, false) then 0.28 else 1.0 end
            * case when coalesce(road.is_major_road_like, false) then 0.55 else 1.0 end
            * case when coalesce(road.is_private_like, false) then 0.18 else 1.0 end
            * case when road.name ~ '^[\d\-\s_]+$' then 0.48 else 1.0 end
          )
        )
      ) as computed_driveability_penalty
    from public.curvy_roads as road
    left join public.route_generation_batches as batch
      on batch.batch_id = road.generation_batch_id
    where (
      (road.publication_kind = 'legacy' and road.generation_batch_id is null)
      or (
        include_generated
        and road.publication_kind = 'osm_generated'
        and batch.status = 'active'
      )
    )
      and st_dwithin(
        road.center_point,
        st_setsrid(st_makepoint(user_lng, user_lat), 4326)::geography,
        radius_m
      )
      and road.winding_score >= min_score
      and road.distance_km >= 4.0
  ), scored_routes as (
    select
      base_routes.*,
      greatest(
        0.05,
        least(
          1.0,
          case when distance_km < 8.0 then 0.82 else 1.0 end
          * case
              when distance_from_user_km <= 15.0 then 1.0
              when distance_from_user_km >= 80.0 then 0.45
              else 1.0 - ((distance_from_user_km - 15.0) / 65.0) * 0.55
            end
          * case
              when stop_sign_count >= 5 and distance_km < 12.0 then 0.15
              when stop_control_density >= 0.65 and max_continuous_km < 1.2 then 0.20
              else 1.0
            end
          * coalesce(nullif(residential_penalty, 0), 1.0)
        )
      ) as context_adjustment
    from base_routes
    where not coalesce(is_facility_like, false)
      and not coalesce(is_connector_like, false)
      and not (stop_sign_count >= 5 and distance_km < 12.0)
      and not (stop_control_density >= 0.65 and max_continuous_km < 1.2)
      and not (name ~ '^[\d\-\s_]+$' and distance_km < 8.0)
  )
  select
    scored.id, scored.name, scored.center_lat, scored.center_lng,
    scored.nodes, scored.distance_km, scored.curvature_score,
    scored.winding_score, scored.star_rating, scored.sharp_curve_count,
    scored.tight_curve_km, scored.medium_curve_km, scored.max_continuous_km,
    scored.is_loop, scored.elevation_delta, scored.geohash4,
    scored.region, scored.source, scored.run_count, scored.published_by,
    scored.created_at, scored.stop_sign_count, scored.traffic_signal_count,
    scored.stop_control_density, scored.computed_flow_score,
    scored.computed_fun_score, scored.computed_driveability_penalty,
    scored.road_class_bucket, scored.is_named, scored.is_facility_like,
    scored.is_bridge_like, scored.is_connector_like, scored.is_major_road_like,
    scored.is_private_like, scored.residential_ratio, scored.service_ratio,
    scored.local_road_ratio, scored.intersection_density, scored.building_density,
    scored.housing_proximity_score, scored.urban_friction_score,
    scored.residential_penalty, scored.residential_version,
    scored.residential_enriched_at, scored.quality_label,
    scored.quality_reject_reason, scored.route_character, scored.primary_reason,
    scored.caution_note, scored.quality_version, scored.quality_enriched_at,
    scored.elevation_profile, scored.road_names, scored.surface_summary,
    scored.speed_limit_summary, scored.nearby_pois, scored.route_context,
    scored.context_version, scored.context_enriched_at,
    scored.distance_from_user_km,
    scored.computed_fun_score * scored.computed_flow_score
      * scored.computed_driveability_penalty * scored.context_adjustment,
    scored.province_code,
    scored.publication_kind = 'osm_generated',
    scored.activated_at,
    catalog.epoch
  from scored_routes as scored
  cross join public.route_catalog_state as catalog
  where catalog.singleton_key
  order by
    scored.computed_fun_score * scored.computed_flow_score
      * scored.computed_driveability_penalty * scored.context_adjustment desc,
    scored.distance_from_user_km
  limit max_results;
$$;
revoke all on function revv_private.find_visible_curvy_roads(
  double precision, double precision, integer, double precision, integer, boolean
) from public, anon, authenticated, service_role;

create or replace function public.find_curvy_roads(
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
language plpgsql stable security definer
set search_path = pg_catalog, pg_temp
set statement_timeout = '8s'
as $$
declare
  bounded_radius integer := least(greatest(coalesce(radius_m, 50000), 1000), 160000);
  bounded_results integer := least(greatest(coalesce(max_results, 30), 1), 120);
begin
  if (select auth.uid()) is null
     and coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if user_lat is null or user_lng is null
     or user_lat not between -90 and 90 or user_lng not between -180 and 180 then
    raise exception 'invalid coordinates' using errcode = '22023';
  end if;
  return query
  select
    visible.id, visible.name, visible.center_lat, visible.center_lng,
    visible.nodes, visible.distance_km, visible.curvature_score,
    visible.winding_score, visible.star_rating, visible.sharp_curve_count,
    visible.tight_curve_km, visible.medium_curve_km, visible.max_continuous_km,
    visible.is_loop, visible.elevation_delta, visible.geohash4,
    visible.region, visible.source, visible.run_count, visible.published_by,
    visible.created_at, visible.stop_sign_count, visible.traffic_signal_count,
    visible.stop_control_density, visible.flow_score, visible.fun_score,
    visible.driveability_penalty, visible.road_class_bucket, visible.is_named,
    visible.is_facility_like, visible.is_bridge_like, visible.is_connector_like,
    visible.is_major_road_like, visible.is_private_like,
    visible.residential_ratio, visible.service_ratio, visible.local_road_ratio,
    visible.intersection_density, visible.building_density,
    visible.housing_proximity_score, visible.urban_friction_score,
    visible.residential_penalty, visible.residential_version,
    visible.residential_enriched_at, visible.quality_label,
    visible.quality_reject_reason, visible.route_character,
    visible.primary_reason, visible.caution_note, visible.quality_version,
    visible.quality_enriched_at, visible.elevation_profile, visible.road_names,
    visible.surface_summary, visible.speed_limit_summary, visible.nearby_pois,
    visible.route_context, visible.context_version, visible.context_enriched_at,
    visible.distance_from_user_km, visible.route_rank_score
  from revv_private.find_visible_curvy_roads(
    user_lat, user_lng, bounded_radius,
    greatest(coalesce(min_score, 0), 0), bounded_results, false
  ) as visible;
end;
$$;
revoke all on function public.find_curvy_roads(
  double precision, double precision, integer, double precision, integer
) from public, anon;
grant execute on function public.find_curvy_roads(
  double precision, double precision, integer, double precision, integer
) to authenticated, service_role;

alter function public.find_curvy_map_segments(
  double precision, double precision, integer, double precision, integer
) rename to find_curvy_map_segments_pre_publication_internal;
revoke all on function public.find_curvy_map_segments_pre_publication_internal(
  double precision, double precision, integer, double precision, integer
) from public, anon, authenticated, service_role;

create function public.find_curvy_map_segments(
  user_lat double precision,
  user_lng double precision,
  radius_m integer default 50000,
  min_distance_km double precision default 0.3,
  max_results integer default 30
)
returns table (
  id text, name text, center_lat double precision, center_lng double precision,
  nodes jsonb, distance_km double precision, winding_score double precision,
  star_rating smallint, sharp_curve_count integer,
  tight_curve_km double precision, medium_curve_km double precision,
  max_continuous_km double precision, is_loop boolean,
  elevation_delta double precision, region text, source text,
  run_count integer, published_by uuid, stop_sign_count integer,
  traffic_signal_count integer, stop_control_density double precision,
  flow_score double precision, fun_score double precision,
  driveability_penalty double precision, road_class_bucket text,
  is_named boolean, is_facility_like boolean, is_bridge_like boolean,
  is_connector_like boolean, is_major_road_like boolean,
  is_private_like boolean, quality_label text, quality_reject_reason text,
  route_character text, primary_reason text, caution_note text,
  road_names jsonb, surface_summary text, speed_limit_summary text,
  nearby_pois jsonb, elevation_profile jsonb,
  distance_from_user_km double precision, route_rank_score double precision
)
language plpgsql stable security definer
set search_path = pg_catalog, extensions, public, pg_temp
set statement_timeout = '8s'
as $$
declare
  bounded_radius integer := least(greatest(coalesce(radius_m, 50000), 1000), 160000);
  bounded_min_distance double precision :=
    least(greatest(coalesce(min_distance_km, 0.3), 0.3), 4.0);
  bounded_results integer := least(greatest(coalesce(max_results, 30), 1), 60);
begin
  if (select auth.uid()) is null
     and coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if user_lat is null or user_lng is null
     or user_lat not between -90 and 90 or user_lng not between -180 and 180 then
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
    where road.publication_kind = 'legacy'
      and road.generation_batch_id is null
      and st_dwithin(
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
  ), diversified as (
    select
      nearby.*,
      row_number() over (
        partition by nearby.spatial_cell
        order by nearby.winding_score desc, nearby.distance_km desc,
          nearby.user_distance_km, nearby.id
      ) as cell_rank
    from nearby
  )
  select
    road.id, road.name, road.center_lat, road.center_lng, road.nodes,
    road.distance_km, road.winding_score, road.star_rating,
    road.sharp_curve_count, road.tight_curve_km, road.medium_curve_km,
    road.max_continuous_km, road.is_loop, road.elevation_delta,
    road.region, road.source, road.run_count, road.published_by,
    road.stop_sign_count, road.traffic_signal_count, road.stop_control_density,
    road.flow_score, road.fun_score, road.driveability_penalty,
    road.road_class_bucket, road.is_named, road.is_facility_like,
    road.is_bridge_like, road.is_connector_like, road.is_major_road_like,
    road.is_private_like, road.quality_label, road.quality_reject_reason,
    road.route_character, road.primary_reason, road.caution_note,
    road.road_names, road.surface_summary, road.speed_limit_summary,
    road.nearby_pois, road.elevation_profile, road.user_distance_km,
    coalesce(nullif(road.fun_score, 0), road.winding_score)
  from diversified as road
  where road.cell_rank <= 3
  order by road.cell_rank, road.user_distance_km, road.winding_score desc
  limit bounded_results;
end;
$$;
revoke all on function public.find_curvy_map_segments(
  double precision, double precision, integer, double precision, integer
) from public, anon;
grant execute on function public.find_curvy_map_segments(
  double precision, double precision, integer, double precision, integer
) to authenticated, service_role;

create function public.find_curvy_roads_v2(
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
  distance_from_user_km double precision, route_rank_score double precision,
  province_code text, is_generated boolean, activated_at timestamptz,
  catalog_epoch bigint
)
language plpgsql stable security definer
set search_path = pg_catalog, pg_temp
set statement_timeout = '8s'
as $$
declare
  bounded_radius integer := least(greatest(coalesce(radius_m, 50000), 1000), 160000);
  bounded_results integer := least(greatest(coalesce(max_results, 30), 1), 120);
begin
  if (select auth.uid()) is null
     and coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if user_lat is null or user_lng is null
     or user_lat not between -90 and 90 or user_lng not between -180 and 180 then
    raise exception 'invalid coordinates' using errcode = '22023';
  end if;
  return query
  select visible.*
  from revv_private.find_visible_curvy_roads(
    user_lat, user_lng, bounded_radius,
    greatest(coalesce(min_score, 0), 0), bounded_results, true
  ) as visible;
end;
$$;
revoke all on function public.find_curvy_roads_v2(
  double precision, double precision, integer, double precision, integer
) from public, anon;
grant execute on function public.find_curvy_roads_v2(
  double precision, double precision, integer, double precision, integer
) to authenticated, service_role;

create function public.get_route_nodes_v2(route_ids_input text[])
returns table (
  id text,
  nodes jsonb,
  province_code text,
  is_generated boolean,
  activated_at timestamptz,
  catalog_epoch bigint
)
language plpgsql stable security definer
set search_path = pg_catalog, pg_temp
set statement_timeout = '8s'
as $$
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
  select
    road.id,
    road.nodes,
    road.province_code,
    road.publication_kind = 'osm_generated',
    road.activated_at,
    catalog.epoch
  from public.curvy_roads as road
  left join public.route_generation_batches as batch
    on batch.batch_id = road.generation_batch_id
  cross join public.route_catalog_state as catalog
  where catalog.singleton_key
    and road.id = any(route_ids_input)
    and (
      (road.publication_kind = 'legacy' and road.generation_batch_id is null)
      or (road.publication_kind = 'osm_generated' and batch.status = 'active')
    )
  order by array_position(route_ids_input, road.id);
end;
$$;
revoke all on function public.get_route_nodes_v2(text[])
  from public, anon;
grant execute on function public.get_route_nodes_v2(text[])
  to authenticated, service_role;

create function public.get_route_catalog_v2()
returns table (
  catalog_epoch bigint,
  route_ids text[],
  updated_at timestamptz
)
language plpgsql stable security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  if (select auth.uid()) is null
     and coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  return query
  select catalog.epoch, catalog.route_ids, catalog.updated_at
  from public.route_catalog_state as catalog
  where catalog.singleton_key;
end;
$$;
revoke all on function public.get_route_catalog_v2()
  from public, anon;
grant execute on function public.get_route_catalog_v2()
  to authenticated, service_role;

create or replace function public.increment_route_run_count(
  route_id_input text,
  run_id_input text
)
returns void language plpgsql security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  with inserted as (
    insert into public.route_run_receipts (run_id, route_id, user_id)
    select run.id, route_id_input, current_user_id
    from public.runs as run
    join public.curvy_roads as road on road.id = route_id_input
    left join public.route_generation_batches as batch
      on batch.batch_id = road.generation_batch_id
    where run.id = run_id_input
      and run.user_id = current_user_id
      and run.route_id = route_id_input
      and (
        (road.publication_kind = 'legacy' and road.generation_batch_id is null)
        or (road.publication_kind = 'osm_generated' and batch.status = 'active')
      )
    on conflict (run_id) do nothing
    returning 1
  )
  update public.curvy_roads
  set run_count = coalesce(run_count, 0) + 1
  where id = route_id_input
    and exists (select 1 from inserted);
end;
$$;
revoke all on function public.increment_route_run_count(text, text)
  from public, anon;
grant execute on function public.increment_route_run_count(text, text)
  to authenticated, service_role;

select revv_private.rebuild_route_catalog(false);
notify pgrst, 'reload schema';
