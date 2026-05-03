# REVV iOS TestFlight Release Quality Checklist

목표: 1차 배포는 iOS TestFlight 베타 기준으로 안정성, 첫 경험, 실제 주행 플로우를 먼저 닫는다.

## P0 - TestFlight 차단 항목

- [x] `flutter analyze` 통과
- [x] `flutter test` 통과
- [ ] `.env` 또는 `--dart-define-from-file=.env`로 Supabase/Mapbox 설정 확인
- [ ] iPhone 실기기 실행: `flutter run --dart-define-from-file=.env`
- [ ] Firebase 의존성 없음 확인: `rg "Firebase|FirebaseFunctions|cloud_functions|firebase_core" lib pubspec.yaml`
- [ ] Supabase Edge Functions 배포 및 secrets 확인: `call-ai`, `get-weather`, `list-google-tts-voices`, `synthesize-tts`
- [x] Supabase RLS migration 반영 및 Edge Function rate limit 적용
- [x] 첫 실행 권한 설명 표시 후 위치/마이크 권한 요청
- [x] 위치 거부 시 루트 탐색 불가 이유와 설정 이동 안내 표시
- [x] 마이크 거부 시 음성 기능만 비활성화되고 앱 사용은 계속 가능
- [ ] Supabase 정상/미설정/네트워크 실패/캐시 있음/캐시 없음/루트 0개 상태 안내 확인
- [ ] 루트 선택 -> 주행 시작 -> 이탈/복귀 -> 종료 -> RunCard 저장 플로우 확인
- [ ] 실기기 10분 주행 smoke test 중 크래시 없음
- [ ] 주행 중 필수 버튼만 노출: 종료, 음소거, 핵심 경고
- [ ] 과속/위험 주행을 자극하는 문구 없음

## P1 - 베타 완성도

- [ ] 홈/루트파인더/저장/기록/Garage CTA 언어 통일
- [x] 저장 루트에서 지도 보기, 주행, 편집 재사용 흐름 확인
- [x] GPS path 없는 짧은 세션 저장 fallback 확인
- [x] AI 분석 실패 시 RunCard fallback 문구 확인
- [ ] Mapbox/GPS/IMU/TTS/STT listener dispose 누수 점검
- [ ] TestFlight용 위치/마이크/데이터 저장 설명 문구 정리
- [ ] 날씨 API 키 관리 제거: `get-weather`를 Open-Meteo 기반 무키 API로 전환

## P2 - 공개 배포 전

- [ ] App Store 개인정보 라벨/권한 설명 검토
- [ ] Android 권한/백그라운드 정책 별도 검증
- [ ] Supabase RLS/콘솔 설정 최종 검토
- [ ] 앱 아이콘, 스크린샷, 베타 피드백 링크 준비

## Manual Smoke Test Script

1. 앱 삭제 후 재설치
2. 첫 실행 권한 설명 확인
3. 위치 허용, 마이크 허용 케이스로 홈 진입
4. 루트 찾기에서 현재 위치 기준 루트 표시 확인
5. 루트 선택 후 주행 시작
6. 10분 주행 유지, TTS/경고/지도 안정성 확인
7. 종료 후 RunCard 저장 확인
8. 앱 재실행 후 기록/저장 루트 확인

## Environment

```sh
flutter analyze
flutter test
flutter run --dart-define-from-file=.env
```

필수 `.env` 키:

```sh
SUPABASE_URL=...
SUPABASE_ANON_KEY=...
```

Supabase 서버 secrets:

```sh
AI_API_KEY=...
WEATHER_API_KEY=...
GOOGLE_TTS_API_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...
```

Mapbox token은 현재 `MapboxService` 설정을 사용한다. TestFlight 전에는 토큰 노출 정책을 별도 점검한다.
