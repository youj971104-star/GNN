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
		skill = Config.DefaultSkill, -- 장착한 스킬 (E)
		pity = { sinceLegendary = 0 },
		stats = { matches = 0, wins = 0, holesWon = 0, sinks = 0, knockouts = 0, pulls = 0 },
		lastDailyDay = 0,
		lastVipGemDay = 0,
		quests = { day = 0, Play = 0, Hit = 0, Win = 0, done = {} }, -- 일일 미션
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
for _, name in ipairs({ "State", "Match", "Notify", "Announce", "ChargeStart", "Swing", "UseItem", "Dash", "Skill", "Ultimate", "GachaResult", "Impact" }) do
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
local LobbyBuilder = require(script.Parent.LobbyBuilder)
local lobbySpawn, boards = LobbyBuilder.Build()
do
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
end

----------------------------------------------------------------------
-- 그래픽: 밝고 선명한 만화풍 조명 (빛 번짐, 색 보정, 햇살, 구름)
-- ※ Studio 에서 Lighting.Technology 를 'Future' 로 바꾸면 빛·그림자가 더 좋아짐 (스크립트로는 못 바꿈)
----------------------------------------------------------------------
do
	local Lighting = game:GetService("Lighting")
	Lighting.Brightness = 3
	Lighting.ExposureCompensation = 0.15
	Lighting.Ambient = Color3.fromRGB(110, 115, 135)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 150, 170)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.ShadowSoftness = 0.25
	local function ensure(className, props)
		local inst = Lighting:FindFirstChildOfClass(className) or Instance.new(className)
		for k, v in pairs(props) do
			inst[k] = v
		end
		inst.Parent = Lighting
	end
	ensure("Atmosphere", { Density = 0.28, Offset = 0.1, Color = Color3.fromRGB(200, 225, 255), Decay = Color3.fromRGB(120, 150, 200), Glare = 0.25, Haze = 1.2 })
	ensure("BloomEffect", { Intensity = 0.6, Size = 26, Threshold = 1.05 })
	ensure("ColorCorrectionEffect", { Saturation = 0.18, Contrast = 0.1, Brightness = 0.02 })
	ensure("SunRaysEffect", { Intensity = 0.07, Spread = 0.6 })
	pcall(function()
		local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
		clouds.Cover = 0.55
		clouds.Density = 0.6
		clouds.Color = Color3.fromRGB(255, 255, 255)
		clouds.Parent = workspace.Terrain
	end)
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
		skill = data.skill,
		pity = data.pity.sinceLegendary,
		stats = data.stats,
		passes = Monetization.GetOwned(player),
		restricted = restricted[player] == true,
		starterBought = data.starterBought,
		quests = data.quests,
		queued = player:GetAttribute("Queued") == true,
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
		queued = (function()
			local n = 0
			for _, p in ipairs(Players:GetPlayers()) do
				if p:GetAttribute("Queued") then
					n += 1
				end
			end
			return n
		end)(),
		maxPlayers = Config.MaxPlayers,
	})
end

----------------------------------------------------------------------
-- 골프 규칙 연결
----------------------------------------------------------------------
-- 메테오 스윙 충격파 연출 (모두에게 보임)
local function shockwave(position, radius, color)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.1
	ring.Size = Vector3.new(0.4, 2, 2)
	ring.CFrame = CFrame.new(position - Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	game:GetService("TweenService"):Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.1, radius * 2.4, radius * 2.4), Transparency = 1 }):Play()
	game:GetService("Debris"):AddItem(ring, 0.5)
	local fx = Instance.new("Explosion")
	fx.Position = position
	fx.BlastRadius = 0
	fx.BlastPressure = 0
	fx.DestroyJointRadiusPercent = 0
	fx.Parent = workspace
end

local changePending = false
Golf.Start({
	shockwave = shockwave,
	skillOf = function(player)
		local data = DataService.Get(player)
		return data and data.skill or Config.DefaultSkill
	end,
	notify = notify,
	announce = announce,
	ballStart = CourseBuilder.BallStart,
	playerStart = CourseBuilder.PlayerStart,
	onChange = function()
		changePending = true
	end,
	impact = function(position, color, big)
		remotes.Impact:FireAllClients(position, color, big)
	end,
	onBallHit = function(player)
		questProgress(player, "Hit", 1)
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
				notify(hitter, "⛳ 홀인 보너스 💰 +5", Color3.fromRGB(255, 230, 120))
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

-- 로비 연습 스윙: 모션과 골프채 효과만 (공·사람은 안 맞음)
local practiceLast = {}
local function practiceCharge(player)
	local character = player.Character
	if character and character:FindFirstChild("GolfClub") then
		character:SetAttribute("ChargeStart", workspace:GetServerTimeNow())
		character:SetAttribute("Charging", true)
	end
end
local function practiceSwing(player, power)
	local character = player.Character
	if not (character and character:FindFirstChild("GolfClub")) or type(power) ~= "number" then
		return
	end
	if practiceLast[player] and os.clock() - practiceLast[player] < Config.Club.cooldown then
		return
	end
	practiceLast[player] = os.clock()
	character:SetAttribute("Charging", false)
	character:SetAttribute("SwingPower", math.clamp(power, 0, 1))
	character:SetAttribute("SwingId", (character:GetAttribute("SwingId") or 0) + 1)
	task.delay(Config.Club.impactDelay, function()
		if character.Parent then
			character:SetAttribute("HitId", (character:GetAttribute("HitId") or 0) + 1) -- 큰 폭발 효과 보여 주기
		end
	end)
end
Players.PlayerRemoving:Connect(function(p)
	practiceLast[p] = nil
end)

remotes.ChargeStart.OnServerEvent:Connect(function(player)
	if match.phase == "Playing" and inMatch(player) then
		Golf.ChargeStart(player)
	elseif not inMatch(player) or match.phase ~= "Playing" then
		practiceCharge(player)
	end
end)
remotes.Swing.OnServerEvent:Connect(function(player, direction, power)
	if match.phase == "Playing" and inMatch(player) then
		Golf.Swing(player, direction, power)
	elseif not inMatch(player) or match.phase ~= "Playing" then
		practiceSwing(player, power)
	end
end)
remotes.Dash.OnServerEvent:Connect(function(player, moveDir)
	if match.phase == "Playing" and inMatch(player) then
		Golf.Dash(player, moveDir)
	end
end)
remotes.Skill.OnServerEvent:Connect(function(player, aim)
	if match.phase == "Playing" and inMatch(player) then
		Golf.UseSkill(player, aim)
	end
end)
remotes.Ultimate.OnServerEvent:Connect(function(player)
	if match.phase == "Playing" and inMatch(player) then
		Golf.UseUltimate(player)
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
		-- PLAY 버튼을 눌러 대기열에 들어간 사람만
		if p:GetAttribute("Queued") and DataService.Get(p) and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
			table.insert(list, p)
		end
	end
	return list
end

local function today()
	return os.time() // 86400
end

-- 일일 미션: 진행도 올리고, 목표에 닿으면 바로 보상
local function questProgress(player, key, amount)
	local data = DataService.Get(player)
	local q = data and data.quests
	local def = Config.Quests[key]
	if not (q and def) then
		return
	end
	if q.day ~= today() then
		data.quests = { day = today(), Play = 0, Hit = 0, Win = 0, done = {} }
		q = data.quests
	end
	if q.done[key] then
		return
	end
	q[key] = math.min(def.goal, (q[key] or 0) + amount)
	if q[key] >= def.goal then
		q.done[key] = true
		data.coins += def.coins or 0
		data.gems += def.gems or 0
		notify(player, string.format("✅ 일일 미션 '%s' 완료! 💰 +%d%s", def.name, def.coins or 0, def.gems and ("  💎 +" .. def.gems) or ""), Color3.fromRGB(140, 255, 160))
	end
end

-- 전체 서버 순위 (OrderedDataStore). Studio 에서 API 접근이 꺼져 있으면 조용히 건너뜀
local DataStoreService = game:GetService("DataStoreService")
local winsStore, koStore
pcall(function()
	winsStore = DataStoreService:GetOrderedDataStore("PopGolfWins_v1")
	koStore = DataStoreService:GetOrderedDataStore("PopGolfKO_v1")
end)
local nameCache = {}
local function nameOf(userId)
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	nameCache[userId] = ok and name or ("#" .. userId)
	return nameCache[userId]
end
local function pushGlobal(player, data)
	task.spawn(function()
		pcall(function()
			if winsStore then
				winsStore:SetAsync(tostring(player.UserId), data.stats.wins)
			end
			if koStore then
				koStore:SetAsync(tostring(player.UserId), data.stats.knockouts)
			end
		end)
	end)
end
local function refreshGlobalBoards()
	for _, entry in ipairs({ { winsStore, boards.globalWins, "🏆" }, { koStore, boards.globalKO, "💫" } }) do
		local store, label, icon = entry[1], entry[2], entry[3]
		if store and label then
			local ok, pages = pcall(function()
				return store:GetSortedAsync(false, 10)
			end)
			if ok and pages then
				local lines = {}
				for i, row in ipairs(pages:GetCurrentPage()) do
					table.insert(lines, string.format("%d. %s   %s %d", i, nameOf(tonumber(row.key)), icon, row.value))
				end
				label.Text = #lines > 0 and table.concat(lines, "\n") or "아직 기록이 없어요"
			else
				label.Text = "순위를 불러오지 못했어요\n(게임 설정 > 보안 > API 접근 켜기)"
			end
		end
	end
end
task.spawn(function()
	while true do
		refreshGlobalBoards()
		task.wait(120)
	end
end)

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
	Club.RemoveCap(player)
	player:SetAttribute("Team", nil)
	player:SetAttribute("UltActive", false)
	player:SetAttribute("Powered", false)
	player:SetAttribute("Gauge", 0)
	player.Neutral = true
	if character then
		character:SetAttribute("Charging", false) -- 골프채는 로비에서도 계속 들고 있음
	end
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
				questProgress(p, "Play", 1)
				if winnerTeam == index then
					coins += Config.Rewards.matchWin
					gems += Config.Rewards.winGems
					data.stats.wins += 1
					questProgress(p, "Win", 1)
				end
				pushGlobal(p, data)
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
				notify(p, string.format("🏁 %s · 💰 +%d%s", result, coins, gems > 0 and ("  💎 +" .. gems) or ""), Color3.fromRGB(255, 230, 120))
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
	-- 로비 순위 게시판 갱신 (지금 서버에 있는 사람 중 승리 순)
	local rows = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local d = DataService.Get(p)
		if d then
			table.insert(rows, { name = p.DisplayName, wins = d.stats.wins, ko = d.stats.knockouts })
		end
	end
	table.sort(rows, function(a, b)
		return a.wins > b.wins
	end)
	local lines = {}
	for i = 1, math.min(10, #rows) do
		table.insert(lines, string.format("%d. %s   🏆%d  💫%d", i, rows[i].name, rows[i].wins, rows[i].ko))
	end
	boards.serverMvp.Text = #lines > 0 and table.concat(lines, "\n") or "-"
	for place = 1, 3 do
		boards.podium[place].Text = rows[place] and rows[place].name or "-"
	end
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
			Club.GiveCap(p, Config.Teams[index].color)
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
	local function onCharacter(character)
		character:WaitForChild("HumanoidRootPart", 10)
		character:WaitForChild("Humanoid", 10)
		task.wait(0.3) -- 관절이 모두 만들어질 때까지
		if not character.Parent then
			return
		end
		-- 경기 중에 리스폰되면 우리 팀 공 옆으로
		if inMatch(player) and match.phase ~= "Waiting" and match.phase ~= "Results" then
			Golf.PlacePlayer(player, nil)
			local team = player:GetAttribute("Team")
			if team then
				Club.GiveCap(player, Config.Teams[team].color)
			end
		end
		-- 골프채는 로비에서도 항상 들고 있음 (장착한 스킨 바로 보이게)
		Club.Give(player, data.equipped)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
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
	Club.Give(player, skinId) -- 로비에서도 바로 바뀜
	return true, Config.Skins[skinId].name .. " 장착! (로비에서 휘둘러 효과를 확인해 보세요)"
end

-- PLAY 버튼: 대기열 들어가기 / 나가기
function actions.Queue(player, data, on)
	player:SetAttribute("Queued", on == true)
	return true, on and "⛳ 대기열에 들어갔어요! 곧 경기가 시작돼요" or "대기열에서 나왔어요"
end

function actions.SelectSkill(player, data, skillId)
	local skill = type(skillId) == "string" and Config.Skills[skillId]
	if not skill then
		return false
	end
	data.skill = skillId
	return true, skill.name .. " 장착!"
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
