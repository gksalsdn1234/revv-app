# REVV Lean MVP — Claude 컨텍스트

**이 레포가 유일한 활성 작업 경로다** (`lean_mvp` 브랜치). `~/revv-app`(구버전)·`~/Documents/revv-app`(백업 + `route-selector-proto` 브랜치)은 참조용.

## 앱 한 줄
드라이빙 루트 추천 + 주행 기록. "좋은 길을 알려주고, 달리면 내 지도가 칠해진다." 캐나다 기준.

## 북극성 (모든 결정의 기준)
`docs/2026-07-02-launch-plan.md` 0~2.6장 — V1 범위 잠금: 파인더(플래너 흡수) + 학습루프 DB + 출시. 새 아이디어는 V2+ 백로그로. 내비·계기판·만인용 여행앱은 안 만든다 (경량 코파일럿 안내는 예외 확정, 2026-07-09). 실주행 검증 없는 루트 기능 출고 금지.

## 절대 규칙
- **안전 언어**: 속도·기록 자극 표현 금지 (MAX/BEST/PK/신기록 등). 코파일럿 발화는 페이스노트 문법 — 방향+성격만, 기어·스로틀·속도 지시 금지
- **화면 문자열은 한/영/불 3언어 세트**, v5 토큰(AppColors/AppText)
- **push는 민우 승인 후만**. `PLAN.md`·`plans/`·`codex-build.sh` 커밋 금지
- 커뮤니케이션: 한국어. 좋은 아이디어는 작업 완료 후 간략 제안

## 작업 체제 (Codex 핸드오프)
- Claude = 플랜(`plans/X.md`)·리뷰·검증·커밋 / Codex = 구현: `./codex-build.sh plans/X.md < /dev/null > 로그 2>&1 &`
  - **stdin 반드시 닫기** (`< /dev/null`) — 안 닫으면 "Reading additional input from stdin" 무한 대기 (로그 3줄 정지가 시그니처)
  - **보이는 티커 태스크 필수** (로그 정지 감지 포함) — 무음 감시 루프 금지
  - Codex 한도 시 Claude 직접 구현 허용 (민우 승인). CLI 400 "requires newer version" → `npm i -g @openai/codex`
  - 대형 구조 웨이브는 상위 모델(-c model=…)+high, 중소형은 기본 모델 (한도 관리)
- 매 웨이브 후 Claude 독립 검증: `/Users/minwoohan/flutter/bin/flutter analyze && flutter test` (Codex 샌드박스는 SDK 캐시 쓰기 불가 — 자체 검증 실패 보고는 정상)
- **Codex 웨이브 후 실기기 빌드 전 `flutter pub get` 필수** (샌드박스가 pub 경로를 /private/tmp로 오염)

## 빌드·배포
- 실기기: `flutter build ios --release --dart-define-from-file=.env --dart-define=REVV_WALKIE_LAB=true` → `xcrun devicectl device install app --device <id> build/ios/iphoneos/Runner.app` → `devicectl device process launch --device <id> com.revv.revvApp`
  - 민우폰 `00008120-000621623E90A01E` · Geon폰 `00008120-00162D5C3C70201E`(USB) · flutter run 무선 launch는 자주 실패 — devicectl이 안정적
- `.env`: SUPABASE_URL/ANON_KEY + MAPBOX_ACCESS_TOKEN (커밋 금지). Mapbox secret: `~/.mapbox_secret` (스타일 편집용, rotate 예정)
- 심사 빌드는 `REVV_WALKIE_LAB` **제외** (워키는 V2 랩 기능)
- 시뮬레이터: debug만 지원, `xcrun simctl location <id> set 45.5017,-73.5673` + `simctl io <id> screenshot`으로 무권한 캡처 가능 (부트=파인더라 첫 화면 검수 용이)

## 현재 아키텍처 (2026-07-10)
- **부트 → 파인더** (홈 소멸): 탭 = 지도/기록/설정 (`lean_app_shell_screen`)
- **파인더 = 루트 셀렉터**: 지도 라인이 피커 — 탭=프리뷰 카드(상세·➕체인)→상세, 무번호 리스트 시트, 상단은 목적지 필 하나. 정복 잔광(달린 길 레드)·생추천(free-roam)
- **여정 시트** `widgets/journey_sheet.dart`: 옵션·타임라인·기본vs REVV 비교·드라이브 시작·외부내비(entry+key1~2+exit)
- **코파일럿**: 랠리 페이스노트 단일 음성("300, 우측 갈림길 — 바로 좌 타이트"), enhanced 보이스, 이탈 재계산(60s 쿨다운), 구글 핸드오프↔복귀 자동 재개(pending_drive)
- **워키토키**(랩 플래그): Supabase Realtime PCM16 — 배칭·지터버퍼·자동재연결·반이중·보이스웨이브
- **지도**: REVV Signature v1 `mapbox://styles/mingwoo/cmrd3w7yt005f01qo8l1f4anc` (도로 위계 반전 다크). 스프린트는 navigation-night. 런치 이미지는 브랜드 레드
- **DB (전부 라이브)**: curvy_roads(83k 읽기전용) · runs/run_details · route_feedback · recommendation_logs(shown/chosen) · telemetry_summary(급제동·급조작·부드러움) · photo_spots·route_scores(V2/V3 그릇) · user_preferences(빈 그릇) · crew_channels/members
- **마이그레이션 규칙**: 파일은 `supabase/migrations/`, `test/supabase_migrations_security_test.dart`에 등록 필수(fail-closed RLS 패턴). 라이브 적용은 Claude가 Supabase MCP로

## 릴리즈 블로커/보류
- `assets/sounds/beep.mp3` = F1 방송 클립 — 제출 전 교체 (오리지널: `git show b8abd21:assets/sounds/beep.mp3`). 민우 결정: 테스트 중엔 유지
- 잔여 수동 항목: `docs/prelaunch_remaining_manual.md`

## GitHub
- Repo: https://github.com/gksalsdn1234/revv-app (Private) — push는 승인 후
