# REVV Privacy Policy / 개인정보 처리방침

Last updated / 마지막 업데이트: 2026-08-05

## 1. Overview / 개요

REVV is a route discovery and driving rhythm copilot app. REVV helps drivers find available curvy routes, preview route details, follow route progress during a drive, and save post-drive summaries.

REVV는 운전자가 이용 가능한 와인딩 루트를 찾고, 루트 정보를 확인하며, 주행 중 루트 진행을 보고, 주행 후 요약을 저장하기 위한 앱입니다.

## 2. Data We Collect / 수집하는 데이터

REVV may collect or process the following data to provide app functionality:

- Location data: used for nearby route discovery, current location display, route progress, and drive tracking.
- Driving data: distance, duration, route samples, speed, G-force values, selected route, and drive summaries.
- User identifier: a Supabase anonymous or user identifier used to separate each user’s records.
- Route feedback: route ratings, safety feedback, hidden routes, and “do not recommend again” choices.
- Exploration progress: coarse map cell identifiers derived after a saved real drive. The exploration feature does not upload an additional ordered GPS breadcrumb stream.

REVV는 앱 기능 제공을 위해 다음 데이터를 수집하거나 처리할 수 있습니다.

- 위치 데이터: 주변 루트 탐색, 현재 위치 표시, 루트 진행률 계산, 주행 기록에 사용됩니다.
- 주행 데이터: 거리, 시간, 경로 샘플, 속도, G값, 선택 루트, 주행 요약이 포함될 수 있습니다.
- 사용자 식별자: Supabase 익명 또는 사용자 ID를 사용해 사용자별 기록을 분리합니다.
- 루트 피드백: 루트 평가, 위험 신고, 숨김, 다시 추천하지 않기 선택을 저장할 수 있습니다.
- 탐험 진행 정보: 실제 주행을 저장한 뒤 생성되는 저해상도 지도 셀 ID입니다. 탐험 기능을 위해 별도의 시간순 GPS 원본 경로를 추가 업로드하지 않습니다.

## 3. How We Use Data / 데이터 사용 목적

We use data only for app functionality, including:

- Finding relevant driving routes.
- Showing route progress during a drive.
- Saving and restoring drive history.
- Restoring coarse explored-map progress for the current anonymous or identified REVV cloud identity.
- Improving route recommendation quality.
- Responding to route feedback and resolving app issues.

수집한 데이터는 다음 목적에만 사용합니다.

- 관련성 높은 주행 루트 추천.
- 주행 중 루트 진행 안내.
- 주행 기록 저장 및 복원.
- 현재 REVV 익명 또는 식별 클라우드 ID에 연결된 저해상도 탐험 진행 복원.
- 루트 추천 품질 개선.
- 루트 피드백 대응 및 앱 문제 해결.

## 4. Data Sharing / 데이터 공유

REVV does not sell personal data and does not use collected data for third-party advertising tracking.

REVV uses Supabase for anonymous authentication, cloud storage, and server functions; Mapbox for map display, place search and geocoding, directions, route matching, and SDK telemetry; and OpenWeatherMap for weather information. Place searches send the entered search text and, when available, a proximity coordinate directly to Mapbox. Directions and route matching send the required route coordinates to Mapbox. The Mapbox SDK may also send de-identified location, usage, performance, and diagnostic data, with telemetry controls available through the Mapbox attribution control. Weather requests send coordinates to REVV's Supabase server function, which forwards coordinates to OpenWeatherMap to retrieve current conditions.

The shipped app does not send per-user location queries to the Overpass API. Overpass may be used only in offline/internal route-data enrichment, not for a user's live in-app route search.

When a user chooses to open external navigation, REVV sends the selected route coordinates, and when applicable the current or saved home location, to Google Maps or Waze through an HTTPS link so that the provider can calculate and display directions. This transfer occurs only after the user selects the external navigation action and is then governed by the provider's privacy policy.

REVV는 개인정보를 판매하지 않으며, 제3자 광고 추적 목적으로 데이터를 사용하지 않습니다.

REVV는 익명 인증·클라우드 저장·서버 기능을 위해 Supabase를, 지도 표시·장소 검색 및 지오코딩·경로 안내·경로 매칭·SDK 텔레메트리를 위해 Mapbox를, 날씨 정보 제공을 위해 OpenWeatherMap을 사용합니다. 장소 검색 시 입력한 검색어와 가능한 경우 근접 좌표가 Mapbox에 직접 전달됩니다. 경로 안내와 경로 매칭에는 필요한 루트 좌표가 Mapbox에 전달됩니다. Mapbox SDK는 비식별 위치·사용·성능·진단 데이터를 전송할 수 있으며, Mapbox 저작자 표시 컨트롤에서 텔레메트리 설정을 이용할 수 있습니다. 날씨 요청 시 좌표가 REVV의 Supabase 서버 함수로 전달되고, 해당 함수가 현재 날씨 조회를 위해 좌표를 OpenWeatherMap에 전달합니다.

출시 앱은 사용자별 위치 질의를 Overpass API로 보내지 않습니다. Overpass는 사용자의 실시간 앱 내 루트 검색이 아니라 오프라인/내부 루트 데이터 보강에만 사용될 수 있습니다.

사용자가 외부 내비게이션 열기를 선택하면 REVV는 경로 계산과 표시를 위해 선택한 루트 좌표와 필요한 경우 현재 위치 또는 저장한 집 위치를 HTTPS 링크로 Google Maps 또는 Waze에 전달합니다. 이 전달은 사용자가 외부 내비게이션 동작을 직접 선택한 경우에만 발생하며, 이후 처리는 각 제공자의 개인정보 처리방침을 따릅니다.

## 5. User Controls / 사용자 제어

Users can:

- Turn cloud drive history storage on or off in the app.
- Delete saved driving records in the app.
- Delete explored-map progress together with saved driving records.
- Delete the guest cloud account and its associated server-side data in the app.
- Arm automatic recording for one selected route; background location is used only while that armed/active drive is running and remains visibly indicated by the operating system. On iOS, REVV requests When-In-Use authorization, not Always authorization.
- Change location permission in iOS Settings.

사용자는 다음을 제어할 수 있습니다.

- 앱에서 클라우드 주행 기록 저장을 켜거나 끌 수 있습니다.
- 앱에서 저장된 주행 기록을 삭제할 수 있습니다.
- 저장된 주행 기록과 함께 탐험 지도 진행을 삭제할 수 있습니다.
- 앱에서 게스트 클라우드 계정과 연결된 서버 데이터를 삭제할 수 있습니다.
- 선택한 루트 한 개에 대해서만 자동 기록을 준비할 수 있습니다. 백그라운드 위치는 해당 준비/주행이 진행 중일 때만 사용되며 운영체제 위치 표시가 유지됩니다. iOS에서는 Always 권한이 아닌 사용 중(When-In-Use) 위치 권한을 요청합니다.
- iOS 설정에서 위치 권한을 변경할 수 있습니다.

## 6. Data Retention / 데이터 보관

Drive records may be stored until the user deletes them. Pending local upload data may be temporarily stored on the device to prevent drive data loss when the network is unavailable.

주행 기록은 사용자가 삭제할 때까지 저장될 수 있습니다. 네트워크가 불안정할 때 주행 데이터 손실을 막기 위해 업로드 대기 데이터가 기기에 일시적으로 저장될 수 있습니다.

## 7. Contact / 문의

For privacy questions or deletion requests, contact:

Email: gksalsdn1234559@gmail.com

개인정보 관련 문의 또는 삭제 요청은 아래로 연락해 주세요.

이메일: gksalsdn1234559@gmail.com

## 8. App Support / 앱 지원

For help with REVV, email gksalsdn1234559@gmail.com. Include the app version,
iOS version, device model, and a short description of the issue. Do not send
passwords, authentication codes, or precise trip and location history.

REVV 사용 관련 지원은 gksalsdn1234559@gmail.com으로 문의해 주세요. 앱 버전,
iOS 버전, 기기 모델, 문제에 대한 간단한 설명을 포함해 주세요. 비밀번호, 인증
코드, 상세 주행 또는 위치 기록은 보내지 마세요.
