-- V2/V3 데이터 그릇 (북극성 2.6 + 백로그): 스키마만 미리, 클라이언트는 출시 후.

create table if not exists public.photo_spots (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null default auth.uid(),
  lat double precision not null,
  lng double precision not null,
  name text not null default '',
  source text not null default 'user' check (source in ('user', 'osm', 'places')),
  status text not null default 'candidate'
    check (status in ('candidate', 'verified', 'rejected')),
  vote_count integer not null default 0,
  created_at timestamptz not null default now()
);
alter table public.photo_spots enable row level security;
drop policy if exists photo_spots_read on public.photo_spots;
drop policy if exists photo_spots_owner_insert on public.photo_spots;
create policy photo_spots_read on public.photo_spots
  for select to authenticated using (true);
create policy photo_spots_owner_insert on public.photo_spots
  for insert to authenticated with check (created_by = (select auth.uid()));

create table if not exists public.route_scores (
  route_id text primary key references public.curvy_roads(id) on delete cascade,
  winding_score double precision,
  scenic_score double precision,
  night_view_score double precision,
  photo_score double precision,
  chill_score double precision,
  safety_stop_score double precision,
  version text,
  enriched_at timestamptz not null default now()
);
alter table public.route_scores enable row level security;
drop policy if exists route_scores_read on public.route_scores;
create policy route_scores_read on public.route_scores
  for select to anon, authenticated using (true);

grant select, insert on public.photo_spots to authenticated;
revoke update, delete on public.photo_spots from authenticated;
revoke all on public.photo_spots from anon;
grant select on public.route_scores to anon, authenticated;
revoke insert, update, delete on public.route_scores from anon, authenticated;;
