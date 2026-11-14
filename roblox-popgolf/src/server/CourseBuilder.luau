-- 홀(코스)을 코드로 만듭니다. 매 홀마다 모양이 새로 바뀝니다.
-- 바닥 타일을 격자 위에 '꼬불꼬불한 길'로 이어 붙이고, 길이 아닌 쪽에는 벽을 세웁니다.
-- 장애물: 범퍼 기둥, 언덕 턱, 회전 막대, 움직이는 블록, 가속 발판, ❓ 아이템 상자

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local CourseBuilder = {}

local T = Config.Course.tile
local UP = Vector3.new(0, 1, 0)
local DIRS = { Vector2.new(0, 1), Vector2.new(1, 0), Vector2.new(0, -1), Vector2.new(-1, 0) }

local THEMES = {
	{ name = "초록 필드", a = Color3.fromRGB(110, 200, 90), b = Color3.fromRGB(95, 180, 80), wall = Color3.fromRGB(240, 240, 240) },
	{ name = "사막 오아시스", a = Color3.fromRGB(240, 210, 140), b = Color3.fromRGB(225, 195, 125), wall = Color3.fromRGB(200, 120, 70) },
	{ name = "눈꽃 마을", a = Color3.fromRGB(235, 245, 255), b = Color3.fromRGB(215, 230, 250), wall = Color3.fromRGB(120, 180, 240) },
	{ name = "사탕 나라", a = Color3.fromRGB(255, 190, 220), b = Color3.fromRGB(250, 170, 205), wall = Color3.fromRGB(255, 255, 255) },
	{ name = "밤하늘 그린", a = Color3.fromRGB(60, 80, 140), b = Color3.fromRGB(50, 70, 125), wall = Color3.fromRGB(255, 220, 90) },
}

local current -- 현재 홀 정보

local function part(props, parent)
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		if k ~= "ClassName" then
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function key(v)
	return v.X .. "," .. v.Y
end

-- 스스로 겹치지 않는 꼬불길 만들기
local function makePath(rng, length)
	for _ = 1, 200 do
		local cells = { Vector2.new(0, 0) }
		local visited = { [key(cells[1])] = true }
		local dirIndex = 1
		local ok = true
		while #cells < length do
			local cur = cells[#cells]
			local options = {}
			-- 직진 60%, 좌·우 20%씩 (뒤로는 안 감)
			for _, choice in ipairs({ { 0, 6 }, { 1, 2 }, { -1, 2 } }) do
				local di = ((dirIndex - 1 + choice[1]) % 4) + 1
				local nxt = cur + DIRS[di]
				local free = not visited[key(nxt)]
				-- 이전 칸 말고 다른 칸과 붙으면 벽이 이상해지므로 피함
				if free then
					for _, d in ipairs(DIRS) do
						local nb = nxt + d
						if nb ~= cur and visited[key(nb)] then
							free = false
						end
					end
				end
				if free then
					for _ = 1, choice[2] do
						table.insert(options, di)
					end
				end
			end
			if #options == 0 then
				ok = false
				break
			end
			dirIndex = options[rng:NextInteger(1, #options)]
			local nxt = cur + DIRS[dirIndex]
			table.insert(cells, nxt)
			visited[key(nxt)] = true
		end
		if ok then
			return cells
		end
	end
	-- 실패하면 일자 코스
	local cells = {}
	for i = 0, length - 1 do
		table.insert(cells, Vector2.new(0, i))
	end
	return cells
end

local function world(origin, cell, y)
	return origin + Vector3.new(cell.X * T, y or 0, cell.Y * T)
end

local function spinner(folder, center, theme, rng)
	local pivot = part({ Name = "Pivot", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 2, 2), CFrame = CFrame.new(center + UP * 1.5) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(80, 80, 90), Material = Enum.Material.Metal }, folder)
	local bar = part({ Name = "SpinBar", Size = Vector3.new(T - 6, 1.4, 1.2), CFrame = CFrame.new(center + UP * 1.2), Color = theme.wall, Material = Enum.Material.SmoothPlastic }, folder)
	bar.Anchored = false
	local rot = CFrame.Angles(0, 0, math.rad(90))
	local a0 = Instance.new("Attachment")
	a0.CFrame = CFrame.new() -- 피벗은 이미 세워져 있어서 X축이 위쪽
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
	hinge.AngularVelocity = rng:NextNumber(1, 1.8) * (rng:NextNumber() < 0.5 and 1 or -1)
	hinge.Parent = bar
	pcall(function()
		bar:SetNetworkOwner(nil)
	end)
end

local function mover(folder, center, along, theme, rng, movers)
	local base = part({ Name = "MoverBase", Size = Vector3.new(1, 1, 1), CFrame = CFrame.lookAt(center + UP * 1.5, center + UP * 1.5 + along), Transparency = 1, CanCollide = false, CanQuery = false }, folder)
	local block = part({ Name = "Mover", Size = Vector3.new(5, 3, 3), CFrame = base.CFrame, Color = theme.wall, Material = Enum.Material.SmoothPlastic }, folder)
	block.Anchored = false
	local a0 = Instance.new("Attachment")
	a0.Parent = base
	local a1 = Instance.new("Attachment")
	a1.Parent = block
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = a0
	prism.Attachment1 = a1
	prism.ActuatorType = Enum.ActuatorType.Servo
	prism.ServoMaxForce = 1e8
	prism.Speed = rng:NextNumber(6, 10)
	prism.Parent = block
	table.insert(movers, { constraint = prism, range = T / 2 - 4, period = (T - 8) / prism.Speed + 0.6, offset = rng:NextNumber(0, 2) })
	pcall(function()
		block:SetNetworkOwner(nil)
	end)
end

function CourseBuilder.Build(holeNumber, seed)
	if current then
		current.alive = false
		current.folder:Destroy()
	end
	local rng = Random.new(seed)
	local theme = THEMES[((holeNumber - 1 + seed) % #THEMES) + 1]
	Lighting.ClockTime = theme.name == "밤하늘 그린" and 20 or 14

	local folder = Instance.new("Folder")
	folder.Name = "Hole"
	folder.Parent = workspace

	local origin = Vector3.new(0, 0, 0)
	local length = rng:NextInteger(Config.Course.minTiles, Config.Course.maxTiles)
	local cells = makePath(rng, length)
	local index = {}
	for i, c in ipairs(cells) do
		index[key(c)] = i
	end

	local hole = { folder = folder, theme = theme, cells = cells, boxes = {}, movers = {}, boosters = {}, alive = true }

	for i, cell in ipairs(cells) do
		local center = world(origin, cell)
		part({ Name = "Floor", Size = Vector3.new(T, 2, T), CFrame = CFrame.new(center - UP), Color = (cell.X + cell.Y) % 2 == 0 and theme.a or theme.b, Material = Enum.Material.Grass }, folder)
		-- 벽: 앞뒤 칸과 이어진 쪽이 아니면 막음
		for _, d in ipairs(DIRS) do
			local nb = cell + d
			local j = index[key(nb)]
			if not (j and math.abs(j - i) == 1) then
				local dir3 = Vector3.new(d.X, 0, d.Y)
				local wallCenter = center + dir3 * (T / 2) + UP * (Config.Course.wallHeight / 2)
				local size = (d.X ~= 0) and Vector3.new(1, Config.Course.wallHeight, T + 1) or Vector3.new(T + 1, Config.Course.wallHeight, 1)
				part({ Name = "Wall", Size = size, CFrame = CFrame.new(wallCenter), Color = theme.wall, Material = Enum.Material.SmoothPlastic }, folder)
				-- 투명 울타리: 선수가 벽을 뛰어넘어 코스 밖으로 떨어지지 않게
				local fenceH = Config.Course.fenceHeight - Config.Course.wallHeight
				local fenceCenter = center + dir3 * (T / 2) + UP * (Config.Course.wallHeight + fenceH / 2)
				local fsize = (d.X ~= 0) and Vector3.new(1, fenceH, T + 1) or Vector3.new(T + 1, fenceH, 1)
				part({ Name = "Fence", Size = fsize, CFrame = CFrame.new(fenceCenter), Transparency = 1, CanQuery = false }, folder)
			end
		end
	end

	-- 출발(티)과 홀컵
	local first, last = cells[1], cells[#cells]
	local teePos = world(origin, first)
	part({ Name = "Tee", Size = Vector3.new(12, 0.2, 6), CFrame = CFrame.new(teePos + UP * 0.1), Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.SmoothPlastic, Transparency = 0.4, CanCollide = false }, folder)
	local cupPos = world(origin, last)
	part({ Name = "Cup", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, Config.Ball.cupRadius * 2, Config.Ball.cupRadius * 2), CFrame = CFrame.new(cupPos + UP * 0.06) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(20, 20, 20), CanCollide = false }, folder)
	part({ Name = "FlagPole", Size = Vector3.new(0.3, 12, 0.3), CFrame = CFrame.new(cupPos + UP * 6), Color = Color3.fromRGB(240, 240, 240), CanCollide = false }, folder)
	local flag = part({ Name = "Flag", Size = Vector3.new(0.2, 3, 4.5), CFrame = CFrame.new(cupPos + UP * 10.5 + Vector3.new(0, 0, 2.2)), Color = Color3.fromRGB(255, 70, 70), Material = Enum.Material.Fabric, CanCollide = false }, folder)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 120)
	light.Range = 18
	light.Parent = flag

	-- 첫 칸에서 둘째 칸 방향 = 출발 방향
	local startDir = Vector3.new(cells[2].X - first.X, 0, cells[2].Y - first.Y)

	-- 중간 칸 장애물
	local middle = {}
	for i = 2, #cells - 1 do
		table.insert(middle, i)
	end
	for _, i in ipairs(middle) do
		local cell = cells[i]
		local center = world(origin, cell)
		local prev, nxt = cells[i - 1], cells[i + 1]
		local inDir = Vector3.new(cell.X - prev.X, 0, cell.Y - prev.Y)
		local outDir = Vector3.new(nxt.X - cell.X, 0, nxt.Y - cell.Y)
		local straight = inDir == outDir
		local roll = rng:NextNumber()
		if roll < 0.22 then
			-- 범퍼 기둥
			for _ = 1, rng:NextInteger(1, 3) do
				local off = Vector3.new(rng:NextNumber(-T / 2 + 4, T / 2 - 4), 0, rng:NextNumber(-T / 2 + 4, T / 2 - 4))
				local bumper = part({ Name = "Bumper", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(center + off + UP * 1.5) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(255, 90, 90), Material = Enum.Material.Neon }, folder)
				bumper.CustomPhysicalProperties = PhysicalProperties.new(1, 0.1, 1, 1, 100) -- 통통 튐
			end
		elseif roll < 0.38 and straight then
			-- 언덕 턱: 바닥에 반쯤 묻힌 원통 (높이 0.6, 샷의 띄움으로 넘어감)
			local cf = CFrame.lookAt(center, center + outDir) -- X축 = 진행 방향의 옆
			part({ Name = "Hump", Shape = Enum.PartType.Cylinder, Size = Vector3.new(T, 4, 4), CFrame = cf * CFrame.new(0, -1.4, 0), Color = theme.b, Material = Enum.Material.Grass }, folder)
		elseif roll < 0.52 then
			spinner(folder, center, theme, rng)
		elseif roll < 0.64 and straight then
			mover(folder, center, outDir, theme, rng, hole.movers)
		elseif roll < 0.78 and straight then
			-- 가속 발판
			local pad = part({ Name = "Booster", Size = Vector3.new(6, 0.2, 8), CFrame = CFrame.lookAt(center + UP * 0.1, center + UP * 0.1 + outDir), Color = Color3.fromRGB(80, 220, 255), Material = Enum.Material.Neon, CanCollide = false }, folder)
			table.insert(hole.boosters, { part = pad, dir = outDir })
		end
	end

	-- ❓ 아이템 상자
	local picks = table.clone(middle)
	for _ = 1, math.min(Config.Course.itemBoxesPerHole, #picks) do
		local idx = table.remove(picks, rng:NextInteger(1, #picks))
		local center = world(origin, cells[idx])
		local off = Vector3.new(rng:NextNumber(-8, 8), 0, rng:NextNumber(-8, 8))
		local box = part({ Name = "ItemBox", Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(center + off + UP * 3) * CFrame.Angles(math.rad(45), math.rad(45), 0), Color = Color3.fromRGB(255, 210, 60), Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false }, folder)
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(40, 40)
		gui.AlwaysOnTop = false
		gui.StudsOffset = Vector3.new(0, 2.2, 0)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "❓"
		label.TextScaled = true
		label.Parent = gui
		gui.Parent = box
		box:SetAttribute("Active", true)
		table.insert(hole.boxes, box)
	end

	hole.tee = teePos
	hole.startDir = startDir
	hole.cup = cupPos
	hole.length = #cells
	current = hole

	-- 움직이는 블록 왕복
	task.spawn(function()
		local t = 0
		while hole.alive do
			task.wait(0.1)
			t += 0.1
			for _, m in ipairs(hole.movers) do
				local phase = math.floor((t + m.offset) / m.period) % 2
				m.constraint.TargetPosition = phase == 0 and m.range or -m.range
			end
			for _, box in ipairs(hole.boxes) do
				if box.Parent then
					box.CFrame = box.CFrame * CFrame.Angles(0, math.rad(6), 0)
				end
			end
		end
	end)

	return hole
end

-- 팀 공 출발 위치: 티 위에 팀마다 좌우로 나란히
function CourseBuilder.BallStart(hole, teamIndex, teamCount)
	local side = Vector3.new(hole.startDir.Z, 0, -hole.startDir.X)
	local spread = (teamIndex - (teamCount + 1) / 2) * 7
	return hole.tee + side * spread + UP * (Config.Ball.diameter / 2 + 0.2)
end

-- 선수 출발 위치: 우리 팀 공 바로 뒤
function CourseBuilder.PlayerStart(hole, teamIndex, teamCount, slot)
	local ballPos = CourseBuilder.BallStart(hole, teamIndex, teamCount)
	local side = Vector3.new(hole.startDir.Z, 0, -hole.startDir.X)
	local pos = ballPos - hole.startDir * 6 + side * ((slot - 1.5) * 3) + UP * 3
	return CFrame.lookAt(pos, pos + hole.startDir)
end

function CourseBuilder.Clear()
	if current then
		current.alive = false
		current.folder:Destroy()
		current = nil
	end
end

return CourseBuilder
