-- ⛳ 펑! 골프 파티 서버
-- 대기 → 홀 3개(모두 동시에 플레이) → 결과·보상 → 반복

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PolicyService = game:GetService("PolicyService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local Monetization = require(script.Parent.Monetization)
local CourseBuilder = require(script.Parent.CourseBuilder)
local Golf = require(script.Parent.Golf)
local Gacha = require(script.Parent.Gacha)

DataService.Configure("PopGolfData_v1", function()
	return {
		coins = 0,
		gems = 0,
		shards = 0,
		skins = { White = true },
		equipped = "White",
		pity = { sinceLegendary = 0 },
		stats = { matches = 0, wins = 0, holes = 0, holeInOnes = 0, bestPoints = 0, pulls = 0 },
		lastDailyDay = 0,
		lastVipGemDay = 0,
		starterBought = false,
		receipts = {},
	}
end)

----------------------------------------------------------------------
-- 리모트
----------------------------------------------------------------------
local remoteFolder = Instance.new("Folder")
remoteFolder.Name = "Remotes"
local remotes = {}
for _, name in ipairs({ "State", "Match", "Notify", "Announce", "Shoot", "UseItem", "GachaResult" }) do
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
-- 로비
----------------------------------------------------------------------
local LOBBY = Vector3.new(0, 400, 0)
do
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	lobby.Parent = workspace
	local floor = Instance.new("Part")
	floor.Anchored = true
	floor.Size = Vector3.new(80, 2, 80)
	floor.Position = LOBBY - Vector3.new(0, 1, 0)
	floor.Color = Color3.fromRGB(110, 200, 90)
	floor.Material = Enum.Material.Grass
	floor.Parent = lobby
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = LOBBY + Vector3.new(0, 0.5, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(255, 255, 255)
	spawn.Parent = lobby
	-- 장식 깃발
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2
		local pole = Instance.new("Part")
		pole.Anchored = true
		pole.Size = Vector3.new(0.4, 14, 0.4)
		pole.Position = LOBBY + Vector3.new(math.cos(a) * 30, 7, math.sin(a) * 30)
		pole.Color = Color3.new(1, 1, 1)
		pole.Parent = lobby
		local flag = Instance.new("Part")
		flag.Anchored = true
		flag.Size = Vector3.new(0.2, 3, 5)
		flag.Position = pole.Position + Vector3.new(0, 5.5, 2.5)
		flag.Color = Color3.fromRGB(255, 70, 70)
		flag.Material = Enum.Material.Fabric
		flag.Parent = lobby
	end
end

----------------------------------------------------------------------
-- 상태 / 화면 갱신
----------------------------------------------------------------------
local restricted = {} -- [Player] = 확률형 아이템 제한 지역 여부
local match = {
	phase = "Waiting", -- Waiting | Intermission | Countdown | Playing | HoleResult | Results
	hole = 0,
	endsAt = 0,
	players = {}, -- 참가자 목록
	totals = {}, -- [Player] = 누적 점수
	theme = "",
}

local function notify(player, text, color)
	if player and player.Parent then
		remotes.Notify:FireClient(player, text, color)
	end
end

local function announce(text, seconds)
	remotes.Announce:FireAllClients(text, seconds)
end

local function refresh(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls["🏆 승리"].Value = data.stats.wins
		ls["⛳ 홀인원"].Value = data.stats.holeInOnes
	end
	remotes.State:FireClient(player, {
		coins = data.coins,
		gems = data.gems,
		shards = data.shards,
		skins = data.skins,
		equipped = data.equipped,
		pity = data.pity.sinceLegendary,
		stats = data.stats,
		passes = Monetization.GetOwned(player),
		restricted = restricted[player] == true,
		starterBought = data.starterBought,
		oddsBasic = Gacha.OddsTable("Basic"),
		oddsPremium = Gacha.OddsTable("Premium"),
	})
end

local function broadcastMatch()
	local board = {}
	for _, p in ipairs(match.players) do
		if p.Parent then
			table.insert(board, { userId = p.UserId, name = p.DisplayName, total = match.totals[p] or 0 })
		end
	end
	table.sort(board, function(a, b)
		return a.total > b.total
	end)
	local playing = {}
	for _, p in ipairs(match.players) do
		playing[tostring(p.UserId)] = true
	end
	remotes.Match:FireAllClients({
		phase = match.phase,
		hole = match.hole,
		holes = Config.HolesPerMatch,
		timeLeft = math.max(0, match.endsAt - os.clock()),
		board = board,
		balls = Golf.Snapshot(),
		playing = playing,
		theme = match.theme,
		need = Config.MinPlayers,
	})
end

----------------------------------------------------------------------
-- 골프 모듈 연결
----------------------------------------------------------------------
local changePending = false
Golf.Start({
	notify = notify,
	announce = announce,
	teePosition = CourseBuilder.TeePosition,
	onChange = function()
		changePending = true
	end,
	onHoleInOne = function(player)
		local data = DataService.Get(player)
		if data then
			data.stats.holeInOnes += 1
			data.gems += 5
			notify(player, "🎉 홀인원 보너스 💎 +5", Color3.fromRGB(140, 220, 255))
		end
	end,
})
-- 화면 갱신은 최대 0.25초에 한 번
task.spawn(function()
	while true do
		task.wait(0.25)
		if changePending then
			changePending = false
			broadcastMatch()
		end
	end
end)

remotes.Shoot.OnServerEvent:Connect(function(player, direction, power)
	if match.phase == "Playing" then
		Golf.Shoot(player, direction, power)
	end
end)
remotes.UseItem.OnServerEvent:Connect(function(player)
	if match.phase == "Playing" then
		Golf.UseItem(player)
	end
end)

----------------------------------------------------------------------
-- 캐릭터: 경기 중에는 로비에 고정 (카메라는 공을 따라감)
----------------------------------------------------------------------
local function setLocked(player, locked)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = locked
	end
end

----------------------------------------------------------------------
-- 경기 진행
----------------------------------------------------------------------
local function readyPlayers()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if DataService.Get(p) and p.Character then
			table.insert(list, p)
		end
	end
	return list
end

local function today()
	return os.time() // 86400
end

local function finishMatch()
	match.phase = "Results"
	match.endsAt = os.clock() + 8
	local ranking = {}
	for _, p in ipairs(match.players) do
		if p.Parent then
			table.insert(ranking, { player = p, total = match.totals[p] or 0 })
		end
	end
	table.sort(ranking, function(a, b)
		return a.total > b.total
	end)
	for place, r in ipairs(ranking) do
		local p = r.player
		local data = DataService.Get(p)
		if data then
			local coins = Config.Rewards.play + r.total * Config.Rewards.perPoint
			data.coins += coins
			data.stats.matches += 1
			data.stats.bestPoints = math.max(data.stats.bestPoints, r.total)
			local gems = 0
			if place == 1 and r.total > 0 and #ranking >= 2 then
				data.stats.wins += 1
				gems += Config.Rewards.winGems
			end
			if data.lastDailyDay < today() then
				data.lastDailyDay = today()
				gems += Config.Rewards.dailyGems
				if p.MembershipType == Enum.MembershipType.Premium then
					gems += Config.PremiumDailyGems
				end
			end
			data.gems += gems
			notify(p, string.format("🏁 %d등 · 🪙 +%d%s", place, coins, gems > 0 and ("  💎 +" .. gems) or ""), Color3.fromRGB(255, 230, 120))
			refresh(p)
		end
		setLocked(p, false)
	end
	if ranking[1] then
		announce(string.format("🏆 우승: %s (%d점)", ranking[1].player.DisplayName, ranking[1].total), 6)
	end
	broadcastMatch()
	task.wait(8)
	CourseBuilder.Clear()
	Golf.Clear()
	match.players = {}
	match.totals = {}
	match.hole = 0
	match.phase = "Waiting"
	broadcastMatch()
end

local function playMatch(participants)
	match.players = participants
	match.totals = {}
	for _, p in ipairs(participants) do
		match.totals[p] = 0
		setLocked(p, true)
	end
	local seed = math.random(1, 1e6)
	for holeNumber = 1, Config.HolesPerMatch do
		-- 참가자가 모두 나가면 중단
		local alive = {}
		for _, p in ipairs(match.players) do
			if p.Parent then
				table.insert(alive, p)
			end
		end
		if #alive == 0 then
			break
		end
		match.hole = holeNumber
		local hole = CourseBuilder.Build(holeNumber, seed + holeNumber)
		match.theme = hole.theme.name
		Golf.BeginHole(hole, alive, function(p)
			local data = DataService.Get(p)
			return data and data.equipped or "White"
		end)

		match.phase = "Countdown"
		match.endsAt = os.clock() + Config.Countdown
		broadcastMatch()
		announce(string.format("⛳ %d번 홀 · %s", holeNumber, hole.theme.name), Config.Countdown)
		task.wait(Config.Countdown)

		Golf.Go()
		match.phase = "Playing"
		match.endsAt = os.clock() + Config.HoleTime
		broadcastMatch()
		local lastBroadcast = 0
		while os.clock() < match.endsAt and not Golf.AllDone() do
			task.wait(0.2)
			if os.clock() - lastBroadcast > 1 then
				lastBroadcast = os.clock()
				broadcastMatch()
			end
		end

		local results = Golf.EndHole()
		for _, r in ipairs(results) do
			if r.player.Parent then
				match.totals[r.player] = (match.totals[r.player] or 0) + r.points
				local data = DataService.Get(r.player)
				if data and r.place then
					data.stats.holes += 1
				end
			end
		end
		match.phase = "HoleResult"
		match.endsAt = os.clock() + 4
		broadcastMatch()
		task.wait(4)
	end
	finishMatch()
end

task.spawn(function()
	while true do
		local list = readyPlayers()
		if #list < Config.MinPlayers then
			match.phase = "Waiting"
			broadcastMatch()
			task.wait(2)
		else
			match.phase = "Intermission"
			match.endsAt = os.clock() + Config.Intermission
			while os.clock() < match.endsAt do
				broadcastMatch()
				task.wait(1)
			end
			list = readyPlayers()
			if #list >= Config.MinPlayers then
				local participants = {}
				for i = 1, math.min(#list, Config.MaxPlayers) do
					table.insert(participants, list[i])
				end
				playMatch(participants)
			end
		end
	end
end)

----------------------------------------------------------------------
-- 결제
----------------------------------------------------------------------
local function giveGems(player, data, amount)
	data.gems += amount
	notify(player, "💎 젬 +" .. amount, Color3.fromRGB(140, 220, 255))
end

local productHandlers = {}
for key, info in pairs(Config.Products) do
	productHandlers[key] = function(player, data)
		if info.once and data.starterBought then
			-- 이미 산 1회 한정 상품이 또 결제되면 젬으로만 지급
			giveGems(player, data, info.gems)
			return
		end
		giveGems(player, data, info.gems)
		if info.skin then
			if data.skins[info.skin] then
				data.shards += Config.RarityById[Config.Skins[info.skin].rarity].shards
			else
				data.skins[info.skin] = true
			end
			notify(player, "🎁 " .. Config.Skins[info.skin].name .. " 공 획득!", Color3.fromRGB(255, 220, 120))
		end
		if info.once then
			data.starterBought = true
		end
	end
end

local function grantVipDaily(player)
	local data = DataService.Get(player)
	if data and Monetization.Owns(player, "VIP") and data.lastVipGemDay < today() then
		data.lastVipGemDay = today()
		giveGems(player, data, 20)
		refresh(player)
	end
end

DataService.Start()
Monetization.Start({
	notify = notify,
	refresh = refresh,
	productHandlers = productHandlers,
	onPass = function(player, key)
		local data = DataService.Get(player)
		if key == "VIP" then
			player:SetAttribute("VIP", true)
			if data then
				data.skins.VIPCrown = true
			end
			grantVipDaily(player)
		end
	end,
})

----------------------------------------------------------------------
-- 접속 / 퇴장
----------------------------------------------------------------------
local function onPlayerAdded(player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local wins = Instance.new("IntValue")
	wins.Name = "🏆 승리"
	wins.Parent = ls
	local hio = Instance.new("IntValue")
	hio.Name = "⛳ 홀인원"
	hio.Parent = ls
	ls.Parent = player

	task.spawn(function()
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		-- 정보를 못 받으면 안전하게 '제한'으로 취급 (Studio 테스트에서는 예외)
		if not ok then
			restricted[player] = not RunService:IsStudio()
		else
			restricted[player] = info.ArePaidRandomItemsRestricted == true
		end
		refresh(player)
	end)

	Monetization.LoadPlayer(player)
	local data = DataService.Load(player)
	if not data then
		return
	end
	player.CharacterAdded:Connect(function(character)
		-- 경기 중에 리스폰되면 다시 고정
		if table.find(match.players, player) and match.phase ~= "Waiting" and match.phase ~= "Results" then
			local root = character:WaitForChild("HumanoidRootPart", 10)
			if root then
				root.Anchored = true
			end
		end
	end)
	refresh(player)
	task.delay(4, grantVipDaily, player)
	broadcastMatch()
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	local i = table.find(match.players, player)
	if i then
		table.remove(match.players, i)
	end
	match.totals[player] = nil
	restricted[player] = nil
	DataService.Release(player)
	Monetization.RemovePlayer(player)
end)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

----------------------------------------------------------------------
-- 클라이언트 요청 (가챠, 장착, 조각 구매)
----------------------------------------------------------------------
local actions = {}

function actions.Pull(player, data, arg)
	if type(arg) ~= "table" then
		return false
	end
	local ok, result = Gacha.Pull(data, arg.capsule, arg.count, restricted[player] ~= false)
	if not ok then
		return false, result
	end
	remotes.GachaResult:FireClient(player, result)
	for _, r in ipairs(result) do
		if r.rarity == "Legendary" or r.rarity == "Mythic" then
			announce(string.format("✨ %s 님이 %s 공을 뽑았어요!", player.DisplayName, Config.Skins[r.skin].name), 4)
		end
	end
	return true
end

function actions.Equip(player, data, skinId)
	if type(skinId) ~= "string" or not data.skins[skinId] then
		return false, "가지고 있지 않은 공이에요"
	end
	data.equipped = skinId
	return true, Config.Skins[skinId].name .. " 장착!"
end

function actions.BuyShard(player, data, skinId)
	return Gacha.BuyWithShards(data, skinId)
end

local last = {}
actionRemote.OnServerInvoke = function(player, action, arg)
	if type(action) ~= "string" or not actions[action] then
		return false
	end
	if last[player] and os.clock() - last[player] < 0.4 then
		return false, "잠시만요..."
	end
	last[player] = os.clock()
	local data = DataService.Get(player)
	if not data then
		return false, "데이터 불러오는 중..."
	end
	local ok, msg = actions[action](player, data, arg)
	refresh(player)
	return ok, msg
end
Players.PlayerRemoving:Connect(function(p)
	last[p] = nil
end)

print("[PopGolf] 서버 준비 완료")
