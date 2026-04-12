# Curvature Pipeline

REVV용 사전 계산 와인딩 도로 파이프라인입니다.

## 구성

- `download_kmz.py`
  - roadcurvature.com에서 `c_300` KMZ 링크를 찾아 다운로드합니다.
- `parse_kml.py`
  - KMZ를 풀고 KML Placemark를 추출합니다.
- `process_roads.py`
  - 노드 다운샘플링, 중심점, 거리, 곡률 프로파일, winding score, 안정적 ID를 계산합니다.
- `upload_to_supabase.py`
  - 분석 결과를 Supabase `curvy_roads` 테이블에 upsert합니다.

## 설치

```bash
pip install -r tools/curvature_pipeline/requirements.txt
```

## 사용 예시

```bash
python tools/curvature_pipeline/download_kmz.py -o data/kmz
python tools/curvature_pipeline/parse_kml.py data/kmz/sample.kmz -o data/sample.json
python tools/curvature_pipeline/process_roads.py data/sample.json -o data/analyzed.json
SUPABASE_URL=... SUPABASE_SERVICE_KEY=... python tools/curvature_pipeline/upload_to_supabase.py data/analyzed.json
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
