create table if not exists public.crew_channels (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null default '',
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  constraint crew_channels_code_format check (
    code ~ '^[A-HJ-NP-Z2-9]{8}$'
  )
);

create table if not exists public.crew_channel_members (
  channel_id uuid not null references public.crew_channels(id) on delete cascade,
  member_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null default '',
  joined_at timestamptz not null default now(),
  primary key (channel_id, member_id),
  constraint crew_channel_members_display_name_length check (
    char_length(display_name) <= 24
  )
);

alter table public.crew_channels enable row level security;
alter table public.crew_channel_members enable row level security;

create or replace function public.generate_crew_channel_code()
returns text
language plpgsql
set search_path = public, pg_temp
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  generated_code text := '';
  char_index integer;
begin
  for char_index in 1..8 loop
    generated_code := generated_code ||
      substr(alphabet, (get_byte(gen_random_bytes(1), 0) % length(alphabet)) + 1, 1);
  end loop;

  return generated_code;
end;
$$;

create or replace function public.prepare_crew_channel_insert()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  generated_code text;
begin
  loop
    generated_code := public.generate_crew_channel_code();
    exit when not exists (
      select 1
        from public.crew_channels
       where code = generated_code
    );
  end loop;

  new.code := generated_code;
  new.created_at := now();
  new.expires_at := now() + interval '24 hours';
  return new;
end;
$$;

drop trigger if exists crew_channels_prepare_insert on public.crew_channels;
create trigger crew_channels_prepare_insert
  before insert on public.crew_channels
  for each row
  execute function public.prepare_crew_channel_insert();

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
      from public.crew_channel_members
     where channel_id = channel_id_input
       and member_id = (select auth.uid())
  );
$$;

drop policy if exists crew_channels_member_select on public.crew_channels;
create policy crew_channels_member_select on public.crew_channels
  for select
  to authenticated
  using (public.is_current_crew_channel_member(id));

drop policy if exists crew_channels_owner_insert on public.crew_channels;
create policy crew_channels_owner_insert on public.crew_channels
  for insert
  to authenticated
  with check (
    (select auth.uid()) is not null
    and owner_id = (select auth.uid())
  );

drop policy if exists crew_channel_members_channel_select on public.crew_channel_members;
create policy crew_channel_members_channel_select on public.crew_channel_members
  for select
  to authenticated
  using (public.is_current_crew_channel_member(channel_id));

drop policy if exists crew_channel_members_self_delete on public.crew_channel_members;
create policy crew_channel_members_self_delete on public.crew_channel_members
  for delete
  to authenticated
  using (member_id = (select auth.uid()));

create or replace function public.join_crew_channel(
  code_input text,
  display_name_input text default ''
)
returns public.crew_channel_members
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_user_id uuid := (select auth.uid());
  normalized_code text := upper(btrim(coalesce(code_input, '')));
  normalized_display_name text := left(btrim(coalesce(display_name_input, '')), 24);
  fallback_index integer;
  target_channel public.crew_channels%rowtype;
  joined_member public.crew_channel_members%rowtype;
begin
  if current_user_id is null then
    raise exception 'authentication required'
      using errcode = '28000';
  end if;

  if not public.consume_edge_rate_limit(
    'join_crew_channel',
    current_user_id::text,
    10,
    60
  ) then
    raise exception 'join rate limit exceeded'
      using errcode = 'P0001';
  end if;

  if normalized_code !~ '^[A-HJ-NP-Z2-9]{8}$' then
    raise exception 'invalid crew channel code'
      using errcode = '22023';
  end if;

  select *
    into target_channel
    from public.crew_channels
   where code = normalized_code
     and expires_at > now();

  if not found then
    raise exception 'invalid crew channel code'
      using errcode = '22023';
  end if;

  if normalized_display_name = '' then
    select count(*) + 1
      into fallback_index
      from public.crew_channel_members
     where channel_id = target_channel.id;

    normalized_display_name := '크루원 ' || fallback_index::text;
  end if;

  insert into public.crew_channel_members (
    channel_id,
    member_id,
    display_name
  )
  values (
    target_channel.id,
    current_user_id,
    normalized_display_name
  )
  on conflict (channel_id, member_id) do update
    set display_name = excluded.display_name
  returning * into joined_member;

  return joined_member;
end;
$$;

revoke all on public.crew_channels, public.crew_channel_members
  from public, anon;
grant select, insert on public.crew_channels
  to authenticated;
grant select, delete on public.crew_channel_members
  to authenticated;
grant select, insert, update, delete
  on public.crew_channels,
     public.crew_channel_members
  to service_role;

revoke all on function public.generate_crew_channel_code()
  from public, anon, authenticated;
revoke all on function public.prepare_crew_channel_insert()
  from public, anon, authenticated;
revoke all on function public.is_current_crew_channel_member(uuid)
  from public, anon;
grant execute on function public.is_current_crew_channel_member(uuid)
  to authenticated, service_role;
revoke all on function public.join_crew_channel(text, text)
  from public, anon;
grant execute on function public.join_crew_channel(text, text)
  to authenticated, service_role;;
