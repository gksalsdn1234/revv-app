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

## 현재 버전: v1.29

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
│   ├── audio_service.dart            # 오디오 (미등록)
│   ├── revv_ai_service.dart          # AI 서비스 (미등록)
│   ├── stt_service.dart              # 음성인식 (미등록)
│   └── route_brief_service.dart      # 루트 브리핑 (미등록)
├── screens/
│   ├── cruise_screen.dart            # 메인 화면 — 왼쪽 56px 세로 레일
│   │                                 # _LeftRail: 속도/날씨/루트/여정/OBD/기록/AI/GO/MIC
│   ├── sprint_screen.dart            # 스프린트 모드 — TBT 배너 + G포스 미니 원형
│   ├── routes_screen.dart            # 루트 탐색 — 체인 연결 루트, flyTo
│   ├── obd_screen.dart               # OBD 전용 3탭 화면
│   ├── run_card_screen.dart          # 런 종료 결과 카드 (자동 저장)
│   ├── route_wizard_screen.dart      # 루트 wizard
│   └── trip_planner_screen.dart      # 여정 플래너 (POI → 귀가)
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

## 구현된 주요 기능 (v1.29 기준)
- **루트 탐색**: bearing rate 기반 커브 분석, curveRatio×√dist 밀도 점수, 반경 30/50/100km
- **체인 연결**: 선택 루트 끝점 15km 반경 연결 루트 자동 탐색, 가로 스크롤 카드
- **루트 카드 탭 → 지도 flyTo**: _lastFlownRouteId로 중복 이동 방지
- **스프린트 모드**: 주행 시작 → GPS 실시간 수집 → 종료 → 런카드
- **턴바이턴 음성 안내**: Mapbox steps + flutter_tts, 300m/80m 예고, 음소거 토글
- **G포스 미니 원형**: SprintScreen 우하단, CustomPainter, ImuService 50Hz
- **DrivingContextService**: 속도/G포스 → cruise/sport/attack 모드 자동 전환
- **OBD 연동**: VEEPEAK BLE OBD2, RPM/연료/스로틀/냉각수
- **nav polyline**: 현재 위치 → 루트 시작점 파란 선
- **런카드**: 거리/시간/날씨, 자동 저장, N회차 표시
- **왼쪽 레일 UI**: 56px 세로 탭 (NavigationRail 패턴)

## 미구현 (다음 작업 우선순위)
1. **런 히스토리 화면** — `run_history_service.dart`에 데이터 쌓이는데 볼 화면 없음 (`history_screen.dart` 신규)
2. **런카드 공유** — screenshot 패키지 + share_plus로 이미지 저장/공유
3. **JARVIS 주행 후 자동 분석 리포트** — 런 종료 시 Claude API 호출
4. **실기기 테스트** — G포스/TBT/DrivingContext/NavPolyline 에뮬레이터에서 미검증

## 미등록 서비스 (main.dart에 없음)
AudioService, RevvAiService, SttService, RouteBriefService — 연결 또는 삭제 정리 필요

## Mapbox 설정
- Public Token: `lib/services/mapbox_service.dart`에 있음
- Mapbox username: mingwoo
- 커스텀 스타일: `mapbox://styles/mingwoo/cmmk93np3003301rzajll6msm` (REVV Waze Neon v3)
- 스프린트 navStyle: `mapbox://styles/mapbox/navigation-night-v1`

## Firebase
- 세계수(로드맵) 호스팅: https://revv-eb7c9.web.app
- 세계수 로컬: `C:\Users\gksal\Desktop\REVV_guide.html`
- 배포: `cp REVV_guide.html ~/revv-guide-host/index.html && cd ~/revv-guide-host && firebase deploy --only hosting`
- 세계수 수정 시 항상 위 배포 명령 실행할 것

## GitHub
- Repo: https://github.com/gksalsdn1234/revv-app (Private)
- 작업 후 commit + push 할 것
