-- 별똥별 타이쿤 서버 진입점
-- 게임 흐름: 별 줍기 → 판매 발판에서 코인 → 업그레이드/펫 → 환생(영구 배율) → 반복

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PolicyService = game:GetService("PolicyService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local MapBuilder = require(script.Parent.MapBuilder)
local StarService = require(script.Parent.StarService)
local Monetization = require(script.Parent.Monetization)

----------------------------------------------------------------------
-- 리모트
----------------------------------------------------------------------
local remoteFolder = Instance.new("Folder")
remoteFolder.Name = "Remotes"
local remotes = {}
for _, name in ipairs({ "State", "Notify", "Collect", "Bag", "Announce", "Hatched" }) do
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remoteFolder
	remotes[name] = r
end
local actionRemote = Instance.new("RemoteFunction")
actionRemote.Name = "Action"
actionRemote.Parent = remoteFolder
remoteFolder.Parent = ReplicatedStorage

----------------------------------------------------------------------
-- 상태
----------------------------------------------------------------------
local plots = MapBuilder.Build()
local plotOwner = {} -- [plot] = Player
local playerPlot = {} -- [Player] = plot
local policies = {} -- [Player] = { paidRandomRestricted = bool }
local meteorUntil = 0

local function notify(player, text, color)
	remotes.Notify:FireClient(player, text, color)
end

local function getStats(player, data)
	local owns = function(key)
		return Monetization.Owns(player, key)
	end
	local now = os.time()
	local meteor = now < meteorUntil

	local luck = Config.GetUpgradeValue("Luck", data.upgrades.Luck)
	if owns("Lucky") then
		luck *= 2
	end
	if data.boosts.luckUntil > now then
		luck *= 3
	end
	if meteor then
		luck *= 2
	end

	local interval = Config.GetUpgradeValue("SpawnRate", data.upgrades.SpawnRate)
	if meteor then
		interval /= 3
	end

	local bagCap = Config.GetUpgradeValue("Bag", data.upgrades.Bag)
	if owns("VIP") then
		bagCap = math.floor(bagCap * 1.5)
	end

	local petMult = 1
	local petById = {}
	for _, pet in ipairs(data.pets) do
		petById[pet.uid] = pet
	end
	for _, uid in ipairs(data.equipped) do
		local pet = petById[uid]
		local def = pet and Config.Pets[pet.id]
		if def then
			petMult += def.bonus
		end
	end

	local coinMult = Config.GetRebirthMultiplier(data.rebirths) * petMult
	if owns("DoubleCoins") then
		coinMult *= 2
	end
	if owns("VIP") then
		coinMult *= 1.25
	end
	if player.MembershipType == Enum.MembershipType.Premium then
		coinMult *= 1 + Config.PremiumCoinBonus
	end

	return {
		luck = luck,
		interval = interval,
		magnet = Config.GetUpgradeValue("Magnet", data.upgrades.Magnet),
		bagCap = bagCap,
		petMult = petMult,
		coinMult = coinMult,
		slots = Config.BaseEquipSlots + (owns("PetSlots") and 2 or 0),
		autoSell = owns("AutoSell"),
	}
end

local function updateLeaderstats(player, data)
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls["⭐ 코인"].Value = Format.Short(data.coins)
		ls["🔄 환생"].Value = data.rebirths
	end
end

local function today()
	return os.time() // 86400
end

local function buildSnapshot(player, data)
	local stats = getStats(player, data)
	local upgrades = {}
	for _, id in ipairs(Config.UpgradeOrder) do
		local level = data.upgrades[id]
		local def = Config.Upgrades[id]
		upgrades[id] = {
			level = level,
			max = def.maxLevel,
			value = Config.GetUpgradeValue(id, level),
			nextValue = Config.GetUpgradeValue(id, math.min(level + 1, def.maxLevel)),
			cost = Config.GetUpgradeCost(id, level),
		}
	end
	local dailyAvailable = data.daily.lastDay < today()
	local nextStreak = (data.daily.lastDay == today() - 1) and data.daily.streak + 1 or 1
	if not dailyAvailable then
		nextStreak = data.daily.streak + 1
	end
	local dayIndex = ((nextStreak - 1) % #Config.DailyRewards) + 1
	local now = os.time()

	return {
		coins = data.coins,
		rebirths = data.rebirths,
		bagCount = data.bag.count,
		bagValue = data.bag.value,
		stats = stats,
		upgrades = upgrades,
		rebirthCost = Config.GetRebirthCost(data.rebirths),
		rebirthNextMult = Config.GetRebirthMultiplier(data.rebirths + 1),
		rebirthMult = Config.GetRebirthMultiplier(data.rebirths),
		pets = data.pets,
		equipped = data.equipped,
		passes = Monetization.GetOwned(player),
		daily = {
			available = dailyAvailable,
			day = dayIndex,
			reward = Config.DailyRewards[dayIndex] * (data.rebirths + 1),
		},
		luckBoostLeft = math.max(0, data.boosts.luckUntil - now),
		meteorLeft = math.max(0, meteorUntil - now),
		packSmall = Config.GetCoinPackAmount(data.rebirths, false),
		packLarge = Config.GetCoinPackAmount(data.rebirths, true),
		paidRandomRestricted = policies[player] and policies[player].paidRandomRestricted or false,
		starsCollected = data.starsCollected,
	}
end

local function refresh(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	updateLeaderstats(player, data)
	remotes.State:FireClient(player, buildSnapshot(player, data))

	-- 다른 플레이어에게도 보이는 펫 (클라이언트가 이 속성을 읽어 펫을 그림)
	local ids = {}
	local petById = {}
	for _, pet in ipairs(data.pets) do
		petById[pet.uid] = pet
	end
	for _, uid in ipairs(data.equipped) do
		if petById[uid] then
			table.insert(ids, petById[uid].id)
		end
	end
	player:SetAttribute("Pets", table.concat(ids, ","))
end

local function addCoins(player, data, amount)
	data.coins += amount
	data.totalCoins += amount
end

local function sell(player, data, silent)
	if data.bag.count <= 0 then
		return 0
	end
	local stats = getStats(player, data)
	local earned = math.floor(data.bag.value * stats.coinMult + 0.5)
	addCoins(player, data, earned)
	data.bag.count = 0
	data.bag.value = 0
	remotes.Bag:FireClient(player, 0, 0, stats.bagCap)
	remotes.Notify:FireClient(player, "+" .. Format.Short(earned) .. " 코인", Color3.fromRGB(255, 220, 120), silent and "small" or nil)
	refresh(player)
	return earned
end

local function startMeteorShower(buyer)
	meteorUntil = math.max(meteorUntil, os.time()) + Config.MeteorShowerDuration
	remotes.Announce:FireAllClients(
		string.format("☄️ %s 님이 유성우를 불렀어요! 2분 동안 모두 별 3배 + 행운 x2!", buyer.DisplayName),
		meteorUntil - os.time()
	)
	for _, p in ipairs(Players:GetPlayers()) do
		refresh(p)
	end
end

local context = {
	remotes = remotes,
	notify = notify,
	getData = DataService.Get,
	getStats = getStats,
	sell = sell,
	addCoins = addCoins,
	refresh = refresh,
	short = Format.Short,
	startMeteorShower = startMeteorShower,
}

DataService.Start()
StarService.Start(context)
Monetization.Start(context)

----------------------------------------------------------------------
-- 판매 발판
----------------------------------------------------------------------
local sellDebounce = {}
for _, plot in ipairs(plots) do
	local pad = plot:FindFirstChild("SellPad")
	if pad then
		pad.Touched:Connect(function(hit)
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if not player then
				return
			end
			if sellDebounce[player] and os.clock() - sellDebounce[player] < 0.5 then
				return
			end
			sellDebounce[player] = os.clock()
			local data = DataService.Get(player)
			if data then
				sell(player, data, false)
			end
		end)
	end
end

----------------------------------------------------------------------
-- 땅 배정
----------------------------------------------------------------------
local function setSign(plot, text)
	local sign = plot:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChildOfClass("BillboardGui")
	local label = gui and gui:FindFirstChild("Label")
	if label then
		label.Text = text
	end
end

local function assignPlot(player)
	for _, plot in ipairs(plots) do
		if not plotOwner[plot] then
			plotOwner[plot] = player
			playerPlot[player] = plot
			setSign(plot, player.DisplayName .. "의 별밭")
			StarService.AssignPlot(plot, player)
			return plot
		end
	end
	return nil
end

local function teleportToPlot(player, character)
	local plot = playerPlot[player]
	local spawnPart = plot and plot:FindFirstChild("Spawn")
	if not spawnPart then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root then
		task.wait(0.1)
		character:PivotTo(spawnPart.CFrame + Vector3.new(0, 3, 0))
	end
end

----------------------------------------------------------------------
-- 접속 / 퇴장
----------------------------------------------------------------------
local function onPlayerAdded(player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local coins = Instance.new("StringValue")
	coins.Name = "⭐ 코인"
	coins.Value = "0"
	coins.Parent = ls
	local reb = Instance.new("IntValue")
	reb.Name = "🔄 환생"
	reb.Parent = ls
	ls.Parent = player

	task.spawn(function()
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		policies[player] = { paidRandomRestricted = ok and info and info.ArePaidRandomItemsRestricted or false }
		refresh(player)
	end)

	Monetization.LoadPlayer(player)
	local data = DataService.Load(player)
	if not data then
		return
	end

	assignPlot(player)
	player.CharacterAdded:Connect(function(character)
		teleportToPlot(player, character)
	end)
	if player.Character then
		task.spawn(teleportToPlot, player, player.Character)
	end

	refresh(player)
	if data.starsCollected == 0 then
		notify(player, "환영해요! 떨어지는 별 근처로 가면 자동으로 주워요 ⭐", Color3.fromRGB(200, 200, 255))
	elseif data.daily.lastDay < today() then
		notify(player, "오늘의 출석 보상을 받을 수 있어요! 🎁", Color3.fromRGB(140, 255, 160))
	end
end

local function onPlayerRemoving(player)
	local plot = playerPlot[player]
	if plot then
		StarService.ReleasePlot(plot)
		plotOwner[plot] = nil
		playerPlot[player] = nil
		setSign(plot, "빈 땅")
	end
	sellDebounce[player] = nil
	policies[player] = nil
	DataService.Release(player)
	Monetization.RemovePlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

-- 플레이 시간 기록 (분석용) + 부스트 타이머 갱신
task.spawn(function()
	while true do
		task.wait(30)
		for _, p in ipairs(Players:GetPlayers()) do
			local data = DataService.Get(p)
			if data then
				data.playtime += 30
				if data.boosts.luckUntil > 0 and data.boosts.luckUntil <= os.time() and data.boosts.luckUntil > os.time() - 31 then
					notify(p, "행운 물약 효과가 끝났어요.", Color3.fromRGB(200, 200, 200))
					refresh(p)
				end
			end
		end
	end
end)

----------------------------------------------------------------------
-- 클라이언트 요청 처리 (모든 검증은 서버에서)
----------------------------------------------------------------------
local actions = {}

function actions.BuyUpgrade(player, data, id)
	local def = Config.Upgrades[id]
	if not def then
		return false, "잘못된 업그레이드"
	end
	local level = data.upgrades[id]
	if level >= def.maxLevel then
		return false, "최대 레벨이에요"
	end
	local cost = Config.GetUpgradeCost(id, level)
	if data.coins < cost then
		return false, "코인이 부족해요"
	end
	data.coins -= cost
	data.upgrades[id] = level + 1
	return true, def.name .. " Lv." .. (level + 1)
end

function actions.Rebirth(player, data)
	local cost = Config.GetRebirthCost(data.rebirths)
	if data.coins < cost then
		return false, "코인이 부족해요 (" .. Format.Short(cost) .. " 필요)"
	end
	data.rebirths += 1
	data.coins = 0
	data.bag.count = 0
	data.bag.value = 0
	for id in pairs(data.upgrades) do
		data.upgrades[id] = 0
	end
	remotes.Announce:FireAllClients(
		string.format("🔄 %s 님이 %d번째 환생을 했어요!", player.DisplayName, data.rebirths),
		4
	)
	return true, "환생 완료! 코인 배율 x" .. Config.GetRebirthMultiplier(data.rebirths)
end

local function rollEgg(egg)
	local roll = math.random() * 100
	for _, entry in ipairs(egg.chances) do
		roll -= entry.chance
		if roll <= 0 then
			return entry.pet
		end
	end
	return egg.chances[#egg.chances].pet
end

function actions.Hatch(player, data, eggId)
	local egg = Config.Eggs[eggId]
	if not egg then
		return false, "잘못된 알"
	end
	if #data.pets >= Config.MaxPetInventory then
		return false, "펫 가방이 가득 찼어요. 펫을 놓아 주세요"
	end
	if data.coins < egg.cost then
		return false, "코인이 부족해요"
	end
	data.coins -= egg.cost
	local petId = rollEgg(egg)
	local uid = tostring(data.nextPetUid)
	data.nextPetUid += 1
	table.insert(data.pets, { uid = uid, id = petId })

	-- 빈 슬롯이 있으면 자동 장착
	local stats = getStats(player, data)
	if #data.equipped < stats.slots then
		table.insert(data.equipped, uid)
	end

	local def = Config.Pets[petId]
	if def.rarity == "Legendary" or def.rarity == "Cosmic" then
		remotes.Announce:FireAllClients(
			string.format("🎉 %s 님이 %s 을(를) 뽑았어요!", player.DisplayName, def.name),
			4
		)
	end
	remotes.Hatched:FireClient(player, petId)
	return true, def.name .. " 획득!"
end

function actions.Equip(player, data, uid)
	if type(uid) ~= "string" or table.find(data.equipped, uid) then
		return false
	end
	local found = false
	for _, pet in ipairs(data.pets) do
		if pet.uid == uid then
			found = true
			break
		end
	end
	if not found then
		return false
	end
	if #data.equipped >= getStats(player, data).slots then
		return false, "장착 슬롯이 가득 찼어요"
	end
	table.insert(data.equipped, uid)
	return true
end

function actions.Unequip(player, data, uid)
	local index = table.find(data.equipped, uid)
	if not index then
		return false
	end
	table.remove(data.equipped, index)
	return true
end

function actions.EquipBest(player, data)
	local sorted = table.clone(data.pets)
	table.sort(sorted, function(a, b)
		return Config.Pets[a.id].bonus > Config.Pets[b.id].bonus
	end)
	local slots = getStats(player, data).slots
	data.equipped = {}
	for i = 1, math.min(slots, #sorted) do
		table.insert(data.equipped, sorted[i].uid)
	end
	return true, "가장 좋은 펫을 장착했어요"
end

function actions.ReleasePet(player, data, uid)
	for i, pet in ipairs(data.pets) do
		if pet.uid == uid then
			table.remove(data.pets, i)
			local e = table.find(data.equipped, uid)
			if e then
				table.remove(data.equipped, e)
			end
			return true, Config.Pets[pet.id].name .. " 을(를) 놓아 줬어요"
		end
	end
	return false
end

function actions.ClaimDaily(player, data)
	local t = today()
	if data.daily.lastDay >= t then
		return false, "오늘은 이미 받았어요. 내일 또 와요!"
	end
	if data.daily.lastDay == t - 1 then
		data.daily.streak += 1
	else
		data.daily.streak = 1
	end
	data.daily.lastDay = t
	local dayIndex = ((data.daily.streak - 1) % #Config.DailyRewards) + 1
	local reward = Config.DailyRewards[dayIndex] * (data.rebirths + 1)
	addCoins(player, data, reward)
	return true, string.format("%d일차 출석 보상 +%s 코인!", dayIndex, Format.Short(reward))
end

function actions.Sell(player, data)
	-- 자동 판매 게임패스 보유자만 어디서든 판매 가능
	if not Monetization.Owns(player, "AutoSell") then
		return false, "판매 발판에서 팔 수 있어요"
	end
	sell(player, data, false)
	return true
end

local lastAction = {}
actionRemote.OnServerInvoke = function(player, action, arg)
	if type(action) ~= "string" or not actions[action] then
		return false
	end
	local now = os.clock()
	if lastAction[player] and now - lastAction[player] < 0.08 then
		return false, "너무 빨라요"
	end
	lastAction[player] = now
	local data = DataService.Get(player)
	if not data then
		return false, "데이터 불러오는 중..."
	end
	local ok, msg = actions[action](player, data, arg)
	refresh(player)
	return ok, msg
end

Players.PlayerRemoving:Connect(function(player)
	lastAction[player] = nil
end)

print("[Starfall] 서버 준비 완료")
