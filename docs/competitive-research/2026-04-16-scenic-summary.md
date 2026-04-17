# Scenic Summary

Last checked: 2026-04-16

## Product Position
Scenic은 `Plan, Ride, Track`을 하나의 흐름으로 묶지만, 실제 강점은 `ride-time UX`, `CarPlay`, `import flexibility`에 있다. REVV가 주행 중 인터랙션과 route rejoin 흐름을 정할 때 가장 많이 참고해야 할 앱이다.

## Discovery Flow
- App Store 기준 `public routes`, `search area`, `round trip in any given direction`, `curvy route to a destination`이 모두 discovery entry다.
- route planning entry는 존재하지만, product messaging에서 `plan + discover + import`가 같은 레벨로 묶여 있다.
- route generation 자체보다 `다른 툴에서 만든 route도 Scenic 안에서 운영한다`는 포지션이 강하다.

## Routing Controls
- 공식 help와 forum 기준 Scenic 자체 routing mode는 존재하지만, 고급 shaping control은 제한적이다.
- 여러 routing mode를 구간별로 다르게 적용하는 기능은 약하고, 복잡한 플래닝은 Kurviger/Furkot 등 외부 planner import를 적극 권장한다.
- 이건 Scenic이 planner보다 navigator에 더 가깝다는 신호다.

## Ride-Time UX
- 이 앱의 핵심 차별점이다.
- CarPlay 관련 릴리즈 노트가 매우 촘촘하고, 최근 버전에서도 route mode 변경, stop 추가, alternate route 선택, POI search가 CarPlay에 계속 추가되고 있다.
- 공식 help 문서 기준 `guide to route start / join route from current location` 선택이 명시적이다.
- detour behavior, skip waypoint, zoom modes, safety cameras, closures가 help center 1차 카테고리로 보인다.

## Saved Route / Import / Share
- Google Maps URL, GPX, KML, KMZ, GDB, ITN import를 공식 help가 전면적으로 설명한다.
- Scenic WebApp drag & drop까지 제공한다.
- route source를 앱 내부 생성보다 더 넓게 받아들이는 구조다.

## Community or Public Routes
- public routes는 많지만, REVER처럼 community product가 중심은 아니다.
- discovery와 sharing을 보조하는 수준이다.

## Pricing / Feature Gating
- App Store 기준 subscription model이다.
- Premium, offline maps, enhanced navigation capabilities가 유료 축이다.
- 다만 messaging은 paywall보다 `best riding experience` 중심으로 포장돼 있다.

## Known Complaints
- 커뮤니티 패턴은 비교적 일관적이다.
- `ride-time navigation and CarPlay are strong`, `route planning is clunky`, `complex planning은 외부 툴이 낫다`는 평가가 반복된다.
- REVV는 planner와 navigator를 한 화면에 과하게 합치지 말아야 한다는 근거로 볼 수 있다.

## REVV Takeaway
- 따라갈 것:
  - active navigation UI
  - CarPlay / large-screen interaction assumptions
  - route start 합류와 rejoin UX
  - import-friendly mindset
- 다르게 갈 것:
  - REVV는 planner에서 더 강한 route quality 설명을 제공해야 한다.
  - Scenic처럼 planner를 약하게 두기보다, discovery와 planner를 더 자연스럽게 연결해야 한다.

## Sources
- Official site: [scenic.app](https://scenic.app/)
- Help center: [Scenic Help Center](https://scenic.app/help/)
- Import coverage: [Ways and sources to Import](https://scenic.app/help/ways-sources-to-import/)
- Rejoin/start logic: [Start a route in the middle](https://scenic.app/help/start-a-route-in-the-middle/)
- App Store listing: [Scenic Motorcycle Navigation App](https://apps.apple.com/us/app/scenic-motorcycle-navigation/id1089668246)
- Community signal sample: [Reddit discussion](https://www.reddit.com/r/motorcycles/comments/1fn2cse/tried_out_the_scenic_app/)
