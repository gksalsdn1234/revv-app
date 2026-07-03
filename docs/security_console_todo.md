# REVV Security Console TODO

민우가 Supabase Dashboard, App Store Connect, 또는 실기기에서 직접 확인해야 하는 보안 체크리스트다. 시크릿 값은 이 문서에 기록하지 않는다.

## Supabase Dashboard

- [ ] Edge Functions `call-ai`, `get-weather`, `list-google-tts-voices`, `synthesize-tts`가 JWT verification enabled 상태인지 확인한다.
- [ ] Edge Function secrets가 Dashboard 또는 `supabase secrets list`에서 존재하는지 확인한다. 값은 기록하지 않는다.
- [ ] Security Advisor를 실행하고 남은 경고가 `docs/security_hardening_plan.md`의 비차단 항목과 일치하는지 확인한다.
- [ ] Data API exposed schema/role 설정이 `docs/supabase_security_verification.md`의 권한 기대치와 일치하는지 확인한다.
- [ ] `anon` role이 `runs`, `run_details`, `route_records`, `route_feedback`, `saved_routes`, `discovered_routes`를 읽거나 쓸 수 없는지 확인한다.
- [ ] `edge_rate_limits` 테이블이 client-accessible 상태가 아니고 `service_role`만 `consume_edge_rate_limit` RPC를 실행할 수 있는지 확인한다.
- [ ] Auth 콘솔에서 anonymous beta auth posture, password, MFA 경고가 MVP 노출 범위와 맞는지 확인한다.

## Staging / Production Verification

- [ ] 새 Supabase 프로젝트 bootstrap을 `supabase db reset` 또는 staging project에서 검증한다.
- [ ] 외부 TestFlight 확대 전 `docs/supabase_security_verification.md` runbook을 다시 실행한다.
- [ ] 새 외부 베타 빌드마다 Supabase migration list, privilege checks, Security Advisor 결과를 다시 확인한다.

## Device Verification

- [ ] 클라우드 기록 저장 토글을 끈 뒤 신규 상세 telemetry가 업로드되지 않고 legacy pending payload가 삭제되는지 실기기에서 확인한다.
- [ ] 긴 주행 세션 후 pending detail payload가 secure storage 한계에 접근하는지 관찰한다. 한계가 보이면 encrypted file storage 전환 작업으로 분리한다.
- [ ] Supabase 정상, 미설정, 네트워크 실패, 후보 0개, 캐시 사용 상태 안내가 실기기에서 민감 위치/원시 예외 없이 표시되는지 확인한다.
