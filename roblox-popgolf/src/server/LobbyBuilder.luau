-- 로비: 실내 '네온 아레나 홀' (어두운 남색 + 청록·분홍 네온)
-- 뒷벽: 대형 전광판 3개(전체 승리 순위 · 이 서버 MVP + 시상대 · 넘어뜨림 왕)
-- 오른쪽: 빛나는 캡슐 포스터 + 캡슐 머신 / 왼쪽: 회전하는 골프채 전시대 · 스킬 보드 · 상점 키오스크
-- 시설의 ProximityPrompt(속성 OpenMenu)를 누르면 해당 메뉴가 열림

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local LobbyBuilder = {}

local CENTER = Vector3.new(0, 400, 0)
local UP = Vector3.new(0, 1, 0)
local HALL_W, HALL_D, HALL_H = 150, 120, 42

local PAL = {
	floor = Color3.fromRGB(26, 30, 58),
	floorLine = Color3.fromRGB(60, 220, 255),
	wall = Color3.fromRGB(32, 38, 78),
	wallDark = Color3.fromRGB(20, 22, 46),
	pillar = Color3.fromRGB(48, 58, 110),
	cyan = Color3.fromRGB(60, 230, 255),
	pink = Color3.fromRGB(255, 70, 190),
	purple = Color3.fromRGB(150, 80, 255),
	gold = Color3.fromRGB(255, 200, 70),
	blue = Color3.fromRGB(60, 120, 255),
	white = Color3.fromRGB(240, 245, 255),
	screen = Color3.fromRGB(10, 14, 30),
}

local folder
local spinners = {}

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

local function neon(size, cf, color, transparency)
	return part({ Size = size, CFrame = cf, Color = color, Material = Enum.Material.Neon, Transparency = transparency or 0, CanCollide = false, CastShadow = false })
end

local function light(parentPart, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range or 16
	l.Brightness = brightness or 1.5
	l.Parent = parentPart
	return l
end

local function surface(partObj, face, ppS)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face or Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = ppS or 30
	sg.LightInfluence = 0 -- 어두운 홀에서도 화면처럼 밝게
	sg.Parent = partObj
	return sg
end

local function text(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function prompt(partObj, actionText, objectText, menuKey)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = actionText
	pp.ObjectText = objectText
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 14
	pp.RequiresLineOfSight = false
	pp:SetAttribute("OpenMenu", menuKey)
	pp.Parent = partObj
	return pp
end

-- 네온 테두리 액자 (전광판·포스터 공용). 반환: 화면 파트
local function framedPanel(cf, w, h, frameColor)
	local screen = part({ Size = Vector3.new(w, h, 0.6), CFrame = cf, Color = PAL.screen, Material = Enum.Material.SmoothPlastic })
	local t = 0.5
	neon(Vector3.new(w + t * 2, t, 0.8), cf * CFrame.new(0, h / 2 + t / 2, 0), frameColor)
	neon(Vector3.new(w + t * 2, t, 0.8), cf * CFrame.new(0, -h / 2 - t / 2, 0), frameColor)
	neon(Vector3.new(t, h, 0.8), cf * CFrame.new(w / 2 + t / 2, 0, 0), frameColor)
	neon(Vector3.new(t, h, 0.8), cf * CFrame.new(-w / 2 - t / 2, 0, 0), frameColor)
	light(screen, frameColor, 26, 1.2)
	return screen
end

-- 순위 전광판: 머리 띠(색) + 제목 + 10줄 목록. 반환: 목록 TextLabel
local function leaderboardBoard(cf, title, color)
	local screen = framedPanel(cf, 20, 26, color)
	local sg = surface(screen, Enum.NormalId.Front, 24)
	local header = Instance.new("Frame")
	header.Size = UDim2.fromScale(1, 0.13)
	header.BackgroundColor3 = color
	header.BorderSizePixel = 0
	header.Parent = sg
	text(header, { Size = UDim2.fromScale(1, 1), Text = title, TextColor3 = Color3.fromRGB(20, 20, 30) })
	local list = text(sg, {
		Position = UDim2.fromScale(0.05, 0.16),
		Size = UDim2.fromScale(0.9, 0.82),
		Text = "불러오는 중...",
		TextScaled = false,
		TextSize = 44,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LineHeight = 1.15,
	})
	return list
end

-- 시상대 1·2·3 (이름표는 Main 이 채움)
local function podium(pos)
	local names = {}
	for _, d in ipairs({ { 2, -6, 3, PAL.white }, { 1, 0, 5, PAL.gold }, { 3, 6, 2, Color3.fromRGB(230, 150, 90) } }) do
		local place, x, h, c = d[1], d[2], d[3], d[4]
		local block = part({ Size = Vector3.new(5.6, h, 5), CFrame = CFrame.new(pos + Vector3.new(x, h / 2, 0)), Color = PAL.pillar, Material = Enum.Material.SmoothPlastic })
		neon(Vector3.new(5.8, 0.3, 5.2), CFrame.new(pos + Vector3.new(x, h, 0)), c)
		local sg = surface(block, Enum.NormalId.Front, 20)
		text(sg, { Size = UDim2.fromScale(1, 1), Text = tostring(place), TextColor3 = c })
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(180, 40)
		bb.StudsOffset = Vector3.new(0, h / 2 + 3, 0)
		bb.MaxDistance = 90
		bb.LightInfluence = 0
		names[place] = text(bb, { Size = UDim2.fromScale(1, 1), Text = "-", TextColor3 = c, TextStrokeTransparency = 0.3 })
		bb.Parent = block
	end
	return names
end

-- 캡슐 포스터 (빛나는 카드)
local function capsulePoster(cf, title, sub, color, emoji)
	local screen = framedPanel(cf, 11, 16, color)
	local sg = surface(screen, Enum.NormalId.Front, 30)
	local grad = Instance.new("Frame")
	grad.Size = UDim2.fromScale(1, 1)
	grad.BackgroundColor3 = Color3.new(1, 1, 1)
	grad.BorderSizePixel = 0
	grad.Parent = sg
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(color:Lerp(Color3.new(0, 0, 0), 0.3), Color3.fromRGB(15, 15, 35))
	g.Parent = grad
	text(grad, { Position = UDim2.fromScale(0.05, 0.04), Size = UDim2.fromScale(0.9, 0.14), Text = title })
	text(grad, { Position = UDim2.fromScale(0.05, 0.2), Size = UDim2.fromScale(0.9, 0.5), Text = emoji })
	text(grad, { Position = UDim2.fromScale(0.05, 0.74), Size = UDim2.fromScale(0.9, 0.1), Text = sub, TextColor3 = Color3.fromRGB(255, 240, 200) })
	text(grad, { Position = UDim2.fromScale(0.15, 0.86), Size = UDim2.fromScale(0.7, 0.09), Text = "[E] 뽑으러 가기", TextColor3 = color })
	prompt(screen, "뽑기", title, "Gacha")
end

-- 키오스크 (기둥 + 빛나는 화면)
local function kiosk(pos, yaw, title, color, menuKey, actionText, emoji)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	part({ Size = Vector3.new(6, 1, 4), CFrame = cf * CFrame.new(0, 0.5, 0), Color = PAL.pillar, Material = Enum.Material.SmoothPlastic })
	part({ Size = Vector3.new(1.4, 7, 1.4), CFrame = cf * CFrame.new(0, 4, 0.6), Color = PAL.wallDark, Material = Enum.Material.Metal })
	local screen = framedPanel(cf * CFrame.new(0, 10, 0.6) * CFrame.Angles(math.rad(-10), 0, 0), 9, 6, color)
	local sg = surface(screen, Enum.NormalId.Front, 30)
	text(sg, { Size = UDim2.fromScale(1, 0.6), Text = emoji })
	text(sg, { Position = UDim2.fromScale(0, 0.6), Size = UDim2.fromScale(1, 0.38), Text = title, TextColor3 = color })
	neon(Vector3.new(6.4, 0.2, 4.4), cf * CFrame.new(0, 1.05, 0), color, 0.2)
	prompt(screen, actionText, title, menuKey)
end

function LobbyBuilder.Build()
	local old = workspace:FindFirstChild("Lobby")
	if old then
		old:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = workspace

	local hw, hd = HALL_W / 2, HALL_D / 2

	-- 바닥 + 빛나는 격자선 + 가운데 원
	part({ Size = Vector3.new(HALL_W, 2, HALL_D), CFrame = CFrame.new(CENTER - UP), Color = PAL.floor, Material = Enum.Material.SmoothPlastic, Reflectance = 0.08 })
	for x = -hw + 15, hw - 15, 15 do
		neon(Vector3.new(0.15, 0.05, HALL_D), CFrame.new(CENTER + Vector3.new(x, 0.03, 0)), PAL.floorLine, 0.75)
	end
	for z = -hd + 15, hd - 15, 15 do
		neon(Vector3.new(HALL_W, 0.05, 0.15), CFrame.new(CENTER + Vector3.new(0, 0.03, z)), PAL.floorLine, 0.75)
	end
	for i = 1, 48 do
		local a = i / 48 * math.pi * 2
		local p = CENTER + Vector3.new(math.cos(a) * 22, 0.05, math.sin(a) * 22)
		neon(Vector3.new(3.1, 0.06, 0.35), CFrame.lookAt(p, CENTER + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, math.rad(90), 0), PAL.cyan, 0.2)
	end

	-- 벽 + 네온 줄 + 기둥
	local walls = {
		{ Vector3.new(0, HALL_H / 2, -hd), Vector3.new(HALL_W, HALL_H, 2), Enum.NormalId.Back },
		{ Vector3.new(0, HALL_H / 2, hd), Vector3.new(HALL_W, HALL_H, 2), Enum.NormalId.Front },
		{ Vector3.new(-hw, HALL_H / 2, 0), Vector3.new(2, HALL_H, HALL_D), Enum.NormalId.Right },
		{ Vector3.new(hw, HALL_H / 2, 0), Vector3.new(2, HALL_H, HALL_D), Enum.NormalId.Left },
	}
	for _, w in ipairs(walls) do
		part({ Size = w[2], CFrame = CFrame.new(CENTER + w[1]), Color = PAL.wall, Material = Enum.Material.SmoothPlastic })
		-- 아래쪽 청록 띠, 위쪽 분홍 띠 (벽 안쪽 면에 붙임)
		local inward = -w[1].Unit * Vector3.new(1, 0, 1)
		inward = Vector3.new(inward.X, 0, inward.Z).Unit
		local base = CENTER + Vector3.new(w[1].X, 0, w[1].Z) + inward * 1.1
		local long = (w[2].X > w[2].Z) and Vector3.new(w[2].X, 0.5, 0.2) or Vector3.new(0.2, 0.5, w[2].Z)
		neon(long, CFrame.new(base + UP * 3), PAL.cyan)
		neon(long, CFrame.new(base + UP * (HALL_H - 6)), PAL.pink)
		neon(long * Vector3.new(1, 0.4, 1), CFrame.new(base + UP * (HALL_H - 4)), PAL.purple, 0.3)
	end
	for _, x in ipairs({ -hw + 2, -hw / 2, hw / 2, hw - 2 }) do
		for _, z in ipairs({ -hd + 2, hd - 2 }) do
			part({ Size = Vector3.new(4, HALL_H, 4), CFrame = CFrame.new(CENTER + Vector3.new(x, HALL_H / 2, z)), Color = PAL.pillar, Material = Enum.Material.Metal })
			neon(Vector3.new(0.3, HALL_H - 4, 0.3), CFrame.new(CENTER + Vector3.new(x + 2.1 * (x < 0 and 1 or -1), HALL_H / 2, z + 2.1 * (z < 0 and 1 or -1))), PAL.cyan)
		end
	end

	-- 천장 + 조명 패널
	part({ Size = Vector3.new(HALL_W, 2, HALL_D), CFrame = CFrame.new(CENTER + UP * (HALL_H + 1)), Color = PAL.wallDark, Material = Enum.Material.SmoothPlastic })
	for _, x in ipairs({ -45, -15, 15, 45 }) do
		for _, z in ipairs({ -30, 0, 30 }) do
			local panel = neon(Vector3.new(14, 0.3, 4), CFrame.new(CENTER + Vector3.new(x, HALL_H - 0.2, z)), Color3.fromRGB(210, 230, 255), 0.1)
			local sl = Instance.new("SurfaceLight")
			sl.Face = Enum.NormalId.Bottom
			sl.Range = 40
			sl.Angle = 110
			sl.Brightness = 1.4
			sl.Color = Color3.fromRGB(200, 220, 255)
			sl.Parent = panel
		end
	end

	-- 뒷벽: 전광판 3개 + 시상대
	local backZ = -hd + 3
	local boards = {
		globalWins = leaderboardBoard(CFrame.new(CENTER + Vector3.new(-32, 16, backZ)), "🏆 전체 승리 순위", PAL.blue),
		serverMvp = leaderboardBoard(CFrame.new(CENTER + Vector3.new(0, 18, backZ)), "⚔️ 이 서버 MVP", PAL.gold),
		globalKO = leaderboardBoard(CFrame.new(CENTER + Vector3.new(32, 16, backZ)), "💫 넘어뜨림 왕", PAL.pink),
	}
	boards.podium = podium(CENTER + Vector3.new(0, 0, backZ + 10))

	-- 대형 로고 화면 (뒷벽 위)
	local logo = framedPanel(CFrame.new(CENTER + Vector3.new(0, HALL_H - 8, backZ + 0.2)), 40, 6, PAL.cyan)
	local lsg = surface(logo, Enum.NormalId.Front, 20)
	text(lsg, { Size = UDim2.fromScale(1, 1), Text = "⛳ POP GOLF  ·  팝골프 아레나", TextColor3 = PAL.cyan })

	-- 오른쪽: 캡슐 포스터 + 캡슐 머신
	local rx = hw - 3
	capsulePoster(CFrame.new(CENTER + Vector3.new(rx, 11, -14)) * CFrame.Angles(0, math.rad(-90), 0), "일반 캡슐", "🪙 코인으로 뽑기", Color3.fromRGB(80, 220, 140), "🟢")
	capsulePoster(CFrame.new(CENTER + Vector3.new(rx, 11, 4)) * CFrame.Angles(0, math.rad(-90), 0), "프리미엄 캡슐", "신화 골프채 등장!", PAL.purple, "💎")
	-- 캡슐 머신
	local mpos = CENTER + Vector3.new(hw - 16, 0, 22)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 7, 7), CFrame = CFrame.new(mpos + UP * 2) * CFrame.Angles(0, 0, math.rad(90)), Color = PAL.pink, Material = Enum.Material.SmoothPlastic })
	local glass = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 7, CFrame = CFrame.new(mpos + UP * 7.3), Color = Color3.fromRGB(200, 230, 255), Material = Enum.Material.Glass, Transparency = 0.5 })
	local capsuleColors = { PAL.pink, PAL.gold, PAL.cyan, PAL.purple, Color3.fromRGB(120, 230, 120) }
	local rng = Random.new(5)
	for i = 1, 14 do
		local off = Vector3.new(rng:NextNumber(-1.8, 1.8), rng:NextNumber(-2.2, 0.4), rng:NextNumber(-1.8, 1.8))
		part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.4, CFrame = CFrame.new(mpos + UP * 7.3 + off), Color = capsuleColors[(i % #capsuleColors) + 1], Material = Enum.Material.Neon, CanCollide = false })
	end
	light(glass, PAL.pink, 20, 2)
	prompt(glass, "뽑기", "🎰 캡슐 머신", "Gacha")

	-- 왼쪽: 회전하는 골프채 전시대 + 스킬 보드 + 상점 키오스크
	local lx = -hw + 18
	local ped = CENTER + Vector3.new(lx, 0, -10)
	part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 9, 9), CFrame = CFrame.new(ped + UP * 1.5) * CFrame.Angles(0, 0, math.rad(90)), Color = PAL.pillar, Material = Enum.Material.Metal })
	neon(Vector3.new(0.2, 9.4, 9.4), CFrame.new(ped + UP * 3.05) * CFrame.Angles(0, 0, math.rad(90)), PAL.gold, 0.1).Shape = Enum.PartType.Cylinder
	local showcase = Instance.new("Model")
	showcase.Name = "ClubShowcase"
	local skin = Config.Skins.Comet
	local shaft = part({ Size = Vector3.new(0.3, 7, 0.3), CFrame = CFrame.new(ped + UP * 8), Color = Color3.fromRGB(200, 210, 230), Material = Enum.Material.Metal, CanCollide = false, Parent = showcase })
	part({ Size = Vector3.new(1, 0.9, 2.4), CFrame = CFrame.new(ped + UP * 4.6 + Vector3.new(0, 0, -0.8)), Color = skin.color, Material = Enum.Material.Neon, CanCollide = false, Parent = showcase })
	part({ Size = Vector3.new(0.5, 1.6, 0.5), CFrame = CFrame.new(ped + UP * 11), Color = Color3.fromRGB(30, 30, 40), CanCollide = false, Parent = showcase })
	showcase.PrimaryPart = shaft
	showcase.Parent = folder
	light(shaft, skin.color, 18, 2)
	table.insert(spinners, { model = showcase, base = ped + UP * 8 })
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(220, 46)
	tag.StudsOffset = Vector3.new(0, 6, 0)
	tag.LightInfluence = 0
	text(tag, { Size = UDim2.fromScale(1, 1), Text = "🏌️ 골프채 컬렉션 [E]", TextColor3 = PAL.gold, TextStrokeTransparency = 0.3 })
	tag.Parent = shaft
	prompt(shaft, "골프채 보기", "🏌️ 전시대", "Clubs")

	kiosk(CENTER + Vector3.new(lx, 0, 14), math.rad(90), "⚡ 스킬", Color3.fromRGB(255, 170, 50), "Skills", "스킬 고르기", "⚡")
	kiosk(CENTER + Vector3.new(lx, 0, 32), math.rad(90), "💎 상점", PAL.pink, "Shop", "상점 열기", "💎")

	-- 스폰 (가운데 원)
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 0.2, 12)
	spawn.CFrame = CFrame.new(CENTER + Vector3.new(0, 0.1, 20))
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = folder

	-- 전시 골프채 천천히 회전
	task.spawn(function()
		local t = 0
		while folder.Parent do
			task.wait(0.05)
			t += 0.05
			for _, s in ipairs(spinners) do
				if s.model.Parent then
					s.model:PivotTo(CFrame.new(s.base + UP * math.sin(t * 2) * 0.4) * CFrame.Angles(0, t * 0.9, math.rad(12)))
				end
			end
		end
	end)

	return spawn, boards
end

return LobbyBuilder
