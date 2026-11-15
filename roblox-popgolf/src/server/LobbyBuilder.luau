-- 로비: 하늘에 떠 있는 '클럽하우스 섬'
-- 바위 절벽 섬 + 타일 광장 + 분수 + 클럽하우스 + 걸어가서 쓰는 시설(캡슐 머신·골프채 진열대·스킬 보드·상점)
-- + 연습 그린 + 순위 게시판 + 가로등·나무·벤치·팀 깃발
-- 시설에는 ProximityPrompt 가 있어서 다가가 E(모바일은 버튼)를 누르면 해당 메뉴가 열림 (속성 OpenMenu)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local LobbyBuilder = {}

local CENTER = Vector3.new(0, 400, 0)
local UP = Vector3.new(0, 1, 0)
local RADIUS = 78

local PAL = {
	tileA = Color3.fromRGB(236, 226, 205),
	tileB = Color3.fromRGB(214, 200, 175),
	grass = Color3.fromRGB(110, 190, 85),
	rock = Color3.fromRGB(120, 110, 105),
	wood = Color3.fromRGB(150, 100, 60),
	woodDark = Color3.fromRGB(105, 70, 45),
	roof = Color3.fromRGB(70, 140, 90),
	white = Color3.fromRGB(250, 250, 245),
	gold = Color3.fromRGB(255, 210, 90),
	water = Color3.fromRGB(80, 180, 240),
}

local folder

local function part(props)
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		if k ~= "ClassName" and k ~= "Parent" then
			p[k] = v
		end
	end
	p.Parent = props.Parent or folder
	return p
end

-- 바닥에 세운 원기둥 (topY = 윗면 높이)
local function column(pos, radius, height, color, material, parent)
	return part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(pos + UP * (height / 2)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Parent = parent,
	})
end

local function sign(partObj, face, text, color, bg)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.PixelsPerStud = 40
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = bg or Color3.fromRGB(30, 30, 40)
	label.BackgroundTransparency = bg and 0 or 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = sg
	sg.Parent = partObj
	return label
end

local function prompt(partObj, actionText, objectText, menuKey)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = actionText
	pp.ObjectText = objectText
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp:SetAttribute("OpenMenu", menuKey)
	pp.Parent = partObj
	return pp
end

local function tree(pos, scale, leafColor)
	local h = 9 * scale
	column(pos, 0.9 * scale, h, PAL.woodDark, Enum.Material.Wood)
	local shades = { leafColor, leafColor:Lerp(Color3.new(1, 1, 1), 0.15), leafColor:Lerp(Color3.new(0, 0, 0), 0.15) }
	for i, off in ipairs({ Vector3.new(0, h + 1, 0), Vector3.new(2, h - 1, 1) * scale, Vector3.new(-2, h - 0.5, -1.5) * scale, Vector3.new(0.5, h + 3.2 * scale, 0.5) }) do
		part({ Shape = Enum.PartType.Ball, Size = Vector3.one * (6 - i * 0.6) * scale, CFrame = CFrame.new(pos + off), Color = shades[(i % 3) + 1], Material = Enum.Material.Grass })
	end
end

local function lamp(pos)
	column(pos, 0.25, 9, Color3.fromRGB(40, 40, 50), Enum.Material.Metal)
	local bulb = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, CFrame = CFrame.new(pos + UP * 9.6), Color = Color3.fromRGB(255, 235, 170), Material = Enum.Material.Neon, CanCollide = false })
	local light = Instance.new("PointLight")
	light.Range = 22
	light.Brightness = 1.6
	light.Color = Color3.fromRGB(255, 225, 160)
	light.Parent = bulb
end

local function bench(pos, yaw)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	part({ Size = Vector3.new(6, 0.4, 1.8), CFrame = cf * CFrame.new(0, 1.6, 0), Color = PAL.wood, Material = Enum.Material.WoodPlanks })
	part({ Size = Vector3.new(6, 1.6, 0.3), CFrame = cf * CFrame.new(0, 2.6, 0.8), Color = PAL.wood, Material = Enum.Material.WoodPlanks })
	for _, x in ipairs({ -2.6, 2.6 }) do
		part({ Size = Vector3.new(0.3, 1.6, 1.6), CFrame = cf * CFrame.new(x, 0.8, 0), Color = Color3.fromRGB(50, 50, 60), Material = Enum.Material.Metal })
	end
end

-- 부스(지붕 달린 가판대): 간판 + 메뉴 열기 버튼
local function booth(pos, yaw, title, color, menuKey, actionText)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	part({ Size = Vector3.new(12, 3, 5), CFrame = cf * CFrame.new(0, 1.5, 0), Color = PAL.white, Material = Enum.Material.SmoothPlastic })
	part({ Size = Vector3.new(12.4, 0.4, 5.4), CFrame = cf * CFrame.new(0, 3.2, 0), Color = color, Material = Enum.Material.SmoothPlastic })
	for _, x in ipairs({ -5.6, 5.6 }) do
		part({ Size = Vector3.new(0.5, 7, 0.5), CFrame = cf * CFrame.new(x, 6.5, 2), Color = PAL.white })
	end
	-- 줄무늬 차양
	for i = 0, 5 do
		part({ ClassName = "WedgePart", Size = Vector3.new(2.1, 1.6, 4), CFrame = cf * CFrame.new(-5.25 + i * 2.1, 10.6, 0.4) * CFrame.Angles(0, math.pi, 0), Color = (i % 2 == 0) and color or PAL.white, Material = Enum.Material.Fabric })
	end
	local board = part({ Size = Vector3.new(10, 2.4, 0.4), CFrame = cf * CFrame.new(0, 12.6, 1.8), Color = Color3.fromRGB(35, 35, 45) })
	sign(board, Enum.NormalId.Back, title, Color3.new(1, 1, 1))
	sign(board, Enum.NormalId.Front, title, Color3.new(1, 1, 1))
	local counter = part({ Size = Vector3.new(4, 0.2, 2), CFrame = cf * CFrame.new(0, 3.45, -1.2), Color = color, Material = Enum.Material.Neon })
	prompt(counter, actionText, title, menuKey)
	return cf
end

-- 캡슐 머신 (유리 구 안에 색색 캡슐)
local function capsuleMachine(pos)
	column(pos, 3.2, 4, Color3.fromRGB(255, 90, 140), Enum.Material.SmoothPlastic)
	local glass = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 7, CFrame = CFrame.new(pos + UP * 7.3), Color = Color3.fromRGB(220, 240, 255), Material = Enum.Material.Glass, Transparency = 0.55 })
	local colors = { Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 210, 80), Color3.fromRGB(90, 200, 255), Color3.fromRGB(190, 110, 255), Color3.fromRGB(120, 230, 120) }
	local rng = Random.new(7)
	for i = 1, 14 do
		local off = Vector3.new(rng:NextNumber(-1.8, 1.8), rng:NextNumber(-2.2, 0.4), rng:NextNumber(-1.8, 1.8))
		part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.4, CFrame = CFrame.new(pos + UP * 7.3 + off), Color = colors[(i % #colors) + 1], Material = Enum.Material.SmoothPlastic, CanCollide = false })
	end
	part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, CFrame = CFrame.new(pos + UP * 11), Color = PAL.gold, Material = Enum.Material.Neon })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 200)
	light.Range = 16
	light.Parent = glass
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 50)
	gui.StudsOffset = Vector3.new(0, 7, 0)
	gui.MaxDistance = 70
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(255, 200, 230)
	t.TextStrokeTransparency = 0.2
	t.Text = "🎰 캡슐 뽑기"
	t.Parent = gui
	gui.Parent = glass
	prompt(glass, "뽑기", "🎰 캡슐 머신", "Gacha")
end

-- 골프채 진열대 (스킨 색 골프채가 꽂혀 있음)
local function clubRack(pos, yaw)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	part({ Size = Vector3.new(12, 1, 3), CFrame = cf * CFrame.new(0, 0.5, 0), Color = PAL.woodDark, Material = Enum.Material.WoodPlanks })
	part({ Size = Vector3.new(12, 6, 0.6), CFrame = cf * CFrame.new(0, 3.5, 1.2), Color = PAL.wood, Material = Enum.Material.WoodPlanks })
	local ids = { "Lava", "Galaxy", "Sun", "Rainbow", "Comet", "Aurora" }
	for i, id in ipairs(ids) do
		local skin = Config.Skins[id]
		local x = -5 + (i - 1) * 2
		part({ Size = Vector3.new(0.18, 4.6, 0.18), CFrame = cf * CFrame.new(x, 3.4, 0.5) * CFrame.Angles(0, 0, math.rad(8)), Color = Color3.fromRGB(200, 205, 215), Material = Enum.Material.Metal, CanCollide = false })
		part({ Size = Vector3.new(0.6, 0.6, 1.3), CFrame = cf * CFrame.new(x - 0.25, 1.3, 0.2), Color = skin.color, Material = Enum.Material[skin.material] or Enum.Material.SmoothPlastic, CanCollide = false })
	end
	local board = part({ Size = Vector3.new(10, 2, 0.3), CFrame = cf * CFrame.new(0, 7.8, 1.2), Color = Color3.fromRGB(35, 35, 45) })
	sign(board, Enum.NormalId.Front, "🏌️ 골프채 진열대", PAL.gold)
	sign(board, Enum.NormalId.Back, "🏌️ 골프채 진열대", PAL.gold)
	prompt(board, "골프채 고르기", "🏌️ 진열대", "Clubs")
end

-- 클럽하우스 건물
local function clubhouse(pos)
	local cf = CFrame.new(pos)
	part({ Size = Vector3.new(44, 14, 18), CFrame = cf * CFrame.new(0, 7, 0), Color = PAL.white, Material = Enum.Material.Plaster })
	part({ Size = Vector3.new(46, 1, 20), CFrame = cf * CFrame.new(0, 0.5, 0), Color = PAL.rock, Material = Enum.Material.Slate })
	-- 박공 지붕
	part({ ClassName = "WedgePart", Size = Vector3.new(48, 8, 11), CFrame = cf * CFrame.new(0, 18, -5.5) * CFrame.Angles(0, math.pi, 0), Color = PAL.roof, Material = Enum.Material.Slate })
	part({ ClassName = "WedgePart", Size = Vector3.new(48, 8, 11), CFrame = cf * CFrame.new(0, 18, 5.5), Color = PAL.roof, Material = Enum.Material.Slate })
	-- 창문 (빛나는 유리)
	for _, x in ipairs({ -15, -8, 8, 15 }) do
		part({ Size = Vector3.new(4, 5, 0.3), CFrame = cf * CFrame.new(x, 8, 9.05), Color = Color3.fromRGB(255, 230, 160), Material = Enum.Material.Neon, Transparency = 0.25 })
		part({ Size = Vector3.new(4.6, 0.4, 0.6), CFrame = cf * CFrame.new(x, 5.3, 9.2), Color = PAL.woodDark })
	end
	-- 문
	part({ Size = Vector3.new(6, 9, 0.4), CFrame = cf * CFrame.new(0, 5.5, 9.1), Color = PAL.woodDark, Material = Enum.Material.Wood })
	-- 간판
	local board = part({ Size = Vector3.new(26, 5, 0.6), CFrame = cf * CFrame.new(0, 16, 9.6), Color = Color3.fromRGB(30, 60, 40) })
	sign(board, Enum.NormalId.Front, "⛳ 팝골프 클럽하우스", PAL.gold)
	-- 기둥과 차양
	for _, x in ipairs({ -20, -10, 10, 20 }) do
		part({ Size = Vector3.new(1, 10, 1), CFrame = cf * CFrame.new(x, 5, 13), Color = PAL.white })
	end
	part({ Size = Vector3.new(44, 0.6, 6), CFrame = cf * CFrame.new(0, 10.3, 12), Color = PAL.roof, Material = Enum.Material.Slate })
end

-- 서버 순위 게시판 (Main 이 글자를 채움)
local function leaderboard(pos, yaw)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	for _, x in ipairs({ -6, 6 }) do
		part({ Size = Vector3.new(0.8, 12, 0.8), CFrame = cf * CFrame.new(x, 6, 0), Color = PAL.woodDark, Material = Enum.Material.Wood })
	end
	local board = part({ Name = "Leaderboard", Size = Vector3.new(13, 9, 0.6), CFrame = cf * CFrame.new(0, 8, 0), Color = Color3.fromRGB(25, 45, 35) })
	local label = sign(board, Enum.NormalId.Front, "🏆 오늘의 순위\n(경기가 끝나면 갱신)", Color3.new(1, 1, 1))
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	return label
end

-- 연습 그린 (깃발 + 홀컵)
local function practiceGreen(pos)
	column(pos, 14, 0.4, Color3.fromRGB(140, 220, 110), Enum.Material.Grass)
	column(pos + Vector3.new(4, 0, 3), 1.4, 0.45, Color3.fromRGB(20, 20, 20), Enum.Material.SmoothPlastic).CanCollide = false
	part({ Size = Vector3.new(0.3, 10, 0.3), CFrame = CFrame.new(pos + Vector3.new(4, 5, 3)), Color = PAL.white, CanCollide = false })
	part({ Size = Vector3.new(0.15, 2.4, 3.6), CFrame = CFrame.new(pos + Vector3.new(4, 8.8, 4.8)), Color = Color3.fromRGB(255, 70, 70), Material = Enum.Material.Fabric, CanCollide = false })
end

function LobbyBuilder.Build()
	local old = workspace:FindFirstChild("Lobby")
	if old then
		old:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = workspace

	-- 섬: 위는 잔디 테두리 + 타일 광장, 아래는 점점 좁아지는 바위 절벽
	column(CENTER - UP * 4, RADIUS, 4, PAL.grass, Enum.Material.Grass)
	for i, r in ipairs({ RADIUS - 2, RADIUS - 10, RADIUS - 22, RADIUS - 38, RADIUS - 56 }) do
		column(CENTER - UP * (4 + i * 7), r, 7.2, PAL.rock:Lerp(Color3.fromRGB(80, 70, 65), i / 5), Enum.Material.Rock)
	end
	-- 타일 광장 (체크무늬)
	local tile = 8
	for x = -5, 4 do
		for z = -5, 4 do
			local c = Vector3.new((x + 0.5) * tile, 0, (z + 0.5) * tile)
			if c.Magnitude < RADIUS - 18 then
				part({ Size = Vector3.new(tile - 0.15, 0.3, tile - 0.15), CFrame = CFrame.new(CENTER + c + UP * 0.15), Color = ((x + z) % 2 == 0) and PAL.tileA or PAL.tileB, Material = Enum.Material.Slate })
			end
		end
	end

	-- 가운데 분수
	column(CENTER, 9, 1.6, PAL.rock, Enum.Material.Cobblestone)
	column(CENTER + UP * 0.1, 8, 1.65, PAL.water, Enum.Material.Glass).Transparency = 0.3
	column(CENTER, 2, 5, PAL.white, Enum.Material.Marble)
	column(CENTER + UP * 5, 3.5, 0.6, PAL.white, Enum.Material.Marble)
	local jet = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1, CFrame = CFrame.new(CENTER + UP * 6), Transparency = 1, CanCollide = false })
	local water = Instance.new("ParticleEmitter")
	water.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	water.Color = ColorSequence.new(Color3.fromRGB(180, 230, 255))
	water.Rate = 60
	water.Lifetime = NumberRange.new(0.8, 1.2)
	water.Speed = NumberRange.new(10, 14)
	water.SpreadAngle = Vector2.new(12, 12)
	water.Acceleration = Vector3.new(0, -30, 0)
	water.Size = NumberSequence.new(0.6, 0.2)
	water.Transparency = NumberSequence.new(0.2, 0.8)
	water.EmitterDirection = Enum.NormalId.Top
	water.Parent = jet

	-- 스폰 (분수 앞)
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 0.4, 10)
	spawn.CFrame = CFrame.new(CENTER + Vector3.new(0, 0.4, 20))
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = folder

	-- 시설 배치
	clubhouse(CENTER + Vector3.new(0, 0, -50))
	capsuleMachine(CENTER + Vector3.new(-26, 0, -14))
	clubRack(CENTER + Vector3.new(26, 0, -16), math.rad(-20))
	booth(CENTER + Vector3.new(-34, 0, 16), math.rad(70), "⚡ 스킬 보드", Color3.fromRGB(255, 170, 50), "Skills", "스킬 고르기")
	booth(CENTER + Vector3.new(34, 0, 16), math.rad(-70), "💎 상점", Color3.fromRGB(230, 80, 170), "Shop", "상점 열기")
	practiceGreen(CENTER + Vector3.new(0, 0.3, 50))
	local board = leaderboard(CENTER + Vector3.new(-14, 0, 40), math.rad(200))

	-- 팀 깃발 아치 (빨강·파랑)
	for i, team in ipairs(Config.Teams) do
		local x = i == 1 and -48 or 48
		for _, z in ipairs({ -6, 6 }) do
			part({ Size = Vector3.new(1, 12, 1), CFrame = CFrame.new(CENTER + Vector3.new(x, 6, z)), Color = PAL.white })
		end
		part({ Size = Vector3.new(1.4, 2, 13), CFrame = CFrame.new(CENTER + Vector3.new(x, 12.5, 0)), Color = team.color, Material = Enum.Material.Neon })
		part({ Size = Vector3.new(0.2, 6, 4), CFrame = CFrame.new(CENTER + Vector3.new(x, 8.5, 0)), Color = team.color, Material = Enum.Material.Fabric, CanCollide = false })
	end

	-- 장식: 가로등, 나무, 벤치, 꽃
	for i = 1, 8 do
		local a = (i + 0.5) / 8 * math.pi * 2
		lamp(CENTER + Vector3.new(math.cos(a) * 44, 0, math.sin(a) * 44))
	end
	local leafColors = { Color3.fromRGB(80, 170, 80), Color3.fromRGB(230, 140, 170), Color3.fromRGB(240, 170, 70) }
	for i = 1, 14 do
		local a = i / 14 * math.pi * 2 + 0.2
		local r = RADIUS - 8
		local pos = CENTER + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		if math.abs(pos.Z - CENTER.Z + 50) > 14 then -- 클럽하우스 앞은 비움
			tree(pos, 0.9 + (i % 3) * 0.2, leafColors[(i % 3) + 1])
		end
	end
	bench(CENTER + Vector3.new(-12, 0, 28), math.rad(160))
	bench(CENTER + Vector3.new(12, 0, 28), math.rad(200))
	local flowerColors = { Color3.fromRGB(255, 120, 150), Color3.fromRGB(255, 230, 90), Color3.fromRGB(180, 140, 255), Color3.new(1, 1, 1) }
	local rng = Random.new(3)
	for i = 1, 90 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(RADIUS - 16, RADIUS - 3)
		part({ Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(0.5, 0.9), CFrame = CFrame.new(CENTER + Vector3.new(math.cos(a) * r, 0.3, math.sin(a) * r)), Color = flowerColors[(i % #flowerColors) + 1], Material = Enum.Material.SmoothPlastic, CanCollide = false })
	end

	-- 떨어지지 않게 투명 울타리 (원형으로 24조각)
	for i = 1, 24 do
		local a = i / 24 * math.pi * 2
		local p = CENTER + Vector3.new(math.cos(a) * (RADIUS - 0.5), 6, math.sin(a) * (RADIUS - 0.5))
		part({ Size = Vector3.new(1, 12, RADIUS * 0.28), CFrame = CFrame.lookAt(p, CENTER + UP * 6) * CFrame.Angles(0, math.rad(90), 0), Transparency = 1 })
	end

	return spawn, board
end

return LobbyBuilder
