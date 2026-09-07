# REVV 개발 환경 현황

마지막 확인: 2026-09-07 KST. 제품 상태와 다음 작업은 [오늘 작업 기록](docs/2026-09-07-work-log.md)을 기준으로 한다.

## 사용 가능한 환경

- 활성 폴더: `/Users/minwoohan/Documents/revv-app-release-integration`
- 현재 브랜치: `codex/revv-guideline4-language`
- Flutter 실행 파일: `/Users/minwoohan/flutter/bin/flutter`
- iOS 의존성과 빌드 환경: Debug 시뮬레이터 빌드·설치·실행 성공으로 확인. CocoaPods 설치가 미완료라는 3월 기록은 더 이상 현재 상태가 아니다.
- 확인한 시뮬레이터: iPhone 16e / iOS 26.3.
- Supabase CLI 2.95.4 로그인 및 REVV 프로젝트 연결 확인. MCP 목록에는 REVV가 없어 운영 작업은 기존 CLI 연결을 사용했다.
- 기존 환경 파일: `/Users/minwoohan/Documents/revv-app/.env`. 활성 폴더로 복사하거나 Git에 추가하지 않는다.

## 실행·검증

활성 폴더에서 실행한다.

```sh
/Users/minwoohan/flutter/bin/flutter run --dart-define-from-file=/Users/minwoohan/Documents/revv-app/.env
/Users/minwoohan/flutter/bin/flutter analyze --no-pub
/Users/minwoohan/flutter/bin/flutter test --no-pub
```

성능 계측은 Debug에서 제공된다. 실기기 Profile 측정에는 `--profile --dart-define=REVV_ROUTE_PERF=true`를 추가한다. 로컬 테스트 시 몬트리올 시뮬레이션 좌표는 실제 사용자 GPS 성능을 대표하지 않는다.

## 배포 경계

운영에는 `20260907120251_route_lightweight_overview`와 `20260907131716_route_catalog_ordinal_lookup`가 적용되어 있다. 전체 로컬 마이그레이션을 무조건 push하거나 이미 적용한 배포 트랜잭션을 재실행하지 않는다. 프로젝트와 원격 이력을 먼저 확인한다.

오늘 변경한 앱 소스·아이콘의 App Store 배포는 미수행이다. 소스 버전 `1.38.0+63`의 build 63은 이전에 업로드했으므로 다음 업로드에는 사용하지 않은 빌드 번호가 필요하다. 실기기 Profile 측정과 남은 주행/저장 감사 항목은 별도 검증이 필요하다.
