# 심사 준비 리뷰 — 2026-07-21 새벽 (Claude 인수인계 세션)

민우 지시: "인수인계받아서 심사받아도 되는지 다 뜯어서 코드 리뷰 + UI/UX + 유저 관점 리뷰, 구현은 Codex 위임."
이 세션에서 실측한 것만 기록. 추정엔 (추정) 표시.

## 요약 판정: 코드는 심사 제출 가능 상태에 근접. 남은 블로커는 3개, 그중 2개는 코드가 아니라 민우 손.

- `flutter analyze` 0건, `flutter test` **441개 전부 통과** (이 세션 실행 결과)
- 안전 카피 라운드 2(PLAN.md "높음" 22건)는 **구현 완료 상태** — G METER/PK/BEST G/GRIP/Attack 화면 문자열 grep 결과 0건. 유일한 잔재는 아래 F2
- 워키토키는 `bool.fromEnvironment('REVV_WALKIE_LAB')` 게이트로 심사 빌드에서 완전 제외됨 (기본 false 확인)

## 블로커 (제출 전 반드시)

### B1. beep.mp3 = F1 방송 클립 (라이선스 없음) — 기존 문서화된 블로커, 아직 미해결
- 실측: `git log -- assets/sounds/beep.mp3` → 9e3bb5d(오리지널 복원) 후 757ddf7(**revert, F1 클립 복귀**), 파일 7,818B (7/6)
- 민우 7/6 결정 "지금은 유지, 제출 직전 재확인" → 지금이 그 재확인 시점. **Codex 플랜에 교체 작업 포함함** (오리지널 합성음 복원)

### B2. 미푸시 커밋 다수 (민우 몫)
- `git push origin lean_mvp`는 민우 승인 사항이라 실행 안 함

### B3. 실기기 검증 잔여 (민우 몫 — release_quality_checklist P0 미체크 항목)
- Supabase 정상/미설정/네트워크실패/후보0/캐시 상태 실기기 확인 · 10분 주행 크래시 스모크 · 플래너 빨간 와인딩 선 재확인

## 발견 사항 (이 세션 신규)

### F1. 백그라운드 오디오 모드 정당성 — 문제없음, 단 심사 노트 필요
- `UIBackgroundModes: [audio]`인데 워키(마이크 오디오)는 심사 빌드 제외 → 언뜻 거부 사유(가이드라인 2.16)로 보임
- 추적 결과 정당함: `VoiceBriefingService`(flutter_tts, 주행 중 코너 음성 브리핑)가 lean 빌드에 활성 — 폰 잠근 채 주행할 때 발화하려면 필요 (내비 앱 패턴)
- **조치**: 심사 노트에 "Background audio is used solely for turn-by-turn style voice corner briefings during an active drive session" 명시 (민우가 App Store Connect 심사 노트에 붙여넣기)

### F2. 금지어 잔재 1건 — `lib/ui/app_copy.dart:348` `'최고 속도'/'Max speed'`
- 사용처는 `maxSpeedInternalOnly` 하나뿐이고 공유 카드 렌더에서 `internalOnly` 필터로 걸러짐 → **현재 화면 노출 없음** (grep으로 소비처 전수 확인)
- 그래도 금지 어휘 사전(PLAN 절대 규칙)에 걸리는 문자열이 카피 파일에 남아 있으면 미래 사용 사고 위험 → 중립 명칭으로 교체 (Codex 플랜 포함)

### F3. iOS 권한 문구에 한국어 없음 (EN/FR만)
- KR 출시 계획 고려하면 `InfoPlist.strings` ko 로컬라이즈 필요. 단 1차 심사(북미)는 EN/FR로 충분 → **이번 라운드 제외**, P2 백로그

### F4. UI/UX·유저 관점 (코드 기준 — 실기기 아님)
- 잘된 것: 권한 프라이밍 화면(거부해도 진행 가능 고지) · 파인더 상태 분리(타임아웃/빈 결과/캐시 안내 + 재시도) · 3개 국어 카피 시스템 일관 · 위험 문구 없음
- 관찰 1: 주행 HUD는 속도(민우 결정 유지)+밸런스+종료로 단순 — P0 "필수 정보와 종료 버튼만" 코드상 충족 (실기기 확대경은 민우 확인)
- 관찰 2 (추정): 첫 실행에서 "이 앱이 뭐 하는 앱인지" 설명이 권한 화면 외엔 얇음 — 심사엔 문제없고, 온보딩 1장은 V2 과제로

## Codex 위임 내역 — 완료 (2026-07-21 03:02~03:10)
- 플랜 파일: `plans/PLAN_20260721_review_fixes.md` (B1 + F2)
- Codex가 두 변경 수행: beep.mp3 7818→5421B (오리지널 합성음 복원) · '최고 속도'→'속도 상세' (키는 유지, 3개 국어)
- Codex 샌드박스가 git/flutter 캐시 쓰기를 막아 커밋·전체 테스트는 Claude가 마무리
- 최종 검증 (Claude 실행): `flutter analyze` 0건 · `flutter test` **441개 전부 통과** · `grep 최고` 0건
- 커밋: `40cc631` (beep) · `f688e5d` (카피) — push는 안 함 (민우 승인 대기)
- 블로커 B1 해소됨. 남은 블로커: B2(push 승인), B3(실기기 검증) — 둘 다 민우 몫

## 다음 세션 참고
- 이 리뷰 이후 코드 변경은 Codex 커밋 확인: `git log --oneline -5`
- 민우 기상 후 순서 제안: ① 실기기 스모크 ② push 승인 ③ 스크린샷·심사 노트(F1 문구) ④ 제출
