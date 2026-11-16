-- 3D 모델러 에셋 연결
-- Studio 에서 FBX 를 가져와(3D 가져오기) ReplicatedStorage > Assets 폴더에 넣으면, 이름으로 찾아 배치합니다.
-- 에셋이 없으면 Has() 가 false → 각 빌더가 지금의 기본 도형으로 대체합니다.
--
-- 부품 이름 규칙 (모델링 요청서 5장)
--   Neon_<색>_*   : Neon 재질 + 해당 색 (Cyan/Pink/Purple/Gold/White)
--   Collider_*    : 보이지 않는 충돌면 (이 부품이 있는 모델은 나머지 부품 충돌 끔)
--   Point_*       : 위치만 읽고 숨김 (handle.points 로 돌려줌)
--   Screen_*      : 글자를 띄울 화면 (정면 = Front 면)
--   TeamColor_*   : opts.teamColor 로 칠함
--   Seat_Red/Blue/White_* : 관중석 의자 색 고정
--   Glass_*       : 반투명 유리
-- 이름 뒤에 Blender 가 붙인 ".001" 같은 번호는 떼고 읽습니다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetLib = {}

-- 모델의 "바닥 가운데 기준점"이 모델 전체 상자의 밑면 가운데에서 얼마나 떨어져 있는지 (로블록스 축, 스터드)
-- 납품 FBX 를 직접 재서 만든 값. 가져온 모델의 기준점(Pivot)이 어디에 잡히든 정확한 자리에 놓기 위함
AssetLib.ORIGIN = {
	-- 1차 로비 소품 / 구조물
	Board_Frame = Vector3.new(0, 0, 0),
	Podium = Vector3.new(0, 0, 0),
	Capsule_Machine = Vector3.new(0, 0, 0.028),
	Club_Showcase = Vector3.new(0, 0, 0),
	Kiosk = Vector3.new(0, 0, 0),
	Lobby_Hall = Vector3.new(0, -2, 0),
	Stand_Curve30 = Vector3.new(0, 0, -7.492),
	Stand_Straight20 = Vector3.new(0, 0, -7.9),
	Light_Tower = Vector3.new(0, 0, 0),
	LED_Board = Vector3.new(0, 0, 0),
	-- 2차 코스 장식
	Tree_Round_A = Vector3.new(-0.024, 0, -0.151),
	Tree_Round_B = Vector3.new(-0.019, 0, -0.38),
	Tree_Pine = Vector3.new(0, 0, 0),
	Tree_Palm = Vector3.new(0.82, -0.04, 0),
	Bush_A = Vector3.new(-0.03, -0.479, -0.015),
	Bush_B = Vector3.new(-0.051, -0.506, 0.075),
	Rock_A = Vector3.new(-0.066, 0, -0.286),
	Rock_B = Vector3.new(0.255, 0, 0.084),
	Rock_C = Vector3.new(0.027, 0, -0.037),
	Flower_A = Vector3.new(-0.228, 0, -0.014),
	Flower_B = Vector3.new(0.208, 0, 0.085),
	Flag_Cup = Vector3.new(0.77, -0.495, 0),
	Tee_Marker = Vector3.new(0, 0, 0),
	Golf_Cart = Vector3.new(0, 0, 0),
	Neon_Arch_Gate = Vector3.new(0, 0, 0),
	-- 3차 장비 (헤드 기준점 = 샤프트가 끼워지는 자리)
	Club_Head_Basic = Vector3.new(0.025, -0.83, 0.688),
	Club_Head_Leg1 = Vector3.new(0.114, -0.79, 0.728),
	Club_Head_Leg2 = Vector3.new(0.11, -0.81, 0.705),
	Club_Head_Leg3 = Vector3.new(0.025, -0.8, 0.812),
	Club_Head_Myth1 = Vector3.new(0.189, -0.82, 0.889),
	Club_Head_Myth2 = Vector3.new(0.135, -0.943, 0.763),
	Club_Shaft_Parts = Vector3.new(0, -0.5, 0),
	Team_Ball = Vector3.new(0, -1.1, 0),
	Team_Cap = Vector3.new(0, -0.125, 0.221),
}

local NEON = {
	Cyan = Color3.fromRGB(60, 230, 255),
	Pink = Color3.fromRGB(255, 70, 190),
	Purple = Color3.fromRGB(150, 80, 255),
	Gold = Color3.fromRGB(255, 200, 70),
	White = Color3.fromRGB(255, 252, 240),
	Multi = Color3.fromRGB(60, 230, 255),
}
local SEAT = {
	Red = Color3.fromRGB(255, 80, 80),
	Blue = Color3.fromRGB(80, 150, 255),
	White = Color3.fromRGB(230, 236, 255),
}
-- 텍스처가 안 붙어 왔을 때(가져오기에서 PNG 를 못 찾은 경우) 이름으로 고르는 기본 색. 위에서부터 먼저 맞는 것
local FALLBACK = {
	{ "DarkNavy", Color3.fromRGB(26, 30, 58), "SmoothPlastic" },
	{ "MidNavy", Color3.fromRGB(32, 38, 78), "SmoothPlastic" },
	{ "LightNavy", Color3.fromRGB(48, 58, 110), "SmoothPlastic" },
	{ "Metal", Color3.fromRGB(22, 27, 51), "Metal" },
	{ "Teal", Color3.fromRGB(26, 188, 156), "SmoothPlastic" },
	{ "Pine", Color3.fromRGB(30, 132, 73), "SmoothPlastic" },
	{ "Leaves", Color3.fromRGB(46, 204, 113), "SmoothPlastic" },
	{ "Stems", Color3.fromRGB(46, 204, 113), "SmoothPlastic" },
	{ "Coconut", Color3.fromRGB(74, 46, 27), "SmoothPlastic" },
	{ "Trunk", Color3.fromRGB(92, 62, 46), "Wood" },
	{ "Rock_B", Color3.fromRGB(48, 58, 110), "Slate" },
	{ "Rock", Color3.fromRGB(74, 85, 104), "Slate" },
	{ "Tires", Color3.fromRGB(24, 25, 32), "SmoothPlastic" },
	{ "White", Color3.fromRGB(235, 240, 255), "SmoothPlastic" },
	{ "Grip", Color3.fromRGB(34, 37, 48), "Fabric" },
	{ "Shaft", Color3.fromRGB(212, 218, 232), "Metal" },
	{ "Ferrule", Color3.fromRGB(22, 24, 34), "Metal" },
	{ "Brim", Color3.fromRGB(26, 30, 58), "Fabric" },
	{ "Ball", Color3.fromRGB(245, 245, 245), "SmoothPlastic" },
}

local function baseName(name)
	return (string.gsub(name, "%.%d+$", ""))
end
AssetLib.BaseName = baseName

local function startsWith(s, prefix)
	return string.sub(s, 1, #prefix) == prefix
end

local function folder()
	return ReplicatedStorage:FindFirstChild("Assets")
end

local function find(name)
	local f = folder()
	if not f then
		return nil
	end
	local direct = f:FindFirstChild(name)
	if direct then
		return direct
	end
	for _, c in ipairs(f:GetChildren()) do
		if baseName(c.Name) == name then
			return c
		end
	end
	return nil
end

function AssetLib.Has(name)
	return find(name) ~= nil
end

-- 하나라도 있으면 그 이름 목록을, 없으면 nil
function AssetLib.Available(names)
	local list = {}
	for _, n in ipairs(names) do
		if find(n) then
			table.insert(list, n)
		end
	end
	return #list > 0 and list or nil
end

local function hasTexture(p)
	if p:FindFirstChildOfClass("SurfaceAppearance") then
		return true
	end
	if p:IsA("MeshPart") and p.TextureID ~= "" then
		return true
	end
	return false
end

local function keyword(name, map)
	for k, v in pairs(map) do
		if string.find(name, k, 1, true) then
			return v
		end
	end
	return nil
end

local function styleParts(model, opts)
	local parts = {}
	local hasCollider = false
	for _, d in ipairs(model:GetDescendants()) do
		d.Name = baseName(d.Name)
		if d:IsA("BasePart") then
			table.insert(parts, d)
			if startsWith(d.Name, "Collider_") then
				hasCollider = true
			end
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local collide = opts.collide ~= false
	for _, p in ipairs(parts) do
		local n = p.Name
		p.Anchored = opts.anchored ~= false
		p.CanCollide = collide and not hasCollider
		if startsWith(n, "Point_") then
			p.Transparency = 1
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
		elseif startsWith(n, "Collider_") then
			p.Transparency = 1
			p.CanCollide = collide
			p.CastShadow = false
		elseif startsWith(n, "Neon_") then
			p.Material = Enum.Material.Neon
			p.Color = keyword(n, NEON) or NEON.Cyan
			p.CanCollide = false
			p.CastShadow = false
		elseif startsWith(n, "Glass_") then
			p.Material = Enum.Material.Glass
			p.Transparency = 0.55
			p.CanCollide = false
		elseif startsWith(n, "Screen_") then
			p.Material = Enum.Material.SmoothPlastic
			p.Color = Color3.fromRGB(10, 14, 30)
		elseif startsWith(n, "TeamColor_") then
			p.Color = opts.teamColor or Color3.fromRGB(255, 80, 80)
			p.Material = Enum.Material.SmoothPlastic
		elseif startsWith(n, "Seat_") then
			p.Color = keyword(n, SEAT) or SEAT.White
			p.Material = Enum.Material.SmoothPlastic
		elseif startsWith(n, "Club_Gem") then
			p.Material = Enum.Material.Neon
		elseif not hasTexture(p) then
			for _, f in ipairs(FALLBACK) do
				if string.find(n, f[1], 1, true) then
					p.Color = f[2]
					p.Material = Enum.Material[f[3]]
					break
				end
			end
		end
	end
	return parts
end

-- 이름이 name 인 에셋을 cf(기준점 = 바닥 가운데, 정면 = -Z)에 놓습니다.
-- opts: parent, teamColor, scale, collide(기본 true), anchored(기본 true)
-- 반환: { model, parts = {이름 → 부품}, points = {Point_이름 → CFrame} } 또는 에셋이 없으면 nil
function AssetLib.Spawn(name, cf, opts)
	opts = opts or {}
	local template = find(name)
	if not template then
		return nil
	end
	local model = template:Clone()
	if not model:IsA("Model") then
		local wrap = Instance.new("Model")
		model.Parent = wrap
		model = wrap
	end
	model.Name = name
	local parts = styleParts(model, opts)
	if #parts == 0 then
		model:Destroy()
		return nil
	end

	-- 지금 놓인 상태에서 모든 부품을 감싸는 상자 → 밑면 가운데 → 기준점
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = -minV
	for _, p in ipairs(parts) do
		local h = p.Size / 2
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local w = p.CFrame:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
					minV = minV:Min(w)
					maxV = maxV:Max(w)
				end
			end
		end
	end
	local bottomCenter = Vector3.new((minV.X + maxV.X) / 2, minV.Y, (minV.Z + maxV.Z) / 2)
	local origin = bottomCenter - (AssetLib.ORIGIN[name] or Vector3.zero)
	model.WorldPivot = CFrame.new(origin)
	if opts.scale and opts.scale ~= 1 then
		model:ScaleTo(opts.scale)
	end
	model:PivotTo(cf or CFrame.new())

	local handle = { model = model, parts = {}, points = {} }
	for _, p in ipairs(parts) do
		handle.parts[p.Name] = handle.parts[p.Name] or p
		if startsWith(p.Name, "Point_") then
			handle.points[p.Name] = p.CFrame
		end
	end
	model.Parent = opts.parent
	return handle
end

-- 캐릭터·골프채에 붙일 부품 목록. 기준점 기준 상대 위치(offset)와 함께, 고정 해제·충돌 끈 상태로 돌려줌
-- 반환: { { part = 부품, offset = CFrame }, ... } (Point_ 부품은 빼고) 또는 nil
function AssetLib.Parts(name, opts)
	opts = opts or {}
	opts.anchored = false
	opts.collide = false
	local h = AssetLib.Spawn(name, CFrame.new(), opts)
	if not h then
		return nil
	end
	local list = {}
	for _, d in ipairs(h.model:GetDescendants()) do
		if d:IsA("BasePart") and not startsWith(d.Name, "Point_") and not startsWith(d.Name, "Collider_") then
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			table.insert(list, { part = d, offset = d.CFrame })
		end
	end
	for _, item in ipairs(list) do
		item.part.Parent = nil
	end
	h.model:Destroy()
	return list
end

return AssetLib
