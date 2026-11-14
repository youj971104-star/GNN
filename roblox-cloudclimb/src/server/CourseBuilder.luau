-- 오비 코스를 코드로 생성합니다.
-- 같은 Seed 면 모든 서버에서 똑같은 코스가 만들어집니다.
-- 장애물 종류: 점프 발판, 용암 줄, 움직이는 발판, 사라지는 발판, 회전 막대, 사다리(트러스), 좁은 다리

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local CourseBuilder = {}

local UP = Vector3.new(0, 1, 0)
local KILL_COLOR = Color3.fromRGB(255, 60, 60)

local course -- Folder
local movers = {} -- { constraint, range, period }
local killParts = {}

local function lerp(a, b, t)
	return a + (b - a) * t
end

local D = Config.Difficulty
-- Config.Difficulty 의 { 쉬움, 어려움 } 값을 난이도 d(0~1)에 맞게 섞음
local function tune(pair, d)
	return lerp(pair[1], pair[2], d)
end

-- center: 윗면 중앙이 아니라 파트 중심. dir 방향으로 length, 옆으로 width
local function block(center, dir, width, height, length, color, material, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = Vector3.new(width, height, length)
	p.CFrame = CFrame.lookAt(center, center + dir)
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent or course
	return p
end

-- 윗면이 top 높이에 오도록 발판을 놓음
local function platform(topCenter, dir, width, length, color, parent)
	return block(topCenter - UP * 0.5, dir, width, 1, length, color, Enum.Material.SmoothPlastic, parent)
end

-- 보이는 빨간 블록은 장식이고, 실제 판정은 안쪽의 조금 작은 투명 상자(Hitbox)가 담당
local function makeKill(part)
	part.Color = KILL_COLOR
	part.Material = Enum.Material.Neon
	part.CanCollide = false -- 빨간 블록 위에 서는 일 없이 통과하다가 안쪽 판정에 닿으면 죽음
	part.CanTouch = false

	local margin = Config.Kill.margin * 2
	local hitbox = Instance.new("Part")
	hitbox.Name = "KillHitbox"
	hitbox.Size = Vector3.new(
		math.max(0.2, part.Size.X - margin),
		math.max(0.2, part.Size.Y - margin),
		math.max(0.2, part.Size.Z - margin)
	)
	hitbox.CFrame = part.CFrame
	hitbox.Transparency = 1
	hitbox.CanCollide = false
	hitbox.CanQuery = false
	hitbox.Anchored = part.Anchored
	hitbox.Massless = true
	if not part.Anchored then
		-- 회전 막대처럼 움직이는 함정은 판정 상자를 붙여서 같이 움직이게
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = hitbox
		weld.Parent = hitbox
	end
	hitbox:SetAttribute("Kill", true)
	hitbox.Parent = part.Parent
	table.insert(killParts, hitbox)
	return part
end

----------------------------------------------------------------------
-- 장애물 모듈: (cursor, dir, d(0~1 난이도), rng, zone) → 새 cursor
-- cursor = 마지막 발판 윗면의 '앞쪽 끝' 지점
----------------------------------------------------------------------
local modules = {}

modules.jumps = function(cursor, dir, d, rng, zone)
	local right = dir:Cross(UP)
	local count = 3 + math.floor(d * 3)
	for _ = 1, count do
		local size = tune(D.jumpPadSize, d)
		local gap = tune(D.jumpGap, d) + rng:NextNumber(-0.4, 0.4)
		local rise = rng:NextNumber(0, 1.5)
		local side = rng:NextNumber(-3, 3) * d
		local top = cursor + dir * (gap + size / 2) + UP * rise + right * side
		platform(top, dir, size, size, zone.color)
		cursor = top + dir * (size / 2)
	end
	return cursor
end

modules.lavaStrip = function(cursor, dir, d, rng, zone)
	local length = 26
	local top = cursor + dir * (length / 2 + 0.2)
	platform(top, dir, 8, length, zone.color)
	local bars = math.floor(tune(D.lavaBars, d) + 0.5)
	for i = 1, bars do
		local along = -length / 2 + (i / (bars + 1)) * length
		local bar = block(top + dir * along + UP * 0.75, dir, 8, 1.5, 1.4, KILL_COLOR, Enum.Material.Neon)
		makeKill(bar)
	end
	return top + dir * (length / 2)
end

modules.moving = function(cursor, dir, d, rng, zone)
	local count = 2 + (d > 0.6 and 1 or 0)
	for _ = 1, count do
		local gap = 3
		local size = lerp(7, 5, d)
		local top = cursor + dir * (gap + size / 2)
		local center = top - UP * 0.5

		local base = block(center, dir, 1, 1, 1, zone.color, nil)
		base.Transparency = 1
		base.CanCollide = false
		base.CanQuery = false

		local plat = block(center, dir, size, 1, size, zone.accent, Enum.Material.SmoothPlastic)
		plat.Anchored = false
		local a0 = Instance.new("Attachment")
		a0.Parent = base
		local a1 = Instance.new("Attachment")
		a1.Parent = plat
		local prism = Instance.new("PrismaticConstraint")
		prism.Attachment0 = a0
		prism.Attachment1 = a1
		prism.ActuatorType = Enum.ActuatorType.Servo
		prism.ServoMaxForce = 1e7
		prism.Speed = tune(D.movingSpeed, d)
		prism.LinearResponsiveness = 60
		prism.Parent = plat
		local range = lerp(4, 9, d)
		table.insert(movers, { constraint = prism, range = range, period = (2 * range) / prism.Speed + 1, offset = rng:NextNumber(0, 2), part = plat })
		cursor = top + dir * (size / 2)
	end
	-- 착지 발판
	local land = cursor + dir * 3.5
	platform(land, dir, 6, 4, zone.color)
	return land + dir * 2
end

modules.vanish = function(cursor, dir, d, rng, zone)
	local count = 4 + math.floor(d * 2)
	for _ = 1, count do
		local size = 5
		local gap = tune(D.vanishGap, d)
		local top = cursor + dir * (gap + size / 2) + UP * rng:NextNumber(-0.5, 0.8)
		local p = platform(top, dir, size, size, Color3.fromRGB(255, 255, 255))
		p.Material = Enum.Material.Glass
		p.Transparency = 0.2
		p:SetAttribute("Vanish", true)
		cursor = top + dir * (size / 2)
	end
	return cursor
end

modules.spinner = function(cursor, dir, d, rng, zone)
	local length = 24
	local top = cursor + dir * (length / 2 + 0.2)
	platform(top, dir, 16, length, zone.color)

	local pivotPos = top + UP * 1.8
	local pivot = block(pivotPos, dir, 1.6, 1, 1.6, Color3.fromRGB(60, 60, 70), Enum.Material.Metal)
	pivot.CanCollide = false
	local bar = block(pivotPos, dir, 1, 1, tune(D.spinnerLength, d), KILL_COLOR, Enum.Material.Neon)
	bar.Anchored = false
	bar.CanCollide = false
	bar.Massless = true
	makeKill(bar)

	local rot = CFrame.Angles(0, 0, math.rad(90)) -- 어태치먼트의 X축을 위쪽으로
	local a0 = Instance.new("Attachment")
	a0.CFrame = rot
	a0.Parent = pivot
	local a1 = Instance.new("Attachment")
	a1.CFrame = rot
	a1.Parent = bar
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = a0
	hinge.Attachment1 = a1
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.MotorMaxTorque = 1e9
	hinge.MotorMaxAcceleration = 1e9
	hinge.AngularVelocity = tune(D.spinnerSpeed, d) * (rng:NextNumber() < 0.5 and 1 or -1)
	hinge.Parent = bar
	table.insert(movers, { part = bar })
	return top + dir * (length / 2)
end

modules.truss = function(cursor, dir, d, rng, zone)
	local height = math.floor(lerp(10, 18, d))
	local truss = Instance.new("TrussPart")
	truss.Anchored = true
	truss.Size = Vector3.new(2, height, 2)
	truss.CFrame = CFrame.lookAt(cursor + dir * 1 + UP * (height / 2), cursor + dir * 2 + UP * (height / 2))
	truss.Color = zone.accent
	truss.Parent = course
	local top = cursor + dir * 5 + UP * height
	platform(top, dir, 6, 6, zone.color)
	return top + dir * 3
end

modules.beam = function(cursor, dir, d, rng, zone)
	local length = lerp(16, 26, d)
	local width = tune(D.beamWidth, d)
	local top = cursor + dir * (length / 2 + 1)
	local beam = platform(top, dir, width, length, zone.accent)
	beam.Material = Enum.Material.WoodPlanks
	-- 어려운 단계에선 좁은 다리 옆에 용암 바닥
	if d > 0.5 then
		local lava = block(top - UP * 3, dir, 10, 1, length, KILL_COLOR, Enum.Material.Neon)
		makeKill(lava)
	end
	local land = top + dir * (length / 2 + 3)
	platform(land, dir, 6, 6, zone.color)
	return land + dir * 3
end

-- 장애물 등장 순서 (몇 스테이지부터인지는 Config.Difficulty.unlock)
local MODULE_ORDER = { "jumps", "beam", "truss", "lavaStrip", "spinner", "moving", "vanish" }

----------------------------------------------------------------------
-- 체크포인트
----------------------------------------------------------------------
local function billboard(part, text, color)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 50)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.MaxDistance = 120
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	gui.Parent = part
end

local function checkpoint(top, dir, stage, zone, isFinish)
	local pad = platform(top + dir * 5, dir, 10, 10, isFinish and Color3.fromRGB(255, 215, 90) or zone.accent)
	pad.Name = "Checkpoint" .. stage
	pad.Material = Enum.Material.Neon
	pad:SetAttribute("Stage", stage)
	local label = isFinish and "🏆 정상!" or ("🚩 " .. stage)
	billboard(pad, label, isFinish and Color3.fromRGB(255, 215, 90) or Color3.new(1, 1, 1))
	return pad, top + dir * 10
end

----------------------------------------------------------------------
-- 전체 코스
----------------------------------------------------------------------
function CourseBuilder.Build()
	Lighting.ClockTime = 14
	Lighting.Brightness = 2.5
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmo = Instance.new("Atmosphere")
		atmo.Density = 0.25
		atmo.Color = Color3.fromRGB(200, 225, 255)
		atmo.Haze = 1
		atmo.Parent = Lighting
	end
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	Players.RespawnTime = Config.RespawnTime

	course = Instance.new("Folder")
	course.Name = "Course"
	course.Parent = workspace

	local rng = Random.new(Config.Seed)
	local checkpoints = {}
	local cursor = Vector3.new(0, 40, 0)

	-- 시작 섬
	local startDir = Vector3.new(1, 0, 0)
	platform(cursor - startDir * 10, startDir, 24, 24, Config.Zones[1].color)
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(cursor - startDir * 14 + UP * 0.5)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 0.5
	spawn.Color = Color3.fromRGB(255, 255, 255)
	spawn.Parent = course

	for stage = 1, Config.StageCount + 1 do
		local zone = Config.ZoneFor(stage)
		-- 5 스테이지마다 진행 방향을 +X / +Z 로 번갈아 → 계단식 대각선 코스 (겹치지 않음)
		local dir = (math.floor((stage - 1) / 5) % 2 == 0) and Vector3.new(1, 0, 0) or Vector3.new(0, 0, 1)
		local isFinish = stage == Config.StageCount + 1
		local pad
		pad, cursor = checkpoint(cursor, dir, stage, zone, isFinish)
		checkpoints[stage] = pad
		if isFinish then
			break
		end

		-- 이 스테이지의 장애물 2~3개
		local d = math.clamp((stage - 1) / (Config.StageCount - 1), 0, 1) ^ D.curve
		local available = {}
		for _, name in ipairs(MODULE_ORDER) do
			if stage >= (D.unlock[name] or 1) then
				table.insert(available, name)
			end
		end
		local count = stage <= D.twoObstaclesUntil and 2 or 3
		local startY = cursor.Y
		for _ = 1, count do
			local name = available[rng:NextInteger(1, #available)]
			cursor = modules[name](cursor, dir, d, rng, zone)
		end
		-- 높이를 일정하게 올려서 다음 체크포인트로 이어 줌
		local targetY = startY + Config.StageRise
		if cursor.Y < targetY then
			local stepTop = Vector3.new(cursor.X, targetY, cursor.Z) + dir * 4
			platform(stepTop, dir, 6, 5, zone.color)
			cursor = stepTop + dir * 2.5
		end
	end

	-- 움직이는 장애물: 서버가 물리를 담당 (모든 플레이어에게 같은 위치)
	for _, m in ipairs(movers) do
		if m.part and m.part.Parent then
			pcall(function()
				m.part:SetNetworkOwner(nil)
			end)
		end
	end
	task.spawn(function()
		local t = 0
		while true do
			task.wait(0.1)
			t += 0.1
			for _, m in ipairs(movers) do
				if m.constraint then
					local phase = math.floor((t + m.offset) / m.period) % 2
					m.constraint.TargetPosition = phase == 0 and m.range or -m.range
				end
			end
		end
	end)

	return checkpoints, killParts
end

return CourseBuilder
