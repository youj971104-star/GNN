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

local function burst(e, full)
	local fx = e.fx
	if e.burstEmitter then
		e.burstEmitter:Emit(full and fx.burst.count or math.ceil(fx.burst.count * 0.3))
	end
	if not full then
		return -- 헛스윙: 작은 반짝임만
	end
	if fx.burst.shock and e.head.Parent then
		local ring = glowPart(Enum.PartType.Cylinder, Vector3.new(0.15, 1, 1), fx.colors[1])
		ring.Transparency = 0.2
		ring.CFrame = CFrame.new(e.head.Position) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = fxFolder
		TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, 14, 14), Transparency = 1 }):Play()
		Debris:AddItem(ring, 0.5)
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
	if fx.aura then
		local em = Instance.new("ParticleEmitter")
		em.Texture = TEXTURES[fx.texture] or TEXTURES.sparkle
		em.Color = colorSeq(fx.colors)
		em.Rate = fx.aura.rate
		em.Lifetime = NumberRange.new(0.4, 0.9)
		em.Speed = NumberRange.new(0.6, 1.8)
		em.SpreadAngle = Vector2.new(180, 180)
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, fx.aura.size), NumberSequenceKeypoint.new(1, 0) })
		em.Transparency = NumberSequence.new(0.1, 1)
		em.LightEmission = 1
		em.Drag = 2
		em.Rotation = NumberRange.new(0, 360)
		em.RotSpeed = NumberRange.new(-180, 180)
		if fx.texture == "fire" then
			em.Acceleration = Vector3.new(0, 4, 0)
		elseif fx.texture == "smoke" then
			em.Acceleration = Vector3.new(0, 1.5, 0)
			em.Transparency = NumberSequence.new(0.5, 1)
		end
		em.Parent = att
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
