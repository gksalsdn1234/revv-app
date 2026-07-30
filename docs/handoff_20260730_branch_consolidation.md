# 핸드오프 — 2026-07-30 (Claude → Codex 통합 워크스페이스)

`lean_mvp` 직접 푸시는 원격 정책상 Codex 통합 워크스페이스만 가능하다.
이 문서가 그 정책이 요구하는 핸드오프 기록이다. 아래 커밋은
`claude/release-hardening`에 올라가 있으므로 통합 워크스페이스에서
`lean_mvp`로 머지·푸시하면 된다.

## 1. 미커밋으로 방치돼 있던 작업 (7/25 새벽 작업분, 567줄)

7/23 머지 이후 워킹트리에 미커밋 상태로 5일간 남아 있던 변경을 검토한 결과
버릴 습작이 아니라 완결된 기능 3덩어리였다. 논리 단위로 쪼개 커밋했다.

- `ce04593` — 코파일럿 요약을 코치 목소리로, 제안은 실제 버튼으로
  런에서 코너 밀도·후반부 코너 비중·실하중 코너 수·루트 완주율을 파생시켜
  "시트에서는 볼 수 없던 것" 하나를 말한다. 원시 G값·피크·속도는 어떤 신호도
  노출하지 않는다(안전 카피 규칙 유지, 임계값은 내부 상수). 미완주 루트면
  버튼이 그 루트를 다시 열고, 아니면 파인더를 연다. 리캡 그리드의 중복
  거리·시간 제거.
- `e742206` — 미리보기 루트를 코너 강도 4단계로 채색. 직선·완만은 중립 회색,
  브랜드 레드는 헤어핀에만. 루트 전체를 단색으로 덮어쓰던 난이도 라인에서
  미리보기 루트를 제외.
- `5c0b14f` — 공유 카드 실루엣에 동일한 색 사다리 적용. 카드는 원시 지오메트리를
  받지 않고 자기 정규화 shape에서 각도를 계산하므로 내보낸 이미지에 새로
  새는 정보가 없다.
- `8c4cfd3` — 7/21 사전 제출 리뷰를 `docs/`에 기록 + `.gitignore`에 에이전트
  스크래치(`.dart-tool/`, `.fablize/`, `plans/`, `PLAN.md`, `codex-build.sh`) 추가.

## 2. 검증 (2026-07-30 실행 결과)

- `flutter analyze` → No issues found
- `flutter test` → **461개 전부 통과** (`lean_mvp` 머지 후 상태에서 실행)
- 화면 노출 문자열 금지어 grep → 0건

## 3. 브랜치 정리

- 스테일 워크트리(`/private/tmp/.../merge-lean`)가 `lean_mvp`를 점유해
  체크아웃을 막고 있었다 → `git worktree prune`으로 해제.
- `remote.origin.fetch`가 `lean_mvp` 한 줄로 잘려 있어 나머지 8개 원격
  브랜치가 보이지 않았다 → `+refs/heads/*:refs/remotes/origin/*`로 복구.
- `origin/main` → `lean_mvp`에 머지(`87a3d87`, lean_mvp 로컬에만 존재).
  main의 고유 커밋은 v5 디자인 시스템 적용과 그 revert뿐이라 상쇄되며,
  머지 결과 트리가 lean_mvp와 바이트 단위로 동일함을 `merge-tree`로 사전
  확인했다. 코드 변경 0, 계보만 정리.
- `origin/codex/supabase-curvature` → 고유 커밋 0개, 이미 포함됨.

### 통합하지 않은 브랜치 (의도적)

| 브랜치 | 충돌 | 사유 |
|---|---|---|
| `codex/smart-route-chain-fixes` | 23개 파일 | 5/16 분기, 이후 lean_mvp 139커밋. 루트 체인 3,866줄이 실제로 미반영이나(`route_chain.dart`·`route_chain_builder.dart`·`next_curve_banner.dart` 등 부재) `lean_drive_screen`·`route_drive_cue`·`imu_service`·`map_widget`이 전면 재작성돼 정면 충돌. **제출 후 별도 이식 과제** |
| `claude/heuristic-hamilton` | 28개 파일 | 3/24 분기, lean 이전 코드베이스. 대상 화면 대부분이 lean_mvp에서 삭제된 파일이라 modify/delete 충돌 — 머지 시 죽은 화면 부활 |
| `claude/sns-revenue-strategy-c98e26` | 없음 | 돈벌기 프로젝트(가이드 PDF 파이프라인). 앱 제출 브랜치에 섞을 이유 없음 |

삭제한 브랜치·워크트리는 없다.

## 4. 남은 심사 블로커

- **실기기 검증** (민우 몫): Supabase 정상/미설정/네트워크실패/후보0/캐시 상태 ·
  10분 주행 크래시 스모크 · 플래너 와인딩 선 재확인
- 스크린샷 + 심사 노트 — 백그라운드 오디오 정당화 문구는
  `docs/review_20260721_claude_handoff.md` F1 참조
