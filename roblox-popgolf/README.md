# ⛳ 팝골프 — 로블록스 게임 소스

기획(타깃 연령, 가챠 설계, 수익 모델)은 [GAME_DESIGN.md](GAME_DESIGN.md), 게임 페이지 설명은 [STORE_DESCRIPTION.md](STORE_DESCRIPTION.md), 이미지는 [images/](images/) 를 보세요.

## Studio 에 넣기 (손으로 붙여넣기)
| 어디에 | 무엇을 | 이름 | 파일 |
|---|---|---|---|
| ReplicatedStorage | Folder | `Shared` | |
| └ Shared | ModuleScript | `Config` | `src/shared/Config.luau` |
| └ Shared | ModuleScript | `Format` | `src/shared/Format.luau` |
| └ Shared | ModuleScript | `ClubRig` | `src/shared/ClubRig.luau` |
| ServerScriptService | Folder | `Server` | |
| └ Server | **Script** | `Main` | `src/server/Main.server.luau` |
| └ Server | ModuleScript | `DataService` | `src/server/DataService.luau` |
| └ Server | ModuleScript | `Monetization` | `src/server/Monetization.luau` |
| └ Server | ModuleScript | `CourseBuilder` | `src/server/CourseBuilder.luau` |
| └ Server | ModuleScript | `Golf` | `src/server/Golf.luau` |
| └ Server | ModuleScript | `Gacha` | `src/server/Gacha.luau` |
| └ Server | ModuleScript | `Club` | `src/server/Club.luau` |
| └ Server | ModuleScript | `LobbyBuilder` | `src/server/LobbyBuilder.luau` |
| StarterPlayer → StarterPlayerScripts | Folder | `Client` | |
| └ Client | **LocalScript** | `Main` | `src/client/Main.client.luau` |
| └ Client | ModuleScript | `Shot` | `src/client/Shot.luau` |
| └ Client | ModuleScript | `ClubFX` | `src/client/ClubFX.luau` |
| └ Client | ModuleScript | `SwingAnimator` | `src/client/SwingAnimator.luau` |
| └ Client | ModuleScript | `VFX` | `src/client/VFX.luau` |
| └ Client | ModuleScript | `UIKit` | `src/client/UIKit.luau` |

Rojo 를 쓰면 이 폴더에서 `rojo serve` → Studio 플러그인에서 Connect.

## 출시 전 체크리스트
- **그래픽:** 탐색기 → Lighting 선택 → 속성 `Technology` 를 **Future** 로 (빛·그림자 품질, 스크립트로는 못 바꿈). 나머지 조명·색 보정·구름은 코드가 자동 설정
0. 아바타는 **R6·R15 모두 지원**(키에 맞춰 골프채 길이 자동). 허리 비틀기·팔꿈치까지 자연스러운 건 **R15** 라서 게임 설정 → 아바타 → R15 권장
1. 게임 설정 → 장소(Places) → **최대 플레이어 수 8** (4대4까지. 관전 자리를 두려면 10)
2. 게임패스 2개, 개발자 상품 4개 만들고 ID 를 `Config.luau` 의 `id = 0` 자리에 입력
3. 성숙도 질문지: **폭력 "가벼움·비현실적"**, **유료 확률형 아이템 "예"** (GAME_DESIGN.md 6장)
4. 아이콘·썸네일·상품 이미지는 `images/` 폴더

## 테스트 팁
- 혼자서도 연습 경기가 시작돼요 (`Config.MinPlayers = 1`). 팀전은 **테스트 탭 → 클라이언트 및 서버 → 플레이어 4명(2대2) / 6명(3대3) / 8명(4대4)** 으로 확인
- 팀 최대 인원은 `Config.MaxTeamSize`, 인원별 코스 폭·아이템 수는 `Config.Course.widthPerExtraPlayer`, `boxesPerExtraPlayer`
- 골프채 위치가 어색하면 `ClubRig.luau` 의 `PIVOT_Z`(스윙 중심 앞뒤)·`HEAD_HEIGHT`(클럽 머리 높이)·Geometry 의 `armLen * 0.85`(손 위치), 스윙 크기·속도는 `SwingAnimator.luau` 맨 위 숫자(BACK_MAX, FOLLOW, SWING_TIME, WAIST_TWIST, HAND_GAP)를 조절하세요. 공이 발에서 너무 멀거나 가까우면 `Config.Club.stanceOffset`
- 공이 너무 멀리/가까이 가면 `Config.Ball.maxSpeed`, 너무 높이/낮게 뜨면 `launchAngle`
- 프리미엄 캡슐 테스트: 상품 ID 를 넣고 Studio 에서 젬 상품을 '테스트 구매'(실제 로벅스 차감 없음)
- 공이 너무 빨리/늦게 멈추면 `Config.Ball.rollingDrag`, 샷이 약하면 `maxShotSpeed`, 넘어뜨리기가 너무 세면 `Config.Club` 조절
- ⚠️ 가챠 확률·천장 값을 바꾸면 게임 화면의 확률 표시도 자동으로 바뀝니다 (Config 한 곳만 고치면 됨)
