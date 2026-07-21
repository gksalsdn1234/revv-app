# REVV 협업 프로토콜

## 단일 활성 작업공간

`/Users/minwoohan/Documents/revv-app-release-integration`의 `codex/revv-unified-workspace`가 유일한 활성 통합·릴리즈 작업공간이다. 이전 `revv-app`, `revv-app-claude`, `revv-lean-mvp` 작업공간은 보존용이며 여기에서만 새 작업을 시작한다.

Claude의 새 범위는 항상 이 브랜치의 현재 커밋에서 `claude/*` 작업 브랜치를 새로 만들거나 재배치한 뒤 시작한다. 기존 `revv-app-claude`의 `claude/revv-workbench`는 보존된 프로토타입이며 새 작업의 베이스로 사용하지 않는다.

## 공용 상태판

시작과 종료 시 `/Users/minwoohan/Documents/REVV_AGENT_HANDOFF.md`를 읽고 갱신한다. 상태판에는 작업 소유 파일, 의도, 검증 결과, 커밋 해시만 적는다. 비밀값·토큰·개인정보는 적지 않는다.

## 작업 규칙

1. 시작 전 `git status`, 현재 브랜치, 마지막 커밋을 확인한다.
2. 다른 에이전트가 소유한 파일은 명시적 인수인계 전까지 수정하지 않는다.
3. 통합은 명시적 커밋 단위로만 한다. Claude는 `claude/*`에서 커밋하고, Codex는 검토 후 이 통합 브랜치에 반영한다.
4. 활성 작업공간에서 `git pull`을 실행하지 않는다. 원격 변경은 먼저 `git fetch origin`으로 확인한다.
5. 같은 파일을 다룰 때는 상태판에 소유자를 먼저 기록한다. 다른 에이전트의 진행 중 파일은 수정하지 않는다.
6. 대규모 포맷팅·리라이트·생성 파일 변경은 이유를 상태판에 남긴다.
7. 원격 push, 배포, 데이터베이스 변경은 별도 사용자 승인 없이는 하지 않는다.
