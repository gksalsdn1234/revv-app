create table if not exists public.telemetry_summary (
  run_id text primary key,
  user_id uuid not null default auth.uid(),
  hard_brake_count integer not null default 0,
  harsh_steer_count integer not null default 0,
  smooth_ratio double precision,
  p95_lateral_g double precision,
  sample_seconds integer,
  detail_version text not null default 'v1',
  created_at timestamptz not null default now()
);

alter table public.telemetry_summary enable row level security;

create policy telemetry_summary_owner_insert on public.telemetry_summary
  for insert to authenticated with check (user_id = (select auth.uid()));

create policy telemetry_summary_owner_select on public.telemetry_summary
  for select to authenticated using (user_id = (select auth.uid()));

grant insert, select on public.telemetry_summary to authenticated;
revoke update, delete on public.telemetry_summary from authenticated;
revoke all on public.telemetry_summary from anon;
