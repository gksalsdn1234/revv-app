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
- `upload_to_supabase.py`
  - 분석 결과를 Supabase `curvy_roads` 테이블에 upsert합니다.
  - 추천 필드(`fun_score`, `flow_score`, `driveability_penalty`, `road_class_bucket`)까지 함께 적재합니다.
- `enrich_region_batch.py`
  - 지역별 `top-N` 후보를 Supabase에서 읽고, 이미 enrich된 루트는 건너뛴 뒤 새 루트만 stop-control enrichment와 업로드를 수행합니다.
- `residential_metadata.py`
  - 주거지/로컬도로 성격 데이터를 바탕으로 `urban_friction_score`와 `residential_penalty`를 계산하는 보조 레이어입니다.
- `regions.json`
  - 도시권 배치 설정 파일입니다.

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
SUPABASE_URL=... SUPABASE_SERVICE_KEY=... python tools/curvature_pipeline/upload_to_supabase.py data/analyzed.enriched.json
python tools/curvature_pipeline/enrich_region_batch.py --region montreal
```

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

설계 문서:

- `docs/routefinder/2026-04-14-stop-control-data-plan.md`
- `docs/routefinder/2026-04-15-residential-penalty-plan.md`
