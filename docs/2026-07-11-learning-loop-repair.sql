-- 학습루프 DB 복구 (2026-07-11 검증에서 발견된 미적용 마이그레이션 2건)
-- Supabase 대시보드 → SQL Editor에 전체 붙여넣고 Run.
-- 전부 멱등(IF NOT EXISTS / OR REPLACE)이라 중복 실행 안전.

-- ── 1. region_requests: 커버리지 밖 지역 요청 (수요 데이터) ──
-- 원본: supabase/migrations/20260703070628_region_requests.sql
CREATE TABLE IF NOT EXISTS public.region_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  grid_key TEXT NOT NULL,
  lat_rounded NUMERIC(4,1) NOT NULL,
  lng_rounded NUMERIC(4,1) NOT NULL,
  locale TEXT NOT NULL DEFAULT 'en',
  CONSTRAINT region_requests_lat_rounded_range
    CHECK (lat_rounded BETWEEN -90.0 AND 90.0),
  CONSTRAINT region_requests_lng_rounded_range
    CHECK (lng_rounded BETWEEN -180.0 AND 180.0),
  CONSTRAINT region_requests_locale_known
    CHECK (locale IN ('ko', 'en', 'fr'))
);

CREATE INDEX IF NOT EXISTS idx_region_requests_grid_created
  ON public.region_requests(grid_key, created_at DESC);

ALTER TABLE public.region_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS region_requests_anon_insert ON public.region_requests;
CREATE POLICY region_requests_anon_insert ON public.region_requests
  FOR INSERT
  TO anon
  WITH CHECK (true);

REVOKE ALL ON public.region_requests FROM PUBLIC, anon, authenticated;
GRANT INSERT ON public.region_requests TO anon;

-- ── 2. increment_route_run_count: 루트 재주행 카운트 (재방문 = 해자 데이터) ──
-- 원본: supabase/migrations/20260501000000_security_rls.sql + 20260501004000 권한
CREATE OR REPLACE FUNCTION public.increment_route_run_count(route_id_input TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.curvy_roads
  SET run_count = COALESCE(run_count, 0) + 1
  WHERE id = route_id_input;
END;
$$;

REVOKE ALL ON FUNCTION public.increment_route_run_count(TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_route_run_count(TEXT)
  TO authenticated, service_role;

-- ── 3. find_curvy_roads 타임아웃 대책 (2026-07-12 실기기 무한로딩 원인) ──
-- 원인: 전국 83k행 + 보강 데이터 적재 후 콜드 캐시에서 쿼리가 3.5초를 넘겨
-- anon 롤 statement_timeout에 걸림 (57014) → 앱이 "커브길 필드 로딩 중"에서 정지.
-- 캐시가 식을 때마다 각 지역의 첫 사용자가 같은 증상을 겪으므로 아래 3개 적용:

-- 3a. 대량 적재 후 플래너 통계 갱신 (실행계획 개선)
ANALYZE public.curvy_roads;

-- 3b. 공간 인덱스 적용 확인 (미적용이었다면 이게 핵심 수리)
CREATE INDEX IF NOT EXISTS idx_curvy_roads_center
  ON public.curvy_roads USING GIST(center_point);

-- 3c. anon 타임아웃 여유 확보 (3s → 15s; 새 연결부터 적용)
ALTER ROLE anon SET statement_timeout = '15s';
NOTIFY pgrst, 'reload config';

-- ── 검증 (실행 후 아래 두 개가 각각 1행씩 나와야 함) ──
SELECT 'region_requests OK' AS check WHERE to_regclass('public.region_requests') IS NOT NULL;
SELECT 'increment_route_run_count OK' AS check
  WHERE to_regprocedure('public.increment_route_run_count(text)') IS NOT NULL;


-- ── 4. find_curvy_roads v2 — 미사용 지오메트리 제거 (응답 1.89MB→~1.1MB, 콜드 비용 감소) ──
-- 원본: supabase/migrations/20260712100000_find_curvy_roads_slim.sql
-- find_curvy_roads v2: 응답에서 미사용 지오메트리 제거 (route_line 38% + center_point)
-- 앱은 nodes(JSONB)만 사용 — route_line/center_point는 전송·TOAST 읽기 순수 낭비 (2026-07-12 실측 1.89MB→~1.1MB)
-- 반환 타입이 바뀌므로 DROP 후 재생성.

DROP FUNCTION IF EXISTS find_curvy_roads(DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, DOUBLE PRECISION, INTEGER);

CREATE OR REPLACE FUNCTION find_curvy_roads(
  user_lat DOUBLE PRECISION,
  user_lng DOUBLE PRECISION,
  radius_m INTEGER DEFAULT 50000,
  min_score DOUBLE PRECISION DEFAULT 0,
  max_results INTEGER DEFAULT 30
)
RETURNS TABLE (
  id TEXT,
  name TEXT,
  center_lat DOUBLE PRECISION,
  center_lng DOUBLE PRECISION,
  nodes JSONB,
  distance_km DOUBLE PRECISION,
  curvature_score DOUBLE PRECISION,
  winding_score DOUBLE PRECISION,
  star_rating SMALLINT,
  sharp_curve_count INTEGER,
  tight_curve_km DOUBLE PRECISION,
  medium_curve_km DOUBLE PRECISION,
  max_continuous_km DOUBLE PRECISION,
  is_loop BOOLEAN,
  elevation_delta DOUBLE PRECISION,
  geohash4 TEXT,
  region TEXT,
  source TEXT,
  run_count INTEGER,
  published_by UUID,
  created_at TIMESTAMPTZ,
  stop_sign_count INTEGER,
  traffic_signal_count INTEGER,
  stop_control_density DOUBLE PRECISION,
  flow_score DOUBLE PRECISION,
  fun_score DOUBLE PRECISION,
  driveability_penalty DOUBLE PRECISION,
  road_class_bucket TEXT,
  is_named BOOLEAN,
  is_facility_like BOOLEAN,
  is_bridge_like BOOLEAN,
  is_connector_like BOOLEAN,
  is_major_road_like BOOLEAN,
  is_private_like BOOLEAN,
  residential_ratio DOUBLE PRECISION,
  service_ratio DOUBLE PRECISION,
  local_road_ratio DOUBLE PRECISION,
  intersection_density DOUBLE PRECISION,
  building_density DOUBLE PRECISION,
  housing_proximity_score DOUBLE PRECISION,
  urban_friction_score DOUBLE PRECISION,
  residential_penalty DOUBLE PRECISION,
  residential_version TEXT,
  residential_enriched_at TIMESTAMPTZ,
  quality_label TEXT,
  quality_reject_reason TEXT,
  route_character TEXT,
  primary_reason TEXT,
  caution_note TEXT,
  quality_version TEXT,
  quality_enriched_at TIMESTAMPTZ,
  elevation_profile JSONB,
  road_names JSONB,
  surface_summary TEXT,
  speed_limit_summary TEXT,
  nearby_pois JSONB,
  route_context JSONB,
  context_version TEXT,
  context_enriched_at TIMESTAMPTZ,
  distance_from_user_km DOUBLE PRECISION,
  route_rank_score DOUBLE PRECISION
)
LANGUAGE sql
STABLE
AS $$
  WITH base_routes AS (
    SELECT
      curvy_roads.*,
      ST_Distance(
        center_point,
        ST_SetSRID(ST_MakePoint(user_lng, user_lat), 4326)::geography
      ) / 1000.0 AS distance_from_user_km,
      COALESCE(
        NULLIF(fun_score, 0),
        winding_score
        * (1.0 + LEAST((tight_curve_km + medium_curve_km) / GREATEST(distance_km, 1.0), 0.45))
        * (1.0 + LEAST(max_continuous_km / 12.0, 0.18))
        * CASE WHEN is_loop THEN 1.05 ELSE 1.0 END
        * CASE WHEN elevation_delta >= 40 THEN LEAST(1.0 + elevation_delta / 250.0, 1.14) ELSE 1.0 END
      ) AS computed_fun_score,
      COALESCE(
        NULLIF(flow_score, 0),
        GREATEST(
          0.15,
          LEAST(
            1.0,
            1.0 - (
              (
                COALESCE(stop_sign_count, 0)
                + COALESCE(traffic_signal_count, 0) * 1.5
              ) / GREATEST(distance_km, 1.0)
            ) * 0.35
            + CASE WHEN max_continuous_km >= 1.5 THEN 0.08 ELSE 0.0 END
          )
        )
      ) AS computed_flow_score,
      COALESCE(
        NULLIF(driveability_penalty, 0),
        GREATEST(
          0.05,
          LEAST(
            1.0,
            CASE WHEN COALESCE(is_named, TRUE) THEN 1.0 ELSE 0.78 END
            * CASE WHEN COALESCE(is_facility_like, FALSE) THEN 0.08 ELSE 1.0 END
            * CASE WHEN COALESCE(is_connector_like, FALSE) THEN 0.18 ELSE 1.0 END
            * CASE WHEN COALESCE(is_bridge_like, FALSE) THEN 0.28 ELSE 1.0 END
            * CASE WHEN COALESCE(is_major_road_like, FALSE) THEN 0.55 ELSE 1.0 END
            * CASE WHEN COALESCE(is_private_like, FALSE) THEN 0.18 ELSE 1.0 END
            * CASE WHEN name ~ '^[\d\-\s_]+$' THEN 0.48 ELSE 1.0 END
          )
        )
      ) AS computed_driveability_penalty
    FROM curvy_roads
    WHERE ST_DWithin(
            center_point,
            ST_SetSRID(ST_MakePoint(user_lng, user_lat), 4326)::geography,
            radius_m
          )
      AND winding_score >= min_score
      AND distance_km >= 4.0
  ),
  scored_routes AS (
    SELECT
      base_routes.*,
      GREATEST(
        0.05,
        LEAST(
          1.0,
          CASE
            WHEN distance_km < 8.0 THEN 0.82
            ELSE 1.0
          END
          * CASE
              WHEN distance_from_user_km <= 15.0 THEN 1.0
              WHEN distance_from_user_km >= 80.0 THEN 0.45
              ELSE 1.0 - ((distance_from_user_km - 15.0) / 65.0) * 0.55
            END
          * CASE
              WHEN stop_sign_count >= 5 AND distance_km < 12.0 THEN 0.15
              WHEN stop_control_density >= 0.65 AND max_continuous_km < 1.2 THEN 0.20
              ELSE 1.0
            END
          * COALESCE(NULLIF(residential_penalty, 0), 1.0)
        )
      ) AS context_adjustment
    FROM base_routes
    WHERE NOT COALESCE(is_facility_like, FALSE)
      AND NOT COALESCE(is_connector_like, FALSE)
      AND NOT (
        stop_sign_count >= 5
        AND distance_km < 12.0
      )
      AND NOT (
        stop_control_density >= 0.65
        AND max_continuous_km < 1.2
      )
      AND NOT (
        name ~ '^[\d\-\s_]+$'
        AND distance_km < 8.0
      )
  )
  SELECT
    scored_routes.id,
    scored_routes.name,
    scored_routes.center_lat,
    scored_routes.center_lng,
    scored_routes.nodes,
    scored_routes.distance_km,
    scored_routes.curvature_score,
    scored_routes.winding_score,
    scored_routes.star_rating,
    scored_routes.sharp_curve_count,
    scored_routes.tight_curve_km,
    scored_routes.medium_curve_km,
    scored_routes.max_continuous_km,
    scored_routes.is_loop,
    scored_routes.elevation_delta,
    scored_routes.geohash4,
    scored_routes.region,
    scored_routes.source,
    scored_routes.run_count,
    scored_routes.published_by,
    scored_routes.created_at,
    scored_routes.stop_sign_count,
    scored_routes.traffic_signal_count,
    scored_routes.stop_control_density,
    scored_routes.computed_flow_score AS flow_score,
    scored_routes.computed_fun_score AS fun_score,
    scored_routes.computed_driveability_penalty AS driveability_penalty,
    scored_routes.road_class_bucket,
    scored_routes.is_named,
    scored_routes.is_facility_like,
    scored_routes.is_bridge_like,
    scored_routes.is_connector_like,
    scored_routes.is_major_road_like,
    scored_routes.is_private_like,
    scored_routes.residential_ratio,
    scored_routes.service_ratio,
    scored_routes.local_road_ratio,
    scored_routes.intersection_density,
    scored_routes.building_density,
    scored_routes.housing_proximity_score,
    scored_routes.urban_friction_score,
    scored_routes.residential_penalty,
    scored_routes.residential_version,
    scored_routes.residential_enriched_at,
    scored_routes.quality_label,
    scored_routes.quality_reject_reason,
    scored_routes.route_character,
    scored_routes.primary_reason,
    scored_routes.caution_note,
    scored_routes.quality_version,
    scored_routes.quality_enriched_at,
    scored_routes.elevation_profile,
    scored_routes.road_names,
    scored_routes.surface_summary,
    scored_routes.speed_limit_summary,
    scored_routes.nearby_pois,
    scored_routes.route_context,
    scored_routes.context_version,
    scored_routes.context_enriched_at,
    scored_routes.distance_from_user_km,
    (
      scored_routes.computed_fun_score
      * scored_routes.computed_flow_score
      * scored_routes.computed_driveability_penalty
      * scored_routes.context_adjustment
    ) AS route_rank_score
  FROM scored_routes
  ORDER BY
    route_rank_score DESC,
    distance_from_user_km ASC
  LIMIT max_results;
$$;

REVOKE ALL ON FUNCTION find_curvy_roads(DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, DOUBLE PRECISION, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION find_curvy_roads(DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, DOUBLE PRECISION, INTEGER)
  TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';


-- ── 5. 5개 도시 캐시 워밍 크론 (10분 주기) — 콜드 스타트 자체를 제거 ──
-- pg_cron은 postgres 롤로 돌아 statement_timeout 제약 없음.
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.unschedule('warm_curvy_roads_cache')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'warm_curvy_roads_cache');
SELECT cron.schedule('warm_curvy_roads_cache', '*/10 * * * *', $warm$
  SELECT
    (SELECT count(*) FROM find_curvy_roads(45.5017, -73.5673, 160000, 0, 120)),
    (SELECT count(*) FROM find_curvy_roads(46.8139, -71.2080, 160000, 0, 120)),
    (SELECT count(*) FROM find_curvy_roads(43.6532, -79.3832, 160000, 0, 120)),
    (SELECT count(*) FROM find_curvy_roads(49.2827, -123.1207, 160000, 0, 120)),
    (SELECT count(*) FROM find_curvy_roads(51.0447, -114.0719, 160000, 0, 120));
$warm$);
