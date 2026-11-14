# ⛳ 펑! 골프 파티 — 로블록스 게임 소스

기획(타깃 연령, 가챠 설계, 수익 모델)은 [GAME_DESIGN.md](GAME_DESIGN.md), 게임 페이지 설명은 [STORE_DESCRIPTION.md](STORE_DESCRIPTION.md), 이미지는 [images/](images/) 를 보세요.

## Studio 에 넣기 (손으로 붙여넣기)
| 어디에 | 무엇을 | 이름 | 파일 |
|---|---|---|---|
| ReplicatedStorage | Folder | `Shared` | |
| └ Shared | ModuleScript | `Config` | `src/shared/Config.luau` |
| └ Shared | ModuleScript | `Format` | `src/shared/Format.luau` |
| ServerScriptService | Folder | `Server` | |
| └ Server | **Script** | `Main` | `src/server/Main.server.luau` |
| └ Server | ModuleScript | `DataService` | `src/server/DataService.luau` |
| └ Server | ModuleScript | `Monetization` | `src/server/Monetization.luau` |
| └ Server | ModuleScript | `CourseBuilder` | `src/server/CourseBuilder.luau` |
| └ Server | ModuleScript | `Golf` | `src/server/Golf.luau` |
| └ Server | ModuleScript | `Gacha` | `src/server/Gacha.luau` |
| StarterPlayer → StarterPlayerScripts | Folder | `Client` | |
| └ Client | **LocalScript** | `Main` | `src/client/Main.client.luau` |
| └ Client | ModuleScript | `Shot` | `src/client/Shot.luau` |
| └ Client | ModuleScript | `UIKit` | `src/client/UIKit.luau` |

Rojo 를 쓰면 이 폴더에서 `rojo serve` → Studio 플러그인에서 Connect.

## 출시 전 체크리스트
1. 게임 설정 → 장소(Places) → **최대 플레이어 수 8**
2. 게임패스 2개, 개발자 상품 4개 만들고 ID 를 `Config.luau` 의 `id = 0` 자리에 입력
3. 성숙도 질문지: **유료 확률형 아이템 "예"** (GAME_DESIGN.md 6장)
4. 아이콘·썸네일·상품 이미지는 `images/` 폴더

## 테스트 팁
- 혼자서도 경기가 시작돼요 (`Config.MinPlayers = 1`). 아이템 방해는 **테스트 탭에서 플레이어 2명 이상**으로 확인
- 프리미엄 캡슐 테스트: 상품 ID 를 넣고 Studio 에서 젬 상품을 '테스트 구매'(실제 로벅스 차감 없음)
- 공이 너무 빨리/늦게 멈추면 `Config.Ball.rollingDrag`, 샷이 약하면 `maxShotSpeed` 조절
- ⚠️ 가챠 확률·천장 값을 바꾸면 게임 화면의 확률 표시도 자동으로 바뀝니다 (Config 한 곳만 고치면 됨)
