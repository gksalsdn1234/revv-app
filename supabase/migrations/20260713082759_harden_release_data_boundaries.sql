create table if not exists public.route_run_receipts (
  run_id text primary key references public.runs(id) on delete cascade,
  route_id text not null references public.curvy_roads(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.route_run_receipts enable row level security;
revoke all on public.route_run_receipts from public, anon, authenticated;
grant select, insert, update, delete on public.route_run_receipts
  to service_role;

revoke all on function public.increment_route_run_count(text)
  from public, anon, authenticated;
drop function if exists public.increment_route_run_count(text);

create or replace function public.increment_route_run_count(
  route_id_input text,
  run_id_input text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    raise exception 'authentication required'
      using errcode = '28000';
  end if;

  with inserted as (
    insert into public.route_run_receipts (run_id, route_id, user_id)
    select r.id, route_id_input, current_user_id
      from public.runs r
     where r.id = run_id_input
       and r.user_id = current_user_id
       and r.route_id = route_id_input
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

drop policy if exists run_details_owner on public.run_details;
create policy run_details_owner on public.run_details
  for all
  to authenticated
  using (
    run_details.user_id = (select auth.uid())
    and exists (
      select 1
        from public.runs r
       where r.id = run_details.run_id
         and r.user_id = (select auth.uid())
    )
  )
  with check (
    run_details.user_id = (select auth.uid())
    and exists (
      select 1
        from public.runs r
       where r.id = run_details.run_id
         and r.user_id = (select auth.uid())
    )
  );

create or replace function public.is_current_crew_channel_member(
  channel_id_input uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from public.crew_channel_members m
      join public.crew_channels c on c.id = m.channel_id
     where m.channel_id = channel_id_input
       and m.member_id = (select auth.uid())
       and c.expires_at > now()
  );
$$;

drop policy if exists crew_walkie_realtime_receive on realtime.messages;
create policy crew_walkie_realtime_receive on realtime.messages
  for select
  to authenticated
  using (
    realtime.messages.extension in ('broadcast', 'presence')
    and exists (
      select 1
        from public.crew_channel_members m
        join public.crew_channels c on c.id = m.channel_id
       where m.member_id = (select auth.uid())
         and c.expires_at > now()
         and (select realtime.topic()) in (
           'crew:' || m.channel_id::text,
           'crew:' || m.channel_id::text || ':audio'
         )
    )
  );

drop policy if exists crew_walkie_realtime_send on realtime.messages;
create policy crew_walkie_realtime_send on realtime.messages
  for insert
  to authenticated
  with check (
    realtime.messages.extension in ('broadcast', 'presence')
    and exists (
      select 1
        from public.crew_channel_members m
        join public.crew_channels c on c.id = m.channel_id
       where m.member_id = (select auth.uid())
         and c.expires_at > now()
         and (select realtime.topic()) in (
           'crew:' || m.channel_id::text,
           'crew:' || m.channel_id::text || ':audio'
         )
    )
  );

drop policy if exists photo_spots_owner_insert on public.photo_spots;
create policy photo_spots_owner_insert on public.photo_spots
  for insert
  to authenticated
  with check (
    created_by = (select auth.uid())
    and source = 'user'
    and status = 'candidate'
    and vote_count = 0
    and lat between -90 and 90
    and lng between -180 and 180
  );

create or replace function public.enforce_authenticated_write_rate()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_user_id uuid := (select auth.uid());
  row_user_id uuid;
begin
  if current_user_id is null then
    raise exception 'authentication required'
      using errcode = '28000';
  end if;

  row_user_id := ((to_jsonb(new) ->> tg_argv[0])::uuid);
  if row_user_id is distinct from current_user_id then
    raise exception 'row owner does not match authenticated user'
      using errcode = '42501';
  end if;

  if not public.consume_edge_rate_limit(
    tg_argv[1],
    current_user_id::text,
    tg_argv[2]::integer,
    tg_argv[3]::integer
  ) then
    raise exception 'write rate limit exceeded'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke all on function public.enforce_authenticated_write_rate()
  from public, anon, authenticated;

alter table public.region_requests
  add column if not exists user_id uuid default auth.uid()
    references auth.users(id) on delete cascade;

drop policy if exists region_requests_anon_insert on public.region_requests;
drop policy if exists region_requests_owner_insert on public.region_requests;
create policy region_requests_owner_insert on public.region_requests
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

revoke all on public.region_requests from anon;
grant insert on public.region_requests to authenticated;

create unique index if not exists region_requests_user_grid_unique
  on public.region_requests(user_id, grid_key)
  where user_id is not null;

drop trigger if exists region_requests_write_rate
  on public.region_requests;
create trigger region_requests_write_rate
  before insert on public.region_requests
  for each row execute function public.enforce_authenticated_write_rate(
    'user_id', 'region-request', '20', '86400'
  );

drop trigger if exists photo_spots_write_rate on public.photo_spots;
create trigger photo_spots_write_rate
  before insert on public.photo_spots
  for each row execute function public.enforce_authenticated_write_rate(
    'created_by', 'photo-spot', '20', '86400'
  );

alter table public.photo_spots
  drop constraint if exists photo_spots_name_length;
alter table public.photo_spots
  add constraint photo_spots_name_length
  check (char_length(name) <= 120) not valid;

drop trigger if exists recommendation_logs_write_rate
  on public.recommendation_logs;
create trigger recommendation_logs_write_rate
  before insert on public.recommendation_logs
  for each row execute function public.enforce_authenticated_write_rate(
    'user_id', 'recommendation-log', '500', '86400'
  );

alter table public.recommendation_logs
  drop constraint if exists recommendation_logs_route_ids_bounded;
alter table public.recommendation_logs
  add constraint recommendation_logs_route_ids_bounded
  check (
    jsonb_typeof(route_ids) = 'array'
    and jsonb_array_length(route_ids) <= 50
    and pg_column_size(route_ids) <= 16384
  ) not valid;

drop trigger if exists explored_cells_write_rate on public.explored_cells;
create trigger explored_cells_write_rate
  before insert on public.explored_cells
  for each row execute function public.enforce_authenticated_write_rate(
    'user_id', 'explored-cell', '5000', '86400'
  );

drop policy if exists telemetry_summary_owner_insert
  on public.telemetry_summary;
create policy telemetry_summary_owner_insert on public.telemetry_summary
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1
        from public.runs r
       where r.id = telemetry_summary.run_id
         and r.user_id = (select auth.uid())
    )
  );

drop trigger if exists telemetry_summary_write_rate
  on public.telemetry_summary;
create trigger telemetry_summary_write_rate
  before insert on public.telemetry_summary
  for each row execute function public.enforce_authenticated_write_rate(
    'user_id', 'telemetry-summary', '200', '86400'
  );

create or replace function public.create_crew_channel(
  name_input text default ''
)
returns public.crew_channels
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_user_id uuid := (select auth.uid());
  created_channel public.crew_channels%rowtype;
begin
  if current_user_id is null then
    raise exception 'authentication required'
      using errcode = '28000';
  end if;
  if not public.consume_edge_rate_limit(
    'crew-create',
    current_user_id::text,
    5,
    3600
  ) then
    raise exception 'crew channel creation rate limit exceeded'
      using errcode = 'P0001';
  end if;

  insert into public.crew_channels (name, owner_id)
  values (left(btrim(coalesce(name_input, '')), 60), current_user_id)
  returning * into created_channel;

  insert into public.crew_channel_members (
    channel_id,
    member_id,
    display_name
  )
  values (created_channel.id, current_user_id, '크루원 1')
  on conflict (channel_id, member_id) do nothing;

  return created_channel;
end;
$$;

revoke all on function public.create_crew_channel(text)
  from public, anon;
grant execute on function public.create_crew_channel(text)
  to authenticated, service_role;

alter function public.find_curvy_roads(
  double precision,
  double precision,
  integer,
  double precision,
  integer
) set statement_timeout = '8s';
