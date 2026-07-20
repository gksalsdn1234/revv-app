# REVV 협업 프로토콜

## 단일 활성 작업공간

`/Users/minwoohan/Documents/revv-app-release-integration`의 `codex/revv-unified-workspace`가 유일한 활성 통합·릴리즈 작업공간이다. 이전 `revv-app`, `revv-app-claude`, `revv-lean-mvp` 작업공간은 보존용이며 여기에서만 새 작업을 시작한다.

## 공용 상태판

시작과 종료 시 `/Users/minwoohan/Documents/REVV_AGENT_HANDOFF.md`를 읽고 갱신한다. 상태판에는 작업 소유 파일, 의도, 검증 결과, 커밋 해시만 적는다. 비밀값·토큰·개인정보는 적지 않는다.

## 작업 규칙

1. 시작 전 `git status`, 현재 브랜치, 마지막 커밋을 확인한다.
2. 다른 에이전트가 소유한 파일은 명시적 인수인계 전까지 수정하지 않는다.
3. 통합은 명시적 커밋 단위로만 한다.
4. 활성 작업공간에서 `git pull`을 실행하지 않는다. 원격 변경은 먼저 `git fetch origin`으로 확인한다.
5. 대규모 포맷팅·리라이트·생성 파일 변경은 이유를 상태판에 남긴다.
