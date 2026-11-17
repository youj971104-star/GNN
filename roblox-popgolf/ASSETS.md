# 3D 에셋 연결 가이드

모델러에게 받은 FBX를 Studio에 넣으면 게임 코드(`src/shared/AssetLib.luau`)가 **이름으로 찾아서** 로비·코스·골프채·모자에 자동으로 배치합니다.
에셋이 없으면 지금의 기본 도형이 그대로 나오므로, 하나씩 넣어 가며 확인해도 됩니다.

## 1. Studio에 넣는 순서

1. 탐색기에서 **ReplicatedStorage** 아래에 **Folder**를 만들고 이름을 정확히 `Assets`로 바꿉니다.
2. 상단 메뉴에서 **3D 가져오기(Import 3D)**를 누르고 FBX 파일을 하나 고릅니다.
3. 가져오기 창에서 그대로 **가져오기**를 누르면 작업 공간(Workspace)에 모델이 생깁니다.
4. 생긴 모델을 `ReplicatedStorage > Assets` 폴더 안으로 끌어 옮깁니다.
5. 모델 이름이 아래 표의 이름과 **똑같은지** 확인합니다 (보통 FBX 파일 이름이 그대로 붙습니다).
6. 게임을 저장하고 게시하면 메시가 내 계정으로 올라갑니다.

> 텍스처(PNG)가 함께 들어오지 않아 하얗게 보여도 괜찮습니다. 코드가 부품 이름(DarkNavy, Leaves, Rock …)을 보고 기본 색을 입힙니다.
> 이름 뒤에 `.001` 같은 번호가 붙어 있어도 코드가 알아서 떼고 읽습니다.

## 2. 에셋 이름과 쓰이는 곳

| 이름 | 쓰이는 곳 |
|---|---|
| `Lobby_Hall` | 로비 전체. **이게 있어야** 아래 로비 소품도 에셋으로 바뀝니다 (Point_ 자리에 배치) |
| `Board_Frame` | 로비 순위 전광판 3개 (화면 `Screen_Main`에 순위가 뜸) |
| `Podium` | 시상대 (`Point_Name_1~3`에 1~3등 이름) |
| `Capsule_Machine` | 뽑기 기계 |
| `Club_Showcase` | 골프채 전시대 (`Point_Club` 위에서 골프채가 돎) |
| `Kiosk` | 스킬·상점 키오스크 2개 |
| `Tree_Round_A`, `Tree_Round_B`, `Tree_Pine`, `Tree_Palm` | 코스 나무 (무작위 크기·방향) |
| `Bush_A`, `Bush_B` | 나무 옆 덤불 |
| `Rock_A`, `Rock_B`, `Rock_C` | 바위 |
| `Flower_A`, `Flower_B` | 꽃 무리 |
| `Flag_Cup` | 홀컵 깃발 (충돌 꺼짐, 공이 깃대에 안 막힘) |
| `Tee_Marker` | 티 마커 2개 (왼쪽 빨강, 오른쪽 파랑) |
| `Neon_Arch_Gate` | 티 뒤 출발 아치 |
| `Golf_Cart` | 카트 길 옆 골프 카트 |
| `Light_Tower` | 조명탑 6개 (`Point_Spot`에서 스포트라이트) |
| `LED_Board` | 코스 LED 전광판 2개 (`Screen_LED`) |
| `Stand_Straight20` | 그린 옆 관중석 (2개를 나란히) |
| `Club_Head_Basic` | 일반~영웅 스킨 골프채 헤드 |
| `Club_Head_Leg1` · `Leg2` · `Leg3` | 무지개 · 태양 · 황금/VIP 왕관 헤드 |
| `Club_Head_Myth1` · `Myth2` | 오로라 · 혜성 헤드 |
| `Team_Cap` | 경기 중 팀 모자 (팀 색) |

아직 연결하지 않은 것: `Stand_Curve30`, `Club_Shaft_Parts`(지금 샤프트와 모양이 같음), `Team_Ball`, 이펙트 PNG 4장 (아래 3번 참고).

## 3. 다음 단계에서 연결할 것

- **이펙트 이미지**(Spark·Ring·Energy·Smoke): Studio 상단 **보기 → 에셋 관리자 → 일괄 가져오기**로 PNG 4장을 올린 뒤, 각 이미지를 우클릭 → **에셋 ID 복사**해서 `src/shared/Config.luau`의 `Config.FXTextures`에 숫자를 넣으면 바로 적용됩니다 (0 이면 로블록스 기본 이미지).
- **팀 공 딤플**(`Ball_Base_Normal`)은 공을 `Team_Ball` 메시로 바꿀 때 함께 연결합니다.
- `Stand_Curve30`을 쓸 경우, Studio에서 그 안의 `Collider_` 부품들의 **CollisionFidelity**를 `PreciseConvexDecomposition`으로 바꿔 주세요 (곡선이라 기본 충돌이 앞으로 1스터드쯤 튀어나옵니다). 실행 중에는 코드로 바꿀 수 없는 속성입니다.

## 4. 동작 방식 (참고)

- 모델을 놓을 때 기준점은 **바닥 가운데**, 정면은 **-Z**입니다. 가져온 모델의 기준점(Pivot)이 어디에 잡혀 있든, 납품 FBX에서 잰 보정값(`AssetLib.ORIGIN`)으로 정확한 자리에 놓습니다.
- 부품 이름 규칙: `Neon_`(빛남), `Collider_`(보이지 않는 충돌면), `Point_`(위치만 읽고 숨김), `Screen_`(글자 화면), `TeamColor_`(팀 색), `Seat_`(의자 색), `Glass_`(유리).
- 로비 홀은 바닥만 충돌하고, 벽·천장은 코드가 보이지 않는 벽을 세웁니다.
- 로비 시설은 모두 스폰(가운데)을 바라보게 돌려서 놓습니다.

## 5. 경기 화면(HUD) 디자인 이미지

`assets/ui/` 의 PNG를 Studio **에셋 관리자 → 일괄 가져오기**로 올리고, 이미지 ID를 `Config.UIImages` 에 넣으면 그 디자인으로 바뀝니다 (0 이면 지금 모양).

| 이름 | 쓰이는 곳 |
|---|---|
| `HoleStatusPill` | 위쪽 가운데: 왼쪽 모드·홀, 오른쪽 남은 시간 |
| `LiveMatchRankBoard` | 오른쪽 현황판: 1·2줄 레드·블루 공 거리, 3·4줄 레드·블루 선수 |
| `ClubAttackButton` | 샷 버튼 (공이 원 밖이면 살짝 어둡게) |
| `PlayerHPHUD` | 내 정보: 아바타 + 궁극기 게이지(초록) + 대시 준비(파랑) |
| `SwingPowerGauge` | 스윙 힘 게이지: 아직 안 찬 부분은 어둡게, 지금 힘 위치에 하얀 세로선 |

## 6. Meshy AI 소나무

FBX를 가져온 뒤 모델 이름을 `Tree_Pine2` 로 바꿔서 `Assets` 폴더에 넣으면 코스 나무로 섞여 나옵니다. 원본 크기가 1스터드 남짓이라 코드가 높이 20스터드로 자동으로 키웁니다 (`AssetLib.HEIGHT`).

## 7. Meshy AI 불꽃 소용돌이 (메테오 스윙 연출)

FBX를 가져온 뒤 모델 이름을 `FX_Meteor` 로 바꿔서 `Assets` 폴더에 넣으면, 궁극기(메테오 스윙)를 쓸 때 선수 주변에 불꽃 소용돌이가 빙글빙글 돌며 커졌다가 사라집니다. 크기는 궁극기 범위에 맞춰 자동으로 맞춥니다.

## 8. Meshy AI 황금 소용돌이 (홀인 · 퍼펙트 샷)

모델 이름을 `FX_Golden` 으로 바꿔 `Assets` 에 넣으면, 공이 홀컵에 들어갈 때 홀컵에서 크게, 퍼펙트 샷을 칠 때 공 자리에서 작게 황금 소용돌이가 돕니다.

## 9. Meshy AI 블랙 골드 드라이버 (통째 모델 골프채)

모델 이름을 `Club_Driver_BlackGold` 로 바꿔 `Assets` 에 넣으면 신화 등급 스킨 **블랙 골드 드라이버**의 모양이 됩니다 (뽑기에서 나옴). 손잡이~헤드 전체가 이 모델로 바뀌고, 길이는 캐릭터에 맞게 자동으로 맞춥니다. 헤드가 엉뚱한 방향을 보면 `Config.Skins.BlackGold.modelYaw` 를 90 / 180 / -90 으로 바꿔 주세요.
