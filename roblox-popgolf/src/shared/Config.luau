-- ⛳ 팝골프 (Pop Golf) 설정
-- 2대2 팀 배틀 골프: 캐릭터가 코스를 뛰어다니며 골프채로 팀 공을 치고,
-- 상대 선수를 때려 넘어뜨리거나 상대 공을 쳐 내며 먼저 홀컵에 넣는 팀이 이깁니다.

local Config = {}

----------------------------------------------------------------------
-- 경기
----------------------------------------------------------------------
Config.MaxTeamSize = 4 -- 한 팀 최대 인원 (인원에 따라 2대2·3대3·4대4 자동)
Config.MinPlayers = 1 -- 혼자서도 연습 가능 (1명이면 레드 팀만)
Config.MaxPlayers = Config.MaxTeamSize * 2 -- 한 경기 최대 8명 (넘치면 관전 후 다음 판)
Config.Intermission = 15
Config.HolesPerMatch = 3
Config.HoleTime = 180 -- 홀 제한 시간. 끝나면 홀컵에 더 가까운 팀이 승리
Config.Countdown = 3

Config.Teams = {
	{ id = "Red", name = "🔴 레드 팀", color = Color3.fromRGB(255, 80, 80), brick = BrickColor.new("Bright red") },
	{ id = "Blue", name = "🔵 블루 팀", color = Color3.fromRGB(80, 150, 255), brick = BrickColor.new("Bright blue") },
}

-- 공 물리 (공은 포물선으로 날아가고, 그린 위에선 굴러가는 퍼팅)
Config.Ball = {
	diameter = 2.2,
	maxSpeed = 165, -- 최대 파워 샷의 속도(스터드/초). 클수록 멀리
	launchAngle = 36, -- 일반 샷 발사 각도(도). 클수록 높이 뜸
	puttAngle = 4, -- 그린 위에서는 거의 굴림
	puttPower = 0.38, -- 그린 위 샷 세기 배율 (섬세한 퍼팅)
	cupRadius = 2.6, -- 홀컵 판정 반경
	bonkSpeed = 28, -- 공이 이보다 빠르게 날아갈 때 상대 선수에 맞으면 넘어짐
	bonkRadius = 3.2, -- 공과 선수 몸 중심 사이 이 거리 안이면 맞은 것
	cupMaxSpeed = 32, -- 이보다 빠르면 홀컵을 지나쳐 버림
	stopSpeed = 1.2,
	-- 바닥 종류별 굴러가는 저항 (0.1초마다 속도에 곱함, 작을수록 빨리 멈춤)
	drag = { Fairway = 0.975, Rough = 0.93, Green = 0.985, Sand = 0.8, Tee = 0.975 },
}

-- 휘두르기 (공치기 + 사람 치기가 하나의 동작)
-- 꾹 누르면 골프채가 뒤로 올라가며 힘이 모이고, 떼면 휘두름 → 앞에 있는 공(우리 팀/상대 팀 모두)과 상대 선수가 맞음
-- 공이 안 맞을 때 원인 찾기용: true 면 스윙마다 Output 창에 판정 내용을 찍음 (출시 전 false 로)
Config.DebugShots = false
-- 코드 버전 표시 (화면 왼쪽 아래). 업데이트마다 바꿔서 폰·Studio에 최신 코드가 들어갔는지 확인
Config.Build = "1118c"

-- 모델러 이펙트 이미지 (PNG를 로블록스에 올리고 받은 숫자 ID를 넣으면 바로 적용됨)
-- 0 이면 로블록스 기본 이펙트 이미지를 씀
Config.FXTextures = {
	Spark = 113070797605368, -- 반짝임: 공 칠 때 불꽃, 골프채 반짝임, 파워 드라이브
	Ring = 107076033714132, -- 충격파 고리: 공·사람 맞을 때 바닥에 퍼지는 원
	Energy = 135419813624697, -- 에너지: 궁극기 오라, 큰 충격 불꽃
	Smoke = 80468035227651, -- 연기: 서리 골프채 등 연기 효과
}
function Config.FXTexture(key, fallback)
	local id = Config.FXTextures[key]
	if type(id) == "number" and id > 0 then
		return "rbxassetid://" .. id
	end
	return fallback
end

-- 카메라 시점 (조금 위에서, 멀리서 내려다봄). 플레이어가 확대/축소·회전은 그대로 할 수 있음
Config.Camera = {
	distance = 26, -- 시작 거리 (로블록스 기본은 약 12.5)
	pitch = 28, -- 내려다보는 각도 (도). 클수록 위에서 봄
	minZoom = 14, -- 이보다 가까이 확대 못 함 (1인칭·너무 가까운 시점 방지)
	maxZoom = 70,
	fov = 72, -- 시야각 (기본 70)
}

Config.Club = {
	chargeCycle = 1.4, -- 힘 게이지가 0→100%→0 한 번 왕복하는 시간(초)
	-- 선수는 공을 발 앞에 두고 옆으로 서서 침 (목표 방향 = 선수의 왼쪽, 카메라가 보는 방향)
	stanceOffset = 2.6, -- 스윙 존 중심: 선수 몸에서 앞으로 이만큼
	ballZone = 3.4, -- 스윙 존 반지름: 공이 이 안에 있으면 맞음
	reach = 6.5, -- 골프채가 도는 반경: 이 안의 상대 선수가 맞음
	cooldown = 0.55, -- 휘두르기 사이 최소 간격
	impactDelay = 0.12, -- 떼고 나서 골프채가 공을 지나는 순간까지 (스윙 모션과 맞춤)
	stunTime = 1.2, -- 맞은 선수가 넘어져 있는 시간 (대시 회피가 생겨서 짧게)
	knockback = 50, -- 맞은 선수가 날아가는 기본 세기 (힘 게이지에 비례해 커짐)
	minPower = 0.12, -- 살짝 톡 쳐도 이만큼은 나감
	walkSpeed = 24, -- 넓은 코스라 기본보다 빠르게
}

-- 코스 생성 (실제 골프장처럼: 티 → 페어웨이 → 그린, 주변에 러프·벙커·연못·나무)
Config.Course = {
	length = { 260, 380 }, -- 티에서 그린까지 거리 범위
	fairwayWidth = 46, -- 2대2 기준 페어웨이 폭
	widthPerExtraPlayer = 6, -- 한 팀 인원이 1명 늘 때마다 넓어지는 폭 (3대3 +6, 4대4 +12)
	greenRadius = 26,
	bunkers = { 2, 4 },
	ponds = { 0, 2 },
	trees = 40,
	itemBoxes = 4, -- 2대2 기준 아이템 상자 수 (스킬·대시가 기본이라 줄임)
	boxesPerExtraPlayer = 2, -- 한 팀 인원이 1명 늘 때마다 추가되는 상자
	itemBoxRespawn = 8,
}

----------------------------------------------------------------------
-- 배틀 아이템 (코스의 ❓ 상자에서 무료 획득 — 돈으로 살 수 없음)
----------------------------------------------------------------------
Config.ItemOrder = { "Bomb", "Freeze", "Gust" }
Config.Items = {
	Bomb = { name = "💣 물풍선 폭탄", desc = "앞으로 던져서 터진 곳 주변 선수와 공을 날려요", weight = 40 },
	Freeze = { name = "🧊 얼음", desc = "상대 팀 공을 5초 동안 얼려서 아무도 못 치게 해요", weight = 30 },
	Gust = { name = "🌬️ 돌풍", desc = "상대 선수 모두를 공중으로 날려요", weight = 30 },
}

----------------------------------------------------------------------
-- 대시 (Q / 모바일 대시 버튼) — 모두 같은 성능 (돈으로 못 바꿈)
----------------------------------------------------------------------
Config.Dash = {
	speed = 75, -- 순간 속도
	duration = 0.18, -- 미는 시간
	cooldown = 2.2,
	airBonus = 1.25, -- 공중에서 쓰면 더 멀리
	dodge = 0.3, -- 대시 직후 이 시간 동안 휘두르기에 맞지 않음 (회피)
}

----------------------------------------------------------------------
-- 스킬 (E) — 로비에서 하나 골라 장착, 전부 무료
----------------------------------------------------------------------
Config.SkillOrder = { "Tackle", "Recall", "Bubble", "FrostZone", "PowerDrive" }
Config.Skills = {
	Tackle = { name = "💥 돌진 태클", desc = "앞으로 돌진! 부딪힌 상대를 넘어뜨려요", cooldown = 10, color = Color3.fromRGB(255, 120, 60) },
	Recall = { name = "🧲 볼 리콜", desc = "45 안에 있는 우리 팀 공을 내 쪽으로 끌어와요", cooldown = 14, color = Color3.fromRGB(120, 200, 255) },
	Bubble = { name = "🫧 버블 쉴드", desc = "3초 동안 무적. 나를 친 상대가 오히려 튕겨 나가요", cooldown = 15, color = Color3.fromRGB(150, 230, 255) },
	FrostZone = { name = "❄️ 서리 지대", desc = "앞쪽 바닥을 얼려요. 상대는 느려지고 공은 멈춰요 (4초)", cooldown = 14, color = Color3.fromRGB(170, 230, 255) },
	PowerDrive = { name = "⚡ 파워 드라이브", desc = "5초 안의 다음 스윙이 1.45배 세져요", cooldown = 12, color = Color3.fromRGB(255, 230, 80) },
}
Config.DefaultSkill = "Tackle"

----------------------------------------------------------------------
-- 궁극기 (R) — 게이지를 모아서 사용
----------------------------------------------------------------------
Config.Ultimate = {
	name = "☄️ 메테오 스윙",
	desc = "다음 스윙이 주변 12 안의 모든 공과 상대를 날려 버려요",
	gaugeMax = 100,
	perBallHit = 12, -- 공을 칠 때
	perKnock = 20, -- 상대를 넘어뜨릴 때
	perSecond = 1, -- 경기 중 1초마다
	window = 6, -- 켜고 나서 이 시간 안에 휘둘러야 함
	radius = 12,
	launchMult = 1.6, -- 공 속도 배수
	stunTime = 2.4,
}

----------------------------------------------------------------------
-- 일일 미션 (매일 자정(UTC) 초기화). 보상은 코인·젬
----------------------------------------------------------------------
Config.QuestOrder = { "Play", "Hit", "Win" }
Config.Quests = {
	Play = { name = "경기 진행", goal = 3, coins = 150 },
	Hit = { name = "공 치기", goal = 15, coins = 100, gems = 5 },
	Win = { name = "경기 승리", goal = 1, coins = 200, gems = 10 },
}

----------------------------------------------------------------------
-- 아이콘 이미지 (선택). images/icons 의 그림을 로블록스에 올리고 받은 ID 를 넣으면
-- 버튼에 이모지 대신 그림이 나옵니다. 0 이면 이모지로 표시
----------------------------------------------------------------------
Config.Icons = {
	Dash = 0,
	Ultimate = 0,
	Item = 0,
	Tackle = 0,
	Recall = 0,
	Bubble = 0,
	FrostZone = 0,
	PowerDrive = 0,
	NavGacha = 0,
	NavClubs = 0,
	NavSkills = 0,
	NavShop = 0,
	NavStats = 0,
}

----------------------------------------------------------------------
-- 재화
--   💰 코인: 게임으로만 얻음 (절대 판매하지 않음 → 일반 캡슐은 '유료 확률형'이 아님)
--   💎 젬: 게임으로 조금씩 얻거나 로벅스로 구매 → 프리미엄 캡슐 (유료 확률형, 확률 공개)
--   🧩 조각: 중복 스킨을 분해해서 얻음 → 원하는 스킨을 직접 구매
----------------------------------------------------------------------
Config.Rewards = {
	play = 15, -- 경기 참가 코인
	holeWin = 10, -- 이긴 홀마다 코인 (팀원 모두)
	matchWin = 30, -- 경기 승리 코인
	winGems = 5, -- 경기 승리 젬
	dailyGems = 20, -- 매일 첫 경기 젬
	knockout = 1, -- 상대를 넘어뜨릴 때마다 코인
}

----------------------------------------------------------------------
Config.Rarities = {
	{ id = "Common", name = "일반", color = Color3.fromRGB(200, 200, 200), shards = 1 },
	{ id = "Rare", name = "희귀", color = Color3.fromRGB(90, 170, 255), shards = 3 },
	{ id = "Epic", name = "영웅", color = Color3.fromRGB(190, 110, 255), shards = 10 },
	{ id = "Legendary", name = "전설", color = Color3.fromRGB(255, 170, 40), shards = 40 },
	{ id = "Mythic", name = "신화", color = Color3.fromRGB(255, 80, 150), shards = 100 },
}
Config.RarityById = {}
for i, r in ipairs(Config.Rarities) do
	r.index = i
	Config.RarityById[r.id] = r
end

-- 골프채 스킨 (꾸미기 전용 — 성능 차이 없음). 팀 공은 팀 색깔로 고정해서 누구 공인지 헷갈리지 않게
-- effect: "Sparkles" | "Fire" | "Smoke" | "Light" | nil, trail: 휘두를 때 남는 꼬리 색
-- head: 모델러 헤드 모양 (Assets 의 Club_Head_*). 없으면 기본형 Club_Head_Basic
Config.SkinOrder = {
	"White", "Lime", "Sky", "Peach", "Lemon", "Mint",
	"Watermelon", "Ocean", "Choco", "Bubblegum", "Panda",
	"Lava", "Galaxy", "Neon", "Frost",
	"Sun", "Rainbow", "Gold",
	"Comet", "Aurora",
	"VIPCrown",
}
Config.Skins = {
	White = { name = "기본 은색", rarity = "Common", color = Color3.fromRGB(245, 245, 245), material = "SmoothPlastic" },
	Lime = { name = "라임", rarity = "Common", color = Color3.fromRGB(160, 230, 80), material = "SmoothPlastic" },
	Sky = { name = "하늘", rarity = "Common", color = Color3.fromRGB(120, 200, 255), material = "SmoothPlastic" },
	Peach = { name = "복숭아", rarity = "Common", color = Color3.fromRGB(255, 180, 150), material = "SmoothPlastic" },
	Lemon = { name = "레몬", rarity = "Common", color = Color3.fromRGB(255, 235, 90), material = "SmoothPlastic" },
	Mint = { name = "민트", rarity = "Common", color = Color3.fromRGB(150, 240, 200), material = "SmoothPlastic" },
	Watermelon = { name = "수박", rarity = "Rare", color = Color3.fromRGB(60, 170, 70), material = "Fabric", trail = { Color3.fromRGB(80, 200, 90), Color3.fromRGB(255, 90, 100) } },
	Ocean = { name = "바다", rarity = "Rare", color = Color3.fromRGB(40, 120, 220), material = "Glass", trail = { Color3.fromRGB(120, 220, 255), Color3.fromRGB(30, 80, 200) } },
	Choco = { name = "초코", rarity = "Rare", color = Color3.fromRGB(110, 65, 40), material = "SmoothPlastic", trail = { Color3.fromRGB(140, 90, 60), Color3.fromRGB(255, 240, 220) } },
	Bubblegum = { name = "풍선껌", rarity = "Rare", color = Color3.fromRGB(255, 140, 200), material = "SmoothPlastic", trail = { Color3.fromRGB(255, 180, 220), Color3.fromRGB(255, 255, 255) } },
	Panda = { name = "판다", rarity = "Rare", color = Color3.fromRGB(30, 30, 30), material = "Fabric", trail = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(30, 30, 30) } },
	Lava = { name = "용암", rarity = "Epic", color = Color3.fromRGB(255, 90, 30), material = "Neon", effect = "Fire", trail = { Color3.fromRGB(255, 220, 80), Color3.fromRGB(255, 50, 20) } },
	Galaxy = { name = "은하", rarity = "Epic", color = Color3.fromRGB(70, 40, 140), material = "Glass", effect = "Sparkles", trail = { Color3.fromRGB(120, 80, 255), Color3.fromRGB(255, 120, 220) } },
	Neon = { name = "네온", rarity = "Epic", color = Color3.fromRGB(60, 255, 200), material = "Neon", effect = "Light", trail = { Color3.fromRGB(60, 255, 200), Color3.fromRGB(60, 120, 255) } },
	Frost = { fx = { texture = "smoke" }, name = "서리", rarity = "Epic", color = Color3.fromRGB(200, 240, 255), material = "Ice", effect = "Smoke", trail = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(160, 220, 255) } },
	Sun = { head = "Club_Head_Leg2", name = "태양", rarity = "Legendary", color = Color3.fromRGB(255, 200, 40), material = "Neon", effect = "Fire", trail = { Color3.fromRGB(255, 255, 160), Color3.fromRGB(255, 120, 0) } },
	Rainbow = { head = "Club_Head_Leg1", fx = { rainbow = true }, name = "무지개", rarity = "Legendary", color = Color3.fromRGB(255, 255, 255), material = "Neon", effect = "Sparkles", trail = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 220, 80), Color3.fromRGB(80, 220, 120), Color3.fromRGB(80, 160, 255), Color3.fromRGB(190, 100, 255) } },
	Gold = { head = "Club_Head_Leg3", name = "황금", rarity = "Legendary", color = Color3.fromRGB(255, 200, 80), material = "Foil", effect = "Sparkles", trail = { Color3.fromRGB(255, 240, 160), Color3.fromRGB(220, 150, 30) } },
	Comet = { head = "Club_Head_Myth2", name = "혜성", rarity = "Mythic", color = Color3.fromRGB(150, 220, 255), material = "Neon", effect = "Light", trail = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 200, 255), Color3.fromRGB(80, 60, 255) } },
	Aurora = { head = "Club_Head_Myth1", name = "오로라", rarity = "Mythic", color = Color3.fromRGB(120, 255, 200), material = "Glass", effect = "Sparkles", trail = { Color3.fromRGB(90, 255, 190), Color3.fromRGB(110, 140, 255), Color3.fromRGB(230, 120, 255) } },
	-- 뽑기로 나오지 않는 VIP 전용 스킨 (게임패스는 확률형 아이템을 줄 수 없음)
	VIPCrown = { head = "Club_Head_Leg3", name = "👑 VIP 왕관", rarity = "Legendary", color = Color3.fromRGB(255, 215, 90), material = "Neon", effect = "Light", trail = { Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 180, 40) }, exclusive = "VIP" },
}

----------------------------------------------------------------------
-- 골프채 연출 (각자 화면에서 그림). 등급이 높을수록 화려해짐
--   aura  : 머리에서 계속 나오는 빛 입자
--   orbit : 머리 주위를 도는 빛구슬
--   ring  : 머리를 감싸고 도는 빛 고리
--   pulse : 빛이 숨 쉬듯 밝아졌다 어두워짐
--   rainbow : 색이 무지개처럼 계속 바뀜
--   burst : 휘두를 때 터지는 입자 (shock = 충격파 고리, punch = 내 화면 살짝 흔들림)
-- 스킨에 fx = {...} 를 직접 적으면 그 값이 우선합니다.
----------------------------------------------------------------------
local RARITY_FX = {
	Common = { burst = { count = 10 } },
	Rare = { aura = { rate = 6, size = 0.35 }, burst = { count = 18 } },
	Epic = { aura = { rate = 14, size = 0.45 }, orbit = { count = 2, radius = 1.3, speed = 3 }, pulse = true, burst = { count = 28, shock = true } },
	Legendary = { aura = { rate = 22, size = 0.55 }, orbit = { count = 3, radius = 1.5, speed = 3.5 }, ring = true, pulse = true, burst = { count = 45, shock = true, punch = true } },
	Mythic = { aura = { rate = 32, size = 0.6 }, orbit = { count = 4, radius = 1.7, speed = 4.5 }, ring = true, pulse = true, rainbow = true, burst = { count = 70, shock = true, punch = true } },
}
local EFFECT_TEXTURE = { Fire = "fire", Smoke = "smoke" }

-- 스킨 하나의 최종 연출 값
function Config.GetFx(skinId)
	local skin = Config.Skins[skinId] or Config.Skins.White
	local base = RARITY_FX[skin.rarity] or RARITY_FX.Common
	local colors = skin.trail or { skin.color, Color3.new(1, 1, 1) }
	local fx = {
		colors = colors,
		texture = EFFECT_TEXTURE[skin.effect or ""] or "sparkle",
		aura = base.aura and table.clone(base.aura),
		orbit = base.orbit and table.clone(base.orbit),
		ring = base.ring,
		pulse = base.pulse,
		rainbow = base.rainbow,
		burst = table.clone(base.burst),
	}
	for k, v in pairs(skin.fx or {}) do
		fx[k] = v
	end
	return fx
end


----------------------------------------------------------------------
-- 캡슐 뽑기 (가챠) — 확률은 게임 안에 항상 표시
----------------------------------------------------------------------
Config.Capsules = {
	Basic = {
		name = "🟢 일반 캡슐",
		currency = "coins",
		cost = 300,
		odds = { Common = 70, Rare = 25, Epic = 5 }, -- % (합계 100)
	},
	Premium = {
		name = "💎 프리미엄 캡슐",
		currency = "gems",
		cost = 50,
		tenCost = 450, -- 10연차 (1회 무료 효과)
		odds = { Rare = 60, Epic = 30, Legendary = 9, Mythic = 1 },
		paid = true, -- 젬을 로벅스로 살 수 있으므로 '유료 확률형 아이템'
	},
}
-- 천장 (프리미엄 캡슐 전용)
Config.Pity = {
	tenPullMinRarity = "Epic", -- 10연차에는 영웅 이상 최소 1개 보장
	legendaryAt = 50, -- 전설 이상이 50번 동안 안 나오면 50번째는 전설 이상 확정
}
-- 조각 상점: 원하는 스킨을 조각으로 직접 구매 (확률 없이)
Config.ShardPrice = { Common = 10, Rare = 30, Epic = 100, Legendary = 400, Mythic = 1000 }

----------------------------------------------------------------------
-- 수익화 (크리에이터 대시보드에서 만든 ID, 0 = 미설정)
-- ⚠️ 코인을 파는 상품이나 '코인 2배' 패스는 넣지 않습니다.
--    코인을 돈으로 살 수 있게 되면 일반 캡슐도 유료 확률형 아이템이 되기 때문입니다.
----------------------------------------------------------------------
Config.GamePasses = {
	VIP = { id = 2089138053, name = "👑 VIP", desc = "VIP 전용 왕관 골프채 + 채팅 태그 + 매일 젬 +20", price = 299 },
	AimPlus = { id = 2088406112, name = "🎯 정밀 조준", desc = "샷 조준선이 2배 길게 보여요", price = 149 },
}

Config.Products = {
	Gems110 = { id = 3731739437, name = "💎 젬 110", desc = "프리미엄 캡슐 2번", price = 49, gems = 110 },
	Gems500 = { id = 3731739550, name = "💎 젬 500", desc = "10연차 + 50 보너스", price = 199, gems = 500 },
	Gems1300 = { id = 3731739684, name = "💎 젬 1300", desc = "가장 이득!", price = 449, gems = 1300 },
	Starter = { id = 3731739280, name = "🎁 스타터 팩 (1회)", desc = "젬 300 + 희귀 '바다' 골프채 확정", price = 99, gems = 300, skin = "Ocean", once = true },
}

-- 프리미엄 회원 혜택은 코인 대신 '매일 젬'으로 (코인을 어떤 식으로든 돈과 연결하지 않기 위해)
Config.PremiumDailyGems = 10

return Config
