# REVV 개발 방향 리뷰 & 실행 계획서

작성일: 2026-07-01 · 기준 브랜치: `lean_mvp` (v1.38.0+42)

## 1. 앱 리뷰 — 현재 상태 진단

### 잘 되어 있는 것

- **스코프 절제가 훌륭하다.** lean_mvp는 "루트 발견 → 주행 → 기록"의 단일 플로우로 정리됐고, OBD/STT/AI 등 실험 기능은 main에 격리됐다. 화면 5개(loading/home/route_finder/drive/run_summary)로 핵심 루프가 완결된다.
- **루트 품질 엔진이 차별화 자산이다.** `route_loading_policy`의 keep/maybe/reject 티어, 루트 캐릭터(switchback/sweeper/hill climb), 설명 메타데이터, 정지·주거지 패널티 파이프라인은 Calimoto/Scenic이 못 주는 "왜 이 루트인가"를 만든다. 테스트 129개가 이 로직을 두껍게 보호하고 있다.
- **리서치·문서 기반이 탄탄하다.** 경쟁 벤치마크(Calimoto=발견, Scenic=주행, Kurviger=고급 셰이핑), UI 백로그, TestFlight 실행 계획이 이미 실행 가능한 수준으로 정리돼 있다.
- **릴리즈 준비도 거의 끝났다.** IPA 빌드 성공, 서명/프라이버시 매니페스트/암호화 선언 완료. 남은 건 업로드와 실주행 smoke test뿐.

### 문제 / 리스크

1. **가장 큰 리스크는 코드가 아니라 "배포 정체".** 5/15에 IPA까지 만들어 놓고 App Store Connect 업로드·외부 베타가 6주째 미완. 그 사이 커밋은 계속 쌓여 릴리즈 후보와 현재 코드가 벌어졌다. 사용자 피드백 없이 폴리시만 깊어지는 전형적 패턴.
2. **미커밋 WIP가 크고 테스트 1개가 깨져 있다.** IMU 서비스 재작성(182→311줄), 텔레메트리 이벤트 분석(`_run_telemetry_event_analysis.dart`), 공유 카드(`run_share_card_content.dart`), 내비 핸드오프 리팩터가 한 워킹트리에 섞여 있음. `test/widget_test.dart:99` 실패(`analytics['sampleCount']` expected 1, actual 0)는 텔레메트리 리팩터와 직결 — 샘플 직렬화 경로가 깨졌을 가능성.
3. **App Store 심사 리스크: 공유 카드 + G포스.** CLAUDE.md 규칙대로 속도 자극 표현은 금지인데, 공유 카드에 peak G/가속 이벤트를 노출하면 "난폭운전 조장"으로 읽힐 수 있다. 프라이버시 테스트는 있지만 **안전 언어 검수 기준**이 공유 카드에 아직 없다.
4. **베타 피드백 수집 경로가 없다.** TestFlight를 열어도 사용자가 "루트가 별로였다"를 앱 안에서 말할 방법이 route_feedback 모델 외에 UX로 연결돼 있는지 불명확.

## 2. 추천 개발 방향

**한 문장: "더 만들지 말고, 먼저 태우라."** 다음 6주의 우선순위는 (1) WIP 착지 → (2) TestFlight 외부 베타 → (3) 실사용 피드백으로 Routes 화면 개선. 신규 기능은 공유 카드 하나로 제한.

- **차별화 축 유지:** quality/character/explanation 메타데이터가 유일한 해자. 백로그의 Epic 1(Routes discovery-first)이 이 자산을 사용자 눈에 보이게 만드는 최단 경로.
- **공유 카드 = 성장 루프.** 베타 단계에서 유일하게 허용할 신규 기능. 단, 지표는 거리/시간/커브 수/루트 캐릭터 중심으로, 최고속도·G값 강조는 피해서 심사 안전 언어를 지킬 것.
- **Kurviger식 고급 컨트롤, REVER식 커뮤니티는 계속 보류.** 기존 V1 제약 그대로.

## 3. 실행 계획

### Phase 0 — WIP 착지 & 안정화 (1주차)

- [ ] `widget_test.dart:99` 실패 원인 수정 (텔레메트리 샘플 직렬화 회귀)
- [ ] 미커밋 변경을 논리 단위로 분리 커밋: ① IMU 재작성+테스트 ② 텔레메트리 이벤트 분석 ③ 공유 카드 ④ 내비 핸드오프 리팩터
- [ ] 공유 카드 안전 언어 검수: peak G 노출 여부 결정, 문구를 "즐거운 드라이빙" 톤으로
- [ ] `flutter analyze` + `flutter test` 전체 그린 확인 후 `origin/lean_mvp` 푸시

**게이트:** 테스트 전체 통과 + 워킹트리 클린.

### Phase 1 — TestFlight 배포 (2주차)

- [ ] 버전 범프(1.39.0+43) 후 `flutter build ipa --release --dart-define-from-file=.env` 재빌드 (5월 IPA는 폐기 — 코드가 벌어짐)
- [ ] App Store Connect 업로드 → Internal Testing 설치 검증
- [ ] **실기기 10분 실주행 smoke test** (몬트리올 근교 루트 1개: 발견→주행→커브 알림→요약 저장 전체 루프)
- [ ] Beta App Review 제출 → External Testing 오픈 (친구/드라이빙 커뮤니티 10~20명)

**게이트:** 외부 테스터 최소 5명이 실주행 1회 완료.

### Phase 2 — 피드백 루프 구축 (3~4주차)

- [ ] 런 요약 화면에 1탭 루트 평가(👍/👎 + 선택 사유) — `route_feedback` 모델을 UX에 연결
- [ ] Supabase에서 베타 텔레메트리 리뷰: 루트 검색 실패율, 주행 완주율, keep/maybe 노출 비율
- [ ] 공유 카드 출시 (story/square/sticker) — 베타 테스터 유입 경로로 활용
- [ ] 피드백 상위 3개 문제를 다음 Phase 스코프로 확정

**게이트:** 실사용 데이터 기반 개선 목록 확정.

### Phase 3 — 제품 심화 (5~8주차, 기존 백로그 순서 준수)

1. **Routes (Epic 1):** 발견 우선 구조, 루트 카드에 캐릭터+핵심 이유+주의 노트, keep→maybe 정렬, reject 비노출
2. **Route Detail (Epic 2):** "왜 이 루트인가 / 주의할 것 / 체인 후보" 명시
3. **Drive:** off-route/rejoin 상태 개선 (Scenic 벤치마크)

### Phase 4 — 성장·리텐션 (9주차~, 베타 데이터 확인 후)

- 런 히스토리 심화(개인 기록/gold 액센트), 루트 체인 추천 노출, App Store 정식 심사 준비

## 4. 운영 원칙 (재확인)

- 릴리즈 작업은 `lean_mvp`에서만, `main`은 안정 백업
- 발견 질문은 Calimoto, 주행 질문은 Scenic, "왜 좋은 루트인가"는 REVV 자체 메타데이터로 답한다
- 속도 자극 문구 금지 — 공유 카드 포함 모든 신규 표면에 적용
- Mapbox는 에뮬레이터 충돌 → 주행 검증은 항상 실기기

## 5. 알려진 이슈 베이스라인

- `test/widget_test.dart:99` 실패 (2026-07-01 확인) — WIP 텔레메트리 리팩터 회귀, Phase 0에서 수정
- 43개 패키지 메이저 업데이트 보류 중 — 베타 이후 일괄 검토
