# REVV 협업 프로토콜 — 보존 작업공간

이 폴더(`/Users/minwoohan/Documents/revv-app`, `lean_mvp`)는 이전 Western/tooling 변경을 보존하는 용도다. 새 제품 작업, 통합, 릴리즈 작업을 여기서 시작하거나 이 브랜치를 기준으로 병합하지 않는다.

현재 단일 통합 기준은 아래다.

| 역할 | 경로 | 브랜치 | 기준점 |
|---|---|---|---|
| Codex 통합 | `/Users/minwoohan/Documents/revv-app-release-integration` | `codex/revv-unified-workspace` | `codex/revv-collaboration-baseline-20260721` |

Claude의 새 작업은 위 기준점에서 새 `claude/*` 브랜치로 시작한다. 기존 더티 파일과 이 폴더의 미커밋 Western/tooling 변경은 별도 검토 전까지 보존한다.

시작과 종료 시 `/Users/minwoohan/Documents/REVV_AGENT_HANDOFF.md`를 읽고 갱신하고, 파일 소유권을 먼저 기록한다. 원격 push, 배포, 데이터베이스 변경, 또는 작업공간 삭제는 별도 사용자 승인 없이는 하지 않는다.
