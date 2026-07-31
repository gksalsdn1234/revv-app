# 설계 — 커브 필드 히트맵 (캐나다 한정)

작성 2026-07-30. 실측 기준은 이 세션의 Supabase 쿼리와 코드 확인 결과.
한국 지역은 서비스 대상이 아니므로 전 범위에서 제외한다.

## 결론 먼저

**새로 만들 것이 거의 없다.** 렌더러는 앱에 이미 있고, 데이터는 Supabase에
이미 캐나다 전역으로 들어가 있다. 둘이 연결만 안 돼 있다.

- `map_widget.dart:1657` `_drawCurveFieldHeatmap()` — 3버킷 색상 · glow/core
  2중 라인 레이어 · strong 모드까지 **구현 완료**
- `lean_route_finder_screen.dart` 가 그 렌더러에 `curveHeatmapPolylines: const []`
  을 넘긴다 — **빈 배열**. 그래서 아무것도 안 그려진다
- `curvy_roads` 테이블에 **83,232행 / 노드 280만 개**가 캐나다 13개 주 전역으로
  이미 적재돼 있다

즉 Phase 1은 기능 개발이 아니라 **배선**이다.

## 실측 현황

### 앱 쪽 (코드 확인)

| 요소 | 상태 |
|---|---|
| `_drawCurveFieldHeatmap(List<List<LatLng>>)` | 구현됨. 입력 폴리라인을 순회하며 노드별 `bearingDiff/dist`로 버킷 1~3 산출 후 GeoJSON 소스 3개 생성 |
| 버킷 색 | 3=`#FF2E38` · 2=`#FF7A1A` · 1=`#FFE94A` |
| `strongCurveFieldHeatmap` | 불투명도·선폭 강화 모드. 파인더의 `_curveRoadView`에 이미 연결됨 |
| 입력 데이터 | **없음** (`const []`) |

버킷 계산이 **클라이언트에서** 일어난다는 점이 중요하다. 서버는 원시 노드만
주면 되고 위젯 계약(`List<List<LatLng>>`)을 바꿀 필요가 없다.

### 데이터 쪽 (Supabase `curvy_roads`, 실측)

| 항목 | 값 |
|---|---|
| 전체 행 | **83,232** |
| 전체 노드 | **2,800,735** |
| `nodes` jsonb 총량 | **59 MB** (행당 평균 743 B) |
| 테이블 총 크기 | 339 MB |
| 지오메트리 보유 | `nodes` · `route_line` **전 행 보유** |
| `activated_at` 설정 | **24행뿐** |

주별 분포 (상위):

| 주 | 행 | 총 km | 평균 곡률 |
|---|---:|---:|---:|
| ON | 27,194 | 25,737 | 530 |
| QC | 15,827 | 19,898 | 554 |
| **BC** | 14,037 | 21,848 | **758** |
| AB | 10,836 | 8,688 | 499 |
| NS | 4,016 | 9,189 | 740 |
| 기타 9개 주/준주 | 11,322 | 14,006 | — |

품질 라벨 분포:

| `quality_label` | 행 | 평균 길이 | 평균 곡률 |
|---|---:|---:|---:|
| `''` (미보강) | **82,657** | 1.2 km | 577 |
| `maybe` | 238 | 6.1 km | 1,456 |
| `reject` | 180 | 6.1 km | 1,021 |
| `keep` | 157 | 7.6 km | 1,676 |

**이 표가 이 설계의 핵심 근거다.** 82,657행은 평균 1.2km짜리 조각이라
"루트"로는 쓸 수 없어 파인더가 거의 다 걸러낸다. 그런데 히트맵은 정확히
그런 물건이다 — 짧은 조각 수만 개를 곡률로 칠한 것. **파인더에게 쓰레기인
데이터가 히트맵에게는 완성품이다.** 추가 보강 없이 지금 그대로 쓸 수 있다.

## 한국 msgpack 경로를 버리는 이유

이전에 `kr_curvature.msgpack`(181MB, 129만 세그먼트) 이식을 제안했으나 철회한다.

1. 한국은 서비스 대상이 아니다
2. 캐나다 데이터가 이미 **더 나은 형태**로 존재한다 — 서버에 있고(앱 용량 0),
   PostGIS 인덱스가 걸려 있고(`route_line`), 앱이 이미 이 테이블과 통신 중이다
3. msgpack 경로는 변환·번들·갱신 파이프라인을 새로 만들어야 한다

KR msgpack은 Threads 홍보 이미지 자산으로만 유지한다.

## 설계

### Phase 1 — 배선 (반나절)

목표: 파인더 지도에 곡률 히트맵이 실제로 뜬다.

**서버** — 새 RPC `curve_field_in_bbox`

```sql
create or replace function curve_field_in_bbox(
  min_lat double precision, min_lng double precision,
  max_lat double precision, max_lng double precision,
  min_curvature double precision default 400,
  max_rows integer default 600
) returns table (id text, nodes jsonb)
language sql stable security definer set search_path = public as $$
  select c.id, c.nodes
  from curvy_roads c
  where c.center_lat between min_lat and max_lat
    and c.center_lng between min_lng and max_lng
    and c.curvature_score >= min_curvature
  order by c.curvature_score desc
  limit max_rows;
$$;
```

- `max_rows` 상한이 페이로드 폭주 방지장치다. 곡률 내림차순이므로 잘려도
  **가장 굽은 길부터 남는다**
- 기존 `find_curvy_roads`와 별개 함수로 둔다. 그쪽은 루트 추천용이고 품질
  필터가 걸려 있어 히트맵에 쓰면 157행밖에 안 나온다
- RLS: 익명 읽기 허용 (기존 `curvy_roads` 정책과 동일 수준). 보안 인벤토리
  등록 필요 — `96971c8` 커밋이 남긴 전례를 따를 것

**앱**

1. `SupabaseService`에 `fetchCurveField(bbox)` 추가 → `List<List<LatLng>>` 반환
2. 파인더에 `_curveFieldPolylines` 상태 추가. 카메라 이동 디바운스
   (`_cameraDebounce` 이미 있음)에 묶어 bbox 변경 시 재조회
3. `curveHeatmapPolylines: const []` → `_curveFieldPolylines`
4. 줌 임계값 아래(z < 9)에서는 조회 생략 — 광역 뷰는 Phase 2에서 처리

**페이로드 추산** (⚠️ 뷰포트 실측 쿼리는 커넥터 장애로 못 돌림 — 아래는 추정)
행당 노드 JSON 평균 743B 기준, `max_rows=600`이면 원시 약 **450KB**,
HTTP gzip 후 **100~150KB** 수준으로 예상. 모바일 1회 조회로 허용 범위.
**Phase 1 착수 시 실제 뷰포트로 이 수치부터 재보라.**

### Phase 2 — 줌 LOD (2~3일)

Phase 1은 z≥9에서만 동작한다. 줌아웃했을 때 "주 전체가 빛나는" 그림이
이 기능의 실제 값어치이므로 여기가 진짜 작업이다.

| 줌 | 소스 | 형태 |
|---|---|---|
| z ≤ 8 | 사전 집계 격자 | 0.02° 셀 단위 평균 곡률. 머티리얼라이즈드 뷰 `curve_field_grid`. 캐나다 전역이라도 셀 수만 개 수준 → 한 번에 전송 가능 |
| z 9–11 | `ST_Simplify(route_line, ~50m)` | 조각 수 유지, 노드 수 대폭 감소 |
| z ≥ 12 | 원시 `nodes` | Phase 1 경로 그대로 |

z≤8 격자는 **앱 에셋으로 번들해도 된다** — 캐나다 전역 격자는 수백 KB
수준이고 도로는 잘 안 변한다. 그러면 첫 실행에 네트워크 없이도 지도가
빛난다. 첫인상 문제까지 같이 풀린다.

### Phase 3 — 달린 길 vs 안 달린 길 (1~2일)

**재방문 이유는 여기서 생긴다.** Phase 1·2만으로는 예쁜 지도일 뿐이다.

재료가 이미 다 있다:
- `driven_routes_service` — 주행한 루트 기록 중
- `lean_route_finder_screen`의 `_drivenGlowPolylines()` — 이미 달린 길을
  빛나게 그림 (단 로컬 클러스터 범위)
- `route_geometry_matcher` — 주행 궤적을 루트에 매칭

할 일: 히트맵 렌더 시 `driven_routes`와 교차하는 세그먼트를 **다른 레이어로
분리**해 "달린 길"은 채도를 죽이거나 별도 색으로 칠한다. 그러면 지도가
자동으로 이렇게 읽힌다 — *아직 안 칠한 도로가 이만큼 남았다.*

이게 히스토리 탭의 `RUNS / KM TOTAL` 숫자가 못 하는 일이다. 숫자는 쌓이기만
하지만 지도는 **비어 있는 곳을 보여준다.**

## 안 하는 것

- 한국 데이터 이식
- `quality_label` 보강 파이프라인을 82,657행에 돌리기 — 히트맵에 불필요
- 새 곡률 계산 — `curvature_score`가 이미 전 행에 있음
- 벡터 타일 서버(Tegola/Martin 등) 도입 — 이 규모에 과함. RPC + bbox로 충분

## 리스크

| 리스크 | 대응 |
|---|---|
| 페이로드 폭주 | `max_rows` 상한 + 곡률 내림차순. 실측 후 조정 |
| 지도 레이어 과다 → 렌더 끊김 | 이미 버킷당 2레이어(glow/core) 구조라 총 6레이어 고정. 세그먼트 수가 변수이므로 Phase 1에서 실기기 FPS 확인 |
| 카메라 이동 때마다 조회 | 기존 `_cameraDebounce` 재사용. bbox가 이전 조회 범위 안이면 스킵 |
| 출시 일정 침범 | **Phase 1~3 전부 v1.1 이후.** 현재 제출 준비 상태를 건드리지 않는다 |

## 순서 제안

출시 먼저, 그다음 이 설계. Phase 1은 반나절이라 출시 후 첫 업데이트로
바로 낼 수 있고, Phase 3까지 가야 "왜 또 여는지"에 대한 답이 된다.
