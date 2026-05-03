-- REVV security baseline.
-- These policies keep per-user driving data scoped to auth.uid().

do $$
begin
  if to_regclass('public.runs') is not null then
    alter table public.runs enable row level security;
    drop policy if exists "runs_select_own" on public.runs;
    drop policy if exists "runs_insert_own" on public.runs;
    drop policy if exists "runs_update_own" on public.runs;
    drop policy if exists "runs_delete_own" on public.runs;
    create policy "runs_select_own" on public.runs
      for select using (auth.uid() = user_id);
    create policy "runs_insert_own" on public.runs
      for insert with check (auth.uid() = user_id);
    create policy "runs_update_own" on public.runs
      for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
    create policy "runs_delete_own" on public.runs
      for delete using (auth.uid() = user_id);
  end if;

  if to_regclass('public.run_details') is not null then
    alter table public.run_details enable row level security;
    drop policy if exists "run_details_select_own" on public.run_details;
    drop policy if exists "run_details_insert_own" on public.run_details;
    drop policy if exists "run_details_update_own" on public.run_details;
    drop policy if exists "run_details_delete_own" on public.run_details;
    create policy "run_details_select_own" on public.run_details
      for select using (auth.uid() = user_id);
    create policy "run_details_insert_own" on public.run_details
      for insert with check (auth.uid() = user_id);
    create policy "run_details_update_own" on public.run_details
      for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
    create policy "run_details_delete_own" on public.run_details
      for delete using (auth.uid() = user_id);
  end if;

  if to_regclass('public.saved_routes') is not null then
    alter table public.saved_routes enable row level security;
    drop policy if exists "saved_routes_select_own" on public.saved_routes;
    drop policy if exists "saved_routes_insert_own" on public.saved_routes;
    drop policy if exists "saved_routes_update_own" on public.saved_routes;
    drop policy if exists "saved_routes_delete_own" on public.saved_routes;
    create policy "saved_routes_select_own" on public.saved_routes
      for select using (auth.uid() = user_id);
    create policy "saved_routes_insert_own" on public.saved_routes
      for insert with check (auth.uid() = user_id);
    create policy "saved_routes_update_own" on public.saved_routes
      for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
    create policy "saved_routes_delete_own" on public.saved_routes
      for delete using (auth.uid() = user_id);
  end if;

  if to_regclass('public.route_records') is not null then
    alter table public.route_records enable row level security;
    drop policy if exists "route_records_select_own" on public.route_records;
    drop policy if exists "route_records_insert_own" on public.route_records;
    drop policy if exists "route_records_update_own" on public.route_records;
    drop policy if exists "route_records_delete_own" on public.route_records;
    create policy "route_records_select_own" on public.route_records
      for select using (auth.uid() = user_id);
    create policy "route_records_insert_own" on public.route_records
      for insert with check (auth.uid() = user_id);
    create policy "route_records_update_own" on public.route_records
      for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
    create policy "route_records_delete_own" on public.route_records
      for delete using (auth.uid() = user_id);
  end if;

  if to_regclass('public.discovered_routes') is not null then
    alter table public.discovered_routes enable row level security;
    drop policy if exists "discovered_routes_select_own" on public.discovered_routes;
    drop policy if exists "discovered_routes_insert_own" on public.discovered_routes;
    drop policy if exists "discovered_routes_update_own" on public.discovered_routes;
    drop policy if exists "discovered_routes_delete_own" on public.discovered_routes;
    create policy "discovered_routes_select_own" on public.discovered_routes
      for select using (auth.uid() = user_id);
    create policy "discovered_routes_insert_own" on public.discovered_routes
      for insert with check (auth.uid() = user_id);
    create policy "discovered_routes_update_own" on public.discovered_routes
      for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
    create policy "discovered_routes_delete_own" on public.discovered_routes
      for delete using (auth.uid() = user_id);
  end if;
end $$;

