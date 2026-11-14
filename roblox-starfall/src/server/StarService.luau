-- 각 플레이어 땅에 별을 떨어뜨리고, 자석 범위 안에 들어온 별을 주워 담습니다.
-- 줍기 판정은 서버에서만 합니다 (클라이언트 핵으로 별을 원격 수집 못 하게).

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local StarService = {}

local ctx -- Main 에서 넘겨주는 공용 함수들
local starsRoot
local plotState = {} -- [plotModel] = { owner = Player, timer = 0, folder = Folder }

local function rollRarity(luck)
	-- 행운은 일반 등급을 제외한 모든 등급의 가중치를 곱해 줌
	local weights = {}
	local sum = 0
	for i, r in ipairs(Config.Rarities) do
		local w = r.weight
		if i > 1 then
			w *= luck
		end
		weights[i] = w
		sum += w
	end
	local roll = math.random() * sum
	for i, w in ipairs(weights) do
		roll -= w
		if roll <= 0 then
			return Config.Rarities[i]
		end
	end
	return Config.Rarities[1]
end

local function spawnStar(plot, state, luck)
	if #state.folder:GetChildren() >= Config.MaxStarsPerPlot then
		return
	end
	local floor = plot:FindFirstChild("Floor")
	if not floor then
		return
	end
	local rarity = rollRarity(luck)
	local half = floor.Size.X / 2 - 5
	local x = floor.Position.X + (math.random() * 2 - 1) * half
	local z = floor.Position.Z + (math.random() * 2 - 1) * half
	local groundY = floor.Position.Y + floor.Size.Y / 2 + rarity.size / 2 + 0.5

	local star = Instance.new("Part")
	star.Name = "Star"
	star.Shape = Enum.PartType.Ball
	star.Size = Vector3.one * rarity.size
	star.Material = Enum.Material.Neon
	star.Color = rarity.color
	star.Anchored = true
	star.CanCollide = false
	star.CanTouch = false
	star.CanQuery = false
	star.CastShadow = false
	star.Position = Vector3.new(x, groundY + 90, z)
	star:SetAttribute("Rarity", rarity.id)
	star:SetAttribute("Value", rarity.value)
	star:SetAttribute("Born", os.clock())

	if rarity.id ~= "Common" then
		local light = Instance.new("PointLight")
		light.Color = rarity.color
		light.Range = 8 + rarity.size * 3
		light.Brightness = 2
		light.Parent = star
	end
	local trail = Instance.new("Trail")
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, rarity.size / 2, 0)
	a0.Parent = star
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -rarity.size / 2, 0)
	a1.Parent = star
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.35
	trail.Color = ColorSequence.new(rarity.color)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.LightEmission = 1
	trail.Parent = star

	star.Parent = state.folder

	local fall = 1.1 + math.random() * 0.6
	TweenService:Create(star, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = Vector3.new(x, groundY, z),
	}):Play()

	if rarity.id == "Legendary" or rarity.id == "Cosmic" then
		ctx.notify(state.owner, rarity.name .. " 별이 떨어졌어요! ✨", rarity.color)
	end
end

function StarService.AssignPlot(plot, player)
	local folder = Instance.new("Folder")
	folder.Name = tostring(player.UserId)
	folder.Parent = starsRoot
	plotState[plot] = { owner = player, timer = 0, folder = folder, fullWarned = 0 }
end

function StarService.ReleasePlot(plot)
	local state = plotState[plot]
	if state then
		state.folder:Destroy()
		plotState[plot] = nil
	end
end

local function collectLoop()
	local lastSpawnTick = os.clock()
	while true do
		task.wait(0.1)
		local now = os.clock()
		local dt = now - lastSpawnTick
		lastSpawnTick = now

		for plot, state in pairs(plotState) do
			local player = state.owner
			local data = ctx.getData(player)
			if not (player.Parent and data) then
				continue
			end
			local stats = ctx.getStats(player, data)

			-- 1) 별 소환
			state.timer += dt
			local guard = 0
			while state.timer >= stats.interval and guard < 5 do
				state.timer -= stats.interval
				guard += 1
				spawnStar(plot, state, stats.luck)
			end

			-- 2) 오래된 별 정리
			for _, star in ipairs(state.folder:GetChildren()) do
				if now - (star:GetAttribute("Born") or now) > Config.StarLifetime then
					star:Destroy()
				end
			end

			-- 3) 줍기
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not (root and humanoid and humanoid.Health > 0) then
				continue
			end
			local pos = root.Position
			local changed = false
			for _, star in ipairs(state.folder:GetChildren()) do
				local sp = star.Position
				local flat = Vector3.new(sp.X - pos.X, 0, sp.Z - pos.Z).Magnitude
				if flat <= stats.magnet and math.abs(sp.Y - pos.Y) < 20 then
					if data.bag.count >= stats.bagCap then
						if stats.autoSell then
							ctx.sell(player, data, true)
						else
							if now - state.fullWarned > 4 then
								state.fullWarned = now
								ctx.notify(player, "가방이 가득 찼어요! 초록색 판매 발판으로 가세요 💰", Color3.fromRGB(255, 120, 120))
							end
							break
						end
					end
					local value = star:GetAttribute("Value") or 1
					local rarity = star:GetAttribute("Rarity")
					data.bag.count += 1
					data.bag.value += value
					data.starsCollected += 1
					star:Destroy()
					changed = true
					ctx.remotes.Collect:FireClient(player, sp, rarity, value)
				end
			end
			if changed then
				if stats.autoSell and data.bag.count >= stats.bagCap then
					ctx.sell(player, data, true)
				end
				ctx.remotes.Bag:FireClient(player, data.bag.count, data.bag.value, stats.bagCap)
			end
		end
	end
end

function StarService.Start(context)
	ctx = context
	starsRoot = Instance.new("Folder")
	starsRoot.Name = "Stars"
	starsRoot.Parent = workspace
	task.spawn(collectLoop)
end

StarService.RollRarity = rollRarity
return StarService
