# REVV iOS TestFlight Release Quality Checklist

목표: 현재 통합 브랜치를 iOS App Store 심사 후보로 만든다. 범위는 루트 찾기, 코파일럿 TTS 안내, 주행, 요약 저장까지이며 OBD, AI 리뷰, STT, Garage, 고급 리포트는 이번 배포에서 제외한다.

현재 제출 순서와 남은 수동 항목은 `docs/app_store_submission_2026-07-14.md`를 기준으로 한다. `docs/testflight_execution_plan.md`는 이전 build 42/43의 이력 문서다.

## Distribution Status

2026-07-13 최종 심사 후보는 `1.38.0 (55)`다. 탐험 안개와 워키 랩은 비활성이고, 무허가 비프음은 패키지와 함께 제거했다. 모든 코드/UI 수정 후 Release archive를 `build/ios/archive/Runner.xcarchive`에 다시 생성했고, Apple Distribution 인증서/계정이 이 Mac에 없어 IPA export가 차단돼 있다. 최종 빌드의 실제 화면 스크린샷 6장은 완료됐고 App Store Connect 소유자 필드가 남아 있다.

## P0 - TestFlight 차단 항목

- [x] `codex/exploration-cloud-auto-record` 통합 브랜치에서 작업한다. `main`은 안정 백업으로 유지한다.
- [x] `.env.example`에 `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `MAPBOX_ACCESS_TOKEN`을 문서화한다.
- [x] 미사용 Flutter 의존성 및 iOS Pod 흔적이 제거됐는지 확인한다.
- [x] iOS 권한 문구를 실제 요청 권한인 위치 When-In-Use, Motion, 비활성 워키 랩의 Microphone 범위로 제한하고 Speech/Always Location 문구를 제거한다.
- [x] `ITSAppUsesNonExemptEncryption=false`를 `Info.plist`에 명시해 표준 HTTPS 암호화만 사용하는 베타임을 표시한다.
- [x] Firebase, Bluetooth, Speech, `audioplayers`, 무허가 beep/chirp 흔적이 앱/Pod lock에서 사라졌는지 확인한다. 주행 코파일럿 TTS와 기본 비활성 워키 랩의 `record`/`flutter_sound`는 의도적으로 포함한다.
- [x] Privacy manifest가 Runner 리소스에 포함됐는지 확인한다.
- [x] `flutter analyze`와 `flutter test`를 통과한다.
- [x] `flutter build ios --release --no-codesign --dart-define-from-file=/Users/minwoohan/Documents/revv-app/.env`를 통과한다.
- [ ] Xcode에 Apple Developer 계정을 추가하고 Apple Distribution certificate와 App Store provisioning profile을 설치/갱신한다.
- [ ] `flutter build ipa --release --dart-define-from-file=/Users/minwoohan/Documents/revv-app/.env --build-name=1.38.0 --build-number=55` export를 통과한다.
- [x] production Supabase에 `20260713120000_bound_route_search_and_canonical_geometry.sql`까지 적용하고 원격 migration/RLS/권한 smoke test를 완료한다.
- [x] 위치 권한 허용/거부 첫 실행 플로우를 확인한다.
- [ ] Supabase 정상, 미설정, 네트워크 실패, 후보 0개, 캐시 사용 상태 안내를 실기기에서 확인한다.
- [x] 루트 선택 -> 주행 시작 -> 현재 위치 추적 -> 주행 종료 -> 요약 저장 -> 앱 재시작 후 기록 복원을 확인한다.
- [ ] 실기기 10분 주행 smoke test 중 크래시가 없어야 한다.
- [ ] 주행 중 화면은 필수 정보와 종료 버튼만 명확히 보여야 한다.
- [ ] 위험 주행을 자극하는 속도/경쟁 문구가 없어야 한다.

## P1 - 베타 완성도

- [ ] 홈, 루트파인더, 주행, 요약 화면의 CTA를 `루트 찾기`, `주행 시작`, `주행 종료`, `요약 보기` 중심으로 통일한다.
- [ ] 루트 데이터 실패 상태를 사용자 문구로 분리한다.
- [x] 루트 데이터 실패 상태를 사용자 문구로 분리하는 코드 보강을 완료한다.
- [ ] 날씨 실패는 조용히 fallback하고 출시 차단으로 두지 않는다.
- [ ] App Store Connect 노트와 개인정보 답변 초안 및 route/detail/drive/history/settings 스크린샷은 준비됨. 실제 연락 이메일/지원 URL을 확정한다.
- [x] 기본 Flutter 아이콘/런치이미지를 고유 REVV 에셋으로 교체한다.
- [x] 표시 이름이 `REVV`로 설정되고 시뮬레이터/아카이브 설정과 일치하는지 확인한다.

## P2 - 공개 배포 전

- [ ] Open-Meteo 같은 무키 날씨 API로 단순화한다.
- [ ] 저장 루트/고급 기록/OBD/AI 리뷰를 제품 완성도 기준으로 다시 설계한다.
- [ ] Android 권한과 배포 정책은 별도 검증한다.
- [ ] Supabase RLS와 콘솔 설정을 최종 보안 리뷰한다.

## Cloud Data Controls

- [ ] 클라우드 기록 저장 토글이 기본 켜짐으로 표시된다.
- [ ] 토글을 끄면 상세 telemetry가 업로드/영구저장되지 않는다.
- [ ] 기록 삭제가 로컬 캐시와 Supabase 주행 데이터를 삭제한다.
- [ ] 업로드 성공 후 로컬 pending detail이 삭제된다.

## Local Verification

```sh
flutter analyze
flutter test
flutter build ios --release --no-codesign --dart-define-from-file=/Users/minwoohan/Documents/revv-app/.env
```

TestFlight 후보 빌드:

```sh
flutter build ipa --release --dart-define-from-file=/Users/minwoohan/Documents/revv-app/.env --build-name=1.38.0 --build-number=55
```

인증서가 준비되면 후보 IPA가 `build/ios/ipa/revv_app.ipa`에 생성된다. 현재 검증된 산출물은 `build/ios/archive/Runner.xcarchive`다.

미사용 의존성 검증:

```sh
rg "Firebase|cloud_functions|firebase_core|flutter_blue_plus|speech_to_text|audioplayers|assets/sounds/beep.mp3" lib pubspec.yaml ios/Podfile.lock
```

위 명령은 결과가 없어야 한다.

## Manual Smoke Test Script

1. 앱 삭제 후 재설치
2. 첫 실행 위치 권한 설명 확인
3. 위치 허용 후 홈 진입 확인
4. 위치 거부 시 루트 탐색 제한 안내 확인
5. 루트 찾기에서 후보 표시 확인
6. 루트 선택 후 주행 시작
7. 10분 주행 유지, 현재 위치 추적과 다음 커브 안내 확인
8. 주행 종료 후 요약 저장 확인
9. 앱 재실행 후 기록 복원 확인

## App Store Privacy Notes

- Tracking: 사용하지 않음.
- Location: 루트 추천, 주행 중 현재 위치 표시, 주행 기록 저장에 사용.
- User ID: Supabase 익명/인증 사용자 식별자로 개인 기록을 분리하는 데 사용.
- Run data: 주행 거리, 시간, 경로 샘플, 속도, G 값, 피드백은 기록 복원과 향후 리포트 생성을 위해 저장. 사용자는 클라우드 기록 저장을 끄거나 기록을 삭제할 수 있음.
- Speech Recognition, Bluetooth, OBD: 심사 후보에서 사용하지 않음. Microphone 워키 코드는 binary에 포함되지만 `REVV_WALKIE_LAB`가 꺼져 있어 진입점과 권한 요청이 없다. 코파일럿 `flutter_tts`는 주행 안내 기능으로 포함한다.

## Environment

필수 `.env` 키:

```sh
SUPABASE_URL=...
SUPABASE_ANON_KEY=...
MAPBOX_ACCESS_TOKEN=...
```

## ⚠️ RELEASE BLOCKER — 크루 워키토키 PTT 효과음
- [x] 무허가 `assets/sounds/beep.mp3`, `audioplayers`, chirp 구현을 심사 후보에서 제거했다.
