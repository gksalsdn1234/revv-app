# REVV TestFlight 배포 체크리스트

목표: `lean_mvp` 브랜치를 친구/초기 테스터가 설치할 수 있는 iOS TestFlight 베타로 올린다. 이번 배포는 공개 App Store 출시가 아니라, 실제 주행 피드백을 받기 위한 베타 배포다.

## 0. 배포 범위 고정

- [ ] 브랜치가 `lean_mvp`인지 확인한다.
- [ ] `main`은 건드리지 않는다.
- [ ] 이번 빌드 범위는 `홈 -> 루트 찾기 -> 루트 상세 -> 주행 시작 -> 주행 종료 -> 요약 저장`으로 고정한다.
- [ ] OBD, AI 리뷰, TTS, STT, Garage, 결제, Android는 이번 TestFlight 차단 범위에서 제외한다.
- [ ] 알려진 미완성 기능은 베타 노트에 솔직하게 적는다.

## 1. 로컬 코드 검증

- [ ] `flutter analyze` 통과.
- [ ] `flutter test` 통과.
- [ ] `flutter build ios --release --no-codesign --dart-define-from-file=.env` 통과.
- [ ] Firebase, Bluetooth, Speech, TTS, Audio 관련 문자열이 남아 있지 않은지 확인한다.

```sh
rg "Firebase|cloud_functions|firebase_core|flutter_blue_plus|speech_to_text|flutter_tts|audioplayers|share_plus" lib pubspec.yaml ios/Podfile.lock
```

위 명령은 결과가 없어야 한다.

## 2. 환경값 확인

- [ ] `.env`에 `SUPABASE_URL`이 있다.
- [ ] `.env`에 `SUPABASE_ANON_KEY`가 있다.
- [ ] `.env`에 `MAPBOX_ACCESS_TOKEN`이 있다.
- [ ] `.env`는 git에 커밋하지 않는다.
- [ ] `.env.example`에는 키 이름만 있고 실제 secret은 없다.
- [ ] Supabase anon key는 RLS 기준 공개 가능한 anon key인지 확인한다.
- [ ] 새 Supabase/staging 프로젝트에 active migrations를 적용했을 때 `curvy_roads`, `runs`, `run_details`, `route_feedback`, `route_records`, `saved_routes`, `discovered_routes`가 생성되고 Data API GRANT가 적용되는지 확인한다.
- [ ] Supabase Security Advisor에서 RLS/GRANT 경고가 없는지 확인한다.
- [ ] `docs/supabase_security_verification.md`의 local preflight와 remote dry run을 완료한다.

## 3. iOS 설정 확인

- [ ] Bundle ID: `com.revv.revvApp`.
- [ ] Team: `BMG2X5W7V9`.
- [ ] Display Name: `Revv App`.
- [ ] Version: `1.38.0`.
- [ ] Build Number: `42` 또는 이전 업로드보다 높은 숫자.
- [ ] App icon이 기본 Flutter 아이콘이 아닌 REVV 아이콘인지 확인한다.
- [ ] Launch screen이 기본 Flutter 화면이 아닌지 확인한다.
- [ ] `Info.plist` 권한 문구는 실제 요청 권한인 위치 When-In-Use를 설명하고, permission library가 참조할 수 있는 Speech/Always Location purpose string도 방어적으로 포함한다.
- [ ] `Info.plist`에 `ITSAppUsesNonExemptEncryption=false`가 포함되어 표준 HTTPS 암호화만 사용하는 베타임을 명시한다.
- [ ] `ios/Runner/PrivacyInfo.xcprivacy`가 Runner target에 포함되어 있다.

## 4. 개인정보 / App Store Connect 입력 준비

- [ ] Tracking: 사용하지 않음.
- [ ] Location: 루트 추천, 지도 현재 위치 표시, 주행 기록 저장에 사용.
- [ ] User ID: Supabase 사용자 식별 및 사용자별 기록 분리에 사용.
- [ ] Usage Data / Diagnostics: 현재 명시적으로 수집하는 항목만 입력한다.
- [ ] Run Data: 주행 거리, 시간, 경로 샘플, 속도, G 값, 피드백을 저장하며 클라우드 저장 토글과 삭제 기능을 제공한다고 명시한다.
- [ ] 업로드 실패 시 주행 상세는 pending 안전망에만 남고, 업로드 성공 후 로컬 상세 payload가 삭제된다고 내부 검증한다.
- [ ] 업로드 실패 pending 상세 payload는 14일 TTL 이후 자동 삭제되는지 내부 검증한다.
- [ ] Microphone, Bluetooth, Contacts, Photos는 이번 MVP에서 사용하지 않음으로 정리한다. Speech Recognition/Always Location은 앱에서 요청하지 않지만 App Store binary scanner 대응용 purpose string이 포함될 수 있음을 리뷰 노트에 설명한다.
- [ ] 개인정보 처리방침 URL을 준비한다. 1차 TestFlight는 Notion 공개 페이지를 사용하고, 앱 내부 `개인정보 처리방침` 링크도 같은 URL을 연다.
- [ ] `.env`의 `PRIVACY_POLICY_URL`에 Notion 공개 URL을 입력한다.
- [ ] Beta App Review Notes에 위치 권한이 필요한 이유와 테스트 방법을 적는다.

## 5. 릴리즈 빌드 생성

```sh
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release --dart-define-from-file=.env --build-name=1.38.0 --build-number=43
```

- [ ] `build/ios/ipa/*.ipa`가 생성된다.
- [ ] 빌드 넘버가 App Store Connect에 이미 올라간 빌드보다 높다.
- [ ] 업로드 실패 시 signing, provisioning profile, bundle id를 먼저 확인한다.

## 6. App Store Connect 업로드

- [ ] Xcode Organizer 또는 Transporter로 `.ipa`를 업로드한다.
- [ ] App Store Connect에서 빌드 처리가 완료될 때까지 기다린다.
- [ ] TestFlight 탭에서 빌드가 표시되는지 확인한다.
- [ ] Internal Testing 그룹에 먼저 추가한다.
- [ ] 내부 테스트로 앱 실행, 지도 로드, 루트 로드, 주행 시작이 되는지 확인한다.

## 7. 실기기 Smoke Test

- [ ] 앱 삭제 후 TestFlight 빌드로 재설치한다.
- [ ] 첫 실행 위치 권한 설명이 자연스럽게 보인다.
- [ ] 위치 허용 시 홈으로 진입한다.
- [ ] 위치 거부 시 루트 탐색 제한 안내가 보인다.
- [ ] 루트파인더에서 후보가 뜬다.
- [ ] 반경 변경이 동작한다.
- [ ] `이 지역` 검색이 지도 중심 기준으로 동작한다.
- [ ] 루트 상세 화면이 열린다.
- [ ] `주행 시작`이 동작한다.
- [ ] 주행 화면에서 현재 위치가 추적된다.
- [ ] 다음 커브/이탈/복귀 안내가 과하게 튀지 않는다.
- [ ] `주행 종료` 버튼이 쉽게 보이고 눌린다.
- [ ] 요약 저장 후 기록이 남는다.
- [ ] 앱 재시작 후 기록이 복원된다.
- [ ] 최소 10분 실주행 중 크래시가 없다.

## 8. 외부 테스터 배포

- [ ] External Testing 그룹을 만든다.
- [ ] 첫 외부 배포는 Beta App Review가 필요할 수 있으므로 심사 제출 시간을 고려한다.
- [ ] Beta Review Notes에 아래를 포함한다.
- [ ] 테스트 계정이 필요 없다면 “No login required”라고 적는다.
- [ ] 위치 권한 허용 후 루트 찾기 버튼을 누르면 테스트 가능하다고 적는다.
- [ ] 안전 안내: 운전 중 조작하지 말고 정차 중 테스트하라고 적는다.
- [ ] Public Link를 켤지, 이메일 초대로만 할지 결정한다.

Beta Review Notes 예시:

```text
REVV is a driving route discovery beta. No login is required.
To test: allow location permission, open Route Finder, select a route, view details, start a drive, then end the drive to see the summary.
The app uses location to recommend nearby driving routes and record a local run summary. Please test while parked or with a passenger operating the phone.
```

## 9. 테스터에게 보낼 안내문

```text
REVV TestFlight 베타 링크입니다.

해볼 것:
1. 위치 권한 허용
2. 루트 찾기에서 후보 확인
3. 마음에 드는 루트 상세 보기
4. 가능하면 짧게 주행 시작/종료까지 테스트
5. 이상한 점, 헷갈리는 화면, 루트 품질 피드백 보내기

운전 중 직접 조작하지 말고, 정차 중이거나 동승자가 조작해 주세요.
```

## 10. 피드백 수집

- [ ] TestFlight feedback을 App Store Connect에서 확인한다.
- [ ] 앱 내 주행 후 피드백이 저장되는지 확인한다.
- [ ] 별도 Google Form/Notion/웹 폼 중 하나를 준비한다.
- [ ] 피드백은 `크래시`, `루트 안 뜸`, `지도 문제`, `주행 시작 문제`, `루트 품질`, `UI 헷갈림`, `아이디어`로 분류한다.
- [ ] 첫 10명 피드백 전까지 새 기능 추가보다 P0 버그 수정만 한다.

## 11. Go / No-Go 기준

Go:

- [ ] 앱이 TestFlight에서 설치된다.
- [ ] 첫 실행이 크래시 없이 열린다.
- [ ] 지도와 현재 위치가 보인다.
- [ ] 루트 후보가 최소 1개 이상 뜨거나, 실패 이유가 명확히 보인다.
- [ ] 루트 상세과 주행 시작이 동작한다.
- [ ] 주행 종료 후 요약 저장이 된다.
- [ ] 10분 실기기 smoke test에서 크래시가 없다.

No-Go:

- [ ] 앱 실행 크래시.
- [ ] 위치 권한 허용 후에도 지도/루트가 전혀 동작하지 않음.
- [ ] 주행 시작이 막힘.
- [ ] 주행 종료가 불가능함.
- [ ] 기록 저장 중 크래시.
- [ ] 개인정보/권한 설명이 실제 동작과 다름.

## 공식 참고

- [Apple TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)
- [Apple TestFlight external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)
- [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Apple Required Reason APIs / Privacy Manifest](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [Flutter iOS deployment](https://docs.flutter.dev/deployment/ios)
