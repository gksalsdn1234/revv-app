create table if not exists public.edge_rate_limits (
  function_name text not null,
  client_key text not null,
  window_start timestamptz not null,
  request_count integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (function_name, client_key)
);

alter table public.edge_rate_limits enable row level security;

drop policy if exists "edge_rate_limits_no_client_access" on public.edge_rate_limits;
create policy "edge_rate_limits_no_client_access" on public.edge_rate_limits
  for all using (false) with check (false);

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
begin
  if function_name_input is null or client_key_input is null then
    return false;
  end if;
  if limit_count < 1 or window_seconds < 1 then
    return false;
  end if;

  select window_start, request_count
    into existing_window, existing_count
    from public.edge_rate_limits
   where function_name = function_name_input
     and client_key = client_key_input
   for update;

  if not found then
    insert into public.edge_rate_limits (
      function_name,
      client_key,
      window_start,
      request_count
    )
    values (function_name_input, client_key_input, current_window, 1);
    return true;
  end if;

  if existing_window + make_interval(secs => window_seconds) <= current_window then
    update public.edge_rate_limits
       set window_start = current_window,
           request_count = 1,
           updated_at = current_window
     where function_name = function_name_input
       and client_key = client_key_input;
    return true;
  end if;

  if existing_count >= limit_count then
    return false;
  end if;

  update public.edge_rate_limits
     set request_count = request_count + 1,
         updated_at = current_window
   where function_name = function_name_input
     and client_key = client_key_input;
  return true;
end;
$$;

revoke all on function public.consume_edge_rate_limit(text, text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_edge_rate_limit(text, text, integer, integer)
  to service_role;
