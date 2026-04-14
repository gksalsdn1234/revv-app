ALTER TABLE curvy_roads
ADD COLUMN IF NOT EXISTS stop_sign_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS traffic_signal_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS stop_control_density DOUBLE PRECISION DEFAULT 0,
ADD COLUMN IF NOT EXISTS flow_score DOUBLE PRECISION DEFAULT 1.0,
ADD COLUMN IF NOT EXISTS fun_score DOUBLE PRECISION DEFAULT 0,
ADD COLUMN IF NOT EXISTS driveability_penalty DOUBLE PRECISION DEFAULT 1.0,
ADD COLUMN IF NOT EXISTS route_rank_score DOUBLE PRECISION DEFAULT 0,
ADD COLUMN IF NOT EXISTS road_class_bucket TEXT DEFAULT '',
ADD COLUMN IF NOT EXISTS is_named BOOLEAN DEFAULT TRUE,
ADD COLUMN IF NOT EXISTS is_facility_like BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS is_bridge_like BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS is_connector_like BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS is_major_road_like BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS is_private_like BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN curvy_roads.stop_sign_count IS
  'Estimated number of stop-sign-controlled intersections encountered along the route.';
COMMENT ON COLUMN curvy_roads.traffic_signal_count IS
  'Estimated number of traffic-signal-controlled intersections encountered along the route.';
COMMENT ON COLUMN curvy_roads.stop_control_density IS
  'Weighted stop-control count per km. Formula: (stop_sign_count + traffic_signal_count * 1.5) / distance_km.';
COMMENT ON COLUMN curvy_roads.flow_score IS
  '0.0-1.0 uninterrupted driving flow score. Higher is better.';
COMMENT ON COLUMN curvy_roads.fun_score IS
  'Precomputed fun score derived from winding, continuous curves, elevation, and loop bonus.';
COMMENT ON COLUMN curvy_roads.driveability_penalty IS
  '0.0-1.0 penalty factor for facilities, ramps, bridges, private roads, or unnamed roads.';
COMMENT ON COLUMN curvy_roads.road_class_bucket IS
  'Normalized road family bucket such as rural_named, major_connector, bridge, facility, or private_like.';

DROP FUNCTION IF EXISTS find_curvy_roads(
  DOUBLE PRECISION,
  DOUBLE PRECISION,
  INTEGER,
  DOUBLE PRECISION,
  INTEGER
);

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
  center_point GEOGRAPHY(POINT, 4326),
  route_line GEOGRAPHY(LINESTRING, 4326),
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
    scored_routes.center_point,
    scored_routes.route_line,
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
