-- 대기실(로비)과 경기장을 코드로 만듭니다.
-- 경기장은 라운드마다 장애물 배치가 새로 바뀌어서 매판 새로운 숨바꼭질 지형이 됩니다.

local Lighting = game:GetService("Lighting")

local ArenaBuilder = {}

local ARENA_SIZE = 170
local LOBBY_Y = 300

local arenaFolder
local PASTELS = {
	Color3.fromRGB(255, 190, 200),
	Color3.fromRGB(190, 225, 255),
	Color3.fromRGB(200, 255, 210),
	Color3.fromRGB(255, 240, 180),
	Color3.fromRGB(225, 200, 255),
	Color3.fromRGB(255, 215, 180),
}

local function part(className, props)
	local p = Instance.new(className)
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

function ArenaBuilder.BuildLobby()
	Lighting.ClockTime = 15
	Lighting.Brightness = 2.2
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	lobby.Parent = workspace
	part("Part", { Size = Vector3.new(90, 2, 90), Position = Vector3.new(0, LOBBY_Y, 0), Color = Color3.fromRGB(210, 235, 255), Material = Enum.Material.Ice, Parent = lobby })
	-- 난간
	for _, o in ipairs({ { 0, 45, 90, 1 }, { 0, -45, 90, 1 }, { 45, 0, 1, 90 }, { -45, 0, 1, 90 } }) do
		part("Part", { Size = Vector3.new(o[3], 6, o[4]), Position = Vector3.new(o[1], LOBBY_Y + 4, o[2]), Transparency = 0.6, Color = Color3.fromRGB(180, 220, 255), Material = Enum.Material.Glass, Parent = lobby })
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.Position = Vector3.new(0, LOBBY_Y + 1.5, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(120, 190, 255)
	spawn.Material = Enum.Material.Neon
	spawn.Parent = lobby
	-- 장식용 눈사람 기둥
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		local pos = Vector3.new(math.cos(a) * 30, LOBBY_Y + 1, math.sin(a) * 30)
		part("Part", { Shape = Enum.PartType.Ball, Size = Vector3.one * 5, Position = pos + Vector3.new(0, 2.5, 0), Color = Color3.new(1, 1, 1), Material = Enum.Material.Snow, Parent = lobby })
		part("Part", { Shape = Enum.PartType.Ball, Size = Vector3.one * 3.5, Position = pos + Vector3.new(0, 6.5, 0), Color = Color3.new(1, 1, 1), Material = Enum.Material.Snow, Parent = lobby })
	end
	return CFrame.new(0, LOBBY_Y + 4, 0)
end

function ArenaBuilder.BuildArena()
	if arenaFolder then
		arenaFolder:Destroy()
	end
	arenaFolder = Instance.new("Folder")
	arenaFolder.Name = "Arena"
	arenaFolder.Parent = workspace

	local rng = Random.new()
	local half = ARENA_SIZE / 2
	part("Part", { Size = Vector3.new(ARENA_SIZE, 2, ARENA_SIZE), Position = Vector3.new(0, -1, 0), Color = Color3.fromRGB(235, 245, 255), Material = Enum.Material.Snow, Parent = arenaFolder })
	for _, o in ipairs({ { 0, half, ARENA_SIZE, 2 }, { 0, -half, ARENA_SIZE, 2 }, { half, 0, 2, ARENA_SIZE }, { -half, 0, 2, ARENA_SIZE } }) do
		part("Part", { Size = Vector3.new(o[3], 30, o[4]), Position = Vector3.new(o[1], 15, o[2]), Transparency = 0.7, Color = Color3.fromRGB(180, 220, 255), Material = Enum.Material.Glass, Parent = arenaFolder })
	end

	-- 장애물: 상자, 벽, 경사로, 기둥 → 숨고 돌아 도망칠 길을 만들어 줌
	for _ = 1, 45 do
		local kind = rng:NextInteger(1, 4)
		local x = rng:NextNumber(-half + 12, half - 12)
		local z = rng:NextNumber(-half + 12, half - 12)
		-- 가운데 시작 지점은 비워 둠
		if math.abs(x) < 14 and math.abs(z) < 14 then
			continue
		end
		local color = PASTELS[rng:NextInteger(1, #PASTELS)]
		local yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		if kind == 1 then
			local s = Vector3.new(rng:NextNumber(6, 14), rng:NextNumber(4, 9), rng:NextNumber(6, 14))
			part("Part", { Size = s, CFrame = CFrame.new(x, s.Y / 2, z) * yaw, Color = color, Material = Enum.Material.SmoothPlastic, Parent = arenaFolder })
		elseif kind == 2 then
			local s = Vector3.new(rng:NextNumber(16, 30), 8, 2)
			part("Part", { Size = s, CFrame = CFrame.new(x, 4, z) * yaw, Color = color, Material = Enum.Material.Brick, Parent = arenaFolder })
		elseif kind == 3 then
			local s = Vector3.new(8, rng:NextNumber(4, 8), 14)
			part("WedgePart", { Size = s, CFrame = CFrame.new(x, s.Y / 2, z) * yaw, Color = color, Material = Enum.Material.SmoothPlastic, Parent = arenaFolder })
		else
			part("Part", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(14, 5, 5), CFrame = CFrame.new(x, 7, z) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(150, 110, 80), Material = Enum.Material.Wood, Parent = arenaFolder })
			part("Part", { Shape = Enum.PartType.Ball, Size = Vector3.one * 11, CFrame = CFrame.new(x, 16, z), Color = Color3.fromRGB(110, 190, 120), Material = Enum.Material.Grass, CanCollide = false, Parent = arenaFolder })
		end
	end
end

-- 술래는 가운데, 도망자는 가장자리 쪽에 흩어 놓음
function ArenaBuilder.SpawnPoint(isTagger, index, total)
	if isTagger then
		return CFrame.new((index - 1) * 4, 4, 0)
	end
	local a = (index / math.max(total, 1)) * math.pi * 2
	local r = ARENA_SIZE / 2 - 18
	return CFrame.new(math.cos(a) * r, 12, math.sin(a) * r) -- 장애물 위에 떨어져도 괜찮게 높이서
end

return ArenaBuilder
