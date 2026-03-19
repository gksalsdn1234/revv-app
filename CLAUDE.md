# REVV — Claude 컨텍스트

## 앱 개요
드라이빙 루트 추천 + 주행 기록 앱. "숨겨진 이쁜 드라이빙 코스 발견 + 개인 주행 기록 성장"이 핵심 가치.
캐나다 거주 사용자 기준 (T맵/카카오 불필요).

## 중요 규칙
- **앱스토어 심사 기준 준수**: 속도 자극적인 표현 금지. "퍼포먼스 주행" → "즐거운 드라이빙"
- **안전 우선 언어**: 과속·법규 위반 조장 문구 절대 금지
- **버전 관리**: pre-commit 훅이 `lib/widgets/hud_bar.dart` 버전 자동 동기화
- **에뮬레이터**: Mapbox + Android Emulator GFXSTREAM 충돌 → 실기기 필요
- **커뮤니케이션**: 한국어

## 현재 버전: v1.33 (2026-03-19)

## 스택
- Flutter 3.x + Dart
- Mapbox (`mapbox_maps_flutter ^2.3.0`) — 커스텀 스타일 `mapbox://styles/mingwoo/cmmk93np3003301rzajll6msm`
- Overpass API — 루트 탐색 (커브 분석)
- Claude API — Jarvis 브리핑
- Provider — 상태관리 (11개 서비스 등록)
- shared_preferences — 런 기록 + 집 위치 저장
- flutter_tts — 턴바이턴 음성 안내
- sensors_plus — IMU G포스 (ImuService, 50Hz)

## 핵심 파일 구조
```
lib/
├── main.dart                         # Provider 등록 (11개 서비스)
├── models/
│   ├── revv_route.dart               # RevvRoute, LatLng, haversineKm
│   ├── run_session.dart              # 주행 세션 (GPS 경로, 거리, 시간)
│   ├── run_summary.dart              # 저장용 경량 런 요약
│   ├── poi.dart                      # POI 모델 + PoiCategory enum
│   └── nav_step.dart                 # 턴바이턴 NavStep (maneuver→한국어)
├── services/
│   ├── location_service.dart         # GPS 위치 추적
│   ├── route_service.dart            # Overpass API 루트 탐색 + 커브 분석
│   │                                 # fetchConnectingRoutes() — 체인 연결 루트
│   ├── saved_route_service.dart      # 저장된 루트 관리
│   ├── directions_service.dart       # Mapbox Directions API
│   │                                 # getRouteWithSteps() → polyline + NavStep[]
│   ├── turn_by_turn_service.dart     # TBT: 300m/80m 예고, 25m 스텝 전진, TTS
│   ├── run_session_service.dart      # 주행 시작/종료/GPS 수집
│   ├── run_history_service.dart      # 런 기록 저장/로드 (shared_preferences)
│   ├── home_location_service.dart    # 집 위치 저장
│   ├── poi_service.dart              # Overpass POI 검색
│   ├── weather_service.dart          # 날씨
│   ├── mapbox_service.dart           # Mapbox 토큰 + 스타일 URI
│   ├── jarvis_service.dart           # Jarvis AI 패널
│   ├── imu_service.dart              # 가속도계 → lateralG, longitudinalG (50Hz)
│   ├── driving_context_service.dart  # 속도/G포스 → DriveMode (cruise/sport/attack)
│   ├── obd_service.dart              # BLE OBD2 (VEEPEAK) — RPM/연료/스로틀/냉각수
│   ├── waypoint_optimizer.dart       # 루트 경유지 최적화
│   ├── route_builder_service.dart    # 루트 생성 도우미
│   ├── audio_service.dart            # 오디오 — 싱글턴, mic_button에서 직접 사용
│   ├── revv_ai_service.dart          # AI 분석 — 싱글턴, run_card/mic_button에서 직접 사용
│   ├── stt_service.dart              # 음성인식 — 싱글턴, mic_button에서 직접 사용
│   └── route_brief_service.dart      # 루트 브리핑 — routes_bottom_sheet에서 직접 사용
├── screens/
│   ├── cruise_screen.dart            # 메인 화면 — 왼쪽 56px 세로 레일
│   │                                 # _LeftRail: 속도/날씨/루트/여정/OBD/기록/AI/GO/MIC
│   ├── sprint_screen.dart            # 스프린트 모드 — TBT 배너 + G포스 미니 원형
│   ├── routes_screen.dart            # 루트+여정 통합 화면 — ROUTES/TRIP 2탭
│   │                                 # ROUTES탭: 루트 탐색·체인연결·flyTo
│   │                                 # TRIP탭: POI 카테고리 검색 → Google Maps 내비
│   │                                 # initialTab: 0=ROUTES(기본), 1=TRIP
│   ├── obd_screen.dart               # OBD 전용 4탭 화면 (LIVE/DATA/G-FORCE/SETUP)
│   ├── run_card_screen.dart          # 런 종료 결과 카드 (자동 저장)
│   ├── route_wizard_screen.dart      # 루트 wizard
│   └── trip_planner_screen.dart      # (deprecated — routes_screen TRIP탭으로 통합)
├── widgets/
│   ├── hud_bar.dart                  # 상단 HUD (버전 표시)
│   ├── map_widget.dart               # Mapbox 지도 (navPolyline/routePolyline)
│   ├── routes_bottom_sheet.dart      # 루트 선택 + CHAIN 체인 섹션
│   ├── sprint_toggle.dart            # RedGlowButton
│   ├── mic_button.dart               # 마이크 버튼
│   └── jarvis_panel.dart             # Jarvis AI 패널 위젯
└── theme/
    └── colors.dart                   # AppColors
```

## 구현된 주요 기능 (v1.33 기준)
- **루트 탐색**: bearing rate 기반 커브 분석, curveRatio×√dist 밀도 점수, 반경 30/50/100km
- **체인 연결**: 선택 루트 끝점 15km 반경 연결 루트 자동 탐색, 가로 스크롤 카드
- **루트 카드 탭 → 지도 flyTo**: _lastFlownRouteId로 중복 이동 방지
- **스프린트 모드**: 주행 시작 → GPS 실시간 수집 → 종료 → 런카드
- **턴바이턴 음성 안내**: Mapbox steps + flutter_tts, 300m/80m 예고, 음소거 토글
- **G포스 미니 원형**: SprintScreen 우하단, CustomPainter, ImuService 50Hz
- **G포스 전용 탭**: OBD 화면 3번째 탭(_GForceTab) — LayoutBuilder 풀사이즈 _CarGforceMeter, 합성G 수치, MAX 배지, 리셋 버튼
- **루트+여정 통합**: RoutesScreen ROUTES/TRIP 2탭 — 지도 공유, 탭 전환 시 POI 핀 전환
- **Way Stitching**: 끝점 150m 이내 way 자동 체인 연결 → 연속 와인딩 루트
- **루프 감지**: 시작~끝 3km 이내 = isLoop, ×1.25 보너스, 🔄 LOOP 배지
- **거리 패널티**: 15km 이내 패널티 없음, 60km 초과 0.55배 하향
- **DrivingContextService**: 속도/G포스 → cruise/sport/attack 모드 자동 전환
- **OBD 연동**: VEEPEAK BLE OBD2, RPM/연료/스로틀/냉각수
- **nav polyline**: 현재 위치 → 루트 시작점 파란 선
- **런카드**: 거리/시간/날씨, 자동 저장, N회차 표시
- **풀스크린 지도 + 슬라이드 메뉴**: Stack 레이아웃, AnimatedPositioned 왼쪽 레일 (기본 숨김, 햄버거 탭 시 슬라이드인)
- **AppColors v2**: bg/panel/panel2/surface 레이어 체계 + textPrimary/Secondary/Hint 계층
- **Firebase Firestore**: CloudSyncService — 익명 인증, users/{uid}/runs/{runId} 런 동기화
- **share_plus v10**: SharePlus.instance.share(ShareParams) 런카드 공유
- **RunSession 확장**: maxLateralG, maxLongG, peakDriveMode 필드 추가
- **오프라인 루트 캐시**: route_service.dart — 마지막 검색 결과 shared_preferences 저장, 인터넷 끊기면 캐시 복원 + "오프라인 모드" 메시지
- **RunSummary maxLateralG**: 런 요약에 최대 횡G 저장 → history_screen BEST G 스탯 표시
- **집 위치 지도 핀 설정**: routes_screen TRIP탭 "집 설정" → 지도 중앙 핀 모드, getCameraState()로 좌표 읽어 setHome() 저장
- **루트 이탈 감지**: sprint_screen — 루트 진입 후 노드들과 최소 거리 계산, 300m 초과 시 주황 이탈 경고 배너, 200m 복귀 시 해제
- **첫 실행 권한 플로우**: loading_screen — permission_handler로 위치+마이크 권한 애니메이션 중 자동 요청

## 미구현 (다음 작업 우선순위)
1. **실기기 테스트** — G포스/TBT/DrivingContext/NavPolyline/CloudSync/GForceTab/루트이탈 에뮬레이터 미검증
2. **Firebase 보안 규칙** — users/{uid}/runs 오너 전용 read/write 설정 (Firebase Console)
3. **런카드 공유 실기기 테스트** — share_plus v10 ShareParams 실기기에서 검증

## 싱글턴 서비스 (Provider 불필요, 정상 동작 중)
ChangeNotifier를 extend하지 않는 서비스 — Provider 등록 없이 직접 호출 방식으로 사용 중
- **AudioService** → mic_button.dart에서 `AudioService().playBeep()` 직접 사용
- **SttService** → mic_button.dart에서 `SttService().startListening/stopListening()` 직접 사용
- **RevvAiService** → run_card_screen.dart, mic_button.dart에서 직접 사용
- **RouteBriefService** → routes_bottom_sheet.dart에서 직접 사용

## Firebase 서비스 구조
- **CloudSyncService**: `services/cloud_sync_service.dart` — firebase_auth 익명 로그인 + Firestore 런 동기화
- **컬렉션 경로**: `users/{uid}/runs/{runId}`
- **주의**: Firestore 보안 규칙 아직 기본값 — 배포 전 오너 전용으로 설정 필요

## Mapbox 설정
- Public Token: `lib/services/mapbox_service.dart`에 있음
- Mapbox username: mingwoo
- 커스텀 스타일: `mapbox://styles/mingwoo/cmmk93np3003301rzajll6msm` (REVV Waze Neon v3)
- 스프린트 navStyle: `mapbox://styles/mapbox/navigation-night-v1`

## Firebase
- 세계수(로드맵) 호스팅: https://revv-eb7c9.web.app
- 세계수 로컬: `C:\Users\gksal\REVV\REVV_guide.html`
- GitHub Actions 자동 배포: REVV_guide.html push → 자동으로 revv-eb7c9.web.app 배포
- 수동 배포 필요 시: `cd C:\Users\gksal\REVV\.guide-hosting && firebase deploy --only hosting --project revv-eb7c9`

## GitHub
- Repo: https://github.com/gksalsdn1234/revv-app (Private)
- 작업 후 commit + push 할 것
