# Route Audit Tooling

REVV 내부용 route audit 진입점입니다.

이 디렉터리의 목적은 사용자 화면이 아니라 `추천 품질 검증`입니다.

## 구성

- `montreal_candidate_audit.sql`
  - Montreal 상위 후보를 Supabase에서 직접 조회하는 기존 SQL 샘플입니다.
- `export_region_audit.py`
  - Supabase `find_curvy_roads()` 결과를 읽고, 현재 저장된 metadata와
    `quality_metadata.py` 기준 재계산 결과를 비교해 CSV/JSON으로 내보냅니다.
- `export_western_baseline.py`
  - Revv 전용 읽기 전용 감사입니다. 전국/주/중심점 퍼널, 추천 적격성,
    enrichment, 중복, RPC별 payload/latency, 지역 분류와 readiness gate를
    canonical JSON 및 짧은 텍스트 요약으로 내보냅니다. 전국
    `map_distance_window`는 0.3–4 km 거리 분포이고, 실제 지도 노출 수는
    각 중심점의 `find_curvy_map_segments` 결과로 별도 기록합니다.
- `preflight_region_repair.py`
  - `region`이 null/빈 값인 행만 고정 GET으로 읽고, 체크섬이 고정된 Statistics
    Canada 2021 주/준주 디지털 경계(EPSG:3347)에 저장된 중심 좌표를 대입합니다.
    각 행이 정확히 한 경계에 포함될 때만 업데이트 제안을 만들며 DB 쓰기 기능은
    포함하지 않습니다.

## 왜 필요한가

문서 기준 Audit의 목적은 아래 3가지입니다.

1. `quality / character / explanation`가 실제 추천 결과와 일치하는지 검증
2. `fun + flow + residential`가 랭킹에 어떤 영향을 주는지 확인
3. 이 검증 흐름을 사용자-facing 화면과 분리

즉, 앱 UI를 디버깅하기 전에 내부 audit 산출물을 먼저 확인할 수 있게 하는 도구입니다.

## 요구 환경 변수

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY` (legacy 프로젝트에서는 `SUPABASE_ANON_KEY` 허용)
- `SUPABASE_AUDIT_ACCESS_TOKEN` (Revv authenticated 사용자 JWT)

## 사용 예시

```bash
python3 tools/route_audit/export_region_audit.py \
  --region-name montreal \
  --lat 45.4627167 \
  --lng -73.62658 \
  --radius-m 50000 \
  --top-n 200
```

고정 fixture는 외부 요청 없이 동일한 바이트 결과를 만듭니다.
`uv`는 함께 보관된 script lock의 정확한 버전과 artifact hash를 사용합니다.

```bash
uv run tools/route_audit/export_western_baseline.py \
  --fixture tools/route_audit/fixtures/western_baseline.json \
  --json-out /private/tmp/western-baseline.json \
  --summary-out /private/tmp/western-baseline.txt
```

운영 감사는 Revv 프로젝트 ref가 정확히 일치하고 publishable gateway key와
별도의 authenticated read token이 모두 있을 때만 실행됩니다. service-role
키를 읽지 않습니다. `curvy_roads`는 고정 열과 1,000행 페이지로만 읽고,
두 개의 stable 조회 RPC 외의 경로는 허용하지 않습니다. 429/5xx는 한 번만
재시도하며 리다이렉트와 비-2xx 응답은 실패합니다. 응답은 identity encoding과
16 MiB 상한을 적용하고, 키와 Authorization 헤더는 산출물에 포함하지 않습니다.

```bash
SUPABASE_URL=https://zvwgnduuumksuqazpvsf.supabase.co \
SUPABASE_PUBLISHABLE_KEY=... \
SUPABASE_AUDIT_ACCESS_TOKEN=... \
uv run tools/route_audit/export_western_baseline.py \
  --live \
  --json-out /private/tmp/western-live.json \
  --summary-out /private/tmp/western-live.txt
```

정규화된 legacy region은 아래 13개만 허용됩니다.

`alberta→AB`, `british_columbia→BC`, `manitoba→MB`,
`new_brunswick→NB`, `newfoundland_and_labrador→NL`,
`nova_scotia→NS`, `northwest_territories→NT`, `nunavut→NU`,
`ontario→ON`, `prince_edward_island→PE`, `quebec→QC`,
`saskatchewan→SK`, `yukon→YT`.

그 외 null/빈/미지 값은 unclassified로 남고, 추천 적격 row가 하나라도
unclassified이면 JSON은 기록되지만 CLI는 exit 2로 fail-closed 종료합니다.

## 빈 region 복구 사전검증

공식 원본과 라이선스 영수증은 `statcan_province_boundaries_2021.json`에
고정되어 있습니다. 원본 ZIP을 공식 URL에서 내려받은 뒤 SHA-256이
`c4dd830f8a6e9b4a1d80e71bc830ae319aaab37785cc92185e830f5e3da4714e`인지
먼저 확인합니다.

```bash
curl --fail --location \
  'https://www12.statcan.gc.ca/census-recensement/2021/geo/sip-pis/boundary-limites/files-fichiers/lpr_000a21a_e.zip' \
  --output /private/tmp/lpr_000a21a_e.zip

SUPABASE_URL=https://zvwgnduuumksuqazpvsf.supabase.co \
SUPABASE_PUBLISHABLE_KEY=... \
uv run tools/route_audit/preflight_region_repair.py \
  --boundary-archive /private/tmp/lpr_000a21a_e.zip \
  --live
```

출력은 결정론적 제안 JSON, 모호성 JSON, 두 파일과 원본/대상 스냅샷을 묶는
체크섬 영수증입니다. 대상 수가 기본값 230에서 달라지거나, 누락/복수 경계가
하나라도 있으면 exit 2로 종료합니다. 이 CLI는 service-role 키를 읽지 않고
`PATCH`, `POST`, `DELETE`, RPC 또는 `--apply` 동작을 제공하지 않습니다.

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
