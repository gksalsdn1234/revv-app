# AGENTS.md — AI 작업 지침 (Claude/Codex/기타 AI 공통)

이 폴더는 민우의 **돈벌기 프로젝트** (목표 ₩1,000,000, SNS 기반, 북미 타겟)다.
새 세션에서 이 파일만 읽으면 이어서 작업할 수 있어야 한다.

## 컨텍스트
- 민우: 캐나다 거주 개발자. Flutter 드라이빙 앱 **REVV** 출시 직전 (출시 repo: `~/Documents/revv-lean-mvp`, lean_mvp 브랜치)
- 전략: SNS는 수익원이 아니라 유통 채널. 실제 수익 = ① 루트 가이드 PDF($9~12, Gumroad) ② 커스텀 루트 드롭($19) ③ 아마존 제휴 ④ REVV 앱 퍼널
- 오디언스 2종: 운전자(TikTok/Reels/Shorts 영상) + 개발자(Threads/X 빌드인퍼블릭)
- 원본 repo: github.com/gksalsdn1234/revv-app 브랜치 `claude/sns-revenue-strategy-c98e26` (이 폴더와 동일 내용 + git 히스토리)

## 폴더 구조
- `01_전략/` — 마스터 플랜(sns_revenue_plan.md: 상품 사다리·자동화 파이프라인·4주 로드맵), 14일 콘텐츠 캘린더(훅·대본)
- `02_판매상품/` — 완성된 가이드 PDF + Gumroad 복붙 문안
- `03_콘텐츠/` — Threads 14포스트 완성문(EN), 자동응답 엔진(auto_reply_engine.md: 댓글/DM 10유형 위트 답변 + ManyChat 키워드 트리거), 한국어 코미디 계정 컨셉(concept_사장vs판매AI.md: 「기능충 사장 vs 갈굼당하는 판매 AI」 캐릭터극, Threads KR 서브계정용 14포스트)
- `04_파이프라인/` — 가이드 생성 코드 (아래 사용법)
- `05_TCG카드샵서비스/` — 트랙 B. 카드샵 스토어프론트 판매 (소스: `~/Desktop/tkl-demo`). GO_TO_MARKET.md에 라이선스 판정 포함

## 트랙 B 라이선스 규칙 (반드시 준수)
- tkl-demo는 GPL-3.0 홀로 CSS(`app/vendor/pokemon-cards-css/`) + 포켓몬 IP(pokemontcg.io 이미지) 포함.
- **호스팅 서비스로만 판매** — 코드/소스를 고객에게 넘기지 말 것 (GPL 배포 트리거 + 프로프라이어터리 락 불가).
- 마케팅은 "TCG 카드샵 스토어프론트"로. "Pokémon" 브랜드로 마케팅 금지 (TPC 트레이드마크).
- 코드를 정말 팔아야 하면 홀로 CSS를 MIT/자체제작으로 교체 후에만.
- 상세: `05_TCG카드샵서비스/GO_TO_MARKET.md`

## 커스텀 루트 드롭 처리법 (주문 들어왔을 때)
1. `04_파이프라인/fetch_routes.py`의 `REGIONS`를 고객 위치 기준 bbox로 교체 (반경 30/50/100km)
2. `python3 fetch_routes.py` → 점수 상위 확인 (Overpass 504 나면 미러 `overpass.kumi.systems` 재시도)
3. `build_maps.py`의 `PICKS`를 상위 3개로 수정 → 실행 (Mapbox 토큰 포함됨)
4. `build_guide.py`의 `DISPLAY` dict에 3개 루트 설명 작성 → 실행 → PDF 생성 (헤드리스 Chrome 필요)
- 전 과정 약 10분. 스코어링: winding density(°/km) = Σ|Δbearing|/km, score = density×√km

## 반복 작업 (요청 시)
- **주간 배치**: 캘린더 다음 7일 분량의 캡션+해시태그+발행시간(오후 6시 PST)을 Metricool 복붙용으로 출력
- **주간 리뷰**: 민우가 주는 조회수/판매 수치로 상위 포맷 분석 → 다음 주 캘린더 갱신
- **Vol.2 가이드**: Mt Baker Hwy(WA) 지역이 Overpass 타임아웃으로 Vol.1에서 빠짐 — 재시도 후보 1순위. 이후 오리건/캘리포니아

## 불변 규칙
1. **안전 언어**: 속도·스릴 조장 금지. "fast/speed/thrill/racing" ❌ → "scenic/winding/technical/fun to drive" ⭕. 앱스토어 심사 + 브랜드 리스크
2. **계정·비밀번호·결제는 민우만**: AI는 계정 생성/로그인/결제 세팅 금지. 게시물 업로드는 민우 승인 후에만
3. **커스텀 루트는 포장도로만**: `surface!~"gravel|dirt|unpaved"` 필터 유지, 최소 8km
4. **가격 변경·환불 등 돈 결정은 민우 확인 후**
5. REVV 앱 출시 작업(revv-lean-mvp)이 항상 이 프로젝트보다 우선
6. **판매용 산출물은 업로드 전 독립 검수 필수**: 제작에 관여하지 않은 에이전트가 "돈 낸 구매자" 관점으로 리뷰(사실 웹검증 포함) → **BUY 판정 없이는 업로드 금지**. 루트 수치·지도는 `04_파이프라인/fetch_routes_v2.py`(라우팅 실측 + 거리밴드·도로명·연속성 자동 체크, 실패 시 exit 1) 통과분만 사용. v1 `fetch_routes.py`(bbox 조각 합산)는 후보 발굴용으로만 — 상품에 싣는 거리·시간·지도는 반드시 v2로 재측정 (2026-07-18 v1.1 사태: bbox 방식이 거리 3건 오류·조각 지도 → REFUND 판정, v2 전환 후 BUY)

## 현재 TODO (2026-07-18 기준)
- [ ] 민우: 계정 셋업 30분 (README.md STEP 1~2)
- [ ] 민우: 주말 촬영 1회
- [ ] AI: 촬영본 나오면 Week 1 배치 생성
- [ ] AI: 아마존 제휴 계정 승인 후 링크 3종(거치대/대시캠/VEEPEAK OBD) 선정
- [ ] AI: Vol.2 (Mt Baker + 오리건) 데이터 수집
- [ ] 민우: 한국 Threads 서브계정 생성 (concept_사장vs판매AI.md 운영용) + ManyChat 연결 15분 (auto_reply_engine.md 자동발사용)
