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

- **팀 공 딤플**과 **이펙트 텍스처**(Spark·Ring·Energy·Smoke)는 이미지를 로블록스에 올려서 받은 **에셋 ID**가 필요합니다. ID가 생기면 알려 주세요.
- `Stand_Curve30`을 쓸 경우, Studio에서 그 안의 `Collider_` 부품들의 **CollisionFidelity**를 `PreciseConvexDecomposition`으로 바꿔 주세요 (곡선이라 기본 충돌이 앞으로 1스터드쯤 튀어나옵니다). 실행 중에는 코드로 바꿀 수 없는 속성입니다.

## 4. 동작 방식 (참고)

- 모델을 놓을 때 기준점은 **바닥 가운데**, 정면은 **-Z**입니다. 가져온 모델의 기준점(Pivot)이 어디에 잡혀 있든, 납품 FBX에서 잰 보정값(`AssetLib.ORIGIN`)으로 정확한 자리에 놓습니다.
- 부품 이름 규칙: `Neon_`(빛남), `Collider_`(보이지 않는 충돌면), `Point_`(위치만 읽고 숨김), `Screen_`(글자 화면), `TeamColor_`(팀 색), `Seat_`(의자 색), `Glass_`(유리).
- 로비 홀은 바닥만 충돌하고, 벽·천장은 코드가 보이지 않는 벽을 세웁니다.
- 로비 시설은 모두 스폰(가운데)을 바라보게 돌려서 놓습니다.
