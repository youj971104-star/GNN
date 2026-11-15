# 팝골프 3D 모델 (코드로 생성한 로우폴리)

| 파일 | 내용 | 삼각형 | 크기(스터드) |
|---|---|---|---|
| `Tree_Round.obj` | 둥근 나무 (잎 3색) | 468 | 높이 약 16 |
| `Tree_Pine.obj` | 소나무 | 88 | 높이 약 14 |
| `Bush.obj` | 덤불 + 꽃 | 420 | 지름 약 6 |
| `Stand_Section.obj` | 곡선 관중석 60° 한 구역 (5층, 레드·흰색·블루 의자, 네온, 지붕) | 3502 | 폭 약 45 |
| `Light_Tower.obj` | 네온 조명탑 (격자 기둥 + 램프 6개) | 752 | 높이 약 46 |

미리보기: `preview/` 폴더

## Studio 로 가져오기
1. Studio → **파일 → 3D 가져오기(Import 3D)** → `.obj` 선택 (같은 폴더의 `.mtl` 이 색을 담고 있음)
2. 가져오기 창에서 **크기 단위는 스터드** 그대로, **앵커(Anchored)** 켜기
3. 가져온 모델을 `ReplicatedStorage` 안 `Models` 폴더에 넣고 이름을 파일 이름과 같게 (예: `Tree_Round`)
4. 부품 이름(Trunk, Leaves, SeatRed, Neon, Lamp …)으로 나뉘어 있어서 색·재질을 쉽게 바꿀 수 있음
   - `Neon`, `NeonPink`, `Lamp` 부품은 재질을 **Neon** 으로 바꾸면 빛남

## 다시 만들기 / 수정
`python3 gen.py` 를 실행하면 `out/` 에 다시 생성됩니다. 색은 맨 위 `COLORS`, 모양은 각 함수(tree_round, stand_section …)의 숫자를 바꾸면 됩니다.
