# REVV — Claude Desktop 시작 문서

이 저장소에서 작업하기 전 반드시 이 파일과 `COLLABORATION.md`, 그리고 공용 상태판인 `/Users/minwoohan/Documents/REVV_AGENT_HANDOFF.md`를 읽는다.

## 제품 기준

- 북극성: **REVV는 크루 드라이빙 앱이다. 혼자 달리게 두지 않는 앱.**
- Google Maps/Waze와 경쟁하는 내비게이션을 만들지 않는다. REVV는 드라이브 경험과 좋은 루트 선택을 만든다.
- 속도·최고속·G값 경쟁을 조장하지 않는다. 길의 성격, 플로우, 여정, 안전한 경험을 말한다.
- V1은 좋은 루트 선택 → 자신 있는 미리보기 → 외부 내비 시작 → 기록 → 피드백의 학습 루프다.
- V2의 첫 단계는 피드가 아니라, 공유받은 사람이 같은 루트를 이해·저장·참여하는 최소 크루 루프다.

## 현재 상태

- 이 Claude 작업 폴더는 `/Users/minwoohan/Documents/revv-app-claude`다.
- 현재 브랜치 `claude/revv-workbench`는 `route-selector-proto`의 `e494c3c`에서 시작했다.
- 그 기준 커밋에는 다중 루트 선택, 로그인 없는 Google Maps Invite, 다국어/지도 회귀 보완, 앱 분석 리포트가 들어 있다.
- Codex 통합 작업 폴더는 `/Users/minwoohan/Documents/revv-app`의 `lean_mvp`다. 그 폴더의 파일을 직접 수정하지 않는다.

## 시작 순서

1. `git status --short`, `git branch --show-current`, `git log -1 --oneline`으로 현재 상태를 말한다.
2. 공용 상태판에서 다른 에이전트의 작업 소유 파일을 확인한다.
3. 요청 범위와 건드릴 파일을 한 문장으로 선언한 뒤 수정한다.
4. 관련 테스트와 `flutter analyze`를 실행한다.
5. 공용 상태판에 수정 파일, 검증 결과, 다음 사람이 알아야 할 점을 기록한다.

## 협업 규칙

- 이 작업 폴더에서만 편집한다. `lean_mvp`와 Codex 작업 폴더를 직접 덮어쓰지 않는다.
- 다른 에이전트가 소유한 파일은 인수인계 없이 수정하지 않는다.
- `git reset --hard`, 강제 푸시, 임의의 rebase, 대규모 포맷팅은 하지 않는다.
- 커밋·푸시는 사용자가 명시적으로 요청할 때만 한다. 완료 시에는 커밋 해시와 테스트 결과를 상태판에 남긴다.
- 모르는 현재 상태는 추측하지 말고 파일과 Git 상태를 읽는다.

## 가장 먼저 답할 형식

`읽음 — 현재 브랜치 / 마지막 커밋 / 맡을 범위 / 충돌 위험`을 네 줄 이내로 보고하고, 그 다음 작업을 시작한다.
