# REVV 자동응답 엔진 — 댓글/DM 위트 답변 라이브러리

> 쓰는 법 2가지:
> 1. **수동**: 댓글 유형 찾아서 복붙 (오늘부터)
> 2. **자동(ManyChat)**: 각 유형의 keyword를 트리거로, replies를 랜덤 회전 답변으로 등록 → 자동 발사
>
> 톤: 친근·위트·약간 너드미. 안전 규칙 준수 — 속도/스릴/레이싱 조장 금지. 항상 "scenic/winding/fun/safe" 프레임.
> 규칙: 자동 답변은 유형당 3~5개를 랜덤 회전(봇 냄새 방지). 링크 유도는 자연스럽게.

---

## A. "What app is this? / 앱 뭐야?" (전환 최우선)
**keyword**: what app, which app, app name, 앱 뭐, 어플, link to app
- "It's called REVV — I'm building it. It scores roads by how much they twist so you stop driving the same boring 3 routes. Link's in my bio 🔗"
- "REVV 👀 my own app. Think 'Shazam but for good driving roads.' Bio link has it."
- "That's REVV! It ranks roads by curve density so the fun ones actually surface. Coming to your phone soon — bio 🔗"

## B. "Where is this? / 여기 어디?" (참여 최대화)
**keyword**: where is this, location, what road, where, 어디
- "This one's [ROAD NAME] 🤫 the full route + 9 more are in my guide (bio). Locals are gonna be mad I shared it."
- "[ROAD NAME]! One of the ones my algorithm ranked way higher than any 'scenic drive' list. Guide in bio has the map."
- "Not telling 😌 ...ok fine it's [ROAD NAME]. Map's in the guide, link in bio."

## C. "How do you find these? / 어떻게 찾음?" (개발자 후킹)
**keyword**: how do you find, how did you find, how do you know, algorithm, 어떻게 찾
- "I pull every road from OpenStreetMap and score it by degrees-of-turning per km. Straight highway = boring number. This one scored 160°/km 🤓"
- "Math, honestly. Bearing changes per kilometer. The road either turns a lot or it doesn't — no opinions, just data."
- "Built an algorithm that measures how much a road wiggles. Turns out the best ones are never on the 'top scenic drives' lists."

## D. 칭찬 / 감탄 ("beautiful", "wow", "😍", "이쁘다")
**keyword**: beautiful, gorgeous, wow, amazing, stunning, love this, 이쁘, 멋지, 대박
- "Right?? And it's completely empty on a weekday morning. That's the whole reason I built the app."
- "The wild part is this one isn't even in the top 3 — wait till you see the guide 😮‍💨"
- "BC/PNW is unfairly good for this. Thanks for watching 🙏"

## E. 회의적 / 안전 시비 ("dangerous", "speeding", "reckless", "위험")
**keyword**: dangerous, speeding, reckless, illegal, too fast, 위험, 과속
- "Totally fair — but every road here is rewarding at the posted limit. It's about the corners, not the speed. Smooth > fast 🙂"
- "No speeding involved! A winding road is fun at 50 too. The app's whole point is legal, chill driving on better roads."
- "Appreciate the concern — I keep it legal. Good roads make the speed limit feel fun. That's the pitch."

## F. 가격/구매 ("how much", "price", "buy", "얼마")
**keyword**: how much, price, cost, buy, purchase, where to buy, 얼마, 구매
- "Guide's $9 right now (launch price) — bio link. Or the app's free when it drops 👀"
- "$9 for the 10-route guide, or wait for the app (free). Both in bio 🔗"
- "Cheaper than one tank of gas 😄 bio link has it."

## G. 협업/셋업 문의 ("gear", "what camera", "dashcam", "setup", "장비")
**keyword**: what camera, gear, dashcam, mount, setup, filming, 장비, 카메라
- "Just my phone on a dash mount + the app screen recorded. Full setup list is in my bio 🔗 (affiliate — helps me keep building)."
- "Phone + a cheap mount, honestly. Links to my exact gear in bio."
- "No fancy rig — phone POV + REVV's map overlay. Gear links in bio."

## H. 커스텀 루트 리드 ("near me", "my area", "in [city]", "우리동네")
**keyword**: near me, my city, in [지역], my area, do you have, 우리 동네, 근처
- "I can actually make you one 👀 I run the algorithm on YOUR area and send your 3 best local roads. It's the 'Custom Route Drop' in my bio."
- "Tell me your city — I do custom route packs (bio link). The app will do it live once it's out too."
- "That's literally a service I offer — Custom Route Drop, bio link. Send me a postal code and radius."

## I. 트롤/부정 ("boring", "who cares", "cringe", "노잼")
**keyword**: boring, who cares, cringe, lame, 노잼, 관심없
- "More roads for me then 🤷 have a good one!"
- "Fair, not everyone's into driving. Thanks for stopping by 🙂"
- "😂 respect. scroll on, friend."

## J. DM 인사/일반 (ManyChat 웰컴 자동응답)
**keyword**: hi, hello, hey, 안녕 (DM 첫 메시지)
- "hey! 👋 thanks for the DM. if you're after the routes, the guide + app are in my bio. anything specific you're looking for?"
- "yo! 🙌 quick heads up the 10-route guide is in bio. want a custom route pack for your area? just tell me your city."

---

## ManyChat 셋업 요약 (자동 발사)
1. ManyChat 무료 가입 → Instagram(크리에이터 계정) 연결
2. Automation → New → 각 유형을 **Keyword trigger**로 등록 (위 keyword 줄 그대로)
3. 각 트리거에 위 답변 3~5개를 **랜덤 응답**으로 입력 (봇 티 방지)
4. 댓글 자동응답: IG는 특정 게시물 댓글 키워드 → DM 자동 발송이 정석 (공개 댓글 자동답글은 제한적이라 DM 유도가 전환도 더 좋음)
5. B·F·H(전환 유형)는 답변 끝에 링크 버튼 붙이기

## 주의
- 100% 자동은 초기 성장에 오히려 독. **진짜 사람 답글(내가 초안)과 섞을 것.** 자동은 반복 질문(가격/링크/위치)만.
- 답변 라이브러리는 조회수 데이터 쌓이면 갱신. "이 답변이 프로필 클릭 잘 나온다" 싶으면 그 톤으로 확장.
