# REVV — Claude 컨텍스트

## 앱 개요
드라이빙 루트 추천 + 주행 기록 앱. "숨겨진 이쁜 드라이빙 코스 발견 + 개인 주행 기록 성장"이 핵심 가치.

## 중요 규칙
- **앱스토어 심사 기준 준수**: 속도 자극적인 표현 금지. "퍼포먼스 주행" → "즐거운 드라이빙"
- **안전 우선 언어**: 과속·법규 위반 조장 문구 절대 금지
- **버전 관리**: 수정마다 `lib/widgets/hud_bar.dart` 버전 번호 올릴 것 (현재 v1.11)
- **에뮬레이터**: 코드 변경 후 매번 full restart (hot reload 불충분)
- **커뮤니케이션**: 한국어

## 현재 버전: v1.11

## 스택
- Flutter 3.x + Dart
- Mapbox (`mapbox_maps_flutter ^2.3.0`) — 커스텀 스타일 `mapbox://styles/mingwoo/cmmk93np3003301rzajll6msm`
- Overpass API — 루트 탐색 (커브 분석)
- Claude API — Jarvis 브리핑
- Provider — 상태관리
- shared_preferences — 런 기록 + 집 위치 저장
- url_launcher — 여정 플래너 내비게이션 연결

## 핵심 파일 구조
```
lib/
├── main.dart                        # Provider 등록 (6개 서비스)
├── models/
│   ├── revv_route.dart              # RevvRoute, LatLng
│   ├── run_session.dart             # 주행 세션 (GPS 경로, 거리, 시간)
│   ├── run_summary.dart             # 저장용 경량 런 요약
│   └── poi.dart                     # POI 모델 + PoiCategory enum
├── services/
│   ├── location_service.dart        # GPS 위치 추적
│   ├── route_service.dart           # Overpass API 루트 탐색 + 커브 분석
│   ├── run_session_service.dart     # 주행 시작/종료/GPS 수집
│   ├── run_history_service.dart     # 런 기록 저장/로드 (shared_preferences)
│   ├── home_location_service.dart   # 집 위치 저장
│   ├── poi_service.dart             # Overpass POI 검색
│   ├── weather_service.dart         # 날씨
│   ├── mapbox_service.dart          # Mapbox 토큰 + 스타일 URI
│   └── jarvis_service.dart          # Jarvis AI 패널
├── screens/
│   ├── cruise_screen.dart           # 메인 화면 (지도 + 하단 패널)
│   ├── sprint_screen.dart           # 스프린트 모드 (주행 중)
│   ├── routes_screen.dart           # 루트 탐색
│   ├── run_card_screen.dart         # 런 종료 결과 카드 (자동 저장)
│   └── trip_planner_screen.dart     # 여정 플래너 (POI → 귀가)
├── widgets/
│   ├── hud_bar.dart                 # 상단 HUD (버전 표시)
│   ├── map_widget.dart              # Mapbox 지도
│   ├── routes_bottom_sheet.dart     # 루트 선택 바텀시트
│   ├── sprint_toggle.dart           # RedGlowButton
│   └── jarvis_panel.dart            # Jarvis AI 패널 위젯
└── theme/
    └── colors.dart                  # AppColors
```

## 구현된 기능
- 루트 탐색: bearing rate 기반 커브 분석, curveRatio×√dist 밀도 점수, 반경 30/50/100km
- 스프린트 모드: 주행 시작 → GPS 실시간 수집 → 종료 → 런카드
- 런카드: 거리/시간/날씨 표시, 자동 저장, 같은 루트 N회차 표시
- 여정 플래너: POI 카테고리 선택 → Overpass 검색 → Google Maps 연결 (경유지 + 귀가)
- 집 위치 저장 (현재 위치 기반)

## 아직 안 된 것 (다음 작업)
- 런 기록 히스토리 화면 (과거 런 목록)
- 공유카드 기능 (런카드 이미지 저장/공유)
- 스프린트 화면 라이브 스탯 오버레이 (거리 + 경과시간)
- cruise_screen에 여정 플래너 진입 버튼 연결

## Mapbox 설정
- Public Token: `lib/services/mapbox_service.dart`에 있음
- Mapbox username: mingwoo
- 커스텀 스타일: `mapbox://styles/mingwoo/cmmk93np3003301rzajll6msm` (REVV Waze Neon v3)
- 스프린트 navStyle: `mapbox://styles/mapbox/navigation-night-v1`

## GitHub
- Repo: https://github.com/gksalsdn1234/revv-app (Private)
- 작업 후 commit + push 할 것
