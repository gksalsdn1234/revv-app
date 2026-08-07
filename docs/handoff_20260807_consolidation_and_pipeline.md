# 핸드오프 — 두 클론 통합 마무리 + 루트 데이터 실측 (2026-08-07)

작업 브랜치: `claude/consolidate-20260806`
워크트리: `/tmp/revv-consolidate` (⚠ `/tmp` 이므로 재부팅 시 소실)

---

## 0. 지금 상태 한 줄

통합은 끝났고 초록불이다. 릴리즈 빌드를 실기기에 설치까지 마쳤다. 남은 것은 **실기기 smoke test 와 제출 절차**이며, 코드 작업은 더 필요하지 않다.

---

## 1. 커밋 (원격 반영됨)

`claude/consolidate-20260806` 9개.

| 커밋 | 내용 |
|---|---|
| `8fd5007` | 두 클론 통합 — 음성·내비는 Codex 설계, 파인더·요약은 Claude 작업 |
| `a42e1bb` | Mapbox Directions `waypoints` 파라미터 |
| `2f2df03` | 0km 주행에 점수가 매겨지던 것 차단 |
| `e00c371` | 루트 카탈로그 statement timeout + 빌드 중 notify |
| `250e581` | 음성이 같은 방향을 두 번 말하던 것 |
| `9c0c21a` | 코너 등급을 표시 문자열이 아니라 `severity` 에서 읽도록 |
| `7e52e67` | 남은 커브 수 안내 + 흐름 종료 알림 |
| (관측) | overview prefetch 로깅 |
| (지표) | 연속 흐름 유예 `STREAK_GAP_TOLERANCE_KM = 0.25` |

`flutter analyze` 0건 · `flutter test` **671 통과**.

---

## 2. 미커밋 (⚠ 반드시 먼저 처리)

`/tmp/revv-consolidate` 에만 있고 아직 커밋되지 않았다. **git 접근이 세션 중 차단되어 올리지 못했다** (`~/Documents/revv-lean-mvp/.git/worktrees/...` 가 `Operation not permitted`). 터미널에서는 접근이 되므로 직접 올리면 된다.

| 파일 | 내용 |
|---|---|
| `docs/testflight_release_checklist.md` | 브랜치·빌드번호·테스트수 갱신, Codex 검수 반영 |
| `docs/handoff_20260807_consolidation_and_pipeline.md` | 이 문서 |
| `lib/services/location_service.dart` | `startArmedTracking` 주석 (동작 변경 없음) |

```sh
cd /tmp/revv-consolidate && git status --short
git add -A && git commit -m "Update the release checklist after the Codex review"
git push origin claude/consolidate-20260806
```

**`/tmp` 에 있으므로 재부팅 전에 반드시 올릴 것.**

---

## 3. 결정이 필요한 것

### 3.1 주행 중 모드 선택 칩 — 뺄지 말지
주행 화면의 `MODE CRUISE` 칩은 탭하면 `cruise/winding/sport/attack` 을 고른다. 그런데 **앱 동작은 아무것도 바뀌지 않는다.** `recordDriveMode()` 는 모드별 누적 시간만 세고, 그 결과는 런카드의 DRIVE MODE 막대에만 쓰인다. 게다가 `DrivingContextService` 가 속도·G포스로 이미 자동 판정한다.

기능 이득 0, 운전 중 조작 1개. Guideline 1.4.5 방어를 어렵게 만든다. **표시는 남기고 탭만 막는 것을 권한다** (`onSelectDriveMode` 를 null 로).

### 3.2 첫 주행 전 안전 고지 — 넣을지
Beta Notes 에는 "정차 또는 동승자 조작" 이 있는데 **앱 UI 안에는 같은 고지가 없다.** Codex 검수가 2.5.4 보다 1.4.5 를 실질 리스크로 꼽았다. 3.1 을 처리하면 주행 화면에 남는 터치는 음소거 토글과 길게 눌러 종료뿐이라 고지 문구도 단순해진다.

### 3.3 루트 체인 — 이번 범위에 포함할지
`+` 로 최대 6개 연결하는 기능이 코드에 켜져 있는데 §0 배포 범위 목록에 없다. 잠글 계획이면 이 빌드 전에 정해야 한다.

참고: 지금 **이어붙일 재료가 244개뿐**이라(4장) 체인 UX 를 다듬어도 체감이 크지 않다. 재계산 배치 이후에 다시 보는 편이 낫다.

### 3.4 디자인 — 카드 제목 잘림
`No routes found i...` / `Location permissi...` / `Tight curv…` 가 세 화면에서 잘린다. `maxLines: 1` + ellipsis 가 `lean_route_finder_screen.dart` 에만 17곳. 카드 제목을 두 줄까지 허용하면 끝난다. 심사자가 스크린샷을 찍는 화면들이라 체감이 크고 위험이 낮다.

---

## 4. 루트 데이터 실측 — 출시 후 작업

Supabase `curvy_roads` 83,232행을 직접 조회한 결과.

**실제로 달릴 만한 루트는 244개다** (8km 이상 + 연속 와인딩 3km 이상). 목적지급(15km+ · 연속 5km+)은 47개.

- 70.2% 가 1km 미만, 3km 이상은 8.5%
- `quality_reject_reason` 이 달린 건 180개(0.2%) — **품질 게이트가 아니라 전부 길이에서 탈락**
- 지역별: BC 105 · ON 59 · QC 21 · NS 16 · **AB 11** · SK/MB 5 · NB 2 · PE/NT 0

### 4.1 근본 원인 (확정, 수정 완료)
`tools/curvature_pipeline/process_roads.py` — 임계 미달 꼭짓점 하나에 연속 흐름을 0으로 리셋해서, `max_continuous_km` 가 "이어지는 재밌는 구간" 이 아니라 "끊기지 않은 커브 하나" 를 쟀다. 흐름 비율이 길이대와 무관하게 0.19~0.29 로 일정했던 이유.

`STREAK_GAP_TOLERANCE_KM = 0.25` 유예를 넣었다. 값은 실측으로 골랐다 — 0.20~0.35 가 고원이고 0.50 을 넘으면 Sea-to-Sky 비율이 1.00 이 되어 지표가 길이와 구분되지 않는다.

검증: Sea-to-Sky 8.4km 조각 `1.30 → 5.48km` (0.65), 대조군 직선 도로 `1.28 → 1.64km` (0.39) — 굽은 길만 회복하고 직선은 부풀지 않는다.

**⚠ 아직 효과 없음.** DB 83,232행은 그대로다. 재계산 배치를 돌려야 하며, 그 전에 **50~100개 표본 실측**을 권한다. "244 → 약 1,100" 은 도로 2개에서 외삽한 추정치다.

### 4.2 명품 루트가 조각나 있다
Sea-to-Sky 8조각(합 37km, 실제 약 120km), Duffey Lake 7조각(42km), Fulford-Ganges 2조각. 조각 간격은 **0m 가 절반, 나머지는 3.5~5km**(그 사이가 진짜 직선 고속도로다).

- **붙일 것**: 간격 0m 는 무조건 병합. 같은 이름 ≤6km 는 transit 구간으로 표시하며 연결하되, 점수는 굽은 구간만으로 계산하고 거리는 전체로 표시.
- **붙이지 말 것**: 150m 근접 기준. Kelowna 실측상 84.3% 가 근접이지만 끝점 연결은 19.5% 뿐이라 교차로·평행도로를 통째로 묶게 된다. 1km 미만 조각(전체의 70%)은 잘린 게 아니라 원래 짧은 굽이라 병합 대상이 아니다.

### 4.3 고도 데이터가 비어 있다
`elevation_profile` 이 83,232행 **전부 빈 배열**이다. 고저차 음성(크레스트/오르막/내리막)이 한 번도 나온 적이 없고, `drive_elevation_cue.dart`(195줄, 테스트 80개 통과)가 데이터가 없어 통째로 놀고 있다.

### 4.4 자동 조회 줌 문턱
지도를 옮겼을 때 자동으로 그 지역을 조회하는 기능은 **이미 구현돼 있다**(`prefetchRouteOverview`, 카메라 정지 400ms 후). 그런데 `isRouteOverviewZoom` 이 `zoom <= 9.5` 를 요구하는데 **앱 기본 진입 줌이 11.0** 이라 일반 사용에서는 한 번도 실행되지 않는다. 관측 로그를 붙여 확인했다:

```
camera idle zoom=11.0 > 9.5 — no auto fetch
fetch 50.128,-120.168 loaded=true regions=4      ← 줌아웃 후에는 정상 동작
region 50.128,-120.168 got=30 complete=true
```

문턱을 기본 줌 위로 열지는 조회량·비용 판단이 필요하다.

---

## 5. 심사 관련 — Codex 검수 결과

`gpt-5.6-terra` 로 체크리스트를 검수했다. 반영은 끝냈고 요지는 다음과 같다.

**정정된 것**: 처음에 "Always 권한이 없어 iOS 에서 자동 주행 시작이 안 된다" 고 판단했으나 **틀렸다.** `_trackingSettings` 가 `allowBackgroundLocationUpdates: true` 를 설정하고 `UIBackgroundModes=location` 이 살아 있어, When In Use 권한이라도 포그라운드에서 시작한 스트림은 백그라운드에서 이어진다. Always 가 필요한 영역은 "앱 종료 후 위치 이벤트로 재실행" 뿐이다. **다만 실기기 미검증이므로 §7 에 확인 항목을 넣었다.**

**보강한 것**:
- App Privacy 라벨 — "Run Data" 는 ASC 에 없는 분류명이다. Precise Location / User ID / **Product Interaction**(`recommendation_log_service.dart` 가 추천 노출·선택 로그를 서버 저장) / Other Data 로 매핑해야 한다.
- Mapbox telemetry opt-out 이 attribution 메뉴에서 가려지지 않는지 확인 항목 추가.
- Guideline **1.4.5**(안전)가 2.5.4 보다 실질 리스크. 3.1·3.2 참조.
- 계정 삭제는 코드상 양호(익명 계정 삭제 + `delete-account` Edge Function + cascade). end-to-end 런타임 검증 항목만 추가했다.

---

## 6. 다음 사람이 할 일 (순서대로)

1. **미커밋 3개 파일 커밋·푸시** (2장) — `/tmp` 소실 전에
2. **3.1~3.4 결정** — 특히 모드 선택 칩과 안전 고지는 심사에 직접 닿는다
3. **실기기 smoke test** — §7. 주행 없이 가능한 9개부터 (권한 문구, 루트 후보, 반경, `이 지역` 검색, 상세, 주행 시작, 재시작 후 기록 복원). 실주행 필요 6개는 따로
4. **`lean_mvp` 머지** — pre-push 훅 때문에 Codex 통합 워크스페이스에서만 가능
5. App Store Connect 입력 → signed archive → 업로드

**4장(루트 데이터)은 전부 출시 후다.** 북극성 V1 범위 밖이다.

---

## 7. 환경 메모

- iOS 시뮬레이터 빌드는 `--dart-define-from-file=.env` 필수. 빠뜨리면 Mapbox 토큰이 없어 `Map setup needed` 가 뜬다.
- 무선 연결 시 `flutter run --release` 의 설치 단계가 실패한다. 빌드는 성공하므로 설치만 따로 하면 된다:
  ```sh
  xcrun devicectl device install app --device <UDID> build/ios/iphoneos/Runner.app
  ```
- Dart `debugPrint` 는 `xcrun simctl launch --console-pty` 나 `log stream` 으로 잡히지 않는다. `flutter run` 으로 띄워야 보인다.
- 파이프라인 테스트는 Python 3.11+ 와 `bs4` 가 필요하다. 시스템 기본이 3.9 라 그대로는 돌지 않는다. `~/.local/bin/python3.11` 이 있다.
- **`plutil -extract KEY json 파일` 은 원본을 덮어쓴다.** 읽기만 하려면 `-o -` 를 붙일 것. 이번 세션에서 `ios/Runner/Info.plist` 를 이 명령으로 파괴했다가 빌드 산출물에서 역산해 복원했고, 재빌드 결과물이 파괴 이전과 완전 일치함을 확인했다. git 으로 원본 대조는 못 했으므로 접근이 풀리면 `git diff ios/Runner/Info.plist` 를 한 번 봐두면 좋다.
