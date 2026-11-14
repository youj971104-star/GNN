-- ☁️ 구름 오비 서버
-- 체크포인트 저장, 함정, 스테이지 건너뛰기, 트레일, 환생

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local Monetization = require(script.Parent.Monetization)
local CourseBuilder = require(script.Parent.CourseBuilder)

DataService.Configure("CloudClimbData_v1", function()
	return {
		highest = 1, -- 가장 멀리 간 스테이지
		current = 1, -- 지금 서 있는 스테이지 (스테이지 선택으로 바꿀 수 있음)
		coins = 0,
		rebirths = 0,
		deaths = 0,
		trails = { Cloud = true },
		trail = "Cloud",
		receipts = {},
	}
end)

----------------------------------------------------------------------
-- 리모트
----------------------------------------------------------------------
local remoteFolder = Instance.new("Folder")
remoteFolder.Name = "Remotes"
local remotes = {}
for _, name in ipairs({ "State", "Notify", "Announce" }) do
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remoteFolder
	remotes[name] = r
end
local actionRemote = Instance.new("RemoteFunction")
actionRemote.Name = "Action"
actionRemote.Parent = remoteFolder
remoteFolder.Parent = ReplicatedStorage

local checkpoints, killParts = CourseBuilder.Build()
local FINISH = Config.StageCount + 1

local function notify(player, text, color)
	remotes.Notify:FireClient(player, text, color)
end

local function coinMultiplier(player, data)
	local m = 1 + data.rebirths * 0.5
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

-- 스테이지 선택기로 갈 수 있는 가장 높은 스테이지
local function selectMax(data)
	if RunService:IsStudio() and Config.StudioFreeStageSelect then
		return FINISH
	end
	return data.highest
end

local function refresh(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls["🏁 스테이지"].Value = data.highest
		ls["🔄 환생"].Value = data.rebirths
	end
	remotes.State:FireClient(player, {
		highest = data.highest,
		current = data.current,
		coins = data.coins,
		rebirths = data.rebirths,
		deaths = data.deaths,
		trails = data.trails,
		trail = data.trail,
		passes = Monetization.GetOwned(player),
		coinMult = coinMultiplier(player, data),
		stageCount = Config.StageCount,
		selectMax = selectMax(data),
	})
end

----------------------------------------------------------------------
-- 캐릭터: 체크포인트에서 부활, 패스 효과, 트레일
----------------------------------------------------------------------
local function applyCharacter(player, character)
	local data = DataService.Get(player)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (data and humanoid and root) then
		return
	end
	humanoid.WalkSpeed = Monetization.Owns(player, "Speed") and 22 or 16
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = Monetization.Owns(player, "HighJump") and 9.4 or 7.2

	-- 트레일
	local old = root:FindFirstChild("PlayerTrail")
	if old then
		old:Destroy()
	end
	local def = Config.Trails[data.trail] or Config.Trails.Cloud
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
	trail.Lifetime = 0.6
	trail.LightEmission = 0.6
	trail.Transparency = NumberSequence.new(0.1, 1)
	local keypoints = {}
	for i, c in ipairs(def.colors) do
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / math.max(1, #def.colors - 1), c))
	end
	if #keypoints == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, def.colors[1]))
	end
	trail.Color = ColorSequence.new(keypoints)
	trail.Parent = root
end

local function teleportTo(player, stage)
	local character = player.Character
	local pad = checkpoints[stage]
	if character and pad then
		player:SetAttribute("SafeUntil", os.clock() + Config.Kill.spawnProtection)
		character:PivotTo(pad.CFrame + Vector3.new(0, 4, 0))
	end
end

----------------------------------------------------------------------
-- 체크포인트 / 함정
----------------------------------------------------------------------
local function reachStage(player, data, stage)
	if stage > data.current then
		data.current = stage
	end
	if stage > data.highest then
		local firstTime = stage
		data.highest = stage
		local reward = math.floor(Config.StageReward(firstTime - 1, data.rebirths) * coinMultiplier(player, data))
		data.coins += reward
		if stage == FINISH then
			remotes.Announce:FireAllClients(string.format("🏆 %s 님이 정상에 올랐어요! (%d번째 환생 가능)", player.DisplayName, data.rebirths + 1), 6)
		elseif stage % 25 == 0 then
			remotes.Announce:FireAllClients(string.format("🚩 %s 님이 %d 스테이지 돌파!", player.DisplayName, stage), 4)
		else
			notify(player, string.format("🚩 스테이지 %d · +%s 코인", stage, Format.Short(reward)), Color3.fromRGB(255, 220, 120))
		end
	end
	refresh(player)
end

for stage, pad in pairs(checkpoints) do
	pad.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		local data = player and DataService.Get(player)
		if not data then
			return
		end
		-- 스테이지 선택으로 뒤로 간 경우, 앞쪽 체크포인트를 밟아야만 진행
		if stage > data.current and stage <= data.highest + 1 then
			reachStage(player, data, stage)
		elseif stage > data.highest + 1 then
			-- 다른 길로 건너뛴 경우(버그/점프) 는 인정하지 않음
			return
		end
	end)
end

local function killFromHit(hit)
	-- 액세서리(머리카락·모자)는 Accessory 안에 있어서 hit.Parent 가 캐릭터가 아님
	local character = hit.Parent
	if not Config.Kill.ignoreAccessories and character and character:IsA("Accessory") then
		character = character.Parent
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local player = humanoid and Players:GetPlayerFromCharacter(character)
	if not (player and humanoid.Health > 0) then
		return
	end
	if (player:GetAttribute("SafeUntil") or 0) > os.clock() then
		return
	end
	humanoid.Health = 0
end
for _, part in ipairs(killParts) do
	part.Touched:Connect(killFromHit)
end

-- 사라지는 발판
for _, part in ipairs(workspace.Course:GetDescendants()) do
	if part:IsA("BasePart") and part:GetAttribute("Vanish") then
		local busy = false
		part.Touched:Connect(function(hit)
			if busy or not Players:GetPlayerFromCharacter(hit.Parent) then
				return
			end
			busy = true
			TweenService:Create(part, TweenInfo.new(0.6), { Transparency = 0.9 }):Play()
			task.wait(0.6)
			part.CanCollide = false
			task.wait(2.2)
			part.CanCollide = true
			TweenService:Create(part, TweenInfo.new(0.3), { Transparency = 0.2 }):Play()
			task.wait(0.3)
			busy = false
		end)
	end
end

-- 떨어지면 바로 체크포인트로 (죽음 카운트는 올림)
task.spawn(function()
	while true do
		task.wait(0.25)
		for _, player in ipairs(Players:GetPlayers()) do
			local data = DataService.Get(player)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local pad = data and checkpoints[data.current]
			if root and pad and root.Position.Y < pad.Position.Y - 45 then
				data.deaths += 1
				teleportTo(player, data.current)
			end
		end
	end
end)

----------------------------------------------------------------------
-- 결제
----------------------------------------------------------------------
local function skip(player, data, n)
	local target = math.min(data.current + n, FINISH)
	for s = data.current + 1, target do
		reachStage(player, data, s)
	end
	data.current = target
	teleportTo(player, target)
	notify(player, "⏭️ 스테이지 " .. target .. " 으로 이동!", Color3.fromRGB(140, 220, 255))
end

DataService.Start()
Monetization.Start({
	notify = notify,
	refresh = refresh,
	productHandlers = {
		SkipStage = function(player, data)
			skip(player, data, 1)
		end,
		Skip5 = function(player, data)
			skip(player, data, 5)
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
		if player.Character then
			applyCharacter(player, player.Character)
		end
	end,
})

----------------------------------------------------------------------
-- 접속 / 퇴장
----------------------------------------------------------------------
local function onPlayerAdded(player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local st = Instance.new("IntValue")
	st.Name = "🏁 스테이지"
	st.Parent = ls
	local rb = Instance.new("IntValue")
	rb.Name = "🔄 환생"
	rb.Parent = ls
	ls.Parent = player

	Monetization.LoadPlayer(player)
	local data = DataService.Load(player)
	if not data then
		return
	end
	data.current = data.highest -- 접속하면 가장 높은 곳에서 시작

	local function onCharacter(character)
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait(0.1)
		teleportTo(player, data.current)
		applyCharacter(player, character)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Died:Connect(function()
				data.deaths += 1
			end)
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	refresh(player)
	notify(player, "정상까지 " .. Config.StageCount .. " 스테이지! 빨간 건 밟으면 안 돼요 🔥", Color3.fromRGB(220, 230, 255))
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
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

function actions.SetStage(player, data, stage)
	stage = tonumber(stage)
	if not stage then
		return false
	end
	stage = math.clamp(math.floor(stage), 1, selectMax(data))
	data.current = stage
	teleportTo(player, stage)
	return true
end

function actions.BuyTrail(player, data, id)
	local def = Config.Trails[id]
	if not def then
		return false
	end
	if data.trails[id] then
		data.trail = id
		if player.Character then
			applyCharacter(player, player.Character)
		end
		return true, def.name .. " 트레일 장착!"
	end
	if def.cost < 0 then
		return false, "VIP 전용 트레일이에요"
	end
	if data.coins < def.cost then
		return false, "코인이 부족해요"
	end
	data.coins -= def.cost
	data.trails[id] = true
	data.trail = id
	if player.Character then
		applyCharacter(player, player.Character)
	end
	return true, def.name .. " 트레일 구매!"
end

function actions.Rebirth(player, data)
	if data.highest < FINISH then
		return false, "정상에 도착해야 환생할 수 있어요"
	end
	data.rebirths += 1
	data.highest = 1
	data.current = 1
	teleportTo(player, 1)
	remotes.Announce:FireAllClients(string.format("🔄 %s 님이 %d번째 환생! 처음부터 다시 도전!", player.DisplayName, data.rebirths), 5)
	return true, "환생 완료! 코인 배율 x" .. (1 + data.rebirths * 0.5)
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
