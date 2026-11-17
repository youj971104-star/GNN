-- 캡슐 뽑기 (가챠)
-- * 꾸미기(공 스킨)만 나옴 — 승패에 영향 없음
-- * 확률은 Config 에 있고 게임 화면에 그대로 공개
-- * 천장: 10연차 영웅 이상 1개 보장, 프리미엄 50회 안에 전설 이상 확정
-- * 중복은 조각으로 → 조각 상점에서 원하는 스킨을 직접 구매

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Gacha = {}

-- 등급별로 뽑기에 나오는 스킨 목록 (VIP 전용 등 exclusive 는 제외)
local pool = {}
for _, id in ipairs(Config.SkinOrder) do
	local skin = Config.Skins[id]
	if not skin.exclusive then
		pool[skin.rarity] = pool[skin.rarity] or {}
		table.insert(pool[skin.rarity], id)
	end
end
Gacha.Pool = pool

-- 영웅 캡슐: 등급별 영웅 목록 (기본 영웅은 처음부터 가지고 있어서 제외)
local heroPool = {}
for _, id in ipairs(Config.HeroOrder) do
	local hero = Config.Heroes[id]
	if id ~= Config.DefaultHero and not hero.exclusive then
		heroPool[hero.rarity] = heroPool[hero.rarity] or {}
		table.insert(heroPool[hero.rarity], id)
	end
end
Gacha.HeroPool = heroPool

local function giveHero(data, rarity)
	local list = heroPool[rarity]
	local heroId = list[math.random(1, #list)]
	local isNew = not data.heroes[heroId]
	local shards = 0
	if isNew then
		data.heroes[heroId] = true
	else
		shards = Config.RarityById[rarity].shards * 2
		data.shards += shards
	end
	return { hero = heroId, rarity = rarity, new = isNew, shards = shards }
end

local function rarityIndex(id)
	return Config.RarityById[id].index
end

-- odds 에서 등급 하나 뽑기. minRarity 가 있으면 그 이상 등급 안에서만 (비율은 유지)
local function rollRarity(odds, minRarity)
	local minIndex = minRarity and rarityIndex(minRarity) or 0
	local sum = 0
	for id, pct in pairs(odds) do
		if rarityIndex(id) >= minIndex then
			sum += pct
		end
	end
	local r = math.random() * sum
	-- 순서가 일정하도록 등급 순서대로 돎
	for _, rar in ipairs(Config.Rarities) do
		local pct = odds[rar.id]
		if pct and rar.index >= minIndex then
			r -= pct
			if r <= 0 then
				return rar.id
			end
		end
	end
	-- 부동소수 오차 대비: 가능한 가장 높은 등급
	for i = #Config.Rarities, 1, -1 do
		local id = Config.Rarities[i].id
		if odds[id] and i >= minIndex then
			return id
		end
	end
	return "Common"
end

local function giveSkin(data, rarity)
	local list = pool[rarity]
	local skinId = list[math.random(1, #list)]
	local isNew = not data.skins[skinId]
	local shards = 0
	if isNew then
		data.skins[skinId] = true
	else
		shards = Config.RarityById[rarity].shards
		data.shards += shards
	end
	return { skin = skinId, rarity = rarity, new = isNew, shards = shards }
end

-- capsuleId: "Basic" | "Premium", count: 1 또는 10(프리미엄만)
-- 반환: ok, 결과목록 또는 오류 메시지
function Gacha.Pull(data, capsuleId, count, restricted)
	local capsule = Config.Capsules[capsuleId]
	if not capsule or (count ~= 1 and count ~= 10) then
		return false, "잘못된 요청"
	end
	if count == 10 and not capsule.tenCost then
		return false, "10연차는 프리미엄 캡슐만 돼요"
	end
	if capsule.paid and restricted then
		return false, "이 지역에서는 프리미엄 캡슐을 이용할 수 없어요"
	end
	local cost = count == 10 and capsule.tenCost or capsule.cost
	local wallet = capsule.currency -- "coins" | "gems"
	if data[wallet] < cost then
		return false, (wallet == "coins" and "코인" or "젬") .. "이 부족해요"
	end
	data[wallet] -= cost

	local results = {}
	local bestIndex = 0
	for i = 1, count do
		local rarity
		if capsule.kind == "hero" then
			-- 영웅 캡슐도 같은 천장 규칙 (따로 셈)
			data.pity.heroSince = (data.pity.heroSince or 0) + 1
			if data.pity.heroSince >= Config.Pity.legendaryAt then
				rarity = rollRarity(capsule.odds, "Legendary")
			elseif count == 10 and i == 10 and bestIndex < rarityIndex(Config.Pity.tenPullMinRarity) then
				rarity = rollRarity(capsule.odds, Config.Pity.tenPullMinRarity)
			else
				rarity = rollRarity(capsule.odds)
			end
			if rarityIndex(rarity) >= rarityIndex("Legendary") then
				data.pity.heroSince = 0
			end
		elseif capsuleId == "Premium" then
			data.pity.sinceLegendary += 1
			if data.pity.sinceLegendary >= Config.Pity.legendaryAt then
				rarity = rollRarity(capsule.odds, "Legendary")
			elseif count == 10 and i == 10 and bestIndex < rarityIndex(Config.Pity.tenPullMinRarity) then
				rarity = rollRarity(capsule.odds, Config.Pity.tenPullMinRarity)
			else
				rarity = rollRarity(capsule.odds)
			end
			if rarityIndex(rarity) >= rarityIndex("Legendary") then
				data.pity.sinceLegendary = 0
			end
		else
			rarity = rollRarity(capsule.odds)
		end
		bestIndex = math.max(bestIndex, rarityIndex(rarity))
		table.insert(results, capsule.kind == "hero" and giveHero(data, rarity) or giveSkin(data, rarity))
	end
	data.stats.pulls += count
	return true, results
end

-- 조각으로 원하는 스킨 사기
function Gacha.BuyWithShards(data, skinId)
	local skin = Config.Skins[skinId]
	if not skin or skin.exclusive then
		return false, "살 수 없는 스킨이에요"
	end
	if data.skins[skinId] then
		return false, "이미 가지고 있어요"
	end
	local price = Config.ShardPrice[skin.rarity]
	if data.shards < price then
		return false, "조각이 부족해요"
	end
	data.shards -= price
	data.skins[skinId] = true
	return true, skin.name .. " 획득!"
end

-- 화면에 보여 줄 스킨별 확률 (등급 확률 ÷ 그 등급 스킨 수)
function Gacha.OddsTable(capsuleId)
	local capsule = Config.Capsules[capsuleId]
	local rows = {}
	for _, rar in ipairs(Config.Rarities) do
		local pct = capsule.odds[rar.id]
		if pct then
			local list = (capsule.kind == "hero" and heroPool[rar.id]) or pool[rar.id] or {}
			table.insert(rows, { rarity = rar.id, percent = pct, each = #list > 0 and pct / #list or 0, skins = list, heroes = capsule.kind == "hero" })
		end
	end
	return rows
end

return Gacha
