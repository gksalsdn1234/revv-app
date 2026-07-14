# 출시 전 남은 수동 항목 (2026-07-13 최종 후보)

자동화 캠페인(G001~G005)으로 코드 쪽 범위 잠금은 완료. 아래는 민우 판단/손이 필요한 것만.

## 해결 완료

- 무허가 `beep.mp3`, 오디오 패키지, chirp 호출을 심사 후보에서 삭제했다.
- 네이티브/Flutter 로딩 화면의 시각 언어를 하나로 통일했다.
- 심사 후보는 `1.38.0 (55)`이며 탐험 안개와 워키 랩을 활성화하지 않는다.
- production Supabase migration과 Edge Function 배포, 익명/인증/중복/무효 run receipt live smoke test를 완료했다.
- 전국 루트 RPC 반경/결과 제한, 크루 채널 직접 삽입 차단 migration `20260713120000`까지 production에 적용하고 live smoke를 완료했다.
- iOS FFI 로더 크래시를 수정한 `objective_c 9.4.1`로 올리고 깨끗한 시뮬레이터 실행에서 예외가 사라진 것을 확인했다.
- iOS Release archive `build/ios/archive/Runner.xcarchive` 생성을 완료했다.

## 실기기 확인 (코드 완료, 체감 검증만 남음)
- 플래너: 빨간 와인딩 선 표시 문제 — 동시 line redraw `PlatformException`을 재현해 직렬화로 수정했고 런타임 로그는 깨끗함. 맥 잠금 해제 후 새 빌드의 실제 선 표시만 시각 확인 필요
- 생추천형: "그냥 추천받아 달리기" 루프 품질 (실주행 검증 원칙 — 크루와 직접 달려보기)
- 워키: LTE/터널 재연결, ack:false 음질, 250ms 프리버퍼 체감
- 기본vs REVV 비교 라인, 커브 칩 표기
- 학습루프: 실기기에서 추천/선택 후 Supabase recommendation_logs에 행 생기는지 (Table Editor에서 확인)

## 내일 App Store Connect에서만 할 일

- 먼저 Xcode에 Apple Developer 계정과 Apple Distribution 인증서/App Store provisioning profile을 준비해 IPA를 export/upload한다.
- 공개 지원 URL과 심사 연락 이메일 입력 및 실제 접속 확인.
- 개인정보 처리방침의 `[replace-with-contact-email]` 자리표시자를 실제 이메일로 교체하고 공개 페이지를 다시 확인한다.
- 연령 등급 설문 확인, 개인정보 라벨을 `docs/store_assets_draft.md`와 동일하게 입력.
- route map/preview/detail/drive/history/settings 실제 화면 스크린샷 6장을 촬영·승인한 뒤 업로드하고, 빌드 선택과 심사 노트 붙여넣기를 진행한다.
- 최종 IPA 업로드 후 `Add for Review` / `Submit for Review` 실행.

심사 빌드 명령은 `flutter build ipa --release --dart-define-from-file=/Users/minwoohan/Documents/revv-app/.env --build-name=1.38.0 --build-number=55`를 사용한다. 통합 worktree에는 `.env`를 복사하지 않았으며, `REVV_EXPLORATION_FOG`와 `REVV_WALKIE_LAB` 정의는 넣지 않는다.
