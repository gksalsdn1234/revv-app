# REVV Demo Page — Copy & Structure Brief
> Claude 담당 파트: 메시지 구조 / 헤드라인 / 서브카피 / 섹션 순서 / CTA / 수요 검증 질문
> Codex 담당 파트: 실제 UI 구현, 화면 자산 추출, 폼 연결

---

## 페이지 목표 (단 하나)
> **"써보고 싶다"는 마음을 만들고, 연락처 또는 반응을 남기게 한다.**
> 완성도 자랑 ❌ / 기능 목록 나열 ❌ / 10초 안에 가치 전달 ✅

---

## 핵심 포지셔닝 한 줄
```
REVV is an AI driving companion that finds roads worth driving,
keeps you in the zone while you drive, and helps you remember the run after.
```

**한국어 버전 (SNS/설명용)**
```
달릴 맛 나는 루트를 찾아주고, 달리는 동안 집중하게 해주고,
끝난 뒤 그 드라이브를 기억하게 해주는 AI 드라이빙 컴패니언
```

---

## Section 1 — HERO

### 목적
첫 5초 안에 "이 앱은 내 드라이브를 위한 것"임을 느끼게 한다.
드라이빙 앱임을 설명하는 것이 아니라, **드라이브를 즐기는 사람에게 말 거는 것**이 목표.

### 비주얼 지시 (Codex)
- DriveScreen HUD 또는 Routes map + HUD 조합 사용
- 움직임이 있으면 가장 강함 (속도계 올라가거나 루트 flyTo 애니메이션)
- 배경: 어두운 네온 계열 (앱 스타일 그대로)

### 헤드라인 (1안 권장)
```
The roads you've been missing.
```
**서브라인**
```
REVV finds scenic, winding routes near you — then rides along
as your AI co-driver while you drive them.
```

### 헤드라인 2안 (더 직설적)
```
Find roads worth driving.
Drive them with purpose.
Look back on every run.
```

### 헤드라인 3안 (감성 강조)
```
Driving for the sake of driving.
```
**서브라인**
```
Route discovery. Live HUD. Post-drive AI review.
Everything your regular nav app doesn't care about.
```

> **권장**: 1안. "missing"이라는 단어가 루트 발견 기능 + 감정(놓치고 있었다는 아쉬움) 두 가지를 동시에 건드림.

### CTA 버튼 (Hero)
```
[Join the Waitlist]
```
부가 텍스트:
```
Free during early access · iOS & Android
```

---

## Section 2 — WHY REVV

### 목적
기존 내비앱과 무엇이 다른지 1문장으로 설명. 공감 먼저, 솔루션 나중.

### 섹션 헤드라인
```
Google Maps gets you there. REVV makes the drive worth taking.
```

### 본문 (3줄 이내)
```
Most navigation apps optimize for speed and efficiency.
That's fine for commutes. But when you actually want to drive —
to find a great road, feel the car, remember the run — they offer nothing.

REVV is built for those drives.
```

### 선택지: 2-column 레이아웃 (텍스트만으로도 OK)
| 기존 내비 | REVV |
|---|---|
| 최단 경로 | 달릴 맛 나는 루트 |
| 도착지 안내 | 주행 중 HUD + G-force |
| 기록 없음 | AI 리뷰 + 주행 카드 |

---

## Section 3 — 3-STEP FLOW

### 목적
앱이 실제로 어떻게 작동하는지, **과장 없이**, 3단계로 보여준다.
각 단계에 실제 앱 화면 1장 + 짧은 카피.

### 섹션 헤드라인
```
Three moments. One drive.
```

---

### Step 1 — Find a Route
**비주얼**: RoutesScreen — 지도 위 추천 루트 카드, 난이도 배지, 거리
**캡션 헤드라인**:
```
Find routes built for driving, not just getting there.
```
**서브카피**:
```
REVV scans roads near you and scores them by curve density,
distance, and difficulty — so you can pick a route by how fun it'll be.
```
**작은 배지 힌트** (UI에 인라인으로):
- `🔄 LOOP` `SCENIC` `WINDING` `12.4 km`

---

### Step 2 — Drive with HUD
**비주얼**: DriveScreen (SprintScreen) — 속도계, G-force 원형, Drive Mode 배지
**캡션 헤드라인**:
```
Stay in the zone the whole time.
```
**서브카피**:
```
Live speed, lateral G-force, and drive mode — all on screen
while you focus on the road. No notifications. No distractions.
Just the drive.
```
**작은 배지 힌트**:
- `SPORT MODE` `↔ 0.42G` `67 km/h`

---

### Step 3 — Review Your Run
**비주얼**: RunCardScreen — 주행 요약 지도, 거리/시간/최대 G, AI 코치 텍스트
**캡션 헤드라인**:
```
Every drive leaves something worth keeping.
```
**서브카피**:
```
When you're done, REVV shows you the route you took, your stats,
and an AI summary of how the drive felt — so you can actually
remember it, share it, or do it again.
```
**작은 배지 힌트**:
- `Run #7` `18.3 km` `Peak G: 0.61` `AI Review ✨`

---

## Section 4 — DEMAND VALIDATION

### 목적
기능 선호 조사가 아니라 **사용 의향 확인**에 집중.
"좋아 보인다"가 아니라 "써볼 것 같다"를 측정하는 것이 목표.

### 섹션 헤드라인
```
We're building this for drivers like you.
Tell us if we're on track.
```

### 질문 설계 (3문항 이내 권장)

---

**Q1. 사용 의향 (핵심 질문)**
> Single-select / 필수

```
If REVV launched today, how likely are you to try it?
```
- `Definitely — I'd try it this weekend`
- `Probably — sounds like something I'd use`
- `Maybe — depends on execution`
- `Unlikely — not really for me`

---

**Q2. 드라이빙 컨텍스트 파악**
> Single-select / 선택

```
When do you usually drive for fun? (pick the one that fits most)
```
- `Weekend morning runs on empty roads`
- `After work wind-down drives`
- `Road trips where the route matters`
- `I mostly drive for commute / errands`

---

**Q3. 가장 끌리는 기능 (우선순위 파악)**
> Single-select / 선택

```
Which part of REVV sounds most interesting to you?
```
- `Finding routes I didn't know about`
- `The live HUD while driving`
- `Reviewing my drives after the fact`
- `All of it, honestly`

---

### 폼 아래 보조 텍스트
```
No account needed. Takes 30 seconds.
Your answers help us build what actually matters to drivers.
```

---

## Section 5 — CTA (Waitlist)

### 목적
관심 있는 사람이 연락처를 남기게 한다. 가입 장벽 최소화.

### 섹션 헤드라인
```
Be the first to drive with REVV.
```

**서브라인**:
```
Early access is free. We'll reach out when it's ready for you.
```

### 폼 구성
```
[Email address                    ] [Join Waitlist →]
```

**폼 아래 미세 카피**:
```
No spam. Just one message when you can try REVV.
```

### 확인 메시지 (제출 후)
```
You're on the list. 🏁
We'll let you know as soon as early access opens.
```

---

## 전체 섹션 순서 요약

| # | 섹션 | 핵심 역할 | 앱 화면 |
|---|---|---|---|
| 1 | Hero | 첫인상 + 한 줄 가치 | DriveScreen HUD |
| 2 | Why REVV | 기존 내비와의 차이 | 없음 (텍스트/비교) |
| 3 | 3-Step Flow | 실제 동작 증명 | Routes / Drive / RunCard |
| 4 | Demand Validation | 사용 의향 측정 | 없음 (설문) |
| 5 | CTA | 연락처 수집 | 없음 (폼) |

---

## 디자인 원칙 (Codex 전달용)

1. **스크린은 3장 상한** — 많아지면 기능 목록처럼 보임
2. **앱 배경색/폰트 그대로** — REVV Waze Neon 스타일 유지
3. **LoadingScreen은 Hero 배경 또는 브랜드 오프닝으로만** — 핵심 증거 화면 아님
4. **OBD / 클라우드 동기화 / 랭킹은 언급하지 않음** — supporting feature
5. **영어 카피 우선** — 캐나다 타겟
6. **모바일 퍼스트** — 앱을 핸드폰으로 볼 가능성 높음

---

## 10초 테스트 체크리스트
페이지를 처음 본 사람이 10초 안에 답할 수 있어야 함:
- [ ] 이 앱이 뭐 하는 앱인가?
- [ ] 왜 Google Maps랑 다른가?
- [ ] 나한테 맞는 앱인가?
- [ ] 어떻게 연락하거나 신청하는가?
