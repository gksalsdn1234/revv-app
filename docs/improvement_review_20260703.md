# 개선점 전수 리뷰 (2026-07-03, Codex 조사)

**P0 버그**

| 파일:라인 | 문제 | 제안 |
|---|---|---|
| `lib/widgets/copilot_start_sheet.dart:84` | `routeDisplayName()` 폴백이 있는데 시작 체크 시트는 `route.name`을 직접 표시해 숫자 OSM way id가 다시 노출될 수 있음. | 모든 사용자 표시 루트명은 `routeDisplayName(route, language: language)`로 통일. |
| `lib/screens/lean_drive_screen.dart:370` | 주행 HUD도 `_DriveTopBar(routeName: widget.route.name)`로 원본명을 넘겨 최근 이름 폴백 커밋 범위를 우회함. | `_DriveTopBar` 입력을 표시명으로 바꾸고 원본명 직접 렌더 금지. |
| `lib/screens/lean_route_finder_screen.dart:176` | `_requestCoverageNotification()`이 `setState(true)` 후 `recordRegionRequest`/`markRegionRequested` 예외 시 `_coverageRequestInProgress`를 false로 복구하지 않음. | `try/finally`로 플래그 복구하고 실패 스낵바/상태 문구 추가. |
| `lib/screens/lean_drive_screen.dart:82` | `_startDrive()`가 권한/위치 await 후 mounted 확인 없이 타이머 생성·세션 시작(`89`, `93`)을 실행함. | await 직후 `if (!mounted) return;` 후 타이머/세션 시작. |
| `lib/screens/lean_drive_planner_screen.dart:222` | 외부 내비 실행에서 `launchUrl` 두 번을 try/catch 없이 await해 플랫폼 예외 시 화면 피드백 없이 Future 에러로 빠짐. | copilot 내비 헬퍼처럼 예외를 잡고 localized 실패 메시지 표시. |

**P1 UX / 성능**

| 파일:라인 | 문제 | 제안 |
|---|---|---|
| `lib/screens/lean_home_screen.dart:300` | 홈 최상위 build가 `LocationService`, `RouteService`, `RunHistoryService`, `SettingsService`, `SupabaseService`를 모두 watch해 위치 notify마다 홈 전체가 재빌드됨. | `context.select`/`Selector`로 필요한 필드만 구독하고 카드 단위 Consumer로 분리. |
| `lib/screens/lean_route_finder_screen.dart:385` | 파인더 최상위가 `RouteService`와 `LocationService`를 watch하고 같은 build에서 `MapWidget`까지 생성해 route notify가 지도 위젯 비교/갱신까지 끌고 감. | 지도 입력 모델을 select로 축소하고 하단 티켓/상단 필터만 Consumer로 분리. |
| `lib/screens/lean_drive_screen.dart:249` | IMU listener가 임계값마다 `setState`로 전체 주행 화면을 갱신해 지도 위 HUD 전체가 고빈도 리빌드됨. | G-meter 영역만 `ValueListenable`/Consumer로 격리하거나 샘플링 주기 제한. |
| `lib/widgets/map_widget.dart:316` | simulation position 변경마다 `_drawSimulationMarker`가 source/layer 제거 후 재추가(`1022`)를 수행함. | 기존 GeoJSON source data 업데이트 방식으로 마커 위치만 갱신. |
| `lib/widgets/map_widget.dart:367` | `didUpdateWidget`에서 polyline group/list를 점 단위 비교하고 여러 `_draw*` 비동기 작업을 동시에 fire-and-forget함. | route ids/version 토큰으로 변경 감지하고 draw 작업 직렬화/취소 토큰 적용. |
| `lib/screens/lean_home_screen.dart:311` | 홈은 `SafeArea > Padding > Column`에 `Spacer`를 쓰고 스크롤이 없어 최근 주행/가이드 카드/큰 글자 접근성에서 세로 overflow 위험. | 본문을 `CustomScrollView` 또는 `SingleChildScrollView + bottom nav` 구조로 전환. |
| `lib/screens/loading_screen.dart:81` | 로딩 화면도 스크롤 없는 Column에 88px 워드마크, 큰 spacer, 고정 체크 영역을 배치해 작은 화면/글자 확대에서 overflow 가능. | `LayoutBuilder` 기반 축소 또는 scroll fallback 추가. |
| `lib/screens/lean_drive_screen.dart:386` | 주행 화면 하단 HUD는 고정 Row/버튼/폭 104·158 패널 조합이라 작은 폭·프랑스어에서 overflow 가능. | 하단 컨트롤을 `Wrap`/responsive two-row로 전환하고 긴 라벨은 아이콘+tooltip로 축약. |
| `lib/screens/lean_route_detail_screen.dart:188` | 상세 quick stat 4개가 한 Row에 고정 분할되고 값은 18px 한 줄 ellipsis라 프랑스어/큰 접근성 텍스트에서 정보 손실 큼. | 2x2 grid 또는 horizontal scroll로 전환해 값 우선 표시. |
| `lib/screens/lean_route_finder_screen.dart:1762` | DriveBudgetChoiceStrip 높이 38 고정 + 긴 다국어 칩을 가로 리스트에 넣어 큰 텍스트에서 터치/텍스트 클립 위험. | 최소 높이 44 이상, 칩 intrinsic height 허용. |
| `lib/widgets/map_widget.dart:1600` | `SettingsService` language watch가 MapWidget build에 있어 언어 변경 시 플랫폼 지도까지 재빌드 대상이 됨. | fallback 문구만 별도 위젯으로 빼고 Mapbox subtree는 language watch 밖에 둠. |
| `lib/screens/lean_run_summary_screen.dart:541` | 공유 미리보기 높이가 story 320/square 260 고정이라 긴 routeName/metric wrap 시 내부 ellipsis와 정보 손실이 발생. | preset별 preview를 available height 기준으로 계산하고 export 결과와 동일한 aspect constraints 표시. |

**P2 폴리시 / 일관성**

| 파일:라인 | 문제 | 제안 |
|---|---|---|
| `lib/screens/lean_home_screen.dart:813` | 하단 nav 라벨 `Home/History/Settings`가 AppCopy를 우회해 언어 설정과 불일치. | `AppCopy`에 nav 라벨 추가. |
| `lib/screens/lean_home_screen.dart:1430` | 설정 시트에 `JD`, `Driver #042`, `7 RUNS · MEMBER SINCE APR 2026` 더미 프로필이 하드코딩됨. | 실제 상태 기반 문구 또는 베타용 익명 프로필 copy로 교체. |
| `lib/screens/lean_home_screen.dart:1468` | `UNITS & DISPLAY`, `Distance`, `Language`, `DRIVE`, `Voice guidance` 등 설정 라벨 다수가 AppCopy 밖에 있음. | 설정 섹션/라벨 전부 AppCopy로 이동. |
| `lib/screens/loading_screen.dart:151` | 로딩 태그라인과 시스템 체크(`GPS`, `ACQUIRING`, `READY`)가 영어 고정. | 로딩 화면도 현재 language 또는 중립 아이콘 상태로 통일. |
| `lib/ui/run_share_metrics.dart:69` | 공유 카드 지표 라벨(`Distance`, `Duration`, `Avg speed`, `Route ... done`)이 영어 고정이며 language 파라미터가 없음. | `buildRunShareMetrics(language:)`로 지역화. |
| `lib/ui/run_share_card_content.dart:90` | 공유 카드 fallback `Private route`, preset label/month/date가 영어 고정(`128`, `179`). | 공유 카드 content builder에 language 전달. |
| `lib/screens/lean_run_summary_screen.dart:566` | 공유 미리보기 `Share preview`, `Close`, `Export card`가 AppCopy 없이 영어 고정. | summary/share 전용 copy 메서드 추가. |
| `lib/ui/winding_experience.dart:132` | 안전 문구에 “before pushing” 표현이 남아 있어 공격적 주행 뉘앙스가 있음. | “before committing/starting”처럼 관찰·확인 중심 표현으로 교체. |
코드 수정 없이 조사만 했습니다. `docs/improvement_review_20260703.md`는 쓰지 않았습니다. Lazyweb 검색은 사용자 취소로 외부 UI 근거 없이 코드 근거만 사용했습니다.

**P0 버그**

| 파일:라인 | 문제 | 제안 |
|---|---|---|
| `lib/widgets/copilot_start_sheet.dart:84` | `routeDisplayName()` 폴백이 있는데 시작 체크 시트는 `route.name`을 직접 표시해 숫자 OSM way id가 다시 노출될 수 있음. | 모든 사용자 표시 루트명은 `routeDisplayName(route, language: language)`로 통일. |
| `lib/screens/lean_drive_screen.dart:370` | 주행 HUD도 `_DriveTopBar(routeName: widget.route.name)`로 원본명을 넘겨 최근 이름 폴백 커밋 범위를 우회함. | `_DriveTopBar` 입력을 표시명으로 바꾸고 원본명 직접 렌더 금지. |
| `lib/screens/lean_route_finder_screen.dart:176` | `_requestCoverageNotification()`이 `setState(true)` 후 `recordRegionRequest`/`markRegionRequested` 예외 시 `_coverageRequestInProgress`를 false로 복구하지 않음. | `try/finally`로 플래그 복구하고 실패 스낵바/상태 문구 추가. |
| `lib/screens/lean_drive_screen.dart:82` | `_startDrive()`가 권한/위치 await 후 mounted 확인 없이 타이머 생성·세션 시작(`89`, `93`)을 실행함. | await 직후 `if (!mounted) return;` 후 타이머/세션 시작. |
| `lib/screens/lean_drive_planner_screen.dart:222` | 외부 내비 실행에서 `launchUrl` 두 번을 try/catch 없이 await해 플랫폼 예외 시 화면 피드백 없이 Future 에러로 빠짐. | copilot 내비 헬퍼처럼 예외를 잡고 localized 실패 메시지 표시. |

**P1 UX / 성능**

| 파일:라인 | 문제 | 제안 |
|---|---|---|
| `lib/screens/lean_home_screen.dart:300` | 홈 최상위 build가 `LocationService`, `RouteService`, `RunHistoryService`, `SettingsService`, `SupabaseService`를 모두 watch해 위치 notify마다 홈 전체가 재빌드됨. | `context.select`/`Selector`로 필요한 필드만 구독하고 카드 단위 Consumer로 분리. |
| `lib/screens/lean_route_finder_screen.dart:385` | 파인더 최상위가 `RouteService`와 `LocationService`를 watch하고 같은 build에서 `MapWidget`까지 생성해 route notify가 지도 위젯 비교/갱신까지 끌고 감. | 지도 입력 모델을 select로 축소하고 하단 티켓/상단 필터만 Consumer로 분리. |
| `lib/screens/lean_drive_screen.dart:249` | IMU listener가 임계값마다 `setState`로 전체 주행 화면을 갱신해 지도 위 HUD 전체가 고빈도 리빌드됨. | G-meter 영역만 `ValueListenable`/Consumer로 격리하거나 샘플링 주기 제한. |
| `lib/widgets/map_widget.dart:316` | simulation position 변경마다 `_drawSimulationMarker`가 source/layer 제거 후 재추가(`1022`)를 수행함. | 기존 GeoJSON source data 업데이트 방식으로 마커 위치만 갱신. |
| `lib/widgets/map_widget.dart:367` | `didUpdateWidget`에서 polyline group/list를 점 단위 비교하고 여러 `_draw*` 비동기 작업을 동시에 fire-and-forget함. | route ids/version 토큰으로 변경 감지하고 draw 작업 직렬화/취소 토큰 적용. |
| `lib/screens/lean_home_screen.dart:311` | 홈은 `SafeArea > Padding > Column`에 `Spacer`를 쓰고 스크롤이 없어 최근 주행/가이드 카드/큰 글자 접근성에서 세로 overflow 위험. | 본문을 `CustomScrollView` 또는 `SingleChildScrollView + bottom nav` 구조로 전환. |
| `lib/screens/loading_screen.dart:81` | 로딩 화면도 스크롤 없는 Column에 88px 워드마크, 큰 spacer, 고정 체크 영역을 배치해 작은 화면/글자 확대에서 overflow 가능. | `LayoutBuilder` 기반 축소 또는 scroll fallback 추가. |
| `lib/screens/lean_drive_screen.dart:386` | 주행 화면 하단 HUD는 고정 Row/버튼/폭 104·158 패널 조합이라 작은 폭·프랑스어에서 overflow 가능. | 하단 컨트롤을 `Wrap`/responsive two-row로 전환하고 긴 라벨은 아이콘+tooltip로 축약. |
| `lib/screens/lean_route_detail_screen.dart:188` | 상세 quick stat 4개가 한 Row에 고정 분할되고 값은 18px 한 줄 ellipsis라 프랑스어/큰 접근성 텍스트에서 정보 손실 큼. | 2x2 grid 또는 horizontal scroll로 전환해 값 우선 표시. |
| `lib/screens/lean_route_finder_screen.dart:1762` | DriveBudgetChoiceStrip 높이 38 고정 + 긴 다국어 칩을 가로 리스트에 넣어 큰 텍스트에서 터치/텍스트 클립 위험. | 최소 높이 44 이상, 칩 intrinsic height 허용. |
| `lib/widgets/map_widget.dart:1600` | `SettingsService` language watch가 MapWidget build에 있어 언어 변경 시 플랫폼 지도까지 재빌드 대상이 됨. | fallback 문구만 별도 위젯으로 빼고 Mapbox subtree는 language watch 밖에 둠. |
| `lib/screens/lean_run_summary_screen.dart:541` | 공유 미리보기 높이가 story 320/square 260 고정이라 긴 routeName/metric wrap 시 내부 ellipsis와 정보 손실이 발생. | preset별 preview를 available height 기준으로 계산하고 export 결과와 동일한 aspect constraints 표시. |

**P2 폴리시 / 일관성**

| 파일:라인 | 문제 | 제안 |
|---|---|---|
| `lib/screens/lean_home_screen.dart:813` | 하단 nav 라벨 `Home/History/Settings`가 AppCopy를 우회해 언어 설정과 불일치. | `AppCopy`에 nav 라벨 추가. |
| `lib/screens/lean_home_screen.dart:1430` | 설정 시트에 `JD`, `Driver #042`, `7 RUNS · MEMBER SINCE APR 2026` 더미 프로필이 하드코딩됨. | 실제 상태 기반 문구 또는 베타용 익명 프로필 copy로 교체. |
| `lib/screens/lean_home_screen.dart:1468` | `UNITS & DISPLAY`, `Distance`, `Language`, `DRIVE`, `Voice guidance` 등 설정 라벨 다수가 AppCopy 밖에 있음. | 설정 섹션/라벨 전부 AppCopy로 이동. |
| `lib/screens/loading_screen.dart:151` | 로딩 태그라인과 시스템 체크(`GPS`, `ACQUIRING`, `READY`)가 영어 고정. | 로딩 화면도 현재 language 또는 중립 아이콘 상태로 통일. |
| `lib/ui/run_share_metrics.dart:69` | 공유 카드 지표 라벨(`Distance`, `Duration`, `Avg speed`, `Route ... done`)이 영어 고정이며 language 파라미터가 없음. | `buildRunShareMetrics(language:)`로 지역화. |
| `lib/ui/run_share_card_content.dart:90` | 공유 카드 fallback `Private route`, preset label/month/date가 영어 고정(`128`, `179`). | 공유 카드 content builder에 language 전달. |
| `lib/screens/lean_run_summary_screen.dart:566` | 공유 미리보기 `Share preview`, `Close`, `Export card`가 AppCopy 없이 영어 고정. | summary/share 전용 copy 메서드 추가. |
| `lib/ui/winding_experience.dart:132` | 안전 문구에 “before pushing” 표현이 남아 있어 공격적 주행 뉘앙스가 있음. | “before committing/starting”처럼 관찰·확인 중심 표현으로 교체. |
