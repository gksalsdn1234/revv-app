# Rods 티어다운 — 아키텍처·제품 분석 (2026-08-02)

> 대상: `Rods - Pocket Co-driver` **v1.8.10** (`com.rods.app` / iOS `com.driverods.app`),
> 개발사 **Buildrhaus, MB** (리투아니아 소기업 형태). APKPure XAPK 161MB 정적 분석.
> 분석자: Claude(번들 문자열·구조) + Codex(DEX·AXML·리소스), 교차 검증.
>
> **표기 규칙** — `[확인]`은 파일에서 직접 관측된 사실, `[추론]`은 근거 있는 해석.
> 이 구분을 유지한 채 인용할 것. 추론을 사실로 승격시키지 말 것.
>
> **법적 경계**: Hermes 바이트코드(`assets/index.android.bundle`)의 로직·알고리즘·
> 곡률/등급/거리 **임계값은 분석하지도 기록하지도 않았다.** REVV는 동일 수치를
> 자체 DB 실측으로 독립 도출 중이며, 경쟁사 상수를 참조하면 그 작업이 오염된다.
> 후속 작업자도 이 선을 유지할 것. 저쪽 음성 리소스(mp3) 역시 사용 불가.

---

## 0. 한 줄 요약

Rods는 **우리보다 앞선 기술을 가진 회사가 아니라, 우리와 거의 같은 도구로
반 년 먼저 출발한 4~5인 팀**이다. 결정적 차이는 알고리즘이 아니라 **계산을
어디서 하느냐**다 — 저쪽은 서버에서 미리 갈아 지역 SQLite로 배포하고, 우리는
주행 중 온디바이스에서 계산하려 하고 있다.

---

## 1. 기술 스택 `[확인]`

| 층 | Rods | REVV |
|---|---|---|
| 앱 프레임워크 | React Native + Expo (Hermes, 신아키텍처) | Flutter |
| 지도 SDK | **Mapbox** maps 11.16.2 / common 24.16.2 | Mapbox |
| 백엔드 | **Supabase** (`ttoopygcilbkamuhqhfy.supabase.co`) + Edge Functions | **Supabase** |
| 자체 서버 | **`osm-api.driverods.com`** (`/v1/osm/query`, `/voice-packs/`) | 없음 |
| 도로 데이터 | OSM (Overpass `/api/interpreter`) | OSM (Overpass) |
| 고도 데이터 | **`api.opentopodata.org`** (`/v1/srtm30m`, `/v1/eudem25m`) + `SLOPE_FACTOR` | **없음** |
| 로컬 저장 | SQLite (expo-sqlite) | shared_preferences + Supabase |
| 결제 | RevenueCat + Stripe + Paddle | 미정 |
| 분석 | **Mixpanel** + AppsFlyer + Sentry | Sentry |
| 인증 | Apple / Google / Face ID + secure-store | Supabase 익명 |
| 차량 연동 | **CarPlay** (계기판 포함) | 없음 |

**스택이 겹친다는 게 핵심이다.** Supabase·Mapbox·OSM이 동일하다. 넘을 수 없는
격차가 아니라 **순서 차이**다.

---

## 2. 아키텍처 — 가장 중요한 발견

### 2-1. 페이스노트는 미리 계산해서 저장한다 `[확인]`

온디바이스 SQLite가 **두 층**으로 분리돼 있다.

**(A) 앱 Route DB** — 사용자 데이터
| 테이블 | 내용 |
|---|---|
| `routes` | 경로 ID·이름, 시작/끝 좌표, waypoint·geometry JSON, 거리·예상시간, 상태·오류, 다운로드 시각, roundabout/traffic-calming/표면 캐시, 버전 |
| **`pace_notes`** | `id`, `route_id`, **순서**, **전체 페이스노트 JSON**. route 삭제 시 cascade |
| `drive_history` | 경로 참조, 주행 시각, 거리·시간, 실제 거리, reroute 여부 |
| `gps_recordings` | 원시 recording JSON |

**(B) 다운로드 지역 DB** — 서버가 사전 생성해 배포
| 테이블 | 내용 |
|---|---|
| `road_ways` | 도로 등급·표면·이름·일방통행·접근·교차로·**제한속도**·OSM ID·좌표·**bbox** |
| `road_surfaces` | 표면 종류, 좌표 JSON, bbox |
| `traffic_calming` | 위치·유형·구간 끝점·OSM way ID·태그 |
| `roundabouts` | 위치·**반경**·유형 |
| `built_up_areas` | 유형 + bbox |
| `speed_cache` | 속도값·수집 시각·좌표·bbox |
| `metadata` | key/value |

배포 방식 `[확인]`: **`downloadRegionSqlite`**, **`.sqlite.gz`**, 무결성 검사,
손상 DB 격리 후 재다운로드. 모든 지역 테이블에 **bounding-box 인덱스**.

**해석 `[추론]`**: 서버가 지역 단위로 OSM을 전처리해 압축 SQLite로 배포하고,
앱은 주행 중 **조회만** 한다. `pace_notes`가 JSON 컬럼으로 저장된다는 것은
곡률 계산이 주행 시점이 아니라 **경로 생성 시점(또는 서버)** 에 끝난다는 뜻이다.

### 2-2. "이미 루트가 있는 게 아니다" `[추론]`

`road_ways`는 **루트 카탈로그가 아니라 도로 원본**이다. Rods는 루트 발견 앱이
아니므로 "좋은 코스 목록"을 가질 이유가 없다. 사용자가 경로를 만들거나 지역을
받으면 그때 처리한다.

**→ 여기가 REVV의 구조적 우위다.** 저쪽은 사용자가 어디를 달릴지 모르기 때문에
전처리를 미리 못 하고 요청마다 처리한다. **REVV는 `curvy_roads` 83,232행을 이미
갖고 있다** — 우리에게 전처리는 대상이 확정된 **유한한 배치 작업**이다.

---

## 3. 콜 어휘 체계 `[확인]`

`res/raw`에 mp3 **256개** = 125개짜리 **성우 보이스팩 2벌**(v1/v2). TTS 아님.

```
[into_]turn_[simple|advanced]_[등급]_[left|right]_[modifier]
```

- **simple**: easy / medium / hard  ·  **advanced**: 1/2/3/4 + `hairpin` + `square`
- **modifier**: `tightens` · `opens` · `long` · `very_long`
- 연결어 조각: `connector_into`, `connector_finish`, `connector_to_finish`
- `distance` 20종, `offroute_nosignal` **10종**(반복 피로 분산), `countdown` 계열
- **`keepalive_silence`** — 무음 파일

**해석 `[추론]`**: 문장을 조각으로 녹음해 실시간 조합한다. 사전 녹음 음질을
유지하면서 조합 폭발을 감당하는 방법. `tightens`/`opens`는 **반경 프로파일 없이
계산 불가** → 저쪽도 반경 기반이며 코너를 점이 아니라 구간으로 다룬다.

### REVV 대비 격차

| | REVV 현재 | Rods |
|---|---|---|
| 음성 | flutter_tts | 성우 2팩, 조각 조합 |
| 등급 | 4단계 | 6등급 + hairpin + square |
| modifier | 없음 | tightens / opens / long / very_long |
| 코너 길이 | 없음 | long / very_long |
| 반복 대응 | 없음 | 변형 다중화 |
| 고도·경사 | 없음 | SLOPE_FACTOR + DEM |

---

## 4. 오디오 — 실전 노하우 `[확인]`

커스텀 Expo 플러그인과 분석 이벤트가 저쪽이 무엇으로 고생했는지 그대로 드러낸다.

- `withAudioRouteDetector.js` — 오디오 출력 경로(블루투스/스피커/유선) 전환 감지
- `withCallStateDetector.js` — 통화 상태 감지
- `rods-audio` 자체 네이티브 모듈
- `keepalive_silence.mp3`
- 이벤트: **`audio_focus_failed`**, **`audio_countdown_native_failed`**

**해석 `[추론]`**: 음성 콜 앱의 진짜 난제는 곡률이 아니라 **"언제 어디로 소리를
낼 것인가"** 다. 실패를 분석 이벤트로 추적한다는 건 실제로 자주 깨졌다는 뜻이다.
**REVV는 셋 다 없다.** 실기기 테스트에서 반드시 만난다.

---

## 5. 제품 구조 `[확인]`

### 화면 (Expo Router)
- 탭: `/(tabs)/index`, `/routes`, `/settings`
- 경로: `/create-route`, `/route/[id]`, `/route/[id]/drive`, `/route/[id]/simulate`, `/route/processing`
- 주행: **`/free-roam`**, `/drive-settings`
- 온보딩 6단계: `welcome` → `vehicle-type` → `location-prompt` → `plan-route` → `pace-notes` → `free-roam-intro`
- 오프라인: `/settings/downloaded-regions`, `/settings/status`

### 과금 화면 **7종**
`/paywall`, `/one-time-offer`, `/extended-trial`, `/winback-offer`, `/upgrade`,
`/purchase-success`, `/subscription-expired`

딥링크: `/claim/extended-trial`, `/claim/winback-trial`, `/claim/winback-paid`, `/claim/yearly-upgrade`

가격: 14일 체험 → **월 $9.59 / 연 $29.90** (연간이 3개월치보다 싸다)

**해석 `[추론]`**: 윈백 경로가 2종(체험/유료), 월→연 업그레이드 전용 화면까지 있다.
**리텐션이 실제 문제**이며 연간 구독으로 이탈을 막으려 한다.

### 유입 — GPX/KML 임포트가 1급 `[확인]`
Android intentFilter로 `.gpx`/`.kml` 연결, iOS는 문서 타입 + 공유 익스텐션(`RodsShare`).
**해석 `[추론]`**: 루트 발견이 약한 것을 "남의 루트 끌어오기"로 메우는 전략.
저쪽 블로그가 "Calimoto로 찾고 Rods로 달려라"라고 쓴 것의 실제 구현.

### 저쪽이 아는 자기 병목 `[확인]`
분석 이벤트에 이런 게 있다:
- `Free Roam Voice Pack Wait Shown`
- **`Free Roam Abandoned During Voice Pack Wait`**

**해석 `[추론]`**: 보이스팩 다운로드 대기 중 이탈을 별도 이벤트로 센다 =
**그게 실제 이탈 지점**이라는 자백이다. 스토어 리뷰의 "루트 다 짜게 하고 계정
요구하고 그제서야 페이월" 불만과 같은 계열 — **저쪽의 온보딩은 무너져 있다.**

---

## 6. REVV 액션

### 즉시 (출시 전)
1. **오디오 3종 방어** — 오디오 라우트 전환 감지 / 통화 중 콜 중단 / keepalive.
   실기기에서 만나기 전에 넣는다. 저쪽은 이걸 네이티브 플러그인으로 짰다.
2. 진행 중인 `AZ2` 웨이브(신뢰도 게이트·반경 등급·캐싱·ttc)는 계속 간다 —
   서버로 옮기더라도 **곡률 로직 자체는 어디서 돌든 필요**하고 오프라인 폴백이 된다.

### 출시 후 — 우선순위 순
3. **서버 전처리로 이동 (최우선)**. `curvy_roads` 83,232행에 곡률·등급·신뢰도를
   미리 계산해 컬럼으로 저장. 이러면 지금 씨름하는 문제가 통째로 사라진다 —
   17.2ms 컴파일, 게이트 통과율, 캐시 무효화 전부 "주행 중 계산" 전제에서 나온 것이다.
   **우리는 대상이 확정돼 있어 저쪽보다 이걸 하기 쉽다.**
4. **성긴 지오메트리 보강 배치** — 실측상 세그먼트 16.4%가 60m 초과라 코너 상당수가
   `unknown`으로 침묵한다. Mapbox map matching을 서버 배치로 돌려 되살린다.
5. `tightens` / `opens` / 코너 길이 — 반경 배열을 이미 계산하는데 최소값만 쓰고
   버리는 중이라 거의 공짜.
6. 고도·경사(DEM) 축 — 저쪽은 쓰고 우리는 안 쓴다.
7. 음성 품질 (TTS → 성우). 조각 250개면 성우 하루치이나 3개 국어면 750개.
8. CarPlay.

### 하지 말 것
- 저쪽 mp3·카피·알고리즘 상수 사용 (저작권 + clean-room 오염)
- 루트 발견 축을 버리고 페이스노트 앱으로 전향하는 것 — **저쪽이 못 가진 게 그거다**

---

## 7. 포지셔닝

> **Rods는 길을 아는 사람을 위한 앱, REVV는 길을 찾는 사람을 위한 앱.**

저쪽 로드맵에 "Route creation & planning — coming soon"이 걸려 있다.
우리 해자 쪽으로 걸어오고 있으므로 **출시를 앞당길 이유는 되지만 범위를 넓힐
이유는 아니다.**

성숙도: App Store 4.4★ / 리뷰 54개, Android 2026-03 출시, versionCode 164 / iOS build 174.
**아직 초기다.** 지금은 따라잡을 수 있고 6개월 뒤엔 아니다.

---

## 8. 확인하지 못한 것

- 지역 `.sqlite` 실물(APK 미포함) → 용량·다운로드 URL 규칙·샘플 데이터 불명
- 저쪽 곡률 정확도의 **실제 품질** — 정적 분석으로는 판정 불가.
  **남은 유일한 검증 수단은 실주행 테스트**: 우리 DB에서 노드가 성긴 것으로
  확인된 구간에서 Rods를 달려보면 된다. 거기서도 헛소리를 하면 저쪽 역시
  같은 문제를 못 푼 것이고, 우리 `unknown` 침묵 결정이 더 정직한 처리가 된다.
- `RodsAudioFgsService`가 코드엔 있으나 매니페스트에 없음 — dead code 여부 불명
- 오디오 포커스 재시도 조건, 분석 이벤트 실제 발행 여부 (앱 미실행)
- `aapt`/`apkanalyzer`/`jadx` 없이 DEX·AXML·Hermes string table 직접 파싱으로 수행

## 9. 재현 방법

```
xapk 해제 → base/ (1,568 files) + config.arm64_v8a.apk
strings -n 5 base/assets/index.android.bundle   # Hermes v96, 문자열만
unzip -l xapk/config.arm64_v8a.apk | grep '\.so'
cat base/assets/app.config                       # 평문 JSON
unzip -l base.apk | grep res/raw                 # 보이스오버 파일명 체계
```
