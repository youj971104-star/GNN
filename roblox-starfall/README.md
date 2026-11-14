# ⭐ 별똥별 타이쿤 — 로블록스 게임 소스

기획 내용(타깃 연령, 수익 모델, 로드맵)은 [GAME_DESIGN.md](GAME_DESIGN.md) 를 보세요.

## 폴더 구조
```
roblox-starfall/
├─ default.project.json      Rojo 설정 (폴더 → Studio 위치 매핑)
└─ src/
   ├─ shared/   → ReplicatedStorage.Shared
   │   ├─ Config.luau        밸런스·가격·게임패스 ID (여기만 고쳐도 됨)
   │   └─ Format.luau        숫자 줄임 표기 (1.2K, 3.4M)
   ├─ server/   → ServerScriptService.Server
   │   ├─ Main.server.luau   게임 규칙, 판매, 업그레이드, 환생, 펫, 출석
   │   ├─ DataService.luau   저장/불러오기 (세션 잠금, 자동 저장)
   │   ├─ StarService.luau   별 소환·줍기 (서버 판정)
   │   ├─ Monetization.luau  게임패스·개발자 상품 결제 처리
   │   └─ MapBuilder.luau    맵 자동 생성 (허브 + 땅 6개)
   └─ client/   → StarterPlayer.StarterPlayerScripts.Client
       ├─ Main.client.luau   UI 전부 (HUD, 상점, 펫, 환생, 출석), 효과
       └─ PetVisuals.luau    펫이 캐릭터를 따라다니는 연출
```
맵과 UI 를 전부 코드가 만들기 때문에, **빈 Baseplate 템플릿**에 스크립트만 넣으면 바로 플레이됩니다.

## 방법 A — Rojo 로 연결 (추천)
1. Rojo 설치: https://rojo.space (VS Code 확장 + Studio 플러그인)
2. 이 폴더에서 `rojo serve`
3. Studio → 새 Baseplate → Rojo 플러그인 → Connect

## 방법 B — 손으로 붙여넣기
Studio 에서 아래처럼 만들고 각 파일 내용을 복사해 붙여넣으세요. **이름이 정확해야** 합니다.

| Studio 위치 | 종류 | 이름 | 파일 |
|---|---|---|---|
| ReplicatedStorage | Folder | `Shared` | |
| ReplicatedStorage.Shared | ModuleScript | `Config` | shared/Config.luau |
| ReplicatedStorage.Shared | ModuleScript | `Format` | shared/Format.luau |
| ServerScriptService | Folder | `Server` | |
| ServerScriptService.Server | **Script** | `Main` | server/Main.server.luau |
| ServerScriptService.Server | ModuleScript | `DataService` / `StarService` / `Monetization` / `MapBuilder` | server/*.luau |
| StarterPlayer.StarterPlayerScripts | Folder | `Client` | |
| …StarterPlayerScripts.Client | **LocalScript** | `Main` | client/Main.client.luau |
| …StarterPlayerScripts.Client | ModuleScript | `PetVisuals` | client/PetVisuals.luau |

## 출시 전 체크리스트
1. **게임 게시**: File → Publish to Roblox
2. **API 접근 켜기**: Game Settings → Security → *Enable Studio Access to API Services* (Studio 에서도 저장 테스트)
3. **게임패스 / 개발자 상품 만들기**: Creator Dashboard → 내 경험 → Monetization → Passes / Developer Products
   - 만든 뒤 나오는 숫자 ID 를 `Config.luau` 의 `GamePasses` / `Products` 의 `id = 0` 자리에 넣기
   - ID 가 0 인 상품은 상점에 "ID 설정 필요" 로 표시되고 구매 버튼이 동작하지 않음
4. **성숙도 질문지(Maturity & Compliance)** 작성 → Minimal 등급
5. 아이콘(512×512)과 썸네일(1920×1080) 등록 — 클릭률에 가장 큰 영향
6. 공개(Public) 전환 후 소수 인원으로 테스트 → `Config.luau` 숫자로 밸런스 조정

## 테스트 팁
- Studio 의 **Test → Start (플레이어 2명)** 로 서버 공지, 펫 표시, 땅 배정을 확인
- 결제는 Studio 에서 테스트 구매(실제 Robux 차감 없음)로 확인 가능
- 밸런스를 빠르게 보고 싶으면 `Config.Rarities` 의 `value` 를 잠깐 올려서 테스트

## 보안 메모
- 코인, 별 줍기, 구매 가능 여부는 **모두 서버가 판정**합니다. 클라이언트는 "이거 사고 싶어요" 요청만 보냄
- 결제는 지급 + 저장이 끝나야 완료 처리, 같은 영수증 중복 지급 방지
