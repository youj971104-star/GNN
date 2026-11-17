-- 골프채 스킨 연출 (내 화면에서만 그림 → 서버 부담 없음)
-- * 모든 플레이어의 골프채에 등급별 효과: 빛 입자, 도는 빛구슬, 회전 고리, 숨 쉬는 빛, 무지개색
-- * 휘두를 때: 입자 폭발 + 충격파 고리 (+ 내 화면 살짝 펀치)
-- * 메뉴용 3D 미리보기 (ViewportFrame 에서 빙글빙글)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local ClubFX = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- 로블록스에 기본으로 들어 있는 입자 그림
local TEXTURES = {
	sparkle = Config.FXTexture("Spark", "rbxasset://textures/particles/sparkles_main.dds"),
	fire = Config.FXTexture("Energy", "rbxasset://textures/particles/fire_main.dds"),
	smoke = Config.FXTexture("Smoke", "rbxasset://textures/particles/smoke_main.dds"),
}

local fxFolder = Instance.new("Folder")
fxFolder.Name = "ClubFX"
fxFolder.Parent = workspace

local active = {} -- [Tool] = entry
local previews = {} -- { {model, viewport, skinId, angle} }

local function colorSeq(colors)
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local kps = {}
	for i, c in ipairs(colors) do
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
	end
	return ColorSequence.new(kps)
end

local function glowPart(shape, size, color)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

----------------------------------------------------------------------
-- 골프채에 연출 붙이기 / 떼기
----------------------------------------------------------------------
local function detach(tool)
	local e = active[tool]
	if not e then
		return
	end
	for _, inst in ipairs(e.cleanup) do
		if typeof(inst) == "RBXScriptConnection" then
			inst:Disconnect()
		else
			inst:Destroy()
		end
	end
	active[tool] = nil
end

----------------------------------------------------------------------
-- 마무리 연출 (공을 맞혔을 때 헤드 자리에서): 스킨마다 다른 모양
----------------------------------------------------------------------
-- 한 번 뿌리는 입자
local function emitAt(pos, o)
	local holder = glowPart(Enum.PartType.Block, Vector3.one * 0.1, Color3.new(1, 1, 1))
	holder.Transparency = 1
	holder.CFrame = CFrame.new(pos)
	holder.Parent = fxFolder
	local em = Instance.new("ParticleEmitter")
	em.Texture = o.texture or TEXTURES.sparkle
	em.Color = o.color
	em.Rate = 0
	em.Lifetime = o.life or NumberRange.new(0.3, 0.7)
	em.Speed = o.speed or NumberRange.new(8, 16)
	em.SpreadAngle = o.spread or Vector2.new(180, 180)
	em.Size = o.size or NumberSequence.new(0.6, 0)
	em.Transparency = o.transparency or NumberSequence.new(0, 1)
	em.LightEmission = o.light or 1
	em.Drag = o.drag or 5
	em.Acceleration = o.accel or Vector3.zero
	em.RotSpeed = o.rot or NumberRange.new(0)
	em.Rotation = NumberRange.new(0, 360)
	em.Parent = holder
	em:Emit(o.count)
	Debris:AddItem(holder, 2)
end

-- 실제 부품을 사방으로 던짐 (내 화면에서만 물리 계산, 1초 뒤 사라짐)
local function throwBits(pos, count, speed, make)
	for i = 1, count do
		local p = make(i)
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		p.CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		p.Parent = fxFolder
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.4, math.random() - 0.5).Unit
		p.AssemblyLinearVelocity = dir * speed * (0.6 + math.random() * 0.6)
		p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
		TweenService:Create(p, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = p.Size * 0.4 }):Play()
		Debris:AddItem(p, 1)
	end
end

local function flatRing(pos, color, size, time, delay, transparency)
	task.delay(delay or 0, function()
		local ring = glowPart(Enum.PartType.Cylinder, Vector3.new(0.15, 1, 1), color)
		ring.Transparency = transparency or 0.2
		ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = fxFolder
		TweenService:Create(ring, TweenInfo.new(time or 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, size, size), Transparency = 1 }):Play()
		Debris:AddItem(ring, (time or 0.45) + 0.05)
	end)
end

local SWING = {}
function SWING.spark(pos, fx, n)
	emitAt(pos, { color = colorSeq(fx.colors), count = n })
	if fx.burst.shock then
		flatRing(pos, fx.colors[1], 14)
	end
end
function SWING.splash(pos, fx, n)
	throwBits(pos, math.ceil(n / 3), 22, function(i)
		local p = glowPart(Enum.PartType.Ball, Vector3.one * (0.35 + math.random() * 0.3), fx.colors[(i % #fx.colors) + 1])
		p.Material = Enum.Material.Glass
		p.Transparency = 0.25
		return p
	end)
	emitAt(pos, { color = ColorSequence.new(Color3.fromRGB(200, 240, 255)), count = n, speed = NumberRange.new(6, 12), accel = Vector3.new(0, -30, 0), size = NumberSequence.new(0.45, 0.1), light = 0.3 })
	flatRing(pos, Color3.fromRGB(150, 220, 255), 12, 0.5, 0, 0.4)
end
function SWING.flame(pos, fx, n)
	emitAt(pos, { texture = TEXTURES.fire, color = colorSeq(fx.colors), count = n, speed = NumberRange.new(10, 20), size = NumberSequence.new(1.6, 0), accel = Vector3.new(0, 18, 0), drag = 4 })
	emitAt(pos, { color = ColorSequence.new(Color3.fromRGB(255, 200, 80)), count = math.ceil(n / 2), speed = NumberRange.new(14, 26), size = NumberSequence.new(0.3, 0), accel = Vector3.new(0, 10, 0), life = NumberRange.new(0.6, 1.1) })
	flatRing(pos, Color3.fromRGB(255, 120, 40), 16, 0.4)
end
function SWING.frost(pos, fx, n)
	throwBits(pos, math.ceil(n / 3), 18, function()
		local p = glowPart(Enum.PartType.Block, Vector3.new(0.3, 0.6 + math.random() * 0.5, 0.3), Color3.fromRGB(190, 235, 255))
		p.Material = Enum.Material.Ice
		p.Transparency = 0.15
		return p
	end)
	emitAt(pos, { texture = TEXTURES.smoke, color = ColorSequence.new(Color3.new(1, 1, 1)), count = math.ceil(n / 3), speed = NumberRange.new(4, 8), size = NumberSequence.new(1.5, 3), transparency = NumberSequence.new(0.4, 1), light = 0.2, life = NumberRange.new(0.6, 1) })
	flatRing(pos, Color3.fromRGB(180, 230, 255), 14, 0.55, 0, 0.3)
end
function SWING.stars(pos, fx, n)
	emitAt(pos, { color = colorSeq(fx.colors), count = n, speed = NumberRange.new(4, 10), size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 1), NumberSequenceKeypoint.new(1, 0) }), rot = NumberRange.new(-400, 400), life = NumberRange.new(0.6, 1.2), drag = 2, accel = Vector3.new(0, 4, 0) })
	throwBits(pos, 6, 14, function(i)
		local p = glowPart(Enum.PartType.Block, Vector3.new(0.18, 0.7, 0.18), fx.colors[(i % #fx.colors) + 1])
		return p
	end)
	flatRing(pos, fx.colors[1], 12, 0.4)
	flatRing(pos, fx.colors[#fx.colors], 20, 0.6, 0.1, 0.4)
end
function SWING.gold(pos, fx, n)
	throwBits(pos, math.ceil(n / 3), 20, function()
		local p = glowPart(Enum.PartType.Cylinder, Vector3.new(0.12, 0.7, 0.7), Color3.fromRGB(255, 205, 70))
		p.Material = Enum.Material.Foil
		return p
	end)
	emitAt(pos, { color = ColorSequence.new(Color3.fromRGB(255, 240, 170), Color3.fromRGB(255, 190, 50)), count = n, speed = NumberRange.new(8, 14) })
	flatRing(pos, Color3.fromRGB(255, 215, 90), 16, 0.5)
end
function SWING.bubble(pos, fx, n)
	for _ = 1, math.ceil(n / 3) do
		local b = glowPart(Enum.PartType.Ball, Vector3.one * (0.4 + math.random() * 0.5), fx.colors[math.random(1, #fx.colors)])
		b.Material = Enum.Material.Glass
		b.Transparency = 0.45
		b.CFrame = CFrame.new(pos + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 2)
		b.Parent = fxFolder
		local rise = Vector3.new((math.random() - 0.5) * 4, 3 + math.random() * 4, (math.random() - 0.5) * 4)
		local t = 0.6 + math.random() * 0.5
		TweenService:Create(b, TweenInfo.new(t, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { CFrame = b.CFrame + rise, Size = b.Size * 1.6 }):Play()
		task.delay(t, function()
			if b.Parent then
				emitAt(b.Position, { color = ColorSequence.new(Color3.new(1, 1, 1)), count = 4, speed = NumberRange.new(3, 6), size = NumberSequence.new(0.25, 0) }) -- 퐁!
				b:Destroy()
			end
		end)
	end
	flatRing(pos, fx.colors[1], 10, 0.4, 0, 0.4)
end
function SWING.rainbow(pos, fx, n)
	local colors = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 230, 80), Color3.fromRGB(90, 220, 120), Color3.fromRGB(80, 160, 255), Color3.fromRGB(180, 100, 255) }
	for i, c in ipairs(colors) do
		flatRing(pos + Vector3.new(0, i * 0.25, 0), c, 8 + i * 2.5, 0.5, i * 0.04, 0.15)
	end
	emitAt(pos, { color = colorSeq(colors), count = n, speed = NumberRange.new(10, 18) })
end
function SWING.neon(pos, fx, n)
	-- 사방으로 뻗는 번개 줄기
	for k = 1, 5 do
		local a = k / 5 * math.pi * 2 + math.random()
		local prev = pos
		for seg = 1, 4 do
			local nextP = pos + Vector3.new(math.cos(a), (math.random() - 0.3) * 0.6, math.sin(a)) * seg * 1.6 + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
			local len = (nextP - prev).Magnitude
			local bolt = glowPart(Enum.PartType.Block, Vector3.new(0.12, 0.12, len), fx.colors[((k + seg) % #fx.colors) + 1])
			bolt.CFrame = CFrame.lookAt((prev + nextP) / 2, nextP)
			bolt.Parent = fxFolder
			TweenService:Create(bolt, TweenInfo.new(0.35), { Transparency = 1 }):Play()
			Debris:AddItem(bolt, 0.4)
			prev = nextP
		end
	end
	emitAt(pos, { color = colorSeq(fx.colors), count = math.ceil(n / 2), speed = NumberRange.new(12, 20) })
	flatRing(pos, fx.colors[1], 14, 0.35)
end
function SWING.panda(pos, fx, n)
	emitAt(pos, { texture = TEXTURES.smoke, color = ColorSequence.new(Color3.fromRGB(30, 30, 30)), count = math.ceil(n / 2), speed = NumberRange.new(5, 10), size = NumberSequence.new(1.2, 2.5), transparency = NumberSequence.new(0.2, 1), light = 0, life = NumberRange.new(0.5, 0.9) })
	emitAt(pos, { texture = TEXTURES.smoke, color = ColorSequence.new(Color3.new(1, 1, 1)), count = math.ceil(n / 2), speed = NumberRange.new(5, 10), size = NumberSequence.new(1.2, 2.5), transparency = NumberSequence.new(0.2, 1), light = 0.2, life = NumberRange.new(0.5, 0.9) })
end

local function burst(e, full)
	local fx = e.fx
	if e.burstEmitter then
		e.burstEmitter:Emit(math.ceil(fx.burst.count * (full and 0.15 or 0.3))) -- 맞혔을 때는 아래 스킨별 연출이 주인공
	end
	if not full then
		return -- 헛스윙: 작은 반짝임만
	end
	-- 스킨별 마무리 연출 (등급이 높을수록 양이 많음)
	if e.head.Parent then
		local style = SWING[fx.swing] or SWING.spark
		style(e.head.Position, fx, fx.burst.count)
	end
	-- 내가 휘둘렀을 때 화면 살짝 펀치
	if fx.burst.punch and e.owner == player then
		local fov = camera.FieldOfView
		TweenService:Create(camera, TweenInfo.new(0.06), { FieldOfView = fov + 4 }):Play()
		task.delay(0.07, function()
			TweenService:Create(camera, TweenInfo.new(0.2), { FieldOfView = fov }):Play()
		end)
	end
end

local function attach(tool)
	detach(tool)
	local skinId = tool:GetAttribute("Skin")
	local head = tool:FindFirstChild("Head")
	if not (skinId and head) then
		return
	end
	local fx = Config.GetFx(skinId)
	local character = tool.Parent
	local e = {
		tool = tool,
		head = head,
		fx = fx,
		cleanup = {},
		orbs = {},
		owner = character and Players:GetPlayerFromCharacter(character),
		baseColor = head.Color,
	}

	local att = Instance.new("Attachment")
	att.Name = "FXCenter"
	att.Parent = head
	table.insert(e.cleanup, att)

	-- 꼬리 (휘두를 때 남는 빛 자국)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.45, 0)
	a0.Parent = head
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.45, 0)
	a1.Parent = head
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.3
	trail.LightEmission = 1
	trail.Color = colorSeq(fx.colors)
	trail.Transparency = NumberSequence.new(0, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = head
	table.insert(e.cleanup, a0)
	table.insert(e.cleanup, a1)
	table.insert(e.cleanup, trail)

	-- 계속 나오는 빛 입자
	-- 헤드를 덮는 빛 구름 대신, 헤드 겉면에서 반짝 생겼다 사라지는 작은 반짝임 (헤드 모양이 잘 보이게)
	if fx.aura then
		local em = Instance.new("ParticleEmitter")
		em.Texture = TEXTURES[fx.texture] or TEXTURES.sparkle
		em.Color = colorSeq(fx.colors)
		em.Rate = math.max(2, fx.aura.rate * 0.35)
		em.Lifetime = NumberRange.new(0.25, 0.5)
		em.Speed = NumberRange.new(0.2, 0.6)
		em.SpreadAngle = Vector2.new(180, 180)
		em.Shape = Enum.ParticleEmitterShape.Box
		em.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		em.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		-- 커졌다 작아지는 '반짝'
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.35, fx.aura.size * 0.55), NumberSequenceKeypoint.new(1, 0) })
		em.Transparency = NumberSequence.new(0, 0.4)
		em.LightEmission = 0.8
		em.Drag = 2
		em.Rotation = NumberRange.new(0, 360)
		em.RotSpeed = NumberRange.new(-180, 180)
		if fx.texture == "fire" then
			em.Acceleration = Vector3.new(0, 4, 0)
		elseif fx.texture == "smoke" then
			em.Acceleration = Vector3.new(0, 1.5, 0)
			em.Transparency = NumberSequence.new(0.5, 1)
		end
		em.Parent = head -- 부품에 달면 부품 겉면(Shape)에서 나옴
		table.insert(e.cleanup, em)
		e.aura = em
	end

	-- 휘두를 때 터지는 입자
	local bem = Instance.new("ParticleEmitter")
	bem.Texture = TEXTURES.sparkle
	bem.Color = colorSeq(fx.colors)
	bem.Rate = 0
	bem.Lifetime = NumberRange.new(0.3, 0.7)
	bem.Speed = NumberRange.new(8, 16)
	bem.SpreadAngle = Vector2.new(180, 180)
	bem.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	bem.Transparency = NumberSequence.new(0, 1)
	bem.LightEmission = 1
	bem.Drag = 5
	bem.Parent = att
	table.insert(e.cleanup, bem)
	e.burstEmitter = bem

	-- 빛
	if fx.pulse or fx.rainbow then
		local light = Instance.new("PointLight")
		light.Color = fx.colors[1]
		light.Range = 8
		light.Brightness = 2
		light.Parent = head
		table.insert(e.cleanup, light)
		e.light = light
	end

	-- 도는 빛구슬
	if fx.orbit then
		for i = 1, fx.orbit.count do
			local orb = glowPart(Enum.PartType.Ball, Vector3.one * 0.32, fx.colors[((i - 1) % #fx.colors) + 1])
			orb.Parent = fxFolder
			table.insert(e.orbs, orb)
			table.insert(e.cleanup, orb)
		end
	end

	-- 회전 고리
	if fx.ring then
		local ring = glowPart(Enum.PartType.Cylinder, Vector3.new(0.08, 2.6, 2.6), fx.colors[#fx.colors])
		ring.Transparency = 0.35
		ring.Parent = fxFolder
		table.insert(e.cleanup, ring)
		e.ring = ring
	end

	-- 휘두를 때 작은 반짝임, 실제로 맞혔을 때 큰 폭발
	if character then
		table.insert(e.cleanup, character:GetAttributeChangedSignal("SwingId"):Connect(function()
			task.delay(Config.Club.impactDelay, burst, e, false)
		end))
		table.insert(e.cleanup, character:GetAttributeChangedSignal("HitId"):Connect(function()
			burst(e, true)
		end))
	end
	active[tool] = e
	print(string.format("[ClubFX] %s 골프채 효과 적용: %s (%s)", character and character.Name or "?", skinId, (Config.Skins[skinId] or {}).rarity or "?"))
end

-- 장착되어 화면에 보이는 골프채만 연출 (가방 속은 제외)
local watched = setmetatable({}, { __mode = "k" }) -- 이미 감시 중인 골프채 (중복 연결 방지)

local function watchTool(tool)
	if not ((tool:IsA("Model") or tool:IsA("Tool")) and tool.Name == "GolfClub") then
		return
	end
	if watched[tool] then
		watched[tool]()
		return
	end
	local function update()
		if tool:IsDescendantOf(workspace) and tool:GetAttribute("Skin") then
			attach(tool)
		else
			detach(tool)
		end
	end
	watched[tool] = update
	tool:GetAttributeChangedSignal("Skin"):Connect(update)
	tool.AncestryChanged:Connect(update)
	-- 스트리밍 때문에 클럽 머리가 모델보다 늦게 도착할 수 있음 → 도착하면 다시 붙이기
	tool.ChildAdded:Connect(function(child)
		if child.Name == "Head" and not active[tool] then
			update()
		end
	end)
	tool.Destroying:Connect(function()
		detach(tool)
		watched[tool] = nil
	end)
	update()
end

----------------------------------------------------------------------
-- 매 프레임: 빛구슬 회전, 고리 회전, 빛 숨쉬기, 무지개
----------------------------------------------------------------------
local function step()
	local t = os.clock()
	for tool, e in pairs(active) do
		local head = e.head
		if not head.Parent or not tool:IsDescendantOf(workspace) then
			detach(tool)
			continue
		end
		local center = head.Position
		local fx = e.fx
		local rainbowColor = fx.rainbow and Color3.fromHSV((t * 0.25) % 1, 0.8, 1) or nil

		if fx.orbit then
			local n = #e.orbs
			for i, orb in ipairs(e.orbs) do
				local a = t * fx.orbit.speed + (i - 1) * (math.pi * 2 / n)
				local bob = math.sin(t * 3 + i) * 0.35
				orb.CFrame = CFrame.new(center + Vector3.new(math.cos(a) * fx.orbit.radius, bob, math.sin(a) * fx.orbit.radius))
				if rainbowColor then
					orb.Color = Color3.fromHSV(((t * 0.25) + i / n) % 1, 0.8, 1)
				end
			end
		end
		if e.ring then
			e.ring.CFrame = CFrame.new(center) * CFrame.Angles(t * 1.3, t * 2.1, 0) * CFrame.Angles(0, 0, math.rad(90))
			if rainbowColor then
				e.ring.Color = rainbowColor
			end
		end
		if e.light then
			e.light.Brightness = 1.6 + math.sin(t * 4) * 1.2
			if rainbowColor then
				e.light.Color = rainbowColor
			end
		end
		if rainbowColor then
			head.Color = rainbowColor -- 내 화면에서만 바뀜
			-- 모델러 헤드 메시가 붙어 있으면 그 몸통도 같이 무지개색
			local mesh = tool:FindFirstChild("HeadMesh")
			if mesh then
				for _, p in ipairs(mesh:GetChildren()) do
					if p:IsA("BasePart") and string.sub(p.Name, 1, 9) == "Head_Base" then
						p.Color = rainbowColor
					end
				end
			end
			if e.aura then
				e.aura.Color = ColorSequence.new(rainbowColor, Color3.fromHSV(((t * 0.25) + 0.3) % 1, 0.8, 1))
			end
		end
	end

	-- 메뉴 미리보기 회전
	for i = #previews, 1, -1 do
		local pv = previews[i]
		if not pv.viewport.Parent then
			table.remove(previews, i)
		else
			pv.model:PivotTo(CFrame.Angles(0, t * 1.4, 0) * CFrame.Angles(math.rad(-25), 0, math.rad(15)))
			if pv.rainbow then
				pv.head.Color = Color3.fromHSV((t * 0.25) % 1, 0.8, 1)
			end
		end
	end
end

----------------------------------------------------------------------
-- 메뉴용 3D 미리보기
----------------------------------------------------------------------
function ClubFX.Preview(parent, skinId, props)
	local skin = Config.Skins[skinId] or Config.Skins.White
	local fx = Config.GetFx(skinId)
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(200, 200, 210)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.LightDirection = Vector3.new(-1, -1, -1)
	for k, v in pairs(props or {}) do
		vp[k] = v
	end

	local model = Instance.new("Model")
	local shaft = Instance.new("Part")
	shaft.Anchored = true
	shaft.Size = Vector3.new(0.22, 4.2, 0.22)
	shaft.Color = Color3.fromRGB(190, 195, 205)
	shaft.Material = Enum.Material.Metal
	shaft.CFrame = CFrame.new(0, 0.6, 0)
	shaft.Parent = model
	local grip = Instance.new("Part")
	grip.Anchored = true
	grip.Size = Vector3.new(0.32, 1.1, 0.32)
	grip.Color = Color3.fromRGB(35, 35, 40)
	grip.CFrame = CFrame.new(0, 2.2, 0)
	grip.Parent = model
	local head = Instance.new("Part")
	head.Anchored = true
	head.Size = Vector3.new(1.5, 0.75, 0.55)
	head.Color = skin.color
	head.Material = Enum.Material[skin.material] or Enum.Material.SmoothPlastic
	head.CFrame = CFrame.new(0.45, -1.7, 0)
	head.Parent = model
	if Config.RarityById[skin.rarity].index >= 3 then
		local gem = Instance.new("Part")
		gem.Anchored = true
		gem.Shape = Enum.PartType.Ball
		gem.Size = Vector3.one * 0.38
		gem.Material = Enum.Material.Neon
		gem.Color = (skin.trail and skin.trail[#skin.trail]) or skin.color
		gem.CFrame = CFrame.new(0.45, -1.65, -0.3)
		gem.Parent = model
	end
	model.PrimaryPart = shaft
	model.Parent = vp

	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 0, 8.5), Vector3.zero)
	cam.Parent = vp
	vp.CurrentCamera = cam
	vp.Parent = parent
	table.insert(previews, { viewport = vp, model = model, head = head, rainbow = fx.rainbow == true })
	return vp
end

-- 등급 테두리가 반짝이며 도는 효과 (UIStroke 에 무지개/등급색 그라데이션)
local shines = {}
function ClubFX.Shine(stroke, rarityId)
	local r = Config.RarityById[rarityId]
	if not r or r.index < 3 then
		return
	end
	local g = Instance.new("UIGradient")
	if rarityId == "Mythic" then
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 150)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 220, 80)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 220, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 150)),
		})
	else
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, r.color),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, r.color),
		})
	end
	g.Parent = stroke
	table.insert(shines, g)
end

function ClubFX.Start()
	for _, d in ipairs(workspace:GetDescendants()) do
		watchTool(d)
	end
	workspace.DescendantAdded:Connect(watchTool)
	-- 안전장치: 0.5초마다 효과가 빠진 골프채가 있으면 다시 붙이기
	task.spawn(function()
		while true do
			task.wait(0.5)
			for tool, update in pairs(watched) do
				if not active[tool] and tool:IsDescendantOf(workspace) and tool:GetAttribute("Skin") and tool:FindFirstChild("Head") then
					update()
				end
			end
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		step()
		for i = #shines, 1, -1 do
			local g = shines[i]
			if not g.Parent or not g.Parent.Parent then
				table.remove(shines, i)
			else
				g.Rotation = (g.Rotation + dt * 120) % 360
			end
		end
	end)
end

return ClubFX
