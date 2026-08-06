# REVV 협업 프로토콜 — Claude 프로토타입 보존 작업공간

이 폴더(`/Users/minwoohan/Documents/revv-app-claude`, `claude/revv-workbench`)는 더티 상태의 이전 프로토타입을 보존한다. rebase, reset, branch 이동, 또는 새 기능 작업을 여기서 하지 않는다.

## 새 Claude 작업의 기준

현재 단일 통합 기준은 `/Users/minwoohan/Documents/revv-app-release-integration`의 `codex/revv-unified-workspace`이며, 로컬 기준 ref는 `codex/revv-collaboration-baseline-20260721`이다. 새 범위는 이 ref에서 새 `claude/*` 브랜치를 만든 깨끗한 작업공간에서 시작한다.

수정 전후에는 `/Users/minwoohan/Documents/REVV_AGENT_HANDOFF.md`를 읽고, 수정 전 파일 소유권을 기록한다. Codex 통합 브랜치는 직접 수정하거나 push하지 않는다. 원격 push, 배포, 데이터베이스 변경, 또는 이 보존 폴더의 정리는 별도 사용자 승인 없이는 하지 않는다.
