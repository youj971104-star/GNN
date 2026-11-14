-- ⛳ 펑! 골프 파티 (Pop Golf Party) 설정
-- 모두가 동시에 공을 쳐서 홀컵에 넣는 배틀 골프. 아이템으로 서로 방해할 수 있어요.

local Config = {}

----------------------------------------------------------------------
-- 경기
----------------------------------------------------------------------
Config.MinPlayers = 1 -- 혼자서도 연습 가능 (2명 이상이면 더 재밌음)
Config.MaxPlayers = 8
Config.Intermission = 20 -- 경기 사이 대기(초)
Config.HolesPerMatch = 3
Config.HoleTime = 120 -- 홀 하나 제한 시간(초)
Config.MaxStrokes = 12 -- 이 타수를 넘기면 그 홀은 기권 처리
Config.Countdown = 3

-- 홀 순위 점수 (1등, 2등, ...). 못 넣으면 0점
Config.PlacePoints = { 10, 8, 6, 5, 4, 3, 2, 1 }

-- 공 물리
Config.Ball = {
	diameter = 2,
	maxShotSpeed = 120, -- 최대 파워일 때 속도(스터드/초)
	loft = 0.12, -- 샷을 살짝 띄우는 비율 (작은 턱을 넘기 위함)
	rollingDrag = 0.985, -- 0.1초마다 속도에 곱함 (작을수록 빨리 멈춤)
	stopSpeed = 1.2, -- 이 속도보다 느려지면 멈춘 것으로 보고 다음 샷 가능
	cupRadius = 2.4, -- 홀컵 판정 반경
	cupMaxSpeed = 40, -- 이보다 빠르면 홀컵을 지나쳐 버림
}

-- 코스 생성
Config.Course = {
	tile = 20, -- 바닥 타일 한 칸 크기
	minTiles = 7,
	maxTiles = 12,
	wallHeight = 2.5,
	itemBoxesPerHole = 3,
	itemBoxRespawn = 8,
}

----------------------------------------------------------------------
-- 배틀 아이템 (코스의 ❓ 상자에서 무료로 획득 — 돈으로 살 수 없음)
----------------------------------------------------------------------
Config.ItemOrder = { "Bomb", "Freeze", "Super", "Magnet", "Twister" }
Config.Items = {
	Bomb = { name = "💣 폭탄", desc = "내 공 주변(25)의 다른 공을 날려 버려요", weight = 25 },
	Freeze = { name = "🧊 얼음", desc = "홀컵에 가장 가까운 상대 공을 4초 얼려요", weight = 20 },
	Super = { name = "⚡ 슈퍼샷", desc = "다음 샷 파워 1.6배", weight = 20 },
	Magnet = { name = "🧲 자석", desc = "8초 동안 홀컵이 내 공을 끌어당겨요", weight = 20 },
	Twister = { name = "🌀 회오리", desc = "다른 모든 공을 아무 데로나 밀어내요", weight = 15 },
}

----------------------------------------------------------------------
-- 재화
--   🪙 코인: 게임으로만 얻음 (절대 판매하지 않음 → 일반 캡슐은 '유료 확률형'이 아님)
--   💎 젬: 게임으로 조금씩 얻거나 로벅스로 구매 → 프리미엄 캡슐 (유료 확률형, 확률 공개)
--   🧩 조각: 중복 스킨을 분해해서 얻음 → 원하는 스킨을 직접 구매
----------------------------------------------------------------------
Config.Rewards = {
	play = 15, -- 경기 참가 코인
	perPoint = 2, -- 점수 1점당 코인
	winGems = 5, -- 경기 1등 젬
	dailyGems = 20, -- 매일 첫 경기 젬
}

----------------------------------------------------------------------
-- 공 스킨 (꾸미기 전용 — 성능 차이 없음)
-- effect: "Sparkles" | "Fire" | "Smoke" | "Light" | nil
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

Config.SkinOrder = {
	"White", "Lime", "Sky", "Peach", "Lemon", "Mint",
	"Watermelon", "Ocean", "Choco", "Bubblegum", "Panda",
	"Lava", "Galaxy", "Neon", "Frost",
	"Sun", "Rainbow", "Gold",
	"Comet", "Aurora",
	"VIPCrown",
}
Config.Skins = {
	White = { name = "기본 흰 공", rarity = "Common", color = Color3.fromRGB(245, 245, 245), material = "SmoothPlastic" },
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
	Frost = { name = "서리", rarity = "Epic", color = Color3.fromRGB(200, 240, 255), material = "Ice", effect = "Smoke", trail = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(160, 220, 255) } },
	Sun = { name = "태양", rarity = "Legendary", color = Color3.fromRGB(255, 200, 40), material = "Neon", effect = "Fire", trail = { Color3.fromRGB(255, 255, 160), Color3.fromRGB(255, 120, 0) } },
	Rainbow = { name = "무지개", rarity = "Legendary", color = Color3.fromRGB(255, 255, 255), material = "Neon", effect = "Sparkles", trail = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 220, 80), Color3.fromRGB(80, 220, 120), Color3.fromRGB(80, 160, 255), Color3.fromRGB(190, 100, 255) } },
	Gold = { name = "황금", rarity = "Legendary", color = Color3.fromRGB(255, 200, 80), material = "Foil", effect = "Sparkles", trail = { Color3.fromRGB(255, 240, 160), Color3.fromRGB(220, 150, 30) } },
	Comet = { name = "혜성", rarity = "Mythic", color = Color3.fromRGB(150, 220, 255), material = "Neon", effect = "Light", trail = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 200, 255), Color3.fromRGB(80, 60, 255) } },
	Aurora = { name = "오로라", rarity = "Mythic", color = Color3.fromRGB(120, 255, 200), material = "Glass", effect = "Sparkles", trail = { Color3.fromRGB(90, 255, 190), Color3.fromRGB(110, 140, 255), Color3.fromRGB(230, 120, 255) } },
	-- 뽑기로 나오지 않는 VIP 전용 스킨 (게임패스는 확률형 아이템을 줄 수 없음)
	VIPCrown = { name = "👑 VIP 왕관", rarity = "Legendary", color = Color3.fromRGB(255, 215, 90), material = "Neon", effect = "Light", trail = { Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 180, 40) }, exclusive = "VIP" },
}

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
	VIP = { id = 0, name = "👑 VIP", desc = "VIP 전용 왕관 공 + 채팅 태그 + 매일 젬 +20", price = 299 },
	AimPlus = { id = 0, name = "🎯 정밀 조준", desc = "조준선이 2배 길게 보여요", price = 149 },
}

Config.Products = {
	Gems110 = { id = 0, name = "💎 젬 110", desc = "프리미엄 캡슐 2번", price = 49, gems = 110 },
	Gems500 = { id = 0, name = "💎 젬 500", desc = "10연차 + 50 보너스", price = 199, gems = 500 },
	Gems1300 = { id = 0, name = "💎 젬 1300", desc = "가장 이득!", price = 449, gems = 1300 },
	Starter = { id = 0, name = "🎁 스타터 팩 (1회)", desc = "젬 300 + 희귀 '바다' 공 확정", price = 99, gems = 300, skin = "Ocean", once = true },
}

-- 프리미엄 회원 혜택은 코인 대신 '매일 젬'으로 (코인을 어떤 식으로든 돈과 연결하지 않기 위해)
Config.PremiumDailyGems = 10

return Config
