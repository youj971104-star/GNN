-- 🧊 얼음땡 술래잡기 서버
-- 라운드: 대기 → 술래 뽑기 → 경기(술래는 얼리고, 도망자는 얼은 친구를 녹임) → 결과 → 반복

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local Monetization = require(script.Parent.Monetization)
local ArenaBuilder = require(script.Parent.ArenaBuilder)

DataService.Configure("FreezeTagData_v1", function()
	return {
		coins = 0,
		wins = 0,
		freezes = 0,
		thaws = 0,
		rounds = 0,
		trails = { Snow = true },
		trail = "Snow",
		receipts = {},
	}
end)

----------------------------------------------------------------------
-- 리모트
----------------------------------------------------------------------
local remoteFolder = Instance.new("Folder")
remoteFolder.Name = "Remotes"
local remotes = {}
for _, name in ipairs({ "State", "Round", "Notify", "Announce" }) do
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remoteFolder
	remotes[name] = r
end
local actionRemote = Instance.new("RemoteFunction")
actionRemote.Name = "Action"
actionRemote.Parent = remoteFolder
remoteFolder.Parent = ReplicatedStorage

local lobbyCFrame = ArenaBuilder.BuildLobby()

----------------------------------------------------------------------
-- 라운드 상태
----------------------------------------------------------------------
local round = {
	phase = "Waiting", -- Waiting | Intermission | Playing | Ended
	endsAt = 0,
	taggers = {}, -- [Player] = true
	runners = {}, -- [Player] = true
	frozen = {}, -- [Player] = os.clock() 얼은 시각
	shields = {}, -- [Player] = true (한 번 막아 주는 방패, 쓸 때까지 유지)
	ice = {}, -- [Player] = Part
}
local forcedTaggers = {} -- 다음 라운드 술래 확정 구매자

local function notify(player, text, color)
	remotes.Notify:FireClient(player, text, color)
end

local function coinMult(player)
	local m = 1
	if Monetization.Owns(player, "DoubleCoins") then
		m *= 2
	end
	if Monetization.Owns(player, "VIP") then
		m *= 1.5
	end
	if player.MembershipType == Enum.MembershipType.Premium then
		m *= 1 + Config.PremiumCoinBonus
	end
	return m
end

local function refresh(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls["💰 코인"].Value = Format.Short(data.coins)
		ls["🏆 승리"].Value = data.wins
	end
	remotes.State:FireClient(player, {
		coins = data.coins,
		wins = data.wins,
		freezes = data.freezes,
		thaws = data.thaws,
		rounds = data.rounds,
		trails = data.trails,
		trail = data.trail,
		passes = Monetization.GetOwned(player),
		coinMult = coinMult(player),
		shield = round.shields[player] == true,
		forcedTagger = forcedTaggers[player] == true,
	})
end

local function give(player, amount, reason)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local total = math.floor(amount * coinMult(player))
	data.coins += total
	if reason then
		remotes.Notify:FireClient(player, "+" .. total .. " 코인 · " .. reason, Color3.fromRGB(255, 220, 120))
	end
	refresh(player)
end

local function countRunners()
	local alive, total = 0, 0
	for p in pairs(round.runners) do
		total += 1
		if not round.frozen[p] then
			alive += 1
		end
	end
	return alive, total
end

local function broadcastRound()
	local alive, total = countRunners()
	remotes.Round:FireAllClients({
		phase = round.phase,
		timeLeft = math.max(0, round.endsAt - os.clock()),
		alive = alive,
		total = total,
		need = Config.MinPlayers,
	})
end

----------------------------------------------------------------------
-- 캐릭터 꾸미기: 역할 하이라이트, 트레일
----------------------------------------------------------------------
local function setHighlight(character, color)
	local h = character:FindFirstChild("RoleHighlight")
	if not color then
		if h then
			h:Destroy()
		end
		return
	end
	if not h then
		h = Instance.new("Highlight")
		h.Name = "RoleHighlight"
		h.FillTransparency = 0.7
		h.Parent = character
	end
	h.FillColor = color
	h.OutlineColor = color
end

local function applyTrail(player, character)
	local data = DataService.Get(player)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (data and root) then
		return
	end
	local old = root:FindFirstChild("PlayerTrail")
	if old then
		old:Destroy()
	end
	local def = Config.Trails[data.trail] or Config.Trails.Snow
	local a0 = root:FindFirstChild("TrailA0") or Instance.new("Attachment")
	a0.Name = "TrailA0"
	a0.Position = Vector3.new(0, 0.8, 0)
	a0.Parent = root
	local a1 = root:FindFirstChild("TrailA1") or Instance.new("Attachment")
	a1.Name = "TrailA1"
	a1.Position = Vector3.new(0, -0.8, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "PlayerTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.5
	trail.LightEmission = 0.5
	trail.Transparency = NumberSequence.new(0.1, 1)
	local kps = {}
	for i, c in ipairs(def.colors) do
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / math.max(1, #def.colors - 1), c))
	end
	if #kps == 1 then
		table.insert(kps, ColorSequenceKeypoint.new(1, def.colors[1]))
	end
	trail.Color = ColorSequence.new(kps)
	trail.Parent = root
end

local function setRole(player, role)
	player:SetAttribute("Role", role)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = role == "Tagger" and Config.TaggerSpeed or Config.RunnerSpeed
	end
	if character then
		setHighlight(character, role == "Tagger" and Color3.fromRGB(255, 70, 70) or nil)
	end
end

----------------------------------------------------------------------
-- 얼리기 / 녹이기
----------------------------------------------------------------------
local function freeze(runner, by)
	if round.frozen[runner] then
		return
	end
	if round.shields[runner] then
		round.shields[runner] = nil
		notify(runner, "🛡️ 얼음 방패가 막아 줬어요!", Color3.fromRGB(140, 220, 255))
		notify(by, "🛡️ 방패에 막혔어요!", Color3.fromRGB(255, 160, 160))
		-- 방패 직후 바로 다시 얼지 않도록 잠깐 거리두기 판정 무시
		round.frozen[runner] = nil
		runner:SetAttribute("ShieldUntil", os.clock() + 2)
		refresh(runner)
		return
	end
	if (runner:GetAttribute("ShieldUntil") or 0) > os.clock() then
		return
	end
	local character = runner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	round.frozen[runner] = os.clock()
	runner:SetAttribute("Frozen", true)
	root.Anchored = true
	setHighlight(character, Color3.fromRGB(120, 200, 255))

	local ice = Instance.new("Part")
	ice.Name = "IceBlock"
	ice.Anchored = true
	ice.CanCollide = false
	ice.CanQuery = false
	ice.Size = Vector3.new(5, 7, 5)
	ice.CFrame = root.CFrame * CFrame.new(0, -0.5, 0)
	ice.Color = Color3.fromRGB(170, 220, 255)
	ice.Material = Enum.Material.Ice
	ice.Transparency = 0.45
	ice.Parent = workspace
	round.ice[runner] = ice

	local data = DataService.Get(by)
	if data then
		data.freezes += 1
	end
	give(by, Config.Rewards.freeze, runner.DisplayName .. " 얼림!")
	notify(runner, "🧊 얼었어요! 친구가 와서 만지면 녹아요", Color3.fromRGB(140, 220, 255))
	broadcastRound()
end

local function thaw(runner, by)
	if not round.frozen[runner] then
		return
	end
	round.frozen[runner] = nil
	runner:SetAttribute("Frozen", false)
	local character = runner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = false
	end
	if character then
		setHighlight(character, nil)
	end
	if round.ice[runner] then
		round.ice[runner]:Destroy()
		round.ice[runner] = nil
	end
	runner:SetAttribute("ShieldUntil", os.clock() + 1.5) -- 녹자마자 다시 얼지 않게
	if by then
		local data = DataService.Get(by)
		if data then
			data.thaws += 1
		end
		give(by, Config.Rewards.thaw, runner.DisplayName .. " 구출!")
		notify(runner, "🔥 " .. by.DisplayName .. " 님이 녹여 줬어요!", Color3.fromRGB(255, 200, 140))
	end
	broadcastRound()
end

----------------------------------------------------------------------
-- 라운드 진행
----------------------------------------------------------------------
local function teleport(player, cf)
	local character = player.Character
	if character and character:FindFirstChild("HumanoidRootPart") then
		character:PivotTo(cf)
	end
end

local function chooseTaggers(list)
	local count = math.max(1, math.floor(#list / Config.PlayersPerTagger))
	local chosen = {}
	-- 1) 술래 확정 구매자 먼저
	for _, p in ipairs(list) do
		if forcedTaggers[p] and #chosen < count then
			table.insert(chosen, p)
			forcedTaggers[p] = nil
		end
	end
	-- 2) 나머지는 가중치 추첨 (술래 확률 UP 패스 = 3배)
	while #chosen < count do
		local pool, sum = {}, 0
		for _, p in ipairs(list) do
			if not table.find(chosen, p) then
				local w = Monetization.Owns(p, "TaggerChance") and 3 or 1
				table.insert(pool, { p = p, w = w })
				sum += w
			end
		end
		if #pool == 0 then
			break
		end
		local roll = math.random() * sum
		for _, e in ipairs(pool) do
			roll -= e.w
			if roll <= 0 then
				table.insert(chosen, e.p)
				break
			end
		end
	end
	return chosen
end

local function readyPlayers()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if DataService.Get(p) and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
			table.insert(list, p)
		end
	end
	return list
end

local function cleanupRound()
	for p in pairs(round.frozen) do
		thaw(p, nil)
	end
	for _, ice in pairs(round.ice) do
		ice:Destroy()
	end
	-- 방패(shields)는 쓰기 전까지 다음 라운드로 이어짐
	round.taggers, round.runners, round.frozen, round.ice = {}, {}, {}, {}
	for _, p in ipairs(Players:GetPlayers()) do
		setRole(p, "Lobby")
		p:SetAttribute("Frozen", false)
		teleport(p, lobbyCFrame + Vector3.new(math.random(-10, 10), 0, math.random(-10, 10)))
		refresh(p)
	end
end

local function endRound(winner)
	round.phase = "Ended"
	round.endsAt = os.clock() + 5
	local text
	if winner == "Runners" then
		text = "🔵 도망자 승리! 끝까지 살아남았어요!"
		for p in pairs(round.runners) do
			local data = DataService.Get(p)
			if data then
				data.wins += 1
			end
			give(p, Config.Rewards.win, "승리")
		end
	else
		text = "🔴 술래 승리! 모두 얼어 버렸어요!"
		for p in pairs(round.taggers) do
			local data = DataService.Get(p)
			if data then
				data.wins += 1
			end
			give(p, Config.Rewards.win, "승리")
		end
	end
	remotes.Announce:FireAllClients(text, 5)
	broadcastRound()
	task.wait(5)
	cleanupRound()
end

local function playRound()
	local list = readyPlayers()
	ArenaBuilder.BuildArena()
	local taggers = chooseTaggers(list)
	local runnerList = {}
	for _, p in ipairs(list) do
		if table.find(taggers, p) then
			round.taggers[p] = true
		else
			round.runners[p] = true
			table.insert(runnerList, p)
		end
		local data = DataService.Get(p)
		if data then
			data.rounds += 1
		end
		give(p, Config.Rewards.play, nil)
	end
	for i, p in ipairs(taggers) do
		setRole(p, "Tagger")
		teleport(p, ArenaBuilder.SpawnPoint(true, i, #taggers))
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root then
			root.Anchored = true -- 잠깐 묶어 둠
		end
		remotes.Announce:FireClient(p, "🔴 당신은 술래! " .. Config.TaggerReleaseDelay .. "초 뒤 출발, 모두 얼려요!", 4)
	end
	for i, p in ipairs(runnerList) do
		setRole(p, "Runner")
		teleport(p, ArenaBuilder.SpawnPoint(false, i, #runnerList))
		remotes.Announce:FireClient(p, "🔵 도망쳐요! 얼은 친구를 만지면 녹일 수 있어요", 4)
	end

	round.phase = "Playing"
	round.endsAt = os.clock() + Config.RoundTime
	broadcastRound()

	task.delay(Config.TaggerReleaseDelay, function()
		for p in pairs(round.taggers) do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root then
				root.Anchored = false
			end
		end
	end)

	local released = os.clock() + Config.TaggerReleaseDelay
	local lastSurviveTick = os.clock()
	while round.phase == "Playing" do
		task.wait(0.1)
		local now = os.clock()

		-- 판정
		if now >= released then
			for tagger in pairs(round.taggers) do
				local tr = tagger.Character and tagger.Character:FindFirstChild("HumanoidRootPart")
				if tr then
					for runner in pairs(round.runners) do
						if not round.frozen[runner] then
							local rr = runner.Character and runner.Character:FindFirstChild("HumanoidRootPart")
							if rr and (rr.Position - tr.Position).Magnitude <= Config.TagDistance then
								freeze(runner, tagger)
							end
						end
					end
				end
			end
		end
		for saver in pairs(round.runners) do
			if not round.frozen[saver] then
				local sr = saver.Character and saver.Character:FindFirstChild("HumanoidRootPart")
				if sr then
					for target, frozenAt in pairs(round.frozen) do
						local ice = round.ice[target]
						if ice and now - frozenAt >= Config.ThawCooldown and (ice.Position - sr.Position).Magnitude <= Config.TagDistance + 1 then
							thaw(target, saver)
						end
					end
				end
			end
		end

		-- 생존 보상
		if now - lastSurviveTick >= 10 then
			lastSurviveTick = now
			for runner in pairs(round.runners) do
				if not round.frozen[runner] then
					give(runner, Config.Rewards.surviveTick, nil)
				end
			end
			broadcastRound()
		end

		-- 승패
		local alive, total = countRunners()
		local taggersLeft = next(round.taggers) ~= nil
		if total == 0 or not taggersLeft then
			endRound("Runners")
		elseif alive == 0 then
			endRound("Taggers")
		elseif now >= round.endsAt then
			endRound("Runners")
		end
	end
end

task.spawn(function()
	while true do
		local list = readyPlayers()
		if #list < Config.MinPlayers then
			round.phase = "Waiting"
			broadcastRound()
			task.wait(2)
		else
			round.phase = "Intermission"
			round.endsAt = os.clock() + Config.Intermission
			while os.clock() < round.endsAt do
				broadcastRound()
				task.wait(1)
			end
			if #readyPlayers() >= Config.MinPlayers then
				playRound()
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
		SelfThaw = function(player, _data)
			if round.phase == "Playing" and round.frozen[player] then
				thaw(player, nil)
				notify(player, "🔥 스스로 녹았어요! 다시 도망쳐요!", Color3.fromRGB(255, 200, 140))
			else
				-- 라운드가 끝나 버렸으면 다음 라운드 방패로 바꿔 줌 (구매가 헛되지 않게)
				round.shields[player] = true
				notify(player, "라운드가 끝나서 🛡️ 얼음 방패로 바꿔 드렸어요", Color3.fromRGB(140, 220, 255))
			end
		end,
		IceShield = function(player, _data)
			round.shields[player] = true
			notify(player, "🛡️ 얼음 방패 장착! 한 번 얼지 않아요", Color3.fromRGB(140, 220, 255))
		end,
		BeTagger = function(player, _data)
			forcedTaggers[player] = true
			notify(player, "😈 다음 라운드 술래 확정!", Color3.fromRGB(255, 120, 120))
		end,
		Coins = function(player, data)
			data.coins += 500
			notify(player, "💰 코인 +500", Color3.fromRGB(255, 220, 120))
		end,
	},
	onPass = function(player, key)
		if key == "VIP" then
			player:SetAttribute("VIP", true)
			local data = DataService.Get(player)
			if data then
				data.trails.Gold = true
			end
		end
	end,
})

----------------------------------------------------------------------
-- 접속 / 퇴장
----------------------------------------------------------------------
local function onPlayerAdded(player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local coins = Instance.new("StringValue")
	coins.Name = "💰 코인"
	coins.Value = "0"
	coins.Parent = ls
	local wins = Instance.new("IntValue")
	wins.Name = "🏆 승리"
	wins.Parent = ls
	ls.Parent = player
	player:SetAttribute("Role", "Lobby")

	Monetization.LoadPlayer(player)
	if not DataService.Load(player) then
		return
	end
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		applyTrail(player, character)
		-- 라운드 중에 죽으면(낙사 등) 도망자는 얼은 상태로 취급
		if round.runners[player] and round.phase == "Playing" then
			teleport(player, ArenaBuilder.SpawnPoint(false, math.random(1, 8), 8))
		elseif round.taggers[player] and round.phase == "Playing" then
			setRole(player, "Tagger")
			teleport(player, ArenaBuilder.SpawnPoint(true, 1, 1))
		end
	end)
	if player.Character then
		applyTrail(player, player.Character)
	end
	refresh(player)
	broadcastRound()
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	round.taggers[player] = nil
	round.runners[player] = nil
	round.frozen[player] = nil
	round.shields[player] = nil
	forcedTaggers[player] = nil
	if round.ice[player] then
		round.ice[player]:Destroy()
		round.ice[player] = nil
	end
	DataService.Release(player)
	Monetization.RemovePlayer(player)
end)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

----------------------------------------------------------------------
-- 클라이언트 요청
----------------------------------------------------------------------
local actions = {}

function actions.BuyTrail(player, data, id)
	local def = Config.Trails[id]
	if not def then
		return false
	end
	if not data.trails[id] then
		if def.cost < 0 then
			return false, "VIP 전용 트레일이에요"
		end
		if data.coins < def.cost then
			return false, "코인이 부족해요"
		end
		data.coins -= def.cost
		data.trails[id] = true
	end
	data.trail = id
	applyTrail(player, player.Character)
	return true, def.name .. " 트레일 장착!"
end

local last = {}
actionRemote.OnServerInvoke = function(player, action, arg)
	if type(action) ~= "string" or not actions[action] then
		return false
	end
	if last[player] and os.clock() - last[player] < 0.15 then
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
