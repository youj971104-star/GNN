-- 별똥별 타이쿤 (Starfall Tycoon) - 게임 밸런스와 수익화 설정
-- 숫자만 바꿔도 밸런스를 조절할 수 있도록 모든 값을 여기에 모았습니다.

local Config = {}

----------------------------------------------------------------------
-- 수익화: 크리에이터 대시보드에서 만든 ID 로 바꿔 넣으세요 (0 = 아직 없음)
----------------------------------------------------------------------
Config.GamePasses = {
	DoubleCoins = { id = 0, name = "코인 2배", desc = "별을 팔 때 코인을 항상 2배로 받습니다.", price = 199 },
	AutoSell = { id = 0, name = "자동 판매", desc = "가방이 차면 어디서든 자동으로 팝니다.", price = 149 },
	Lucky = { id = 0, name = "행운의 부적", desc = "희귀한 별이 떨어질 확률이 2배가 됩니다.", price = 249 },
	PetSlots = { id = 0, name = "펫 슬롯 +2", desc = "펫을 2마리 더 장착할 수 있습니다.", price = 99 },
	VIP = { id = 0, name = "VIP", desc = "코인 +25%, 이름 옆 VIP 태그, 가방 +50%.", price = 399 },
}

Config.Products = {
	CoinsSmall = { id = 0, name = "코인 꾸러미", desc = "지금 진행도에 맞춘 코인을 받습니다.", price = 49 },
	CoinsLarge = { id = 0, name = "코인 금고", desc = "꾸러미의 6배 코인을 받습니다.", price = 199 },
	LuckBoost = { id = 0, name = "행운 물약 (15분)", desc = "15분 동안 행운 x3.", price = 39 },
	MeteorShower = { id = 0, name = "유성우 소환", desc = "서버 전체 2분간 유성우! 모두의 땅에 별이 3배 빨리, 행운 x2.", price = 99 },
}

-- 로블록스 프리미엄 회원 보너스 (프리미엄 이용자가 오래 머물수록 Premium Payouts 수익이 늘어남)
Config.PremiumCoinBonus = 0.1

----------------------------------------------------------------------
-- 별 등급
----------------------------------------------------------------------
Config.Rarities = {
	{ id = "Common", name = "일반", value = 1, weight = 1000, color = Color3.fromRGB(255, 244, 170), size = 1.4 },
	{ id = "Rare", name = "희귀", value = 6, weight = 140, color = Color3.fromRGB(110, 200, 255), size = 1.7 },
	{ id = "Epic", name = "영웅", value = 30, weight = 22, color = Color3.fromRGB(200, 120, 255), size = 2.0 },
	{ id = "Legendary", name = "전설", value = 180, weight = 3, color = Color3.fromRGB(255, 170, 60), size = 2.5 },
	{ id = "Cosmic", name = "우주", value = 1500, weight = 0.35, color = Color3.fromRGB(255, 90, 160), size = 3.2 },
}

----------------------------------------------------------------------
-- 업그레이드 (코인으로 구매)
----------------------------------------------------------------------
Config.UpgradeOrder = { "Magnet", "Bag", "SpawnRate", "Luck" }

Config.Upgrades = {
	Magnet = { name = "자석 범위", unit = "스터드", maxLevel = 30, baseCost = 20, growth = 1.55 },
	Bag = { name = "가방 크기", unit = "개", maxLevel = 40, baseCost = 35, growth = 1.5 },
	SpawnRate = { name = "별 소환 속도", unit = "초", maxLevel = 30, baseCost = 60, growth = 1.6 },
	Luck = { name = "행운", unit = "배", maxLevel = 40, baseCost = 150, growth = 1.68 },
}

function Config.GetUpgradeValue(id: string, level: number): number
	if id == "Magnet" then
		return 7 + level * 1.5
	elseif id == "Bag" then
		return 20 + level * 15
	elseif id == "SpawnRate" then
		return math.max(0.25, 2.2 * (0.92 ^ level)) -- 별 하나가 떨어지는 간격(초)
	elseif id == "Luck" then
		return 1 + level * 0.12
	end
	return 0
end

function Config.GetUpgradeCost(id: string, level: number): number
	local u = Config.Upgrades[id]
	return math.floor(u.baseCost * (u.growth ^ level))
end

----------------------------------------------------------------------
-- 환생 (리셋 대신 영구 배율)
----------------------------------------------------------------------
function Config.GetRebirthCost(rebirths: number): number
	return math.floor(5000 * (4 ^ rebirths))
end

function Config.GetRebirthMultiplier(rebirths: number): number
	return 1 + rebirths * 0.5
end

----------------------------------------------------------------------
-- 펫 (별 요정) - 알은 게임 코인으로만 뽑습니다. 확률은 UI 에 항상 표시합니다.
----------------------------------------------------------------------
Config.Pets = {
	Twinkle = { name = "반짝이", rarity = "Common", bonus = 0.10, color = Color3.fromRGB(255, 244, 170) },
	Puff = { name = "구름콩", rarity = "Common", bonus = 0.12, color = Color3.fromRGB(235, 235, 255) },
	Comet = { name = "꼬리별", rarity = "Rare", bonus = 0.25, color = Color3.fromRGB(110, 200, 255) },
	Moonbun = { name = "달토끼", rarity = "Rare", bonus = 0.30, color = Color3.fromRGB(200, 220, 255) },
	Nebula = { name = "성운냥", rarity = "Epic", bonus = 0.60, color = Color3.fromRGB(200, 120, 255) },
	Solar = { name = "해님룡", rarity = "Legendary", bonus = 1.50, color = Color3.fromRGB(255, 170, 60) },
	Galaxy = { name = "은하수고래", rarity = "Cosmic", bonus = 4.00, color = Color3.fromRGB(255, 90, 160) },
}

Config.EggOrder = { "Basic", "Starlight", "Galaxy" }

-- chances 는 % (합계 100)
Config.Eggs = {
	Basic = {
		name = "기본 알",
		cost = 400,
		chances = { { pet = "Twinkle", chance = 45 }, { pet = "Puff", chance = 35 }, { pet = "Comet", chance = 15 }, { pet = "Moonbun", chance = 5 } },
	},
	Starlight = {
		name = "별빛 알",
		cost = 15000,
		chances = { { pet = "Comet", chance = 45 }, { pet = "Moonbun", chance = 35 }, { pet = "Nebula", chance = 18 }, { pet = "Solar", chance = 2 } },
	},
	Galaxy = {
		name = "은하 알",
		cost = 750000,
		chances = { { pet = "Nebula", chance = 60 }, { pet = "Solar", chance = 36 }, { pet = "Galaxy", chance = 4 } },
	},
}

Config.BaseEquipSlots = 3
Config.MaxPetInventory = 60

----------------------------------------------------------------------
-- 접속 보상 / 기타
----------------------------------------------------------------------
-- 7일 연속 출석. 보상 = base * (환생 + 1)
Config.DailyRewards = { 150, 300, 500, 800, 1200, 2000, 5000 }

Config.StarLifetime = 60 -- 땅에 떨어진 별이 사라지기까지(초)
Config.MaxStarsPerPlot = 40
Config.MeteorShowerDuration = 120
Config.LuckBoostDuration = 15 * 60

-- 코인 꾸러미 양은 플레이어 진행도(다음 환생 비용)에 비례 → 언제 사도 '쓸모 있는' 양
function Config.GetCoinPackAmount(rebirths: number, large: boolean): number
	local base = math.max(1000, math.floor(Config.GetRebirthCost(rebirths) * 0.2))
	return large and base * 6 or base
end

return Config
