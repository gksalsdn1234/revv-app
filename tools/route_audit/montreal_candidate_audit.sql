WITH params AS (
  SELECT
    45.4627167::double precision AS user_lat,
    -73.62658::double precision AS user_lng,
    50000::integer AS radius_m,
    200::integer AS max_rows
),
scored AS (
  SELECT
    cr.id,
    cr.name,
    cr.distance_km,
    cr.winding_score,
    cr.tight_curve_km,
    cr.medium_curve_km,
    cr.max_continuous_km,
    cr.is_loop,
    cr.region,
    ST_Distance(
      cr.center_point,
      ST_SetSRID(ST_MakePoint(p.user_lng, p.user_lat), 4326)::geography
    ) / 1000.0 AS distance_from_user_km,
    (
      cr.winding_score
      * LEAST(GREATEST(cr.distance_km, 4.0) / 6.0, 3.0)
      * CASE
          WHEN coalesce(cr.name, '') ~* '\m(kart|karting|drift|circuit|raceway|speedway|motorsport|autocross|pit\s?lane|paddock|test\s?track|trackday)\M' THEN 0.05
          WHEN coalesce(cr.name, '') ~* '\m(pont|bridge|viaduct|causeway)\M' THEN 0.08
          WHEN coalesce(cr.name, '') ~* '\m(sortie|exit|ramp|bretelle|interchange|junction|connector)\M' THEN 0.15
          WHEN coalesce(cr.name, '') ~* '\m(boulevard|autoroute|highway)\M' THEN 0.35
          WHEN coalesce(cr.name, '') ~ '^[\d\-\s_]+$' THEN 0.25
          ELSE 1.0
        END
    ) AS route_rank_score
  FROM curvy_roads cr
  CROSS JOIN params p
  WHERE ST_DWithin(
          cr.center_point,
          ST_SetSRID(ST_MakePoint(p.user_lng, p.user_lat), 4326)::geography,
          p.radius_m
        )
    AND cr.distance_km >= 4.0
),
labeled AS (
  SELECT
    row_number() OVER (
      ORDER BY route_rank_score DESC, distance_from_user_km ASC
    ) AS rank_position,
    id,
    name,
    round(distance_km::numeric, 2) AS distance_km,
    round(distance_from_user_km::numeric, 2) AS distance_from_user_km,
    round(winding_score::numeric, 2) AS winding_score,
    round(route_rank_score::numeric, 2) AS route_rank_score,
    round(tight_curve_km::numeric, 2) AS tight_curve_km,
    round(medium_curve_km::numeric, 2) AS medium_curve_km,
    round(max_continuous_km::numeric, 2) AS max_continuous_km,
    is_loop,
    region,
    (coalesce(name, '') ~ '^[\d\-\s_]+$') AS is_numeric_name,
    (coalesce(name, '') ~* '\m(kart|karting|drift|circuit|raceway|speedway|motorsport|autocross|pit\s?lane|paddock|test\s?track|trackday)\M') AS is_facility_like,
    (coalesce(name, '') ~* '\m(pont|bridge|viaduct|causeway)\M') AS is_bridge_like,
    (coalesce(name, '') ~* '\m(sortie|exit|ramp|bretelle|interchange|junction|connector)\M') AS is_ramp_like,
    (coalesce(name, '') ~* '\m(autoroute|highway|boulevard|route\s+[0-9]+|rang|chemin|pont)\M') AS is_major_road_like,
    CASE
      WHEN distance_km < 5 THEN 'short'
      WHEN distance_km < 10 THEN 'medium'
      ELSE 'long'
    END AS length_band,
    CASE
      WHEN coalesce(name, '') ~* '\m(kart|karting|drift|circuit|raceway|speedway|motorsport|autocross|pit\s?lane|paddock|test\s?track|trackday)\M' THEN 'reject'
      WHEN coalesce(name, '') ~ '^[\d\-\s_]+$' THEN 'reject'
      WHEN coalesce(name, '') ~* '\m(sortie|exit|ramp|bretelle|interchange|junction|connector)\M' THEN 'reject'
      WHEN distance_km < 5 THEN 'reject'
      WHEN coalesce(name, '') ~* '\m(pont|bridge|viaduct|causeway)\M' THEN 'maybe'
      WHEN coalesce(name, '') ~* '\m(autoroute|highway|boulevard)\M' THEN 'maybe'
      ELSE 'keep'
    END AS suggested_action,
    CASE
      WHEN coalesce(name, '') ~* '\m(kart|karting|drift|circuit|raceway|speedway|motorsport|autocross|pit\s?lane|paddock|test\s?track|trackday)\M' THEN 'track_or_facility'
      WHEN coalesce(name, '') ~ '^[\d\-\s_]+$' THEN 'numeric_only_name'
      WHEN coalesce(name, '') ~* '\m(sortie|exit|ramp|bretelle|interchange|junction|connector)\M' THEN 'ramp_or_connector'
      WHEN distance_km < 5 THEN 'too_short'
      WHEN coalesce(name, '') ~* '\m(pont|bridge|viaduct|causeway)\M' THEN 'bridge_like'
      WHEN coalesce(name, '') ~* '\m(autoroute|highway|boulevard)\M' THEN 'major_road_like'
      ELSE 'keep_candidate'
    END AS suggested_reason
  FROM scored
)
SELECT *
FROM labeled
ORDER BY rank_position
LIMIT (SELECT max_rows FROM params);
