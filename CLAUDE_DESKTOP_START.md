# Claude Desktop 시작 프롬프트

REVV 작업을 시작한다. 먼저 아래 파일을 순서대로 읽고 이번 대화 내내 따른다.

1. `/Users/minwoohan/Documents/revv-app-release-integration/AGENTS.md`
2. `/Users/minwoohan/Documents/revv-app-release-integration/COLLABORATION.md`
3. `/Users/minwoohan/Documents/REVV_AGENT_HANDOFF.md`

현재 협업 기준은 `/Users/minwoohan/Documents/revv-app-release-integration`의 `codex/revv-collaboration-baseline-20260721`이다. 기존 `/Users/minwoohan/Documents/revv-app-claude`는 더티 프로토타입 보존용이므로 rebase·reset·새 기능 구현에 사용하지 않는다.

새 범위가 배정되면 기준 ref에서 깨끗한 `claude/*` 브랜치를 만들고, 수정 전에 공용 상태판 `File ownership`에 본인 이름·범위·파일을 기록한다. 수정 후에는 파일 목록, 검증 결과, 커밋 해시, 다음 행동을 상태판에 남긴다. Codex 통합 브랜치에 직접 커밋하거나 push하지 않는다.

읽은 뒤 네 줄 이내로 다음만 보고한다.

```text
읽음
현재 브랜치 / 마지막 커밋
이번에 맡을 범위
Codex와의 충돌 위험
```
