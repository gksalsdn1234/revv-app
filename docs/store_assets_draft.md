# REVV Store Assets Draft

작성 기준: `docs/2026-07-02-launch-plan.md` Week 2 Track B, `docs/release_quality_checklist.md` App Store Privacy Notes, `lib/screens` 5개 화면, 지정 서비스 4개 파일.

## 1. 앱 이름 / 서브타이틀

### 한국어안

| 안 | 앱 이름 | 서브타이틀 |
|---|---|---|
| KO-1 | REVV | 몬트리올 커브 루트 |
| KO-2 | REVV Drive | 드라이브 설계와 기록 |
| KO-3 | REVV Montreal | 와인딩 루트 로그 |

### 영어안

| Option | App Name | Subtitle |
|---|---|---|
| EN-1 | REVV | Montreal curve routes |
| EN-2 | REVV Drive | Design the drive |
| EN-3 | REVV Montreal | Routes and drive logs |

## 2. 앱 설명

### 한국어

몬트리올 근처의 굽이진 길을 지도에서 발견하세요.  
커브 수, 흐름, 거리로 오늘의 드라이브를 설계하세요.  
주행 후에는 경로와 여정을 기록으로 남기세요.

REVV는 주말 드라이브를 준비하고 복기하기 위한 앱입니다. 현재 위치 또는 지역 프리셋에서 루트 후보를 찾고, 지도에서 커브 밀도와 루트 형태를 비교할 수 있습니다.

루트 상세 화면에서는 거리, 예상 시간, 정지 요소, 커브 흐름, 코파일럿 브리핑, 턴 플랜 미리보기를 확인합니다. 시작 전에는 외부 내비 앱으로 출발점까지 이동하거나, 앱 안에서 바로 주행을 시작할 수 있습니다.

주행 중 화면은 지도, 남은 거리, 진행률, 다음 커브 안내, 종료 버튼 중심으로 구성됩니다. 주행 후에는 지도 리플레이, 거리와 시간, 코너 이벤트, 노면/날씨 메모, 공유 카드 초안을 확인할 수 있습니다.

클라우드 기록 저장은 설정에서 켜고 끌 수 있으며, 기록 삭제 기능을 제공합니다. 익명 세션으로 개인 기록을 분리하므로 앱 입구에서 계정을 만들 필요가 없습니다.

### English

Find curved roads around Montreal on the map.  
Shape today’s drive with curve count, flow, and distance.  
After the drive, keep the route and journey in your log.

REVV helps you prepare and review weekend drives. Search near your current location or from region presets, then compare route shape and curve density directly on the map.

Route detail shows distance, estimated time, stop elements, flow notes, copilot briefing, and a turn plan preview. Before you begin, you can open an external navigation app to the start point or start the drive inside REVV.

During a drive, the screen focuses on the map, remaining distance, progress, next curve guidance, and a clear end control. Afterward, review a map replay, distance and duration, corner events, road/weather notes, and a share card draft.

Cloud drive storage can be turned on or off in settings, and drive data can be deleted. Anonymous sessions separate personal history without requiring account creation at app launch.

## 3. 키워드

| 언어 | 키워드 초안 |
|---|---|
| English | Montreal,route planner,scenic drive,curve map,drive log,road trip,Quebec,car routes |
| French | Montréal,itinéraire,route panoramique,virages,carnet de trajet,Québec,balade auto |

## 4. 프라이버시 라벨 매핑

| Apple 라벨 항목 | 수집 여부 | 코드 근거 | 연결성 / 용도 검토 |
|---|---:|---|---|
| Location | 예 | `SupabaseService.findCurvyRoads`, `fetchNearbyRoutesDirect`, `WeatherService.fetchWeather`, `RunHistoryService.save`, `RunTelemetryDetail.fromSession` | 루트 검색과 날씨 조회에 현재 좌표를 사용합니다. 주행 기록에는 시작/종료 좌표와 경로 샘플이 포함될 수 있습니다. 클라우드 저장을 켠 경우 익명 `user_id`와 함께 저장됩니다. |
| Identifiers / User ID | 예 | `SupabaseService.init`, `uid`, `SecureSessionStore` | Supabase 익명 인증 ID와 세션 토큰으로 개인 기록을 분리합니다. 이메일, 이름, 전화번호는 코드상 수집하지 않습니다. |
| Usage Data / Product Interaction | 예 | `RunHistoryService.saveFeedback`, `recordRouteRun`, `saveRouteBookmark`, `saveDiscoveredRoutes` | 루트 피드백, 루트 실행 카운트, 저장한 루트, 발견한 루트 캐시가 앱 기능 복원과 루트 품질 개선에 사용됩니다. |
| Fitness / Movement | 예 | `RunSession`, `RunTelemetryDetail`, `RunHistoryService.save` | 거리, 시간, 이동 페이스 수치, 관성 센서 요약, 코너 이벤트, 주행 모드 샘플을 기록 복기와 공유 카드 생성에 사용합니다. |
| Diagnostics | 아니오 | 지정 서비스 4개 파일 기준 별도 크래시/성능 SDK 없음 | 이 플랜 범위의 코드 근거로는 진단 데이터 수집을 확인하지 못했습니다. |
| Contact Info | 아니오 | 익명 인증 유지, 입력 필드 없음 | 이메일, 이름, 전화번호 수집 근거 없음. |
| Tracking | 아니오 | `release_quality_checklist.md` App Store Privacy Notes | 타사 광고 추적 또는 교차 앱 추적 근거 없음. |

### "사용자에게 연결되지 않는 데이터" 검토

앱은 실명 계정을 만들지 않고 Supabase 익명 인증을 사용합니다. 따라서 이메일, 이름, 전화번호 같은 직접 식별자에는 연결되지 않습니다. 다만 클라우드 기록 저장을 켠 경우 위치/주행/피드백 데이터가 앱 내부 익명 `user_id`에 묶여 복원과 삭제에 사용되므로, App Store Connect 답변에서는 "사용자의 실제 신원에는 연결하지 않음"과 "익명 앱 ID에는 연결됨"을 구분해 확인해야 합니다.

클라우드 기록 저장을 끄면 상세 기록은 로컬 저장 위주로 유지되고 pending 업로드가 삭제됩니다. 다만 루트 검색과 날씨 조회에는 기능 수행을 위한 좌표 전송이 발생할 수 있습니다.

## 5. Review Notes

REVV uses When-In-Use location permission to find nearby curved routes, show the current position on the route map, provide in-drive route progress, and save a post-drive route log when the user completes a drive.

No demo account is required. The app creates an anonymous Supabase session automatically so the reviewer can open the app, allow location access, find routes, start a drive, and save a log without entering credentials.

The driving surface is designed to reduce interaction while the vehicle is moving. The active drive screen keeps the map, remaining distance, next curve cue, progress, mute toggle, and end control visible. Route choice, detailed review, sharing, settings, and deletion actions are intended for before or after the drive.

## 6. 베타 / 버전 노트 초안

### 한국어

REVV 첫 공개 후보입니다.

- 몬트리올과 주요 지역 프리셋에서 굽이진 루트 후보를 찾을 수 있습니다.
- 지도에서 커브 밀도, 루트 형태, 거리, 예상 시간을 비교할 수 있습니다.
- 주행 중 진행률, 남은 거리, 다음 커브 안내를 확인할 수 있습니다.
- 주행 후 지도 리플레이, 거리/시간 기록, 코너 이벤트, 공유 카드 초안을 볼 수 있습니다.
- 익명 세션 기반 클라우드 기록 저장 토글과 전체 기록 삭제 기능을 제공합니다.

### English

Initial public candidate for REVV.

- Find curved route candidates around Montreal and supported region presets.
- Compare curve density, route shape, distance, and estimated duration on the map.
- During a drive, view progress, remaining distance, and next curve guidance.
- After a drive, review a map replay, distance/duration log, corner events, and a share card draft.
- Includes anonymous-session cloud storage controls and full drive data deletion.

## 7. 지원 URL / 마케팅 URL 자리표시

| 항목 | 상태 |
|---|---|
| Support URL | 민우 결정 필요: App Store Connect에 넣을 공개 지원 페이지 URL |
| Marketing URL | 민우 결정 필요: 랜딩 페이지 또는 Notion 공개 페이지 사용 여부 |
| Privacy Policy URL | 민우 결정 필요: `docs/privacy_policy_notion_draft.md` 게시 후 공개 URL 확정 |
| Review Contact | 민우 결정 필요: 심사 대응 이메일 또는 연락 창구 |
