alter table public.runs drop constraint if exists runs_user_id_fkey;
alter table public.runs add constraint runs_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

alter table public.run_details drop constraint if exists run_details_user_id_fkey;
alter table public.run_details add constraint run_details_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

alter table public.route_records drop constraint if exists route_records_user_id_fkey;
alter table public.route_records add constraint route_records_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

alter table public.route_feedback drop constraint if exists route_feedback_user_id_fkey;
alter table public.route_feedback add constraint route_feedback_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

delete from public.route_feedback
where ctid in (
  select feedback_ctid
  from (
    select
      ctid as feedback_ctid,
      row_number() over (
        partition by user_id, run_id
        order by created_at desc, id desc
      ) as duplicate_rank
    from public.route_feedback
    where run_id is not null
  ) ranked_feedback
  where duplicate_rank > 1
);
create unique index if not exists route_feedback_user_run_unique
  on public.route_feedback(user_id, run_id);

alter table public.saved_routes drop constraint if exists saved_routes_user_id_fkey;
alter table public.saved_routes add constraint saved_routes_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

alter table public.discovered_routes drop constraint if exists discovered_routes_user_id_fkey;
alter table public.discovered_routes add constraint discovered_routes_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

alter table public.curvy_roads
  drop constraint if exists curvy_roads_published_by_fkey;
alter table public.curvy_roads
  add constraint curvy_roads_published_by_fkey
  foreign key (published_by) references auth.users(id) on delete set null;

alter table public.telemetry_summary
  drop constraint if exists telemetry_summary_run_id_fkey;
alter table public.telemetry_summary
  add constraint telemetry_summary_run_id_fkey
  foreign key (run_id) references public.runs(id) on delete cascade not valid;
alter table public.telemetry_summary
  drop constraint if exists telemetry_summary_user_id_fkey;
alter table public.telemetry_summary
  add constraint telemetry_summary_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade not valid;

alter table public.recommendation_logs
  drop constraint if exists recommendation_logs_user_id_fkey;
alter table public.recommendation_logs
  add constraint recommendation_logs_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade not valid;
alter table public.user_preferences
  drop constraint if exists user_preferences_user_id_fkey;
alter table public.user_preferences
  add constraint user_preferences_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade not valid;
alter table public.photo_spots
  drop constraint if exists photo_spots_created_by_fkey;
alter table public.photo_spots
  add constraint photo_spots_created_by_fkey
  foreign key (created_by) references auth.users(id) on delete cascade not valid;

truncate table public.edge_rate_limits;
create index if not exists edge_rate_limits_updated_at_idx
  on public.edge_rate_limits(updated_at);

create extension if not exists pgcrypto with schema extensions;

create or replace function public.consume_edge_rate_limit(
  function_name_input text,
  client_key_input text,
  limit_count integer,
  window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_window timestamptz := now();
  existing_window timestamptz;
  existing_count integer;
  normalized_client_key text;
begin
  if function_name_input is null or client_key_input is null then
    return false;
  end if;
  if limit_count < 1 or window_seconds < 1 then
    return false;
  end if;

  normalized_client_key := case
    when client_key_input ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then 'db-user:' || encode(
        extensions.digest(client_key_input, 'sha256'),
        'hex'
      )
    else client_key_input
  end;

  perform pg_advisory_xact_lock(
    hashtextextended(function_name_input || ':' || normalized_client_key, 0)
  );

  delete from public.edge_rate_limits
   where updated_at < current_window - interval '1 day';

  select window_start, request_count
    into existing_window, existing_count
    from public.edge_rate_limits
   where function_name = function_name_input
     and client_key = normalized_client_key
   for update;

  if not found then
    insert into public.edge_rate_limits (
      function_name, client_key, window_start, request_count
    ) values (function_name_input, normalized_client_key, current_window, 1);
    return true;
  end if;

  if existing_window + make_interval(secs => window_seconds) <= current_window then
    update public.edge_rate_limits
       set window_start = current_window,
           request_count = 1,
           updated_at = current_window
     where function_name = function_name_input
       and client_key = normalized_client_key;
    return true;
  end if;

  if existing_count >= limit_count then
    return false;
  end if;

  update public.edge_rate_limits
     set request_count = request_count + 1,
         updated_at = current_window
   where function_name = function_name_input
     and client_key = normalized_client_key;
  return true;
end;
$$;

revoke all on function public.consume_edge_rate_limit(text, text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_edge_rate_limit(text, text, integer, integer)
  to service_role;

create or replace function public.enforce_authenticated_write_rate()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  current_user_id uuid := (select auth.uid());
  row_user_id uuid;
  pseudonymous_user_key text;
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

  pseudonymous_user_key := 'db-user:' || encode(
    extensions.digest(current_user_id::text, 'sha256'),
    'hex'
  );
  if not public.consume_edge_rate_limit(
    tg_argv[1],
    pseudonymous_user_key,
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
