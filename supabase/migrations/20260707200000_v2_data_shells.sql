-- V2/V3 데이터 그릇 (북극성 2.6 + 백로그, 2026-07-06 확정 아이디어):
-- 코드는 다시 만들 수 있지만 데이터는 못 만든다 — 스키마만 미리 깔고
-- 클라이언트/UI는 출시 후. fail-closed RLS.

-- 참여형 사진스팟 (V2 해자 1순위): 후보 제안 → 👍 누적 → verified 승격.
-- 스팟 좌표는 개인 위치가 아니라 공유 장소 자산이라 정확 좌표를 저장한다.
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
-- 공유 자산: 로그인 유저 모두 조회, 제안은 본인 명의로만.
-- 승격/투표 집계는 service_role(서버)만 — 클라이언트 update/delete 정책 없음.
create policy photo_spots_read on public.photo_spots
  for select to authenticated using (true);
create policy photo_spots_owner_insert on public.photo_spots
  for insert to authenticated with check (created_by = (select auth.uid()));

-- 루트 점수 분리 (V3 개인화·테마 추천 기반): 단일 fun_score를 넘어
-- 모드별 가중치의 원료. 파이프라인(service_role)만 쓴다.
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
-- curvy_roads와 동일하게 읽기 전용 공개 데이터.
create policy route_scores_read on public.route_scores
  for select to anon, authenticated using (true);

grant select, insert on public.photo_spots to authenticated;
revoke update, delete on public.photo_spots from authenticated;
revoke all on public.photo_spots from anon;
grant select on public.route_scores to anon, authenticated;
revoke insert, update, delete on public.route_scores from anon, authenticated;
