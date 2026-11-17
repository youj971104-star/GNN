-- GolfHitEffectFancy (ModuleScript) - 화려한 버전
-- 위치: ReplicatedStorage > Shared > GolfHitEffectFancy (Rojo 로 동기화)
-- 팝골프 연결: 공을 맞히면 서버가 Impact(kind = "ballhit")를 보내고, 각 화면의 VFX 가 FX.Play 를 부름
--
-- 사용법:
--   local FX = require(game.ReplicatedStorage.GolfHitEffectFancy)
--   FX.Play(hitPosition, hitDirection, power)   -- power: 0~1
--   FX.AttachTrail(ballPart)                    -- 공에 꼬리(트레일) 붙이기 (한 번만)
--   FX.Shake(power)                             -- 카메라 흔들림 (LocalScript에서만)

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local FX = {}

-- 모델러 이펙트 이미지가 있으면 그걸 쓰고, 없으면 로블록스 기본 이미지
local STAR = Config.FXTexture("Spark", "rbxasset://textures/particles/sparkles_main.dds")
local SMOKE = Config.FXTexture("Smoke", "rbxasset://textures/particles/smoke_main.dds")

-- 이펙트 부품은 한 폴더에 모아 둠 (workspace 가 지저분해지지 않게)
local fxFolder = workspace:FindFirstChild("HitFX") or Instance.new("Folder")
fxFolder.Name = "HitFX"
fxFolder.Parent = workspace

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 80, 80)),
	ColorSequenceKeypoint.new(0.20, Color3.fromRGB(255, 200, 60)),
	ColorSequenceKeypoint.new(0.40, Color3.fromRGB(120, 255, 120)),
	ColorSequenceKeypoint.new(0.60, Color3.fromRGB(80, 220, 255)),
	ColorSequenceKeypoint.new(0.80, Color3.fromRGB(160, 100, 255)),
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 100, 220)),
})

local function anchorPart(cf)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = cf
	p.Parent = fxFolder
	return p
end

local function neonPart(shape, color, size, cf)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Parent = fxFolder
	return p
end

local function tween(inst, t, props, style)
	TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quart, Enum.EasingDirection.Out), props):Play()
end

-- 1) 중앙 플래시 + 점광원
local function flash(pos, power)
	local f = neonPart(Enum.PartType.Ball, Color3.fromRGB(255, 252, 210), Vector3.one * 0.5, CFrame.new(pos))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 240, 180)
	light.Range = 20 + power * 20
	light.Brightness = 6
	light.Parent = f

	tween(f, 0.22, { Size = Vector3.one * (4 + power * 6), Transparency = 1 })
	tween(light, 0.3, { Brightness = 0 })
	Debris:AddItem(f, 0.4)
end

-- 2) 충격파 링 (2겹, 색 다르게, 약간 시차)
local function ring(pos, dir, color, startDelay, diameter, duration)
	task.delay(startDelay, function()
		local r = neonPart(
			Enum.PartType.Cylinder,
			color,
			Vector3.new(0.15, 1, 1),
			CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, math.rad(90), 0)
		)
		r.Transparency = 0.1
		tween(r, duration, { Size = Vector3.new(0.15, diameter, diameter), Transparency = 1 })
		Debris:AddItem(r, duration + 0.1)
	end)
end

-- 3) 방사형 빛줄기 (별 모양 폭발)
local function rays(pos, dir, power)
	local count = 10
	local length = 8 + power * 10
	local up = math.abs(dir.Y) > 0.95 and Vector3.xAxis or Vector3.yAxis
	local base = CFrame.lookAt(pos, pos + dir, up)

	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local sideways = base:VectorToWorldSpace(Vector3.new(math.cos(angle), math.sin(angle), 0))
		local len = length * (0.6 + math.random() * 0.5)
		local cf = CFrame.lookAt(pos, pos + sideways) * CFrame.new(0, 0, -0.3)
		local ray = neonPart(
			Enum.PartType.Block,
			(i % 2 == 0) and Color3.fromRGB(255, 240, 140) or Color3.fromRGB(255, 255, 255),
			Vector3.new(0.12, 0.12, 0.3),
			cf
		)
		tween(ray, 0.3, {
			Size = Vector3.new(0.02, 0.02, len),
			CFrame = cf * CFrame.new(0, 0, -len / 2),
			Transparency = 1,
		})
		Debris:AddItem(ray, 0.4)
	end
end

-- 4) 무지개 스트릭 스파크 (속도 방향으로 길게 늘어남)
local function streaks(pos, dir, power)
	local a = anchorPart(CFrame.lookAt(pos, pos + dir))
	local e = Instance.new("ParticleEmitter")
	e.Texture = STAR
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.EmissionDirection = Enum.NormalId.Front
	e.Color = RAINBOW
	e.LightEmission = 1
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Squash = NumberSequence.new(-2)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(0.4, 0.8)
	e.Speed = NumberRange.new(25 + power * 30, 55 + power * 50)
	e.SpreadAngle = Vector2.new(40, 40)
	e.Drag = 3
	e.Rate = 0
	e.Enabled = false
	e.Parent = a
	e:Emit(math.floor(25 + power * 40))
	Debris:AddItem(a, 1.2)
end

-- 5) 반짝이 별가루 (사방으로 퍼졌다가 천천히 떨어짐)
local function glitter(pos, power)
	local a = anchorPart(CFrame.new(pos))
	local e = Instance.new("ParticleEmitter")
	e.Texture = STAR
	e.Color = ColorSequence.new(Color3.fromRGB(255, 255, 200), Color3.fromRGB(255, 220, 100))
	e.LightEmission = 1
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 1.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-180, 180)
	e.Lifetime = NumberRange.new(0.8, 1.6)
	e.Speed = NumberRange.new(8, 18 + power * 12)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -12, 0)
	e.Drag = 1.5
	e.Rate = 0
	e.Enabled = false
	e.Parent = a
	e:Emit(math.floor(20 + power * 30))
	Debris:AddItem(a, 2)
end

-- 6) 잔디 먼지
local function dust(pos, power)
	local a = anchorPart(CFrame.new(pos))
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE
	e.EmissionDirection = Enum.NormalId.Top
	e.Color = ColorSequence.new(Color3.fromRGB(120, 175, 90)) -- 모래: (215,195,145)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 4 + power * 3),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(0.6, 1.1)
	e.Speed = NumberRange.new(5, 10 + power * 8)
	e.SpreadAngle = Vector2.new(65, 65)
	e.Acceleration = Vector3.new(0, -5, 0)
	e.Rate = 0
	e.Enabled = false
	e.Parent = a
	e:Emit(math.floor(8 + power * 10))
	Debris:AddItem(a, 1.6)
end

function FX.Play(position, direction, power)
	power = math.clamp(power or 0.5, 0, 1)
	direction = (direction and direction.Magnitude > 0) and direction.Unit or Vector3.yAxis

	flash(position, power)
	rays(position, direction, power)
	ring(position, direction, Color3.fromRGB(255, 255, 255), 0, 8 + power * 12, 0.4)
	ring(position, direction, Color3.fromRGB(120, 220, 255), 0.06, 12 + power * 16, 0.55)
	streaks(position, direction, power)
	glitter(position, power)
	dust(position, power)
end

-- 공 꼬리 (Trail): 공 Part에 한 번만 붙이세요
function FX.AttachTrail(ball)
	if ball:FindFirstChild("HitTrail") then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, ball.Size.Y * 0.4, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -ball.Size.Y * 0.4, 0)
	a1.Parent = ball

	local t = Instance.new("Trail")
	t.Name = "HitTrail"
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Lifetime = 0.5
	t.LightEmission = 1
	t.Color = RAINBOW
	t.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	t.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	t.Parent = ball
end

-- 카메라 흔들림 (LocalScript에서만 호출)
function FX.Shake(power)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	power = math.clamp(power or 0.5, 0, 1)
	local duration = 0.25
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - start) / duration
		if t >= 1 then
			conn:Disconnect()
			return
		end
		local s = (1 - t) * power * 0.35
		cam.CFrame = cam.CFrame * CFrame.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
	end)
end

return FX
