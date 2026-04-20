# Route Audit Tooling

REVV 내부용 route audit 진입점입니다.

이 디렉터리의 목적은 사용자 화면이 아니라 `추천 품질 검증`입니다.

## 구성

- `montreal_candidate_audit.sql`
  - Montreal 상위 후보를 Supabase에서 직접 조회하는 기존 SQL 샘플입니다.
- `export_region_audit.py`
  - Supabase `find_curvy_roads()` 결과를 읽고, 현재 저장된 metadata와
    `quality_metadata.py` 기준 재계산 결과를 비교해 CSV/JSON으로 내보냅니다.

## 왜 필요한가

문서 기준 Audit의 목적은 아래 3가지입니다.

1. `quality / character / explanation`가 실제 추천 결과와 일치하는지 검증
2. `fun + flow + residential`가 랭킹에 어떤 영향을 주는지 확인
3. 이 검증 흐름을 사용자-facing 화면과 분리

즉, 앱 UI를 디버깅하기 전에 내부 audit 산출물을 먼저 확인할 수 있게 하는 도구입니다.

## 요구 환경 변수

- `SUPABASE_URL`
- `SUPABASE_SERVICE_KEY`

## 사용 예시

```bash
python3 tools/route_audit/export_region_audit.py \
  --region-name montreal \
  --lat 45.4627167 \
  --lng -73.62658 \
  --radius-m 50000 \
  --top-n 200
```

산출물:

- `tools/route_audit/output/montreal_top200_audit.csv`
- `tools/route_audit/output/montreal_top200_audit.json`

## CSV에 포함되는 핵심 열

- ranking
  - `rank_position`
  - `route_rank_score`
  - `winding_score`
  - `flow_score`
  - `driveability_penalty`
  - `residential_penalty`
- metadata
  - `quality_label`
  - `route_character`
  - `primary_reason`
  - `caution_note`
- audit compare
  - `derived_quality_label`
  - `derived_route_character`
  - `derived_primary_reason`
  - `derived_caution_note`
  - `quality_mismatch`
  - `character_mismatch`
  - `reason_mismatch`
  - `caution_mismatch`

## 해석 가이드

- mismatch가 많으면:
  - enrichment batch가 덜 돌았거나
  - stored metadata와 current logic이 어긋났거나
  - ranking은 최신인데 설명 필드가 stale일 수 있습니다.
- `flow_score`, `stop_control_density`, `residential_penalty`를 함께 보면
  왜 curvy한데도 `keep`이 안 되는지 빠르게 파악할 수 있습니다.

## 주의

- 이 툴은 internal audit 전용입니다.
- 결과 필드는 사용자-facing 화면에 그대로 노출하지 않습니다.
