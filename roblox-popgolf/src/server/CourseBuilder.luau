-- 진짜 골프장 같은 홀을 코드로 만듭니다 (매 홀 새 모양)
-- 티(출발대) → 굽이치는 넓은 페어웨이 → 둥근 그린(깃발·홀컵)
-- 주변: 러프(풀숲, 공이 잘 안 굴러감) · 벙커(모래, 거의 안 굴러감) · 연못(빠지면 마지막 친 자리로) · 나무
-- 바닥 이름(Fairway/Rough/Green/Sand/Tee/Water)으로 공의 굴러가는 저항이 달라집니다.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local CourseBuilder = {}

local UP = Vector3.new(0, 1, 0)
local CC = Config.Course

local THEMES = {
	{ name = "봄 골프장", fairA = Color3.fromRGB(120, 205, 90), fairB = Color3.fromRGB(105, 190, 80), rough = Color3.fromRGB(70, 140, 60), green = Color3.fromRGB(140, 225, 110), leaves = Color3.fromRGB(70, 160, 70), clock = 13 },
	{ name = "바닷가 코스", fairA = Color3.fromRGB(150, 200, 100), fairB = Color3.fromRGB(135, 185, 90), rough = Color3.fromRGB(200, 190, 130), green = Color3.fromRGB(160, 220, 120), leaves = Color3.fromRGB(60, 150, 90), clock = 15 },
	{ name = "가을 단풍 코스", fairA = Color3.fromRGB(150, 190, 80), fairB = Color3.fromRGB(135, 175, 70), rough = Color3.fromRGB(110, 120, 50), green = Color3.fromRGB(160, 210, 100), leaves = Color3.fromRGB(230, 120, 50), clock = 16 },
	{ name = "노을 코스", fairA = Color3.fromRGB(110, 180, 90), fairB = Color3.fromRGB(95, 165, 80), rough = Color3.fromRGB(60, 110, 60), green = Color3.fromRGB(130, 200, 110), leaves = Color3.fromRGB(200, 90, 120), clock = 18 },
}

local current

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

-- 바닥 위에 납작한 원판 (Cylinder 를 세움). topY = 윗면 높이
local function disc(name, center, radius, topY, thickness, color, material, parent)
	return part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, radius * 2, radius * 2),
		CFrame = CFrame.new(center.X, topY - thickness / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
	}, parent)
end

-- 점 p 에서 꺾은선(path)까지의 가장 가까운 거리와, 그 지점의 진행률(0~1)
local function distToPath(p, path)
	local best, bestT = math.huge, 0
	local total, acc = 0, 0
	for i = 1, #path - 1 do
		total += (path[i + 1] - path[i]).Magnitude
	end
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local ab = b - a
		local len = ab.Magnitude
		local t = math.clamp((p - a):Dot(ab) / (len * len), 0, 1)
		local d = (a + ab * t - p).Magnitude
		if d < best then
			best = d
			bestT = (acc + len * t) / total
		end
		acc += len
	end
	return best, bestT
end

-- 꺾은선 위 진행률 t 지점과 그 방향
local function pointOnPath(path, t)
	local total = 0
	for i = 1, #path - 1 do
		total += (path[i + 1] - path[i]).Magnitude
	end
	local target = total * t
	for i = 1, #path - 1 do
		local seg = (path[i + 1] - path[i]).Magnitude
		if target <= seg or i == #path - 1 then
			local dir = (path[i + 1] - path[i]).Unit
			return path[i] + dir * math.min(target, seg), dir
		end
		target -= seg
	end
	return path[#path], Vector3.new(0, 0, 1)
end

-- teamSize: 한 팀 인원 (2~4). 많을수록 페어웨이를 넓히고 아이템 상자를 늘림
function CourseBuilder.Build(holeNumber, seed, teamSize)
	local extra = math.max(0, (teamSize or 2) - 2)
	CourseBuilder.Clear()
	local rng = Random.new(seed)
	local theme = THEMES[((holeNumber - 1 + seed) % #THEMES) + 1]
	Lighting.ClockTime = theme.clock

	local folder = Instance.new("Folder")
	folder.Name = "Hole"
	folder.Parent = workspace

	-- 1) 페어웨이 경로: 티(0,0,0) 에서 +Z 방향으로, 중간에 좌우로 휘어짐 (도그레그)
	local length = rng:NextNumber(CC.length[1], CC.length[2])
	local path = { Vector3.new(0, 0, 0) }
	local x = 0
	local bends = 3
	for i = 1, bends do
		x = math.clamp(x + rng:NextNumber(-45, 45), -70, 70)
		table.insert(path, Vector3.new(x, 0, length * i / (bends + 1)))
	end
	local greenCenter = Vector3.new(math.clamp(x + rng:NextNumber(-30, 30), -80, 80), 0, length)
	table.insert(path, greenCenter)

	-- 2) 바닥(러프) 전체
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, p in ipairs(path) do
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
	end
	local margin = 90
	minX, maxX, minZ, maxZ = minX - margin, maxX + margin, minZ - 60, maxZ + 70
	local center = Vector3.new((minX + maxX) / 2, 0, (minZ + maxZ) / 2)
	local size = Vector3.new(maxX - minX, 4, maxZ - minZ)
	-- 러프 = 로블록스 지형 잔디 (풀잎 장식이 흔들림). 윗면 높이 0
	local terrain = workspace.Terrain
	pcall(function()
		terrain.Decoration = true
	end)
	terrain:SetMaterialColor(Enum.Material.Grass, theme.rough)
	terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(240, 220, 160))
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(125, 120, 115))
	terrain.WaterColor = Color3.fromRGB(60, 170, 220)
	terrain.WaterTransparency = 0.6
	terrain.WaterWaveSize = 0.15
	terrain.WaterWaveSpeed = 8
	terrain:FillBlock(CFrame.new(center - UP * 4), Vector3.new(size.X + 120, 8, size.Z + 120), Enum.Material.Grass)
	-- 코스 바깥 언덕 (지평선이 밋밋하지 않게)
	local hillRng = Random.new(seed + 99)
	for _ = 1, 26 do
		local side = hillRng:NextInteger(1, 4)
		local hx, hz
		if side <= 2 then
			hx = (side == 1) and (minX - hillRng:NextNumber(30, 70)) or (maxX + hillRng:NextNumber(30, 70))
			hz = hillRng:NextNumber(minZ - 40, maxZ + 40)
		else
			hz = (side == 3) and (minZ - hillRng:NextNumber(30, 70)) or (maxZ + hillRng:NextNumber(30, 70))
			hx = hillRng:NextNumber(minX - 40, maxX + 40)
		end
		terrain:FillBall(Vector3.new(hx, -hillRng:NextNumber(4, 14), hz), hillRng:NextNumber(20, 40), Enum.Material.Grass)
		if hillRng:NextNumber() < 0.3 then
			terrain:FillBall(Vector3.new(hx, hillRng:NextNumber(2, 8), hz), hillRng:NextNumber(6, 12), Enum.Material.Rock)
		end
	end
	-- 투명 울타리 (선수가 밖으로 못 나가게, 공은 튕겨 나옴)
	for _, side in ipairs({
		{ Vector3.new(size.X / 2, 30, 0), Vector3.new(2, 60, size.Z) },
		{ Vector3.new(-size.X / 2, 30, 0), Vector3.new(2, 60, size.Z) },
		{ Vector3.new(0, 30, size.Z / 2), Vector3.new(size.X, 60, 2) },
		{ Vector3.new(0, 30, -size.Z / 2), Vector3.new(size.X, 60, 2) },
	}) do
		part({ Name = "Fence", Size = side[2], CFrame = CFrame.new(center + side[1]), Transparency = 1, CanQuery = false }, folder)
	end

	-- 3) 페어웨이: 20스터드마다 줄무늬, 꺾이는 곳은 원판으로 매끄럽게
	local W = CC.fairwayWidth + extra * CC.widthPerExtraPlayer
	local stripe = 0
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local seg = (b - a).Magnitude
		local dir = (b - a).Unit
		local n = math.max(1, math.floor(seg / 20))
		for k = 0, n - 1 do
			local s0 = seg * k / n
			local s1 = seg * (k + 1) / n
			local mid = a + dir * ((s0 + s1) / 2)
			stripe += 1
			part({
				Name = "Fairway",
				Size = Vector3.new(W, 0.2, (s1 - s0) + 0.05),
				CFrame = CFrame.lookAt(mid, mid + dir), -- 두께 0.2, 윗면 높이 0.1
				Color = stripe % 2 == 0 and theme.fairA or theme.fairB,
				Material = Enum.Material.Grass,
			}, folder)
		end
		disc("Fairway", b, W / 2, 0.11, 0.2, theme.fairA, Enum.Material.Grass, folder)
	end

	-- 4) 티(출발대)
	local startDir = (path[2] - path[1]).Unit
	part({ Name = "Tee", Size = Vector3.new(30, 0.3, 18), CFrame = CFrame.lookAt(Vector3.new(0, 0.15, 0), startDir * 10 + Vector3.new(0, 0.15, 0)), Color = Color3.fromRGB(150, 225, 120), Material = Enum.Material.Grass }, folder)
	for _, sx in ipairs({ -12, 12 }) do
		local marker = CFrame.lookAt(Vector3.zero, startDir) * CFrame.new(sx, 0.8, 0)
		part({ Name = "TeeMarker", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.2, CFrame = marker, Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.SmoothPlastic, CanCollide = false }, folder)
	end

	-- 5) 그린 + 홀컵 + 깃발
	local R = CC.greenRadius
	local green = disc("Green", greenCenter, R, 0.25, 0.5, theme.green, Enum.Material.SmoothPlastic, folder)
	green.CustomPhysicalProperties = PhysicalProperties.new(1, 0.15, 0.2, 1, 1)
	disc("GreenFringe", greenCenter, R + 3, 0.2, 0.4, theme.fairA, Enum.Material.Grass, folder).Name = "Fairway"
	local cupAngle = rng:NextNumber(0, math.pi * 2)
	local cup = greenCenter + Vector3.new(math.cos(cupAngle), 0, math.sin(cupAngle)) * rng:NextNumber(0, R * 0.55)
	disc("Cup", cup, Config.Ball.cupRadius, 0.27, 0.1, Color3.fromRGB(15, 15, 15), Enum.Material.SmoothPlastic, folder).CanCollide = false
	part({ Name = "FlagPole", Size = Vector3.new(0.35, 16, 0.35), CFrame = CFrame.new(cup + UP * 8), Color = Color3.new(1, 1, 1), CanCollide = false }, folder)
	local flag = part({ Name = "Flag", Size = Vector3.new(0.2, 3.6, 5.5), CFrame = CFrame.new(cup + UP * 14 + Vector3.new(0, 0, 2.7)), Color = Color3.fromRGB(255, 60, 60), Material = Enum.Material.Fabric, CanCollide = false }, folder)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 120)
	light.Range = 24
	light.Parent = flag
	-- 멀리서도 보이는 깃발 표시
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(70, 70)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	local mark = Instance.new("TextLabel")
	mark.Size = UDim2.fromScale(1, 1)
	mark.BackgroundTransparency = 1
	mark.TextScaled = true
	mark.Text = "⛳"
	mark.Parent = gui
	gui.Parent = flag

	-- 6) 벙커 (페어웨이 가장자리, 그린 주변)
	local nb = rng:NextInteger(CC.bunkers[1], CC.bunkers[2])
	for i = 1, nb do
		local pos
		if i == 1 then
			local a = rng:NextNumber(0, math.pi * 2)
			pos = greenCenter + Vector3.new(math.cos(a), 0, math.sin(a)) * (R + 10)
		else
			local p, dir = pointOnPath(path, rng:NextNumber(0.35, 0.85))
			local side = Vector3.new(dir.Z, 0, -dir.X) * (rng:NextNumber() < 0.5 and -1 or 1)
			pos = p + side * (W / 2 - 4)
		end
		-- 지형 모래로 바꿈 (표면 재질만 교체)
		terrain:FillCylinder(CFrame.new(pos.X, -1, pos.Z), 2.2, rng:NextNumber(8, 13), Enum.Material.Sand)
	end

	-- 7) 연못 (페어웨이 옆이나 일부를 가로지름)
	local np = rng:NextInteger(CC.ponds[1], CC.ponds[2])
	for _ = 1, np do
		local p, dir = pointOnPath(path, rng:NextNumber(0.3, 0.75))
		local side = Vector3.new(dir.Z, 0, -dir.X) * (rng:NextNumber() < 0.5 and -1 or 1)
		local pos = p + side * rng:NextNumber(W / 2, W / 2 + 18)
		-- 땅을 파고 진짜 물을 채움 (가장자리는 모래)
		local r = rng:NextNumber(14, 22)
		terrain:FillCylinder(CFrame.new(pos.X, -1, pos.Z), 2.2, r + 3, Enum.Material.Sand)
		terrain:FillCylinder(CFrame.new(pos.X, -2, pos.Z), 4.2, r, Enum.Material.Air)
		terrain:FillCylinder(CFrame.new(pos.X, -3, pos.Z), 2.4, r, Enum.Material.Water)
	end

	-- 8) 나무·덤불·꽃·바위 (페어웨이·그린에서 떨어진 곳)
	local leafShades = { theme.leaves, theme.leaves:Lerp(Color3.new(1, 1, 1), 0.18), theme.leaves:Lerp(Color3.new(0, 0, 0), 0.2) }
	local function treeAt(pos, scale)
		local h = rng:NextNumber(9, 15) * scale
		part({ Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 1.8 * scale, 1.8 * scale), CFrame = CFrame.new(pos + UP * (h / 2)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(105, 72, 45), Material = Enum.Material.Wood }, folder)
		-- 잎 덩어리 여러 개를 겹쳐서 풍성하게
		for k = 1, 4 do
			local off = Vector3.new(rng:NextNumber(-2.5, 2.5), rng:NextNumber(-1.5, 2.5), rng:NextNumber(-2.5, 2.5)) * scale
			local sz = rng:NextNumber(6, 10) * scale
			part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.one * sz, CFrame = CFrame.new(pos + UP * (h + 1) + off), Color = leafShades[(k % 3) + 1], Material = Enum.Material.Grass }, folder)
		end
	end
	local placed = 0
	for _ = 1, CC.trees * 5 do
		if placed >= CC.trees then
			break
		end
		local pos = Vector3.new(rng:NextNumber(minX + 6, maxX - 6), 0, rng:NextNumber(minZ + 6, maxZ - 6))
		local d = distToPath(pos, path)
		if d > W / 2 + 8 and (pos - greenCenter).Magnitude > R + 14 and pos.Magnitude > 30 then
			treeAt(pos, rng:NextNumber(0.8, 1.3))
			-- 나무 옆 덤불
			for _ = 1, rng:NextInteger(1, 3) do
				local bpos = pos + Vector3.new(rng:NextNumber(-6, 6), 0, rng:NextNumber(-6, 6))
				part({ Name = "Bush", Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(2.5, 4), CFrame = CFrame.new(bpos + UP * 0.8), Color = leafShades[rng:NextInteger(1, 3)], Material = Enum.Material.Grass }, folder)
			end
			placed += 1
		end
	end
	-- 꽃 무리 (러프 곳곳)
	local flowerColors = { Color3.fromRGB(255, 120, 150), Color3.fromRGB(255, 230, 90), Color3.fromRGB(190, 150, 255), Color3.new(1, 1, 1) }
	for _ = 1, 40 do
		local c = Vector3.new(rng:NextNumber(minX + 4, maxX - 4), 0, rng:NextNumber(minZ + 4, maxZ - 4))
		if distToPath(c, path) > W / 2 + 4 and (c - greenCenter).Magnitude > R + 6 then
			local col = flowerColors[rng:NextInteger(1, #flowerColors)]
			for _ = 1, 6 do
				local f = c + Vector3.new(rng:NextNumber(-2, 2), 0.35, rng:NextNumber(-2, 2))
				part({ Name = "Flower", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.6, CFrame = CFrame.new(f), Color = col, Material = Enum.Material.SmoothPlastic, CanCollide = false, CanQuery = false }, folder)
			end
		end
	end
	-- 바위
	for _ = 1, 12 do
		local c = Vector3.new(rng:NextNumber(minX + 4, maxX - 4), 0, rng:NextNumber(minZ + 4, maxZ - 4))
		if distToPath(c, path) > W / 2 + 6 and (c - greenCenter).Magnitude > R + 8 then
			local sz = rng:NextNumber(2, 5)
			part({ Name = "Rock", Size = Vector3.new(sz, sz * 0.7, sz * 1.2), CFrame = CFrame.new(c + UP * sz * 0.25) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3)), Color = Color3.fromRGB(135, 130, 125), Material = Enum.Material.Rock }, folder)
		end
	end
	-- 카트 길 (페어웨이 옆을 따라가는 포장길)
	local cartSide = rng:NextNumber() < 0.5 and 1 or -1
	for k = 1, #path - 1 do
		local a, b = path[k], path[k + 1]
		local dir = (b - a).Unit
		local side = Vector3.new(dir.Z, 0, -dir.X) * cartSide * (W / 2 + 7)
		local mid = (a + b) / 2 + side
		part({ Name = "CartPath", Size = Vector3.new(5, 0.2, (b - a).Magnitude + 5), CFrame = CFrame.lookAt(mid + UP * 0.05, mid + UP * 0.05 + dir), Color = Color3.fromRGB(175, 170, 160), Material = Enum.Material.Concrete }, folder)
	end

	-- 9) ❓ 아이템 상자 (페어웨이 위)
	local boxes = {}
	local boxCount = CC.itemBoxes + extra * CC.boxesPerExtraPlayer
	for i = 1, boxCount do
		local p, dir = pointOnPath(path, (i - 0.5) / boxCount * 0.85 + 0.05)
		local side = Vector3.new(dir.Z, 0, -dir.X) * rng:NextNumber(-W / 2 + 5, W / 2 - 5)
		local box = part({ Name = "ItemBox", Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(p + side + UP * 3) * CFrame.Angles(math.rad(45), math.rad(45), 0), Color = Color3.fromRGB(255, 210, 60), Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false }, folder)
		local bg = Instance.new("BillboardGui")
		bg.Size = UDim2.fromOffset(40, 40)
		bg.StudsOffset = Vector3.new(0, 2.6, 0)
		local q = Instance.new("TextLabel")
		q.Size = UDim2.fromScale(1, 1)
		q.BackgroundTransparency = 1
		q.Text = "❓"
		q.TextScaled = true
		q.Parent = bg
		bg.Parent = box
		box:SetAttribute("Active", true)
		table.insert(boxes, box)
	end

	local hole = {
		folder = folder,
		theme = theme,
		path = path,
		tee = Vector3.new(0, 0.3, 0),
		startDir = startDir,
		cup = cup,
		greenCenter = greenCenter,
		greenRadius = R,
		boxes = boxes,
		boosters = {},
		length = math.floor(length),
		teamSize = teamSize or 2,
		alive = true,
	}
	current = hole

	task.spawn(function()
		while hole.alive do
			task.wait(0.1)
			for _, box in ipairs(boxes) do
				if box.Parent then
					box.CFrame = box.CFrame * CFrame.Angles(0, math.rad(6), 0)
				end
			end
		end
	end)
	return hole
end

-- 팀 공 출발 위치: 티 위 좌우
function CourseBuilder.BallStart(hole, teamIndex, teamCount)
	local side = Vector3.new(hole.startDir.Z, 0, -hole.startDir.X)
	-- 팀 인원이 많을수록 두 팀 공 사이를 넓혀서 출발 때 안 겹치게
	local spread = (teamIndex - (teamCount + 1) / 2) * (9 + math.max(0, (hole.teamSize or 2) - 2) * 4)
	return hole.tee + side * spread + hole.startDir * 2 + UP * (Config.Ball.diameter / 2 + 0.2)
end

-- 선수 출발 위치: 우리 팀 공 바로 뒤
function CourseBuilder.PlayerStart(hole, teamIndex, teamCount, slot, slotCount)
	local ballPos = CourseBuilder.BallStart(hole, teamIndex, teamCount)
	local side = Vector3.new(hole.startDir.Z, 0, -hole.startDir.X)
	local pos = ballPos - hole.startDir * 4 + side * ((slot - ((slotCount or 2) + 1) / 2) * 3) + UP * 3
	return CFrame.lookAt(pos, pos + hole.startDir)
end

function CourseBuilder.Clear()
	workspace.Terrain:Clear() -- 지형도 지움 (로비는 지형을 쓰지 않음)
	if current then
		current.alive = false
		current.folder:Destroy()
		current = nil
	end
end

return CourseBuilder
