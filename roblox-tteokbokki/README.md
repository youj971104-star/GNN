# 🍢 떡볶이 가게 타이쿤 — 로블록스 게임 소스

기획(타깃 연령, 수익 모델, 로드맵)은 [GAME_DESIGN.md](GAME_DESIGN.md) 를 보세요.

## 폴더 구조
```
src/
├─ shared/   → ReplicatedStorage.Shared
│   ├─ Config.luau        밸런스·가격·게임패스 ID (여기만 고쳐도 됨)
│   └─ Format.luau        숫자 줄임 표기
├─ server/   → ServerScriptService.Server
│   ├─ Main.server.luau   게임 규칙 (Script)
│   ├─ Tycoon.luau         가게 터 하나(버튼, 기계, 컨베이어, 계산대)
│   ├─ DataService.luau   저장/불러오기 (세션 잠금, 자동 저장) — 공용
│   └─ Monetization.luau  게임패스·개발자 상품 결제 처리 — 공용
└─ client/   → StarterPlayer.StarterPlayerScripts.Client
    ├─ Main.client.luau   UI (돈, 초당 수입, 바로 짓기 버튼, 상점, 건물 목록, 프랜차이즈) (LocalScript)
    └─ UIKit.luau         코드로 UI 만드는 공용 도구
```
맵과 UI 를 코드가 만들기 때문에 **빈 Baseplate 템플릿**에 넣으면 바로 플레이됩니다.

## Studio 에 넣기
- **Rojo (추천)**: 이 폴더에서 `rojo serve` → Studio Rojo 플러그인에서 Connect
- **손으로**: 위 구조대로 Folder / Script / LocalScript / ModuleScript 를 만들고 이름을 똑같이 (`.server`, `.client`, `.luau` 는 빼고) 지은 뒤 내용 붙여넣기
  - `Main.server.luau` → **Script** `Main`, `Main.client.luau` → **LocalScript** `Main`, 나머지는 **ModuleScript**

## 출시 전 체크리스트
1. File → Publish to Roblox
2. Game Settings → Security → **Enable Studio Access to API Services** (저장 테스트)
3. Creator Dashboard → Monetization 에서 게임패스 / 개발자 상품 만들고, ID 를 `Config.luau` 의 `id = 0` 자리에 입력
4. 성숙도 질문지(Maturity & Compliance) 작성
5. 아이콘 512×512, 썸네일 1920×1080 등록

## 테스트 팁
- 빨리 끝까지 보고 싶으면 `Config.Buttons` 의 cost 를 잠깐 낮추세요
- 서버당 가게 6개 → Game Settings → Places → Max Players 를 **6** 으로 맞추세요
