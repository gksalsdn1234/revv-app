# Threads/X 빌드인퍼블릭 — 첫 14포스트 (복붙용)

톤: 개발자 빌드인퍼블릭. 하루 1개, 스크린샷/지도 이미지 첨부 권장 (괄호 표기).

1. I got bored of driving the same 3 roads, so I built an algorithm that scores every road by how much it actually turns. 1,579 road segments analyzed this week. (첨부: 점수 터미널 출력 스샷)

2. The metric: winding density = degrees of direction change per km. A freeway scores ~5°/km. The best road I found this week scores 178°/km. That's a corner every 200 meters. For 8 km straight.

3. Google Maps optimizes for "fastest." I'm optimizing for "most fun at the speed limit." Completely different graph problem. (첨부: 같은 A→B 두 루트 비교 지도)

4. My algorithm ranked a tiny island road (Fulford–Ganges, Salt Spring Island) above roads 5x its size. Locals confirmed: it's a gem. The data knew before I did. (첨부: map_09)

5. Fun failure: my first scoring formula loved parking lots. Infinite bearing changes per km. Had to filter by road class + minimum length. Every metric can be gamed, even by asphalt.

6. Shipped: my scorer now stitches road segments that share endpoints within 150m. One highway = 40 OSM ways. Data cleaning IS the product.

7. Today I turned the algorithm's output into an actual product: a 13-page PDF guide of the 10 best winding roads in BC + WA. Data → curation → design. Selling it for $9. Link in bio. (첨부: 커버)

8. Building in public honesty: the algorithm found the roads, but I still had to annotate every one by hand. Ferry schedules, logging trucks, where the pavement ends. AI/data gets you 80%. The last 20% is knowing the territory.

9. Overpass API tip: big bounding boxes = 504 timeouts. Split your queries by region and add retry on a mirror server. 4 regions worked, 3 timed out, mirror saved 2 of them.

10. The app version of this (REVV) scores roads in real time around you + tracks your drives with G-force telemetry from your phone's IMU at 50Hz. Flutter + Mapbox. Launching soon. (첨부: 앱 G포스 탭 스샷)

11. Someone asked why not just use existing "scenic route" lists. Because they're all the same 5 roads. My scorer found a farm road between 2,000m mountain walls that isn't on any list. That's the point. (첨부: map_07 Pemberton Meadows)

12. New experiment: Custom Route Drops. You tell me your postal code + radius, my pipeline finds YOUR 3 best local roads and I ship you a mini-guide in 48h. $19. Testing if personalization beats one-size-fits-all. Link in bio.

13. Tech stack for the curious: Overpass API (road geometry) → Python bearing-rate scorer → Mapbox Static API (dark maps) → HTML → headless Chrome → PDF. Zero design tools. The whole guide is code.

14. Week 2 starts tomorrow. Numbers so far: [진짜 숫자로 채우기 — 판매 N건, 팔로워 N, 조회수 상위 포스트]. Building in public means posting this even if it's ugly.
