# Calimoto 티어다운 — 루트 생성 아키텍처 (2026-08-02)

> 대상: `calimoto - Motorcycle Navigation` **v2026.07.5** APK 161MB (3,340 파일) 정적 분석.
> 분석자: Claude(문자열·호스트) + Codex(DEX·AXML·리소스).
> 선행 문서: [2026-04-16-calimoto-summary.md](2026-04-16-calimoto-summary.md) (공개 정보 기반),
> [2026-08-02-rods-teardown.md](2026-08-02-rods-teardown.md) (같은 방식의 Rods 분석)
>
> **표기**: `[확인]` = 파일에서 직접 관측, `[추론]` = 근거 있는 해석.
>
> **법적 경계**: 곡률 스코어링 수식·가중치·임계 상수는 **분석하지도 기록하지도 않았다.**
> 아키텍처와 데이터 흐름만 취했다. REVV는 동일 수치를 자체 DB 실측으로 독립 도출 중이다.
> 앱 코어는 R8 난독화가 강해 실질 구현 클래스 다수가 짧은 식별자로 축약돼 있다.

---

## 0. 한 줄 요약

Calimoto의 강점은 **곡률 알고리즘이 아니라 제품 구조**다 — 라우팅 프로필 / 회피 제약 /
경유지 / 라운드트립 생성 / 결과 시각화를 **분리된 축**으로 두고 각각을 사용자에게
노출한다. 우리는 이 전부를 단일 추천 점수 하나로 뭉쳐놓고 있다.

---

## 1. 루트 생성 아키텍처 `[확인]`

**GraphHopper가 APK에 번들되어 있다.** `com/graphhopper/routing/lm/calimoto-map.geo.json`,
`com/graphhopper/version`, `libmapsforge_converter.so`(오프라인 벡터 지도).
`routing/lm`은 Landmark 계열 경로 탐색 경로다.

동시에 **서버 라우팅 엔드포인트도 존재한다** `[확인]`:

```
/routingRoute?              A→B 경로
/routingRoundTrip?          라운드트립 생성
/getIntoRoute?              현재 위치 → 경로 합류
/convertTrackToRoute?       GPX 트랙 → 도로 경로 변환
/suggestOfflineMaps         필요한 오프라인 지도 추천
/determineTrackRegionCodes? 트랙이 걸친 지역 판정
/v1/groupRide/...           그룹 라이딩
/v1/staticmap/...           정적 지도 이미지
```

**해석 `[추론]`**: 온디바이스 GraphHopper(오프라인)와 서버 라우팅을 **둘 다** 갖고
상황에 따라 쓴다. 다운로드 지도 유무에 따른 실제 분기는 난독화로 복원하지 못했다.

### 3사 비교 — 계산을 어디서 하는가

| | 방식 | 오프라인 |
|---|---|---|
| **Calimoto** | GraphHopper **온디바이스** + 서버 라우팅 병행 | 지역 벡터 지도 다운로드 |
| **Rods** | **서버 전처리** → 지역 SQLite(.gz) 배포 | 사전 계산된 pace_notes 조회 |
| **REVV** | Overpass + Supabase 저장 루트 | 마지막 검색 결과 캐시만 |

---

## 2. 루트 생성 입력 축 `[확인]`

우리에게 가장 중요한 부분이다.

### 라운드트립 (자동 생성)
```
round_trip_length              길이
round_trip_direction           방향        ← 사용자가 지정
round_trip_figure              형상        ← 우리에게 없는 축
round_trip_sightseeing_toggle  관광 경유 포함 여부
```

### 라우팅 프로필 `[확인]`
`Twisty`, `Winding`, 빠른 길 계열 — **곡률 선호를 단계로 노출**한다.

### 회피 제약 `[확인]`
페리 · 유료도로 · 고속도로 · 폐쇄도로 (폐쇄도로는 자동 회피 + 재조정)

### 기타
- 경유지 "intelligent" 배치, 다음 경유지 건너뛰기
- GPX import/export, ITN·KML 내보내기, 기존 트랙 → 도로 경로 변환
- 경로 주변 POI: **곡률 POI**, 트위스티 하이라이트, 도로 사진, 주유소

**REVV 대비 `[추론]`**: 우리 플래너 입력은 **(출발지 + 시간 예산)** 뿐이다.
저쪽은 방향·형상·곡률 강도·테마·회피 조건을 사용자가 직접 고른다.
특히 `round_trip_direction`은 우리 `AF-free-roam-mode` 플랜이 8방위 버킷에서
*시스템이 골라주는* 것과 정반대다 — 사용자가 고르면 의도를 추측할 필요가 없다.

---

## 3. 운영 구조 `[확인]`

### Foreground service 3종 + 2종
```
ServiceLocationNavigation      내비게이션
ServiceLocationTracking        주행 기록
ServiceLocationPausedDriving   주행 일시정지 전용   ← 별도 서비스
ServiceDownload / ServiceMoveMaps   (special-use)
```

**`ACCESS_BACKGROUND_LOCATION`이 없다** `[확인]`. 백그라운드 위치를 권한이 아니라
**위치형 foreground service로만** 처리한다.

**해석 `[추론]`**: 스토어 심사와 권한 마찰을 피하는 방식이다. REVV도 참고할 만하다.
그리고 "주행 일시정지"를 별도 서비스로 둔 것은 우리 `run_session`에 없는 개념이다.

### Android Auto `[확인]`
`CarAppService` exported + AndroidX Car App `NAVIGATION` 카테고리 + `geo:` intent.
(Rods는 CarPlay, Calimoto는 Android Auto — 둘 다 차량 연동이 1급이다.)

### 스택
Mapbox(지도) · GraphHopper(라우팅) · Mapsforge(오프라인) · **Parse Platform**(백엔드) ·
Firebase Auth/Analytics/Crashlytics/Remote Config · Google/Facebook 로그인 ·
Mixpanel + CleverTap + AppsFlyer · Google Play Billing

---

## 4. 과금 경계 — 여기가 제일 배울 점 `[확인]`

**Premium 전용**: 내비게이션 · 트래킹 · 오프라인 지도 · 파일 내보내기 ·
계획한 라이드 내비게이션. 연간 전용으로 파트너 할인.

구독 종류: 주간 · 연간 · **시즌 패스** · **평생 이용권** · 체험 Premium.
무료 지역 개념이 있고, 무료 지역은 국경을 넘는 경로 계산에 제약이 있다.

**해석 `[추론]`**: **"계획은 무료, 주행은 유료"** 다. 루트를 만들어보는 것까지는
공짜로 열어두고 실제로 그 길을 달릴 때 과금한다. 첫 가치를 먼저 주고 결제를
뒤로 미루는 구조다.

### 3사 과금 비교

| | 무료로 되는 것 | 과금 지점 |
|---|---|---|
| **Calimoto** | 루트 계획, 지도 보기 | 내비게이션·트래킹·오프라인 |
| **Rods** | (14일 체험 후) 사실상 없음 | 첫 주행 전에 페이월 |
| **REVV** | 미정 | 미정 |

**Rods는 첫 성공 경험 전에 결제를 요구하고 그 지점에서 이탈을 겪는다**
(리뷰 + `Free Roam Abandoned During Voice Pack Wait` 이벤트).
**Calimoto는 반대로 간다.** 우리는 Calimoto 쪽이 맞다.

---

## 5. 커뮤니티 / 소셜 `[확인]`

- 공개 라이드 발행·검색·지역 피드·익명화·공유 링크 (`calimoto.com/calimotour/r-`, `/t-`)
- 그룹 라이딩: 초대 링크/QR, 실시간 위치 공유, 동기화된 계획 경로, 구성원 관리
- 홈 화면 위젯 2종

**REVV 관련 `[추론]`**: 그룹 라이딩의 실시간 위치 공유는 우리 워키토키와 인접 영역이다.
다만 저쪽도 이건 생성 엔진이 아니라 **재방문 장치**로 붙인 것이다 — 순서상 우리도
자체 추천 루트의 저장·공유·재주행 루프가 먼저다.

---

## 6. REVV 액션

### 지금 판단이 필요한 것 (출시 전)
1. **과금 경계** — Calimoto 방식("계획 무료, 주행 유료")을 기본안으로 삼는다.
   Rods가 실패한 지점을 피하는 가장 검증된 형태다. 코드가 아니라 결정 사항.
2. **백그라운드 위치를 foreground service로만** 처리 — `ACCESS_BACKGROUND_LOCATION`
   없이 간다. 심사 마찰이 줄고, 저쪽 두 곳 다 이 방식이다.

### 출시 후
3. **플래너 입력 축 분리.** 지금 단일 추천 점수로 뭉쳐 있는 것을
   `프로필(곡률 강도) / 회피 제약 / 방향 / 길이 / 테마`로 쪼갠다. 실험과 개인화가
   가능해지고, "왜 이 루트인지" 설명도 가능해진다.
4. **라운드트립을 목적지 경로의 변형으로 만들지 마라.** 별도 생성·검증 경로로 두고
   중복 구간·되돌아감·주행 가능성을 독립 검증한다. (현행 `AF-free-roam-mode` 플랜 재검토)
5. `round_trip_direction` — 방향을 시스템이 추측하지 말고 사용자가 고르게 한다.
6. 곡률 POI / 트위스티 하이라이트 — 내부 점수와 별개로 **사용자에게 보이는 설명 레이어**.
7. 주행 일시정지를 1급 상태로 (`ServiceLocationPausedDriving` 상당).
8. Android Auto / CarPlay.

### 하지 말 것
- 오프라인 라우팅을 흉내내는 것. 저쪽은 GraphHopper + Mapsforge + 지역 카탈로그 +
  무결성 + 저장소 이동 + 국경 처리까지 갖춘 **운영 제품**이다. 우리가 지금 손댈 규모가 아니다.
- 커뮤니티/그룹 기능을 추천 엔진보다 먼저 붙이는 것.

---

## 7. 확인하지 못한 것

- **R8 난독화가 강하다.** `calculateRouteUseCase` 같은 일부 Kotlin 심볼은 남았으나
  실질 구현 클래스 다수는 짧은 식별자로 축약됐다. 곡률 루트 생성의 **내부 단계**는
  복원하지 못했다 — 위 2장은 리소스 문자열·API 경로 기반이다.
- 오프라인 지도 보유 상태에서 온디바이스 GraphHopper와 서버 라우팅 중 무엇이 실제로
  실행되는지의 콜 그래프.
- API 경로와 호스트의 정확한 결합 일부(이름 기반 추정 포함).
- 시간이 자동 경로 생성의 직접 예산 입력인지 여부.
- 도로 표면·오프로드 문자열이 회피 조건으로 연결되는지.
- 로그인 후 기능 플래그, 무료/유료 세부 권한, 실제 네트워크 트래픽.
- `aapt`/`jadx`/`apktool` 없이 바이너리 AXML 직접 파싱으로 수행.
