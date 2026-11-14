-- 맵을 코드로 만듭니다. (Studio 에서 직접 꾸민 맵으로 바꿔도 됩니다:
-- workspace.Plots 안에 Plot1..Plot6 모델을 두고 각 모델에 Floor, SellPad, Sign 파트를 넣으면 그대로 사용)

local Lighting = game:GetService("Lighting")

local MapBuilder = {}

local PLOT_COUNT = 6
local PLOT_SIZE = 70
local RING_RADIUS = 130

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		if k ~= "Parent" then
			p[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

local function billboard(adornee, text, color, size)
	local gui = Instance.new("BillboardGui")
	gui.Size = size or UDim2.fromOffset(260, 60)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 220
	gui.Adornee = adornee
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Name = "Label"
	label.Parent = gui
	gui.Parent = adornee
	return label
end

local function setupLighting()
	Lighting.ClockTime = 21
	Lighting.Brightness = 1.5
	Lighting.Ambient = Color3.fromRGB(70, 70, 110)
	Lighting.OutdoorAmbient = Color3.fromRGB(90, 90, 140)
	Lighting.GlobalShadows = true
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmo = Instance.new("Atmosphere")
		atmo.Density = 0.3
		atmo.Color = Color3.fromRGB(120, 110, 200)
		atmo.Decay = Color3.fromRGB(60, 40, 120)
		atmo.Glare = 0.2
		atmo.Haze = 1.2
		atmo.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.8
		bloom.Size = 30
		bloom.Threshold = 0.9
		bloom.Parent = Lighting
	end
end

local function buildPlot(parent, index, center)
	local model = Instance.new("Model")
	model.Name = "Plot" .. index

	local floor = part({
		Name = "Floor",
		Size = Vector3.new(PLOT_SIZE, 4, PLOT_SIZE),
		CFrame = CFrame.new(center),
		Color = Color3.fromRGB(70, 60, 120),
		Material = Enum.Material.Slate,
		Parent = model,
	})

	-- 가장자리 테두리 (빛나는 선)
	for _, offset in ipairs({
		{ Vector3.new(0, 2.1, PLOT_SIZE / 2), Vector3.new(PLOT_SIZE, 0.3, 1) },
		{ Vector3.new(0, 2.1, -PLOT_SIZE / 2), Vector3.new(PLOT_SIZE, 0.3, 1) },
		{ Vector3.new(PLOT_SIZE / 2, 2.1, 0), Vector3.new(1, 0.3, PLOT_SIZE) },
		{ Vector3.new(-PLOT_SIZE / 2, 2.1, 0), Vector3.new(1, 0.3, PLOT_SIZE) },
	}) do
		part({
			Name = "Edge",
			Size = offset[2],
			CFrame = CFrame.new(center + offset[1]),
			Color = Color3.fromRGB(140, 120, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = model,
		})
	end

	-- 허브 쪽(안쪽) 방향
	local inward = (-center * Vector3.new(1, 0, 1)).Unit
	local sellPos = center + inward * (PLOT_SIZE / 2 - 8) + Vector3.new(0, 2.25, 0)
	local sellPad = part({
		Name = "SellPad",
		Size = Vector3.new(10, 0.5, 10),
		CFrame = CFrame.new(sellPos),
		Color = Color3.fromRGB(80, 255, 140),
		Material = Enum.Material.Neon,
		Parent = model,
	})
	billboard(sellPad, "💰 판매", Color3.fromRGB(120, 255, 160), UDim2.fromOffset(160, 50))

	local spawnPos = center - inward * 10 + Vector3.new(0, 3, 0)
	local spawnPart = part({
		Name = "Spawn",
		Size = Vector3.new(6, 0.2, 6),
		CFrame = CFrame.new(spawnPos),
		Transparency = 1,
		CanCollide = false,
		Parent = model,
	})

	local signPost = part({
		Name = "Sign",
		Size = Vector3.new(14, 6, 1),
		CFrame = CFrame.lookAt(center - inward * (PLOT_SIZE / 2 - 2) + Vector3.new(0, 6, 0), center + Vector3.new(0, 6, 0)),
		Color = Color3.fromRGB(40, 30, 80),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	billboard(signPost, "빈 땅", Color3.new(1, 1, 1))

	model.PrimaryPart = floor
	model.Parent = parent
	return model
end

function MapBuilder.Build()
	setupLighting()

	local existing = workspace:FindFirstChild("Plots")
	if existing and #existing:GetChildren() > 0 then
		return existing:GetChildren()
	end

	local plotsFolder = existing or Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = workspace

	-- 기본 Baseplate 는 치움 (밤하늘 섬 느낌)
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	-- 중앙 허브 섬
	local hub = Instance.new("Model")
	hub.Name = "Hub"
	part({
		Name = "HubFloor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 110, 110),
		CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(60, 50, 110),
		Material = Enum.Material.Slate,
		Parent = hub,
	})
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 2.5, 0)
	spawn.Color = Color3.fromRGB(150, 130, 255)
	spawn.Material = Enum.Material.Neon
	spawn.Duration = 0
	spawn.Parent = hub
	local sign = part({
		Name = "Welcome",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(0, 14, 0),
		Transparency = 1,
		CanCollide = false,
		Parent = hub,
	})
	billboard(sign, "⭐ 별똥별 타이쿤 ⭐", Color3.fromRGB(255, 230, 120), UDim2.fromOffset(420, 90))
	hub.Parent = workspace

	-- 허브와 각 땅을 잇는 다리
	local plots = {}
	for i = 1, PLOT_COUNT do
		local angle = (i - 1) / PLOT_COUNT * math.pi * 2
		local center = Vector3.new(math.cos(angle) * RING_RADIUS, 0, math.sin(angle) * RING_RADIUS)
		local plot = buildPlot(plotsFolder, i, center)
		table.insert(plots, plot)

		local innerR = 55 -- 허브 반지름
		local outerR = RING_RADIUS - PLOT_SIZE / 2
		local mid = center.Unit * ((innerR + outerR) / 2)
		local length = outerR - innerR
		part({
			Name = "Bridge",
			Size = Vector3.new(10, 1, length + 6),
			CFrame = CFrame.lookAt(mid + Vector3.new(0, 1.5, 0), center + Vector3.new(0, 1.5, 0)),
			Color = Color3.fromRGB(110, 90, 180),
			Material = Enum.Material.WoodPlanks,
			Parent = hub,
		})
	end

	return plots
end

return MapBuilder
