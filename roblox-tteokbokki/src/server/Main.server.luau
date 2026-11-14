-- 🍢 떡볶이 가게 타이쿤 서버
-- 가게 터 배정 → 버튼으로 건물 구매 → 음식 생산 → 계산대에서 수금 → 프랜차이즈(환생)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local Monetization = require(script.Parent.Monetization)
local Tycoon = require(script.Parent.Tycoon)

DataService.Configure("TteokbokkiData_v1", function()
	return {
		cash = 0,
		totalCash = 0,
		rebirths = 0,
		bought = {}, -- [buttonId] = true
		rushUntil = 0,
		lastOnline = 0,
		receipts = {},
	}
end)

----------------------------------------------------------------------
-- 리모트
----------------------------------------------------------------------
local remoteFolder = Instance.new("Folder")
remoteFolder.Name = "Remotes"
local remotes = {}
for _, name in ipairs({ "State", "Notify", "Announce", "Offline" }) do
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
-- 맵
----------------------------------------------------------------------
Lighting.ClockTime = 13
Lighting.Brightness = 2.4
local baseplate = workspace:FindFirstChild("Baseplate")
if baseplate then
	baseplate:Destroy()
end
local lotsFolder = Instance.new("Folder")
lotsFolder.Name = "Lots"
lotsFolder.Parent = workspace

-- 가운데 길 + 스폰
local road = Instance.new("Part")
road.Anchored = true
road.Size = Vector3.new(320, 2, 56)
road.Position = Vector3.new(0, -1, 0)
road.Color = Color3.fromRGB(90, 90, 100)
road.Material = Enum.Material.Asphalt
road.Parent = workspace
local spawn = Instance.new("SpawnLocation")
spawn.Anchored = true
spawn.Size = Vector3.new(10, 1, 10)
spawn.Position = Vector3.new(0, 0.5, 0)
spawn.Neutral = true
spawn.Duration = 0
spawn.Color = Color3.fromRGB(255, 120, 80)
spawn.Parent = workspace

local lots = {}
for i = 1, Config.LotCount do
	local col = (i - 1) % 3
	local row = math.floor((i - 1) / 3)
	local origin = Vector3.new((col - 1) * 100, 0, row == 0 and -70 or 70)
	lots[i] = Tycoon.new(i, origin)
end
local playerLot = {} -- [Player] = Tycoon

----------------------------------------------------------------------
-- 계산
----------------------------------------------------------------------
local function notify(player, text, color)
	remotes.Notify:FireClient(player, text, color)
end

local function decoBonus(data)
	local b = 0
	for _, def in ipairs(Config.Buttons) do
		if def.kind == "deco" and data.bought[def.id] then
			b += def.bonus
		end
	end
	return b
end

local function cashMult(player, data)
	local m = (1 + decoBonus(data)) * Config.RebirthMultiplier(data.rebirths)
	if Monetization.Owns(player, "DoubleCash") then
		m *= 2
	end
	if Monetization.Owns(player, "VIP") then
		m *= 1.25
	end
	if player.MembershipType == Enum.MembershipType.Premium then
		m *= 1 + Config.PremiumCashBonus
	end
	if data.rushUntil > os.time() then
		m *= 3
	end
	return m
end

local function allBought(data)
	for _, def in ipairs(Config.Buttons) do
		if not data.bought[def.id] then
			return false
		end
	end
	return true
end

local function availableButtons(data)
	local list = {}
	for _, def in ipairs(Config.Buttons) do
		if not data.bought[def.id] then
			local ok = true
			for _, req in ipairs(def.requires) do
				if not data.bought[req] then
					ok = false
				end
			end
			if ok then
				table.insert(list, def)
			end
		end
	end
	table.sort(list, function(a, b)
		return a.cost < b.cost
	end)
	return list
end

local function cashPack(data, large)
	local nextDef = availableButtons(data)[1]
	local base = math.max(500, nextDef and nextDef.cost or 50000 * Config.RebirthMultiplier(data.rebirths))
	return large and base * 5 or base
end

local function refresh(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls["💰 돈"].Value = Format.Short(data.cash)
		ls["🏪 프랜차이즈"].Value = data.rebirths
	end
	local lot = playerLot[player]
	if lot then
		lot:refreshButtons(data.bought, data.cash)
	end
	local boughtCount = 0
	for _ in pairs(data.bought) do
		boughtCount += 1
	end
	local mult = cashMult(player, data)
	remotes.State:FireClient(player, {
		cash = data.cash,
		rebirths = data.rebirths,
		mult = mult,
		income = Tycoon.IncomePerSecond(data.bought) * mult * (Monetization.Owns(player, "FastCook") and 2 or 1),
		bought = boughtCount,
		total = #Config.Buttons,
		canRebirth = allBought(data),
		nextRebirthMult = Config.RebirthMultiplier(data.rebirths + 1),
		rushLeft = math.max(0, data.rushUntil - os.time()),
		passes = Monetization.GetOwned(player),
		packSmall = cashPack(data, false),
		packLarge = cashPack(data, true),
	})
end

local function buy(player, data, id, free)
	local def = Config.ButtonById[id]
	if not def or data.bought[id] then
		return false
	end
	for _, req in ipairs(def.requires) do
		if not data.bought[req] then
			return false, "먼저 다른 걸 지어야 해요"
		end
	end
	if not free then
		if data.cash < def.cost then
			return false, "돈이 부족해요 (💰 " .. Format.Short(def.cost) .. ")"
		end
		data.cash -= def.cost
	end
	data.bought[id] = true
	local lot = playerLot[player]
	if lot then
		lot:build(id)
	end
	if id == "Gold" then
		remotes.Announce:FireAllClients("🏆 " .. player.DisplayName .. " 님의 가게가 완성됐어요! 프랜차이즈 가능!", 5)
	end
	refresh(player)
	return true, "🔨 " .. def.name .. " 완성!"
end

----------------------------------------------------------------------
-- 버튼 / 계산대 연결
----------------------------------------------------------------------
local touchCooldown = {}
local function onButtonTouch(lot, id, hit)
	local player = lot.owner
	if not player or Players:GetPlayerFromCharacter(hit.Parent) ~= player then
		return
	end
	local key = player.UserId .. id
	if touchCooldown[key] and os.clock() - touchCooldown[key] < 1 then
		return
	end
	touchCooldown[key] = os.clock()
	local data = DataService.Get(player)
	if data then
		local ok, msg = buy(player, data, id, false)
		if msg then
			notify(player, msg, ok and Color3.fromRGB(120, 255, 160) or Color3.fromRGB(255, 130, 130))
		end
	end
end

local function collect(player, data, lot)
	if lot.pending <= 0 then
		return
	end
	local amount = math.floor(lot.pending)
	lot.pending -= amount
	data.cash += amount
	data.totalCash += amount
	lot:setPendingText(lot.pending)
	notify(player, "+💰 " .. Format.Short(amount), Color3.fromRGB(255, 220, 120))
	refresh(player)
end

for _, lot in ipairs(lots) do
	lot:createButtons(onButtonTouch)
	lot.onCollect = function(self, value)
		local player = self.owner
		local data = player and DataService.Get(player)
		if not data then
			return
		end
		local earned = value * cashMult(player, data)
		if Monetization.Owns(player, "AutoCollect") then
			data.cash += math.floor(earned)
			data.totalCash += math.floor(earned)
			self._dirty = true
		else
			self.pending += earned
			self:setPendingText(self.pending)
		end
	end
	lot.onRegister = function(self, hit)
		local player = self.owner
		if player and Players:GetPlayerFromCharacter(hit.Parent) == player then
			local data = DataService.Get(player)
			if data then
				collect(player, data, self)
			end
		end
	end
end

-- 생산 루프
task.spawn(function()
	local last = os.clock()
	local refreshTimer = 0
	while true do
		task.wait(0.1)
		local now = os.clock()
		local dt = now - last
		last = now
		refreshTimer += dt
		for player, lot in pairs(playerLot) do
			local speed = Monetization.Owns(player, "FastCook") and 2 or 1
			lot:tick(dt, speed)
		end
		-- 자동 수금 유저는 1초에 한 번만 화면 갱신
		if refreshTimer >= 1 then
			refreshTimer = 0
			for player, lot in pairs(playerLot) do
				if lot._dirty then
					lot._dirty = false
					refresh(player)
				end
			end
		end
	end
end)

----------------------------------------------------------------------
-- 결제
----------------------------------------------------------------------
DataService.Start()
Monetization.Start({
	notify = notify,
	refresh = refresh,
	productHandlers = {
		CashSmall = function(player, data)
			local amount = cashPack(data, false)
			data.cash += amount
			notify(player, "💵 +" .. Format.Short(amount), Color3.fromRGB(255, 220, 120))
		end,
		CashLarge = function(player, data)
			local amount = cashPack(data, true)
			data.cash += amount
			notify(player, "💰 +" .. Format.Short(amount), Color3.fromRGB(255, 220, 120))
		end,
		Rush = function(player, data)
			data.rushUntil = math.max(data.rushUntil, os.time()) + Config.RushDuration
			remotes.Announce:FireAllClients("🎉 " .. player.DisplayName .. " 님 가게에 손님이 몰려와요! (수입 3배)", 4)
		end,
		BuildNext = function(player, data)
			local nextDef = availableButtons(data)[1]
			if nextDef then
				buy(player, data, nextDef.id, true)
			else
				-- 지을 게 없으면 돈으로 지급 (구매가 헛되지 않게)
				data.cash += cashPack(data, false)
			end
		end,
	},
	onPass = function(player, key)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if key == "VIP" then
			player:SetAttribute("VIP", true)
			if humanoid then
				humanoid.WalkSpeed = 20
			end
		end
		if key == "AutoCollect" then
			local lot = playerLot[player]
			local data = DataService.Get(player)
			if lot and data then
				collect(player, data, lot)
			end
		end
	end,
})

----------------------------------------------------------------------
-- 접속 / 퇴장 (+ 오프라인 수입)
----------------------------------------------------------------------
local function onPlayerAdded(player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "💰 돈"
	cash.Value = "0"
	cash.Parent = ls
	local reb = Instance.new("IntValue")
	reb.Name = "🏪 프랜차이즈"
	reb.Parent = ls
	ls.Parent = player

	Monetization.LoadPlayer(player)
	local data = DataService.Load(player)
	if not data then
		return
	end

	local lot
	for _, l in ipairs(lots) do
		if not l.owner then
			lot = l
			break
		end
	end
	if not lot then
		player:Kick("서버가 가득 찼어요. 다른 서버로 들어와 주세요!")
		return
	end
	playerLot[player] = lot
	lot:assign(player, data.bought)

	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait(0.1)
		character:PivotTo(lot:spawnCFrame())
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and Monetization.Owns(player, "VIP") then
			humanoid.WalkSpeed = 20
		end
	end)
	if player.Character then
		player.Character:PivotTo(lot:spawnCFrame())
	end

	-- 오프라인 수입: 게임 패스 정보가 늦게 올 수 있어 3초 기다렸다가 계산
	task.delay(3, function()
		if not player.Parent or data.lastOnline <= 0 then
			data.lastOnline = os.time()
			return
		end
		local capHours = Monetization.Owns(player, "LongOffline") and 8 or Config.OfflineCapHours
		local away = math.clamp(os.time() - data.lastOnline, 0, capHours * 3600)
		data.lastOnline = os.time()
		if away < 60 then
			return
		end
		local mult = cashMult(player, data)
		local earned = math.floor(Tycoon.IncomePerSecond(data.bought) * mult * away * Config.OfflineRate)
		if earned > 0 then
			data.cash += earned
			data.totalCash += earned
			remotes.Offline:FireClient(player, earned, away, capHours)
			refresh(player)
		end
	end)

	refresh(player)
	if not data.bought.Open then
		notify(player, "초록색 발판을 밟아서 가게를 열어 보세요! 🍢", Color3.fromRGB(200, 255, 200))
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	local lot = playerLot[player]
	local data = DataService.Get(player)
	if lot and data then
		-- 계산대에 남은 돈은 챙겨 줌
		data.cash += math.floor(lot.pending)
		data.lastOnline = os.time()
	end
	if lot then
		lot:release()
		playerLot[player] = nil
	end
	DataService.Release(player)
	Monetization.RemovePlayer(player)
end)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

-- 서버가 갑자기 꺼져도 오프라인 시간이 맞도록 주기적으로 기록
task.spawn(function()
	while true do
		task.wait(30)
		for player in pairs(playerLot) do
			local data = DataService.Get(player)
			if data then
				data.lastOnline = os.time()
			end
		end
	end
end)

----------------------------------------------------------------------
-- 클라이언트 요청
----------------------------------------------------------------------
local actions = {}

function actions.Rebirth(player, data)
	if not allBought(data) then
		return false, "모든 건물을 지어야 프랜차이즈를 열 수 있어요"
	end
	data.rebirths += 1
	data.cash = 0
	data.bought = {}
	local lot = playerLot[player]
	if lot then
		lot:reset()
		lot:assign(player, data.bought)
	end
	remotes.Announce:FireAllClients(string.format("🏪 %s 님이 %d호점을 열었어요!", player.DisplayName, data.rebirths + 1), 5)
	return true, "프랜차이즈 성공! 수입 배율 x" .. Config.RebirthMultiplier(data.rebirths)
end

local last = {}
actionRemote.OnServerInvoke = function(player, action, arg)
	if type(action) ~= "string" or not actions[action] then
		return false
	end
	if last[player] and os.clock() - last[player] < 0.2 then
		return false
	end
	last[player] = os.clock()
	local data = DataService.Get(player)
	if not data then
		return false
	end
	local ok, msg = actions[action](player, data, arg)
	refresh(player)
	return ok, msg
end
Players.PlayerRemoving:Connect(function(p)
	last[p] = nil
end)
