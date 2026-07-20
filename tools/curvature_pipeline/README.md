# Curvature Pipeline

REVV용 사전 계산 와인딩 도로 파이프라인입니다.

## 구성

- `download_kmz.py`
  - roadcurvature.com에서 `c_300` KMZ 링크를 찾아 다운로드합니다.
- `parse_kml.py`
  - KMZ를 풀고 KML Placemark를 추출합니다.
- `process_roads.py`
  - 노드 다운샘플링, 중심점, 거리, 곡률 프로파일, `fun_score`, `driveability_penalty`, 안정적 ID를 계산합니다.
- `enrich_stop_controls.py`
  - Overpass를 사용해 각 루트 주변의 stop sign / traffic signal을 수집하고 `flow_score`를 계산합니다.
- `enrich_route_context.py`
  - Overpass를 사용해 루트 주변의 실제 도로명, road ref, surface, maxspeed, viewpoint/POI를 수집합니다.
  - 결과는 `road_names`, `surface_summary`, `speed_limit_summary`, `nearby_pois`, `route_context`에 저장됩니다.
- `upload_to_supabase.py`
  - 분석 결과를 Supabase `curvy_roads` 테이블에 upsert합니다.
  - 추천 필드(`fun_score`, `flow_score`, `driveability_penalty`, `road_class_bucket`)까지 함께 적재합니다.
- `upload_western_batch.py`
  - checksum으로 덮인 pilot/expansion manifest만 Revv 프로젝트에 shadow 업로드합니다.
  - 기본은 네트워크 없는 dry-run이며 `--apply`와 service-role key가 함께 있어야 변경합니다.
  - whole-batch `shadow→active→disabled` 전환만 지원하며 삭제 명령은 제공하지 않습니다.
- `enrich_region_batch.py`
  - 지역별 `top-N` 후보를 Supabase에서 읽고, 이미 enrich된 루트는 건너뛴 뒤 새 루트만 stop-control enrichment와 업로드를 수행합니다.
- `residential_metadata.py`
  - 주거지/로컬도로 성격 데이터를 바탕으로 `urban_friction_score`와 `residential_penalty`를 계산하는 보조 레이어입니다.
- `regions.json`
  - 도시권 배치 설정 파일입니다.
- `western_sources/`
  - BC/AB/SK/MB의 날짜·크기·MD5가 고정된 Geofabrik PBF와 허브 bounds를 검증합니다.
  - 검증된 PBF를 checksum 주소 캐시에 보관하고 `osmium 1.19.0`으로 허브별 bounded PBF를 생성합니다.
  - 두 번째 실행은 manifest·허브 bounds digest와 캐시 checksum이 모두 유효할 때만 네트워크 요청 없이 checkpoint에서 재개합니다.
- `acquire_western_sources.py`
  - HTTPS allowlist, 최대 16회 HTTP 시도, 전체 취득 30분 제한, 300초 osmium 명령 제한을 강제합니다.
  - 하나의 절대 deadline을 HTTP, checksum 계산, `osmium extract`, `fileinfo`, 최종 receipt까지 전달합니다.
  - `--dry-run`은 manifest만 검증하고 캐시·출력·네트워크를 변경하지 않습니다.

## 설치

```bash
pip install -r tools/curvature_pipeline/requirements.txt
```

## 사용 예시

```bash
python tools/curvature_pipeline/download_kmz.py -o data/kmz
python tools/curvature_pipeline/parse_kml.py data/kmz/sample.kmz -o data/sample.json
python tools/curvature_pipeline/process_roads.py data/sample.json -o data/analyzed.json
python tools/curvature_pipeline/enrich_stop_controls.py data/analyzed.json -o data/analyzed.enriched.json
python tools/curvature_pipeline/enrich_route_context.py data/analyzed.enriched.json -o data/analyzed.context.json
SUPABASE_URL=... SUPABASE_SERVICE_KEY=... python tools/curvature_pipeline/upload_to_supabase.py data/analyzed.enriched.json
python tools/curvature_pipeline/enrich_region_batch.py --region montreal
```

서부 batch는 project/batch/checksum을 명시하고 먼저 dry-run 합니다. `.env` 파일은 자동으로 읽지 않습니다.

```bash
PYTHONPATH=. uv run tools/curvature_pipeline/upload_western_batch.py \
  shadow artifacts/west-pilot-v1-20260716.json \
  --project-ref zvwgnduuumksuqazpvsf \
  --batch-id west-pilot-v1-20260716 \
  --checksum <sha256>
```

동일 명령에 `--apply`를 추가할 때만 `SUPABASE_SERVICE_KEY` 환경 변수를 사용해 변경합니다.

서부 OSM source manifest 검증만 실행:

```bash
PYTHONPATH=. uv run tools/curvature_pipeline/acquire_western_sources.py \
  tools/curvature_pipeline/western_sources/manifests/western-2026-07-15.json \
  --dry-run
```

실제 취득은 checksum 확인 후 약 1.9 GB의 PBF를 내려받으므로, 4 CPU / 2 GB RAM / 20 GB disk / 4 hour 제한을 적용한 `western_sources/Containerfile`에서만 실행합니다. PBF와 checkpoint는 `.pipeline-cache/` 아래에 남고 Git에는 포함하지 않습니다. 신규 생성 데이터는 `western_sources/LICENSE_POLICY.md`의 OSM attribution 정책이 제품에 반영되기 전에는 production에 업로드하지 않습니다.

## 서부 선택 루트 메타데이터 보강

`western_enrichment`는 Todo 7의 `selection_bytes()` JSON과 해당 루트의 전체 geometry/evidence manifest를 checksum으로 연결합니다. 선택된 generated 루트와 version이 빠진 상위 50개 legacy long route만 대상으로 하며 Supabase 업로드는 수행하지 않습니다.

```bash
PYTHONPATH=. uv run --with-requirements tools/curvature_pipeline/western_sources/requirements-western.lock \
  python -m tools.curvature_pipeline.western_enrichment \
  data/western-selection.json data/western-enrichment.json \
  --state-dir .pipeline-cache/western-enrichment \
  --output data/western-enrichment-receipt.json
```

실행기는 Overpass tile/version을 디스크 checkpoint로 재사용하고 겹치는 hub의 요청을 하나로 합칩니다. 동시 요청은 2개, 고유 tile은 120개, endpoint 시도는 tile당 최대 2회, 응답은 8 MiB, 요청 timeout은 12초와 남은 60분 batch deadline 중 더 짧은 값으로 제한됩니다. 빈 응답, highway context가 없는 응답, 잘못된 JSON, 초과 응답, quality/elevation version 누락은 성공으로 기록하지 않습니다. 첫 generated batch에 불완전한 route가 하나라도 있으면 receipt는 `NO_GO`와 nonzero exit를 반환합니다. fixture 옵션은 네트워크 없는 검증용이며 cache와 receipt는 Git에 추가하지 않습니다.

## 서부 결정론적 dry-run 감사 (Todo 9)

`western_audit_cli`는 acquisition→graph→generation→quality/selection→enrichment 전 단계를 `--no-upload` 전용으로 실행하고 사람이 검수할 수 있는 감사 번들을 남깁니다. Supabase/Mapbox/Overpass 네트워크 호출 코드 경로가 아예 없으며(enrichment는 canned fixture transport로만 실행), credential 없이 동작합니다.

```bash
# fixture 모드 (내장 AB/BC/SK 합성 hub, 네트워크·credential 불필요)
PYTHONPATH=. uv run --python 3.12 --no-project \
  --with-requirements tools/curvature_pipeline/western_sources/requirements-western.lock \
  python -m tools.curvature_pipeline.western_audit_cli \
  --mode fixture --snapshot 20260716 --output-dir /tmp/audit-out --no-upload

# real-hub 모드 (이미 취득된 checksum-pinned hub PBF를 로컬에서만 재검증)
PYTHONPATH=. uv run --python 3.12 --no-project \
  --with-requirements tools/curvature_pipeline/western_sources/requirements-western.lock \
  python -m tools.curvature_pipeline.western_audit_cli \
  --mode real-hub --snapshot 20260716 --output-dir /tmp/audit-real --no-upload \
  --manifest tools/curvature_pipeline/western_sources/manifests/western-2026-07-15.json \
  --checkpoint .pipeline-cache/western/outputs/acquisition-checkpoint.json \
  --pbf .pipeline-cache/western/outputs/sk-swift-current-cypress.osm.pbf \
  --hub-id sk-swift-current-cypress

# real-all 모드 (checkpoint가 완료로 표시한 모든 hub PBF를 한 pool로 실행)
PYTHONPATH=. uv run --python 3.12 --no-project \
  --with-requirements tools/curvature_pipeline/western_sources/requirements-western.lock \
  python -m tools.curvature_pipeline.western_audit_cli \
  --mode real-all --snapshot 20260717 --output-dir /tmp/audit-all --no-upload \
  --manifest tools/curvature_pipeline/western_sources/manifests/western-2026-07-15.json \
  --checkpoint .pipeline-cache/western/outputs/acquisition-checkpoint.json \
  --pbf-dir .pipeline-cache/western/outputs

# 위 real-hub/real-all에 --seed-source real을 붙이면 Todo 6 프로덕션 seed 추출로 실행
#   (western_seeds.extract_native_seed_batches → generate_native_routes, hub당 최대 25 candidate)
```

`--seed-source`는 real-hub/real-all 전용입니다. 기본값 `simplified`는 기존 3-window 파이프라인 무결성 seam(hub당 candidate 최대 1개)을 그대로 유지하고, `real`은 Todo 6 프로덕션 seed 추출을 checksum-pinned hub graph에서 직접 실행합니다(0.3–4 km curvature seed fragment → hub당 최대 25개 candidate route, 플랜 Todo 7의 hub당 25개 상한과 일치). candidate 조립은 결정성을 유지한 채 (unchanged) 품질 게이트를 통과할 확률을 높이는 방향으로 동작합니다: residential/service 비중이 낮은 seed를 우선 시작점으로 선택하고, connector 탐색은 실제 거리 12 km 규칙을 그대로 지키면서 residential edge에 비용 페널티(×4)를 적용하며, 이미 사용한 물리 구간의 반대 방향 차선으로 U턴하는 connector를 금지하고, 15 km에 도달한 뒤에도 잠정 residential 노출이 15% 게이트를 넘을 경우 노출을 낮추는 seed로만 한정 연장(최대 24회, 총 79.9 km 이내)합니다. 전방 연장이 막히면 head 쪽(역방향) 연장을 시도해 route_too_short 손실을 줄입니다. 이 모든 것은 게이트 이전(generation) 단계의 개선이며 quality gate·Todo 7 선택 로직 자체는 바이트 단위로 동일하게 적용됩니다. 두 모드 모두 네트워크·credential·wall clock·randomness 없이 graph의 순수 함수입니다. `real` 모드에서는 hub별 seed 정산이 `seeds_in = consumed + rejected_starts + seeds_unused`로 `funnel.json`에 기록되고, generation 단계에도 per-hub RSS/elapsed 안전판이 적용되어 예산을 초과한 hub는 `hub_failures`에 명시적으로 기록된 뒤 pool에서 제외됩니다. `manifest.json`은 `seed_source` 값을 그대로 담습니다.

real-all 모드는 `--pbf-dir` 안의 `<hub_id>.osm.pbf`를 hub ID 정렬 순서로 전부 로드하고(`--hub-id`를 반복 지정하면 부분 집합만), quality gate·overlap dedupe·Todo 7 pilot/expansion 선택은 hub별이 아니라 **합쳐진 pool 전체**에 적용합니다. 로드/검증/예산에 실패한 hub는 조용히 빠지지 않고 `funnel.json`·`manifest.json`의 `hub_failures`에 hub별 사유로 기록됩니다. hub 하나가 병리적으로 커지는 경우를 위한 per-hub 안전판은 `--max-hub-peak-rss-bytes`(기본 4 GiB, hub별 RSS 증가분 기준)와 `--max-hub-elapsed-seconds`(기본 900초)이며, 관측된 수치는 결정적 artifact가 아니라 `resource_metrics.json`의 `per_hub` 항목에만 기록됩니다.

출력 번들: `manifest.json`(전체 artifact sha256 + bundle checksum), `accepted_routes.geojson`, `rejected.csv`/`rejected.json`(단계·사유별), `funnel.json`(hub별 in=accepted+rejected 정합), `overlap_matrix.json`, `resource_metrics.json`(peak RSS, 단계별 elapsed), `samples/*.geojson`(고정 seed `--seed`, 기본 20260716로 뽑은 검수용 geometry). 모든 결정적 artifact는 같은 source checksum에서 byte-identical하게 재현되며, 시각은 입력 데이터나 `--snapshot` 라벨에서만 옵니다.

exit code: `0` READY, `2` PBF checksum 불일치, `3` 품질/할당 미달(`NO_GO_INSUFFICIENT_QUALITY` — Saskatchewan처럼 sparse한 지역을 저품질 루트로 채우지 않고 그대로 no-go 처리), `4` enrichment 불완전, `5` 리소스 예산 초과. 모든 no-go에서도 진단 artifact는 유지됩니다. bounded fixture는 120–250 production quota를 만족할 수 없으므로 exit 3이 정상 기대값입니다.

## 환경 변수

- `SUPABASE_URL`
- `SUPABASE_SERVICE_KEY`

## 노드 형식

입출력 모두 `{"lat": ..., "lng": ...}` 형식을 사용합니다.

## 곡률 정의

- 연속 3점의 bearing 차이를 사용합니다.
- `tight_curve_km`: `>= 200 deg/km`
- `medium_curve_km`: `>= 20 deg/km`
- `winding_score`: `curvature_density * sqrt(distance_km)`

## 후속 데이터 품질 계획

현재 파이프라인은 `fun + flow + penalty` 구조입니다. stop-control enrichment를 수행하면
실제 드라이브 흐름이 좋은 루트가 더 높은 `route_rank_score`를 받습니다.

지역 배치 실행은 `regions.json`을 사용하며, 각 배치는:

- Supabase `find_curvy_roads()`로 후보 추출
- `stop_control_version` 메타데이터로 증분 skip
- `context_version` 메타데이터로 road/surface/speed/POI context 증분 skip
- `quality_version` 메타데이터로 quality/character/explanation 증분 skip
- 타일 캐시 재사용
- 새 stop-control 또는 quality 메타데이터가 필요한 루트만 업로드

형태로 동작합니다.

추가 예정 필드:

- `stop_sign_count`
- `traffic_signal_count`
- `stop_control_density`
- `flow_score`
- `residential_ratio`
- `service_ratio`
- `local_road_ratio`
- `intersection_density`
- `building_density`
- `housing_proximity_score`
- `urban_friction_score`
- `residential_penalty`
- `road_names`
- `surface_summary`
- `speed_limit_summary`
- `nearby_pois`
- `route_context`
- `elevation_profile`

설계 문서:

- `docs/routefinder/2026-04-14-stop-control-data-plan.md`
- `docs/routefinder/2026-04-15-residential-penalty-plan.md`
