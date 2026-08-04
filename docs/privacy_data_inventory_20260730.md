# 개인정보 수집 인벤토리 & App Store 개인정보 선언 (2026-07-30)

배포 전 점검. 아래는 전부 이 세션에서 **코드·Info.plist·Supabase 스키마·라이브
개인정보 처리방침을 직접 확인한 결과**다. 추정은 (추정)으로 표시했다.

## 판정 요약

**기본 설계는 좋다.** 익명 인증, 클라우드 업로드 기본 꺼짐, 앱 내 삭제 기능,
추적 없음. 개인정보 처리방침도 이미 있고 이중언어로 최신(2026-07-22)이다.

**단 실제 동작과 처리방침이 어긋난 곳이 6군데 있다.** 대부분 문구 수정이고,
하나(Google Fonts)는 코드 수정이 낫다.

## 1. 실제로 수집·전송되는 것 (실측)

| 데이터 | 어디서 | 어디로 | 기본값 | 근거 |
|---|---|---|---|---|
| 정밀 위치 (GPS) | `location_service` | 기기 내 · 옵트인 시 Supabase | **켜짐**(앱 기능 필수) | `NSLocationWhenInUseUsageDescription` |
| 주행 GPS 트레이스 (샘플 다수) | 주행 중 기록 | `run_details.telemetry_json` | **꺼짐** | `settings_service.dart:14` `_cloudRunStorageEnabled = false` |
| 주행 시작·종료 좌표 | 주행 저장 | `runs.start_lat/lng`, `end_lat/lng` | 꺼짐(위와 동일 토글) | Supabase 스키마 실측 |
| 속도 (최고·평균) | GPS 파생 | `runs.max_speed_kmh`, `avg_speed_kmh` | 꺼짐 | 스키마 실측 |
| 주행 거동 (급제동·급조향·G값) | IMU (`sensors_plus`) | `telemetry_summary` | 꺼짐 | 스키마 실측 |
| 익명 사용자 ID | Supabase 익명 인증 | 모든 테이블 `user_id` | 켜짐 | `supabase_service.dart:124` `signInAnonymously()` |
| 루트 피드백 | 사용자 입력 | `route_feedback` | 사용자 행동 시 | 스키마 실측 |
| 검색어 + 근접 위치 | 목적지 검색창 | **Mapbox 지오코딩 API 직접 호출** | 사용자 입력 시 | `place_search_service.dart:64` |
| 좌표 (날씨용) | 현재 위치 | Supabase Edge Function → OpenWeatherMap | 켜짐 | `weather_service.dart:23`, 응답 구조가 OWM 포맷 |
| 지도 타일 요청 | 지도 표시 | Mapbox | 켜짐 | `mapbox_maps_flutter` |
| 도로 데이터 쿼리 (bbox) | 루트 탐색 | Overpass API 3개 미러 | 켜짐 | `overpass-api.de` · `overpass.kumi.systems` · `overpass.osm.ch` |
| 폰트 요청 (기기 IP) | 앱 실행 시 | **Google 폰트 서버** | 켜짐 | `text_styles.dart` `GoogleFonts.inter/archivo/rajdhani` + 번들 폰트 없음 |

**수집하지 않는 것 (확인됨)**: 이름·이메일·전화번호·결제정보·연락처·광고 식별자.
계정은 익명 UUID뿐이다. `NSPrivacyTracking = false`, 추적 도메인 없음.

**크래시 리포팅은 현재 꺼져 있다.** `crash_reporting.dart:9`
`kReleaseMode && _sentryDsn.isNotEmpty` 조건인데 `.env`에 `SENTRY_DSN`이 없다.
즉 문서화된 빌드 명령으로 만들면 **Sentry는 아무것도 전송하지 않는다.**

## 2. 제3자 수신자

| 수신자 | 받는 것 | 처리방침 기재 |
|---|---|---|
| Supabase | 주행 기록·텔레메트리·피드백 (옵트인 시) | ✅ 기재됨 |
| Mapbox | 지도 타일 요청, **검색어+위치**, 기기 IP | ⚠️ "지도 표시"로만 기재 — 검색/지오코딩 누락 |
| Google Maps / Waze | 사용자가 외부 내비 선택 시 좌표 | ✅ 기재됨 (상세히) |
| **Google (폰트 서버)** | 앱 실행 시 기기 IP | ❌ **미기재** |
| **Overpass / OpenStreetMap** | 위치 기반 bbox 쿼리 | ❌ **미기재** |
| **OpenWeatherMap** | 좌표 (Supabase 서버 경유, 기기 IP는 미노출) | ❌ **미기재** |
| Sentry | (현재 비활성) | — |

## 3. App Store Connect "앱 개인정보" 답변표 — 그대로 입력

전부 **추적 안 함 / 사용자에 연결됨 / 목적: 앱 기능**. 옵트인 항목도 Apple 기준상
"수집"으로 선언해야 한다(선택적 수집도 수집).

| 카테고리 | 항목 | 수집 | 연결 | 추적 | 목적 |
|---|---|---|---|---|---|
| Location | **Precise Location** | 예 | 예 | 아니오 | App Functionality |
| Location | Coarse Location | 예 | 예 | 아니오 | App Functionality |
| Identifiers | **User ID** | 예 | 예 | 아니오 | App Functionality |
| Usage Data | Product Interaction | 예 | 예 | 아니오 | App Functionality, Analytics |
| **Search History** | 검색어 | 예 | 예 | 아니오 | App Functionality |
| User Content | Other User Content (루트 피드백) | 예 | 예 | 아니오 | App Functionality |
| **Other Data** | 주행 텔레메트리 (속도·G·급제동) | 예 | 예 | 아니오 | App Functionality |
| Diagnostics | Crash Data | **아니오** | — | — | — |
| Contact Info / Financial / Health / Contacts / Browsing History / Purchases / Sensitive Info | — | 아니오 | — | — | — |

- **Diagnostics = 아니오**는 `SENTRY_DSN` 없이 빌드할 때만 맞다. DSN을 넣으면
  Crash Data·Performance Data를 **예**로 바꾸고 처리방침에 Sentry를 추가해야 한다
- ATT(App Tracking Transparency) **불필요** — 추적 없음, `NSUserTrackingUsageDescription` 없음이 맞다

`ios/Runner/PrivacyInfo.xcprivacy`는 PreciseLocation / UserID / OtherDataTypes를
선언하고 있어 위 표와 정합적이다. `NSPrivacyAccessedAPICategoryUserDefaults` 사유
`CA92.1`도 적절하다.

## 4. 고쳐야 할 것

### G1 [높음] 처리방침이 없는 기능을 설명한다 — 백그라운드 위치

처리방침 §5: *"백그라운드 위치는 해당 준비/주행이 진행 중일 때만 사용되며..."*

**앱은 백그라운드 위치를 쓰지 않는다.** `UIBackgroundModes`에는 `audio` 하나뿐이고
(`location` 없음), `location_service.dart`에 always 권한 요청이 없다. Info.plist는
정반대로 *"Background location is not requested in this beta."*라고 명시한다.

→ 처리방침 §5에서 백그라운드 위치·자동 기록 문단을 **삭제하거나** 실제에 맞게
고칠 것. 심사관은 처리방침과 Info.plist를 둘 다 본다.

### G2 [높음] Google Fonts 런타임 다운로드가 미기재

번들 폰트가 없어(`pubspec.yaml`의 fonts 블록은 전부 주석) `google_fonts`가 실행 시
Google 서버에서 Inter·Archivo·Rajdhani를 받아온다. 기기 IP가 Google로 간다.

→ **폰트를 앱에 번들하는 쪽을 권장한다.** 제3자 전송이 사라지고, 오프라인/터널
구간에서 폰트가 깨지지 않는다. 드라이빙 앱이라 오프라인 이점이 실질적이다.
번들하지 않을 거면 처리방침 §4에 Google을 추가해야 한다.

### G3 [중간] Overpass / OpenStreetMap 미기재

루트 탐색이 사용자 위치 기반 bbox 쿼리를 3개 공개 미러로 보낸다.
→ 처리방침 §4에 추가.

### G4 [중간] OpenWeatherMap 미기재

Supabase Edge Function `get-weather` 경유로 좌표가 전달된다. 서버 경유라 기기 IP는
노출되지 않지만 위치는 제3자에게 간다.
→ 처리방침 §4에 하위 처리자로 추가.

### G5 [중간] Mapbox 기재 범위가 좁다

현재 "지도 표시"로만 적혀 있으나 실제로는 **목적지 검색어와 근접 위치**도
`api.mapbox.com`으로 직접 나간다.
→ §4의 Mapbox 설명에 검색/지오코딩을 포함.

### G6 [낮음] 쓰지 않는 권한 문구가 남아 있다

`NSMicrophoneUsageDescription` · `NSSpeechRecognitionUsageDescription`이 Info.plist에
있으나 워키토키는 `REVV_WALKIE_LAB` 게이트로 심사 빌드에서 제외된다.
→ 심사관이 "왜 마이크 권한을 요구하나" 물을 수 있다. 심사 빌드에서 두 키를 빼거나,
심사 노트에 "해당 기능은 이 빌드에서 비활성"이라고 명시할 것.

### G7 [결정 필요] 크래시 리포팅을 켤 것인가

지금 그대로 내면 크래시가 안 보인다. 첫 출시에서 크래시 원인을 못 잡는 건
실질적 손해다. 켜려면 `SENTRY_DSN` 추가 + ASC에서 Diagnostics를 예로 + 처리방침에
Sentry 추가. **민우 결정 사항.**

## 5. 확인하지 못한 것

- 처리방침 §2의 "탐험 진행 정보(저해상도 지도 셀 ID)"에 대응하는 코드를 확인하지
  않았다. 문구가 실제 구현과 맞는지 미검증
- `region_photo_service` · `transit_eta_service`의 외부 호출처 미확인 (제3자 추가
  가능성 있음)
- 시뮬레이터/코드 기준이며 실기기 네트워크 트래픽을 캡처해 대조하지는 않았다

## 6. 배포 전 체크리스트

- [ ] G1 처리방침 §5 백그라운드 위치 문구 수정 (**필수** — 사실과 다름)
- [ ] G2 폰트 번들 or 처리방침에 Google 추가
- [ ] G3·G4·G5 처리방침 §4에 Overpass·OpenWeatherMap 추가, Mapbox 범위 확장
- [ ] G6 마이크·음성인식 권한 처리 결정
- [ ] G7 크래시 리포팅 on/off 결정
- [ ] App Store Connect 앱 개인정보에 위 3번 표 입력
- [ ] 처리방침 갱신 후 "마지막 업데이트" 날짜 변경
