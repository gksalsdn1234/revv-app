# Calimoto Summary

Last checked: 2026-04-16

## Product Position
Calimoto는 `motorcycle navigation and route planning`을 가장 직접적으로 내세우는 기준 제품이다. 공식 사이트의 핵심 메시지는 `curviest routes`, `round trip`, `desktop + app continuity`다. REVV가 route discovery를 어떤 언어와 흐름으로 보여줄지 정할 때 1차 기준으로 잡기 적합하다.

## Discovery Flow
- 시작점은 `지도에서 바로 경로 만들기`와 `자동 round trip 생성` 두 축이다.
- 공식 사이트는 `No time to plan? Let us create a round trip for you`를 전면에 둔다.
- Help Center 기준 round trip은 시작점, 길이, 방향, routing profile만으로 바로 생성된다.
- 수동 조정은 `via point drag & drop` 중심이다.

## Routing Controls
- round trip 설정 축은 단순하다.
- 공개 문서 기준 노출 제어는 `length`, `starting point`, `direction`, `routing profile: winding or twisty` 수준이다.
- 복잡한 shaping controls보다 `빠르게 재밌는 길 생성` 쪽에 무게가 있다.

## Ride-Time UX
- turn-by-turn navigation, caution point alerts, offline maps를 App Store와 공식 사이트에서 강하게 민다.
- 최근 help 문서 기준 road closure 확인과 detour 제안까지 제공한다.
- 라이딩 중 재계산과 closure 우회는 `route settings`와 `map settings`에 연결된다.

## Saved Route / Import / Share
- App Store 기준 GPX import 지원.
- 공식 사이트 기준 ride stats와 ride sharing을 주요 가치로 묶는다.
- route planning은 web과 app 양쪽에서 이어지게 설계되어 있다.

## Community or Public Routes
- App Store와 공식 사이트 모두 `other bikers' routes`, `tens of thousands of routes ridden by other bikers`를 강조한다.
- 다만 커뮤니티 자체가 전면 UI의 중심이라기보다는 discovery 보강 요소에 가깝다.

## Pricing / Feature Gating
- App Store 설명 기준 premium에서 offline maps, navigation, speed limits, caution alerts, lean angle/acceleration analysis를 강조한다.
- 커브 생성과 discovery는 무료 진입이 가능하지만, 실주행 utility는 premium gate 비중이 높다.

## Known Complaints
- 커뮤니티 검색 결과 기준 반복 패턴은 `너무 커브를 우선하다 보니 이상한 우회가 생긴다`, `missed turn 이후 route recovery가 답답하다`, `premium gate가 강하다` 쪽이다.
- 즉 discovery는 강하지만, ride-time recovery UX는 무조건 따라가면 안 된다.

## REVV Takeaway
- 따라갈 것:
  - route discovery 첫 화면의 단순성
  - round trip framing
  - result card에서 `curvy value`를 직관적으로 보여주는 방식
- 다르게 갈 것:
  - REVV는 `twisty`만이 아니라 `fun + flow + residential` 기준으로 route quality를 설명해야 한다.
  - missed turn / detour recovery는 Scenic 스타일로 더 명시적으로 풀어야 한다.

## Sources
- Official site: [calimoto.com/en](https://calimoto.com/en)
- Twisty algorithm: [Our Twisty Roads Algorithm](https://support.calimoto.com/hc/en-us/articles/10514787546908-Our-Twisty-Roads-Algorithm)
- Round trip planning: [How Do I Plan a Round Trip?](https://support.calimoto.com/hc/en-us/articles/7989918956572-How-Do-I-Plan-a-Round-Trip)
- Closures and detours: [See Real-Time Road Closures Right on the Map](https://support.calimoto.com/hc/en-us/articles/19562744207900--NEW-See-Real-Time-Road-Closures-Right-on-the-Map)
- App Store listing: [calimoto Motorcycle Navigation App](https://apps.apple.com/us/app/calimoto-motorcycle-navigation/id1209129603)
- Community signal sample: [Reddit discussion 1](https://www.reddit.com/r/motorcycles/comments/1bbl32q), [Reddit discussion 2](https://www.reddit.com/r/motorcycles/comments/1et94nn/motorbike_navigation_app/)
