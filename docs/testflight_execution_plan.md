# REVV TestFlight Execution Plan

목표: `lean_mvp` 브랜치를 1차 iOS TestFlight 베타로 올린다.

이 문서는 다음 Codex 세션에서도 바로 이어서 작업할 수 있는 실행 계획서다. 작업을 재개하면 먼저 이 파일과 `docs/release_quality_checklist.md`를 읽고, 현재 상태를 확인한 뒤 아래 순서대로 진행한다.

## Resume Protocol

1. 현재 브랜치를 확인한다.

```sh
git status --short --branch
```

2. 반드시 `lean_mvp`에서만 출시 작업을 진행한다. `main`은 안정 백업으로 둔다.
3. 현재 검증 상태를 확인한다.

```sh
flutter analyze
flutter test
flutter build ios --release --no-codesign --dart-define-from-file=.env
```

4. 아래 `Execution Blocks`에서 아직 완료되지 않은 첫 번째 블록부터 진행한다.
5. 완료한 항목은 이 문서와 `docs/release_quality_checklist.md`에 체크한다.
6. TestFlight 전 마지막에는 변경사항을 커밋하고 `origin/lean_mvp`로 푸시한다.

## Current Known State

마지막 확인일: 2026-05-07

- [x] 브랜치: `lean_mvp`
- [x] `flutter analyze` 통과
- [x] `flutter test` 통과
- [x] `flutter build ios --release --no-codesign --dart-define-from-file=.env` 통과
- [x] Firebase / Bluetooth / Speech / TTS / Audio 의존성 제거 확인
- [x] `Info.plist` 권한은 위치 When-In-Use만 유지
- [x] `PrivacyInfo.xcprivacy` Runner 리소스 포함
- [x] `.env.example` 필수 키 정리: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `MAPBOX_ACCESS_TOKEN`
- [x] 버전: `1.38.0+39`
- [x] Bundle ID: `com.revv.revvApp`
- [x] Apple Team: `BMG2X5W7V9`
- [x] 릴리즈 후보 커밋/푸시
- [ ] IPA export
- [ ] App Store Connect 업로드
- [ ] 실기기 10분 주행 smoke test
- [ ] 외부 TestFlight 베타 오픈

## Execution Blocks

### Block 1. Release Candidate Freeze

목표: 지금 작동하는 상태를 잃지 않도록 릴리즈 후보를 고정한다.

작업:

- [x] `git status --short --branch`로 변경 범위 확인
- [x] 민감정보가 git에 들어가지 않았는지 확인
- [x] `flutter analyze` 실행
- [x] `flutter test` 실행
- [x] `flutter build ios --release --no-codesign --dart-define-from-file=.env` 실행
- [x] `docs/release_quality_checklist.md`와 이 문서의 상태 갱신
- [x] 커밋 생성
- [x] `origin/lean_mvp`로 푸시

검증 명령:

```sh
git status --short --branch
rg "SUPABASE_ANON_KEY=|MAPBOX_ACCESS_TOKEN=|eyJhbGci|sk-|service_role" . -g '!pubspec.lock' -g '!ios/Podfile.lock'
flutter analyze
flutter test
flutter build ios --release --no-codesign --dart-define-from-file=.env
```

커밋 메시지 후보:

```sh
git add .
git commit -m "Prepare lean MVP for TestFlight beta"
git push origin lean_mvp
```

완료 기준:

- `analyze/test/release no-codesign build`가 모두 통과한다.
- 커밋이 생성되고 GitHub에 푸시된다.
- `.env` 또는 실제 비밀키가 커밋되지 않는다.

### Block 2. iPhone Core Flow Smoke Test

목표: 친구가 앱을 설치했을 때 첫 사용 흐름이 막히지 않게 한다.

작업:

- [ ] 앱 삭제 후 재설치
- [ ] 첫 실행 위치 권한 안내 확인
- [ ] 위치 권한 허용 시 홈 진입 확인
- [ ] 위치 권한 거부 시 루트 탐색 제한 안내 확인
- [ ] 홈에서 `루트 찾기` 진입 확인
- [ ] 루트파인더에서 루트 후보 표시 확인
- [ ] 반경 변경: `50km`, `100km`, `160km`
- [ ] 표시 개수 변경: `16`, `24`, `32`
- [ ] 지도 마커 선택 시 루트 상세 시트 표시 확인
- [ ] `자세히 보기`가 상세 화면으로 이동하는지 확인
- [ ] `주행 시작`이 주행 화면으로 이동하는지 확인
- [ ] 주행 화면에서 현재 위치 추적 확인
- [ ] 다음 커브 안내 배너 확인
- [ ] `주행 종료` 버튼 확인
- [ ] 종료 후 요약 저장 확인
- [ ] 앱 재시작 후 기록 복원 확인

실행 명령:

```sh
flutter run --release --dart-define-from-file=.env -d 00008120-000621623E90A01E
```

완료 기준:

- 앱 시작부터 요약 저장까지 크래시 없이 이어진다.
- 사용자가 다음에 뭘 해야 하는지 화면에서 명확히 보인다.
- 루트파인더에서 지도, 마커, 하단 티켓이 서로 가리지 않는다.

### Block 3. Failure State Validation

목표: 데이터가 없거나 설정이 빠져도 앱이 고장난 것처럼 보이지 않게 한다.

시나리오:

- [ ] `.env` 없이 실행: 클라우드/지도 설정 안내 확인
- [ ] Supabase 설정 정상: 루트 후보 로드 확인
- [ ] Supabase 후보 0개: 반경 확장 제안 확인
- [ ] 네트워크 실패: 재시도 안내 확인
- [ ] 위치 권한 거부: 설정 이동 안내 확인
- [ ] 캐시 있음: 캐시 기반 후보 표시 확인
- [ ] 캐시 없음: 후보 없음 안내 확인

확인할 사용자 문구:

- Supabase 미설정: `클라우드 설정이 필요해요`
- 루트 후보 0개: `후보가 적어요. 반경을 넓혀볼까요?`
- 위치 거부: `위치 권한이 필요해요`
- 지도 토큰 없음: `지도 설정이 필요해요`

완료 기준:

- 실패 상태에서 크래시가 없다.
- 화면에는 원인과 다음 액션이 하나씩만 보인다.
- 사용자가 앱이 멈췄다고 느끼지 않는다.

### Block 4. IPA Export And Upload

목표: App Store Connect에 올릴 수 있는 `.ipa`를 만든다.

사전 확인:

- [ ] Apple Developer 계정 활성
- [ ] Bundle ID: `com.revv.revvApp`
- [ ] Team: `BMG2X5W7V9`
- [ ] Apple Distribution certificate 준비
- [ ] App Store provisioning profile 준비
- [ ] Xcode Signing 설정 확인

빌드 명령:

```sh
flutter build ipa --release --dart-define-from-file=.env --build-name=1.38.0 --build-number=39
```

업로드 방법:

- Xcode Organizer에서 업로드
- 또는 Transporter로 `.ipa` 업로드

완료 기준:

- `build/ios/ipa/*.ipa`가 생성된다.
- App Store Connect 빌드 목록에 `1.38.0 (39)`가 처리 완료 상태로 보인다.
- Firebase 초기화 실패, 권한 누락, 서명 오류가 없다.

실패 시 확인할 항목:

- Provisioning profile이 App Store용인지 확인
- Bundle ID가 `com.revv.revvApp`와 일치하는지 확인
- Team이 `BMG2X5W7V9`인지 확인
- `objective_c.framework` 서명 phase가 유지되는지 확인

### Block 5. App Store Connect Beta Setup

목표: Beta App Review를 통과할 최소 정보를 준비한다.

작업:

- [ ] 앱 이름 확인: `Revv App`
- [ ] 카테고리 선택
- [ ] 앱 설명 작성
- [ ] 스크린샷 준비
- [ ] 개인정보 처리방침 URL 준비
- [ ] App Privacy 답변 작성
- [ ] Beta App Review Notes 작성
- [ ] 내부 테스터 추가
- [ ] 외부 테스터 그룹 생성
- [ ] 피드백 받을 이메일/채널 정리

Beta Review Notes 초안:

```text
REVV is a route discovery and driving rhythm copilot app. Testers can grant location permission, find nearby driving routes, preview a route, start a drive, and save a post-drive summary. No login is required for the current beta. Location permission is required for route recommendations and active drive tracking.
```

Privacy 답변 기준:

- Tracking: 사용하지 않음
- Precise Location: 앱 기능 제공
- User ID: Supabase 사용자 데이터 분리
- Run Data: 주행 기록 복원 및 리포트 생성
- Microphone / Speech / Bluetooth / OBD: 이번 MVP에서 사용하지 않음

완료 기준:

- 내부 TestFlight 설치 가능
- 외부 TestFlight 제출 가능
- Beta Review에서 기능 설명과 권한 사용 목적이 일치한다.

### Block 6. 10 Minute Real Drive Smoke Test

목표: 실제 도로에서 최소한의 주행 안정성을 확인한다.

테스트 절차:

- [ ] 배터리 30% 이상
- [ ] 위치 권한 허용
- [ ] 루트 하나 선택
- [ ] 주행 시작
- [ ] 10분 이상 앱 유지
- [ ] 현재 위치 추적 확인
- [ ] 다음 커브 안내 확인
- [ ] 앱 백그라운드/복귀 1회 확인
- [ ] 주행 종료
- [ ] 요약 저장
- [ ] 앱 재시작 후 기록 확인

기록할 것:

- 시작 시간
- 종료 시간
- 선택 루트명
- 크래시 여부
- 지도 끊김 여부
- 위치 추적 끊김 여부
- 요약 저장 여부
- 사용 중 헷갈린 화면

완료 기준:

- 10분 동안 크래시가 없다.
- 주행 종료와 요약 저장이 정상 동작한다.
- TestFlight 친구 테스트를 막을 정도의 P0 버그가 없다.

## Beta Launch Gate

아래 항목이 모두 체크되면 외부 TestFlight를 열 수 있다.

- [ ] Block 1 완료
- [ ] Block 2 완료
- [ ] Block 3 주요 실패 상태 확인
- [ ] Block 4 완료
- [ ] Block 5 완료
- [ ] Block 6 완료

열어도 되는 베타 규모:

- 1차: 본인 + 내부 테스터 1-2명
- 2차: 가까운 친구 3-5명
- 3차: 운전 성향이 다른 사용자 10명 내외

## Feedback Collection

친구들에게 받을 질문은 길게 하지 않는다.

필수 질문:

1. 루트가 “달려보고 싶은 길”처럼 느껴졌는가?
2. 왜 추천됐는지 이해됐는가?
3. 주행 중 다음 커브 안내가 도움이 됐는가?
4. 어디서 막혔거나 헷갈렸는가?
5. 다시 켜볼 이유가 있었는가?

앱 내 피드백은 P1 이후로 미루고, 첫 베타는 카톡/메시지/노션으로 받아도 된다.

## Do Not Expand Scope Before Beta

TestFlight 전에는 아래 기능을 추가하지 않는다.

- OBD 재작업
- AI 리뷰 고도화
- Google TTS
- CarPlay
- 오프라인 지도
- 커뮤니티
- 결제/구독
- 풀 루트 생성기

이 기능들은 매력적이지만 지금은 베타 오픈을 늦추는 리스크가 더 크다.

## Next Action

현재 다음 액션은 Block 1이다.

1. 변경사항 확인
2. 민감정보 grep
3. `analyze/test/release no-codesign build`
4. 문서 체크 갱신
5. 커밋
6. 푸시
