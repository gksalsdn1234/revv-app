-- V1 학습루프: 추천 노출/선택 로그 + 최소 취향 테이블.
-- 데이터 최소화: 정확 좌표 대신 geohash4, 루트는 id만. fail-closed RLS.

create table if not exists public.recommendation_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  event text not null check (event in ('shown', 'chosen')),
  mode text not null check (mode in ('destination', 'chain', 'free')),
  origin_geohash4 text,
  budget_minutes integer,
  route_ids jsonb not null default '[]'::jsonb,
  option_kind text,
  created_at timestamptz not null default now()
);
alter table public.recommendation_logs enable row level security;
drop policy if exists recommendation_logs_owner_insert on public.recommendation_logs;
drop policy if exists recommendation_logs_owner_select on public.recommendation_logs;
create policy recommendation_logs_owner_insert on public.recommendation_logs
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy recommendation_logs_owner_select on public.recommendation_logs
  for select to authenticated using (user_id = (select auth.uid()));

create table if not exists public.user_preferences (
  user_id uuid primary key default auth.uid(),
  prefs jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.user_preferences enable row level security;
drop policy if exists user_preferences_owner_all on public.user_preferences;
create policy user_preferences_owner_all on public.user_preferences
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

grant insert, select on public.recommendation_logs to authenticated;
grant all on public.user_preferences to authenticated;
revoke all on public.recommendation_logs from anon;
revoke all on public.user_preferences from anon;;
