-- ⛳ 팝골프 서버 (2대2 팀 배틀 골프)
-- 대기 → 팀 나누기 → 홀 3개 (먼저 넣는 팀이 홀 승리) → 결과·보상 → 반복

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PolicyService = game:GetService("PolicyService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local Monetization = require(script.Parent.Monetization)
local CourseBuilder = require(script.Parent.CourseBuilder)
local Golf = require(script.Parent.Golf)
local Gacha = require(script.Parent.Gacha)
local Club = require(script.Parent.Club)

DataService.Configure("PopGolfData_v2", function()
	return {
		coins = 0,
		gems = 0,
		shards = 0,
		skins = { White = true },
		equipped = "White",
		pity = { sinceLegendary = 0 },
		stats = { matches = 0, wins = 0, holesWon = 0, sinks = 0, knockouts = 0, pulls = 0 },
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
for _, name in ipairs({ "State", "Match", "Notify", "Announce", "ChargeStart", "Swing", "UseItem", "GachaResult" }) do
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
local lobbySpawn
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
	floor.Size = Vector3.new(90, 2, 90)
	floor.Position = LOBBY - Vector3.new(0, 1, 0)
	floor.Color = Color3.fromRGB(110, 200, 90)
	floor.Material = Enum.Material.Grass
	floor.Parent = lobby
	-- 팀 색 바닥 장식 (왼쪽 레드, 오른쪽 블루)
	for i, team in ipairs(Config.Teams) do
		local pad = Instance.new("Part")
		pad.Anchored = true
		pad.Size = Vector3.new(30, 0.2, 60)
		pad.Position = LOBBY + Vector3.new(i == 1 and -25 or 25, 0.1, 0)
		pad.Color = team.color
		pad.Material = Enum.Material.SmoothPlastic
		pad.Transparency = 0.5
		pad.CanCollide = false
		pad.Parent = lobby
	end
	lobbySpawn = Instance.new("SpawnLocation")
	lobbySpawn.Anchored = true
	lobbySpawn.Size = Vector3.new(10, 1, 10)
	lobbySpawn.Position = LOBBY + Vector3.new(0, 0.5, 0)
	lobbySpawn.Neutral = true
	lobbySpawn.Duration = 0
	lobbySpawn.Color = Color3.fromRGB(255, 255, 255)
	lobbySpawn.Parent = lobby
end

----------------------------------------------------------------------
-- 상태
----------------------------------------------------------------------
local restricted = {}
local match = {
	phase = "Waiting", -- Waiting | Intermission | Countdown | Playing | HoleResult | Results
	hole = 0,
	endsAt = 0,
	teams = {}, -- { {Player, Player}, {Player, Player} }
	holeWins = {}, -- [teamIndex] = 이긴 홀 수
	lastHole = nil, -- { winner, reason }
	teamSize = 2, -- 이번 경기 한 팀 최대 인원
	mode = "", -- "2대2" / "3대3" / "3대2" ...
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

local function inMatch(player)
	for _, members in ipairs(match.teams) do
		if table.find(members, player) then
			return true
		end
	end
	return false
end

local function refresh(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls["🏆 승리"].Value = data.stats.wins
		ls["💫 넘어뜨림"].Value = data.stats.knockouts
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
	local teamsInfo = {}
	for i, members in ipairs(match.teams) do
		local names, ids = {}, {}
		for _, p in ipairs(members) do
			if p.Parent then
				table.insert(names, p.DisplayName)
				table.insert(ids, p.UserId)
			end
		end
		teamsInfo[i] = { names = names, ids = ids, holeWins = match.holeWins[i] or 0 }
	end
	remotes.Match:FireAllClients({
		phase = match.phase,
		hole = match.hole,
		holes = Config.HolesPerMatch,
		timeLeft = math.max(0, match.endsAt - os.clock()),
		teams = teamsInfo,
		golf = Golf.Snapshot(),
		theme = match.theme,
		lastHole = match.lastHole,
		need = Config.MinPlayers,
		mode = match.mode,
		maxPlayers = Config.MaxPlayers,
	})
end

----------------------------------------------------------------------
-- 골프 규칙 연결
----------------------------------------------------------------------
local changePending = false
Golf.Start({
	notify = notify,
	announce = announce,
	ballStart = CourseBuilder.BallStart,
	playerStart = CourseBuilder.PlayerStart,
	onChange = function()
		changePending = true
	end,
	onKnockout = function(attacker)
		local data = DataService.Get(attacker)
		if data then
			data.stats.knockouts += 1
			data.coins += Config.Rewards.knockout
		end
	end,
	onSunk = function(teamIndex, hitter)
		-- 우리 팀 공을 직접 넣은 선수에게 보너스
		if hitter and table.find(match.teams[teamIndex] or {}, hitter) then
			local data = DataService.Get(hitter)
			if data then
				data.stats.sinks += 1
				data.coins += 5
				notify(hitter, "⛳ 홀인 보너스 🪙 +5", Color3.fromRGB(255, 230, 120))
			end
		end
	end,
})
task.spawn(function()
	while true do
		task.wait(0.25)
		if changePending then
			changePending = false
			broadcastMatch()
		end
	end
end)

remotes.ChargeStart.OnServerEvent:Connect(function(player)
	if match.phase == "Playing" then
		Golf.ChargeStart(player)
	end
end)
remotes.Swing.OnServerEvent:Connect(function(player, direction, power)
	if match.phase == "Playing" then
		Golf.Swing(player, direction, power)
	end
end)
remotes.UseItem.OnServerEvent:Connect(function(player)
	if match.phase == "Playing" then
		Golf.UseItem(player)
	end
end)

----------------------------------------------------------------------
-- 경기 진행
----------------------------------------------------------------------
local function readyPlayers()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if DataService.Get(p) and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
			table.insert(list, p)
		end
	end
	return list
end

local function today()
	return os.time() // 86400
end

-- 무작위로 섞어서 팀 나누기 (1명이면 레드 팀만)
local function makeTeams(list)
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
	local teamLists = { {}, {} }
	for i, p in ipairs(list) do
		table.insert(teamLists[((i - 1) % 2) + 1], p)
	end
	if #teamLists[2] == 0 then
		teamLists[2] = nil
	end
	return teamLists
end

local function sendToLobby(player)
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.PlatformStand = false
			humanoid.WalkSpeed = 16
		end
		character:PivotTo(lobbySpawn.CFrame + Vector3.new(math.random(-12, 12), 4, math.random(-12, 12)))
	end
	player:SetAttribute("Team", nil)
	player.Neutral = true
	Club.Remove(player)
end

local function finishMatch()
	match.phase = "Results"
	match.endsAt = os.clock() + 8
	local w1, w2 = match.holeWins[1] or 0, match.holeWins[2] or 0
	local winnerTeam = nil
	if #match.teams >= 2 then
		if w1 ~= w2 then
			winnerTeam = w1 > w2 and 1 or 2
		end
	end

	for index, members in ipairs(match.teams) do
		for _, p in ipairs(members) do
			local data = DataService.Get(p)
			if data and p.Parent then
				local coins = Config.Rewards.play + (match.holeWins[index] or 0) * Config.Rewards.holeWin
				local gems = 0
				data.stats.matches += 1
				data.stats.holesWon += match.holeWins[index] or 0
				if winnerTeam == index then
					coins += Config.Rewards.matchWin
					gems += Config.Rewards.winGems
					data.stats.wins += 1
				end
				if data.lastDailyDay < today() then
					data.lastDailyDay = today()
					gems += Config.Rewards.dailyGems
					if p.MembershipType == Enum.MembershipType.Premium then
						gems += Config.PremiumDailyGems
					end
				end
				data.coins += coins
				data.gems += gems
				local result = winnerTeam == nil and "무승부" or (winnerTeam == index and "승리!" or "패배")
				notify(p, string.format("🏁 %s · 🪙 +%d%s", result, coins, gems > 0 and ("  💎 +" .. gems) or ""), Color3.fromRGB(255, 230, 120))
				refresh(p)
			end
		end
	end
	if winnerTeam then
		announce(string.format("🏆 %s 우승! (%d : %d)", Config.Teams[winnerTeam].name, w1, w2), 6)
	elseif #match.teams >= 2 then
		announce(string.format("🤝 무승부! (%d : %d)", w1, w2), 6)
	else
		announce("🏁 연습 경기 끝!", 4)
	end
	broadcastMatch()
	task.wait(6)
	CourseBuilder.Clear()
	Golf.Clear()
	for _, members in ipairs(match.teams) do
		for _, p in ipairs(members) do
			if p.Parent then
				sendToLobby(p)
			end
		end
	end
	match.teams = {}
	match.holeWins = {}
	match.lastHole = nil
	match.hole = 0
	match.mode = ""
	match.teamSize = 2
	match.phase = "Waiting"
	broadcastMatch()
end

local function playMatch(participants)
	match.teams = makeTeams(participants)
	match.holeWins = {}
	local a, b = #match.teams[1], match.teams[2] and #match.teams[2] or 0
	match.teamSize = math.max(a, b)
	match.mode = b > 0 and string.format("%d대%d", a, b) or "연습"
	if b > 0 then
		announce(string.format("⚔️ %s 경기 시작!", match.mode), 3)
		task.wait(1.5)
	end
	for index, members in ipairs(match.teams) do
		match.holeWins[index] = 0
		for _, p in ipairs(members) do
			p:SetAttribute("Team", index)
			p.Neutral = false
			p.TeamColor = Config.Teams[index].brick
			local data = DataService.Get(p)
			Club.Give(p, data and data.equipped or "White")
			notify(p, "당신은 " .. Config.Teams[index].name .. "!", Config.Teams[index].color)
		end
	end
	local seed = math.random(1, 1e6)

	for holeNumber = 1, Config.HolesPerMatch do
		-- 떠난 사람 정리
		local anyone = false
		for _, members in ipairs(match.teams) do
			for i = #members, 1, -1 do
				if not members[i].Parent then
					table.remove(members, i)
				end
			end
			anyone = anyone or #members > 0
		end
		if not anyone then
			break
		end

		match.hole = holeNumber
		match.lastHole = nil
		local hole = CourseBuilder.Build(holeNumber, seed + holeNumber, match.teamSize)
		match.theme = hole.theme.name
		Golf.BeginHole(hole, match.teams)

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
		while os.clock() < match.endsAt and not Golf.Winner() do
			task.wait(0.2)
			if os.clock() - lastBroadcast > 1 then
				lastBroadcast = os.clock()
				broadcastMatch()
			end
		end

		local holeWinner, reason = Golf.EndHole()
		match.lastHole = { winner = holeWinner, reason = reason }
		if holeWinner and #match.teams >= 2 then
			match.holeWins[holeWinner] += 1
			local how = reason == "sunk" and "먼저 홀인" or "홀컵에 더 가까워서"
			announce(string.format("%s %d번 홀 승리! (%s)", Config.Teams[holeWinner].name, holeNumber, how), 4)
		elseif #match.teams >= 2 then
			announce(string.format("%d번 홀 무승부!", holeNumber), 4)
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
		giveGems(player, data, info.gems)
		if info.once and data.starterBought then
			return -- 1회 한정 상품이 또 결제되면 젬만 지급
		end
		if info.skin then
			if data.skins[info.skin] then
				data.shards += Config.RarityById[Config.Skins[info.skin].rarity].shards
			else
				data.skins[info.skin] = true
			end
			notify(player, "🎁 " .. Config.Skins[info.skin].name .. " 골프채 획득!", Color3.fromRGB(255, 220, 120))
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
		if key == "VIP" then
			player:SetAttribute("VIP", true)
			local data = DataService.Get(player)
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
	local ko = Instance.new("IntValue")
	ko.Name = "💫 넘어뜨림"
	ko.Parent = ls
	ls.Parent = player
	player.Neutral = true

	task.spawn(function()
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
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
		character:WaitForChild("HumanoidRootPart", 10)
		-- 경기 중에 리스폰되면 우리 팀 공 옆으로, 골프채 다시 쥐어 주기
		if inMatch(player) and match.phase ~= "Waiting" and match.phase ~= "Results" then
			task.wait(0.2)
			Golf.PlacePlayer(player, nil)
			Club.Give(player, data.equipped)
		end
	end)
	refresh(player)
	task.delay(4, grantVipDaily, player)
	broadcastMatch()
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	for _, members in ipairs(match.teams) do
		local i = table.find(members, player)
		if i then
			table.remove(members, i)
		end
	end
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
			announce(string.format("✨ %s 님이 %s 골프채를 뽑았어요!", player.DisplayName, Config.Skins[r.skin].name), 4)
		end
	end
	return true
end

function actions.Equip(player, data, skinId)
	if type(skinId) ~= "string" or not data.skins[skinId] then
		return false, "가지고 있지 않은 골프채예요"
	end
	data.equipped = skinId
	if inMatch(player) then
		Club.Give(player, skinId)
	end
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

print("[PopGolf] 2대2 팀 배틀 골프 서버 준비 완료")
