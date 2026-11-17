-- 골프채: 가슴 앞 스윙 중심에 관절(Motor6D "ClubMotor")로 붙입니다.
-- 캐릭터마다 키·팔 길이를 재서(ClubRig) 골프채 길이와 기울기를 맞춤 → 어드레스 때 클럽 머리가 발 앞 땅(스윙 존)에 닿음
-- 팔은 각 화면의 SwingAnimator 가 손잡이 쪽으로 뻗게 계산 (R6·R15 모두)
--
-- 골프채 좌표: 샤프트 길이 방향 = 로컬 Y (손잡이가 +Y), 클럽 머리 치는 면 = 로컬 -X
-- 모델 속성(클라이언트가 읽음): Tilt(도), GripDist, Skin

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local ClubRig = require(ReplicatedStorage.Shared.ClubRig)
local AssetLib = require(ReplicatedStorage.Shared.AssetLib)

local Club = {}

local function weldTo(base, part, offset)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.CFrame = base.CFrame * offset
	-- Weld(C0 고정): 샤프트를 나중에 옮겨도 부품이 항상 같은 자리에 붙어 있음
	-- (WeldConstraint 는 게임 세계에 들어갈 때의 위치를 기록해서, 먼저 붙이고 샤프트를 옮기면 부품이 떨어져 나감)
	local w = Instance.new("Weld")
	w.Part0 = base
	w.Part1 = part
	w.C0 = offset
	w.Parent = part
end

-- geo: ClubRig.Geometry 결과 (headDist = 스윙 중심~클럽 머리, grip = 스윙 중심~손잡이)
local function makeClub(geo)
	local model = Instance.new("Model")
	model.Name = "GolfClub"
	-- 스트리밍이 켜져 있어도 골프채 부품이 한꺼번에 도착하게
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)

	-- 샤프트: 손잡이 위끝(grip - 0.5) ~ 클럽 머리(headDist)
	local top = geo.grip - 0.5
	local length = geo.headDist - top
	local center = top + length / 2 -- 스윙 중심에서 샤프트 중심까지

	local shaft = Instance.new("Part")
	shaft.Name = "Shaft"
	shaft.Size = Vector3.new(0.18, length, 0.18)
	shaft.Color = Color3.fromRGB(195, 200, 210)
	shaft.Material = Enum.Material.Metal
	shaft.CanCollide = false
	shaft.CanQuery = false
	shaft.CanTouch = false
	shaft.Massless = true
	shaft.CastShadow = false
	shaft.Parent = model

	-- 스윙 중심에서 거리 d 인 곳의 샤프트 로컬 Y (멀수록 아래)
	local function at(d)
		return center - d
	end

	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(0.3, 0.9, 0.3)
	grip.Color = Color3.fromRGB(35, 35, 40)
	grip.Material = Enum.Material.Fabric
	weldTo(shaft, grip, CFrame.new(0, at(geo.grip), 0))
	grip.Parent = model

	local ferrule = Instance.new("Part")
	ferrule.Name = "Ferrule"
	ferrule.Size = Vector3.new(0.28, 0.3, 0.28)
	ferrule.Color = Color3.fromRGB(170, 175, 185)
	ferrule.Material = Enum.Material.Foil
	weldTo(shaft, ferrule, CFrame.new(0, at(geo.headDist - 0.45), 0))
	ferrule.Parent = model

	-- 클럽 머리: 앞(발끝 쪽, 로컬 -Z)으로 길게, 치는 면은 목표 쪽(-X)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(0.75, 0.7, 1.7)
	weldTo(shaft, head, CFrame.new(0, at(geo.headDist), -0.45))
	head.Parent = model

	local gem = Instance.new("Part")
	gem.Name = "Gem"
	gem.Shape = Enum.PartType.Ball
	gem.Size = Vector3.one * 0.38
	gem.Material = Enum.Material.Neon
	gem.Transparency = 1
	weldTo(shaft, gem, CFrame.new(-0.3, at(geo.headDist) + 0.05, -0.55))
	gem.Parent = model

	model.PrimaryPart = shaft

	-- 모델러 샤프트 메시 (Assets > Club_Shaft_Parts: Club_Grip · Club_Shaft · Club_Ferrule)
	-- 기본 부품과 같은 크기·자리에 겉모습만 덮어씌움 (기본 부품은 투명하게 남겨 관절·이펙트 기준으로 씀)
	local looks = AssetLib.Parts("Club_Shaft_Parts")
	if looks then
		local map = { Club_Grip = grip, Club_Shaft = shaft, Club_Ferrule = ferrule }
		for _, item in ipairs(looks) do
			local base = map[AssetLib.BaseName(item.part.Name)]
			if base then
				local m = item.part
				m.Name = base.Name .. "Look"
				m.Size = base.Size
				weldTo(shaft, m, shaft.CFrame:ToObjectSpace(base.CFrame))
				m.Parent = model
				base:SetAttribute("HasLook", true)
				base.Transparency = 1
			else
				item.part:Destroy()
			end
		end
	end
	model:SetAttribute("ShaftCenter", center)
	model:SetAttribute("HeadY", at(geo.headDist))
	return model
end

-- 모델러 헤드 메시 (Assets 에 있을 때). 스킨에 head 가 지정돼 있으면 그 모양, 아니면 기본형
-- 헤드 기준점(샤프트가 끼워지는 자리)을 샤프트 끝보다 0.48 위에 두면 헤드 몸통 높이가 기존 Head 와 같아짐
local HEAD_RAISE = 0.48
local function setHeadMesh(model, skin)
	local old = model:FindFirstChild("HeadMesh")
	local want = skin.head or "Club_Head_Basic"
	if old and old:GetAttribute("Asset") == want then
		return old
	end
	if old then
		old:Destroy()
	end
	local list = AssetLib.Parts(want) or (want ~= "Club_Head_Basic" and AssetLib.Parts("Club_Head_Basic"))
	if not list then
		return nil
	end
	local shaft = model.PrimaryPart
	local holder = Instance.new("Model")
	holder.Name = "HeadMesh"
	holder:SetAttribute("Asset", want)
	-- (헤드가 좌우 뒤집혀 보이던 건 AssetLib 기준점 부호 문제였음 → AssetLib 에서 고침, 여기선 그대로 붙임)
	local originOffset = CFrame.new(0, (model:GetAttribute("HeadY") or 0) + HEAD_RAISE, 0)
	for _, item in ipairs(list) do
		weldTo(shaft, item.part, originOffset * item.offset)
		item.part.Parent = holder
	end
	holder.Parent = model
	return holder
end

-- 통째 모델 골프채 (손잡이~헤드 한 덩어리, 예: Meshy 드라이버)
-- 로블록스로 가져오면 헤드가 아래, 손잡이가 위로 섬 → 그대로 두고 손잡이 끝을 샤프트 위끝에 맞춤
-- (반대로 들어오는 모델은 스킨에 modelFlip = true), 길이는 이 캐릭터의 샤프트에 맞게 늘림
local function setFullModel(model, skin)
	local old = model:FindFirstChild("FullMesh")
	if old and old:GetAttribute("Asset") == skin.model then
		return old
	end
	if old then
		old:Destroy()
	end
	local list = skin.model and AssetLib.Parts(skin.model)
	if not list then
		return nil
	end
	local shaft = model.PrimaryPart
	-- 원본 높이 (기준점 = 바닥 가운데 = 손잡이 끝)
	local maxY = 0
	for _, item in ipairs(list) do
		local h = item.part.Size / 2
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					maxY = math.max(maxY, (item.offset * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)).Y)
				end
			end
		end
	end
	local length = shaft.Size.Y
	local scale = (length + 0.9) / math.max(maxY, 0.01) -- 손잡이 위 0.3 + 샤프트 + 헤드 0.6
	local holder = Instance.new("Model")
	holder.Name = "FullMesh"
	holder:SetAttribute("Asset", skin.model)
	local top = length / 2 + 0.3 -- 손잡이 끝 자리 (샤프트 로컬 Y)
	local place
	if skin.modelFlip then
		place = CFrame.new(0, top, 0) * CFrame.Angles(math.pi, 0, 0)
	else
		place = CFrame.new(0, top - maxY * scale, 0)
	end
	place *= CFrame.Angles(0, math.rad(skin.modelYaw or 0), 0)
	for _, item in ipairs(list) do
		local p = item.part
		p.Size *= scale
		local o = item.offset
		weldTo(shaft, p, place * (CFrame.new(o.Position * scale) * o.Rotation))
		p.Parent = holder
	end
	holder.Parent = model
	return holder
end

local function applySkin(model, skinId)
	local skin = Config.Skins[skinId] or Config.Skins.White
	-- 통째 모델 스킨이면 기본 샤프트·손잡이·헤드를 숨기고 모델만 보이게 (Head 는 이펙트 기준점이라 투명하게 남김)
	local full = skin.model and setFullModel(model, skin)
	local oldFull = model:FindFirstChild("FullMesh")
	if not full and oldFull then
		oldFull:Destroy()
	end
	if full then
		local hm = model:FindFirstChild("HeadMesh")
		if hm then
			hm:Destroy()
		end
		for _, n in ipairs({ "Shaft", "Grip", "Ferrule", "Head", "Gem", "ShaftLook", "GripLook", "FerruleLook" }) do
			local p = model:FindFirstChild(n)
			if p then
				p.Transparency = 1
			end
		end
		model:SetAttribute("Skin", skinId)
		return
	end
	for _, n in ipairs({ "Shaft", "Grip", "Ferrule" }) do
		local p = model:FindFirstChild(n)
		if p then
			p.Transparency = p:GetAttribute("HasLook") and 1 or 0
		end
		local look = model:FindFirstChild(n .. "Look")
		if look then
			look.Transparency = 0
		end
	end
	local head = model:FindFirstChild("Head")
	local gem = model:FindFirstChild("Gem")
	local ferrule = model:FindFirstChild("Ferrule")
	local shaft = model:FindFirstChild("Shaft")
	head.Color = skin.color
	head.Material = Enum.Material[skin.material] or Enum.Material.SmoothPlastic
	local rarityIndex = Config.RarityById[skin.rarity].index
	local accent = (skin.trail and skin.trail[1]) or skin.color
	local glow = (skin.trail and skin.trail[#skin.trail]) or skin.color
	gem.Transparency = rarityIndex >= 3 and 0 or 1
	-- 헤드 메시가 있으면: 기존 Head 는 투명하게 남겨 두고(이펙트 기준점) 메시를 스킨 색으로 칠함
	local mesh = setHeadMesh(model, skin)
	if mesh then
		head.Transparency = 1
		local meshGem = false
		for _, p in ipairs(mesh:GetChildren()) do
			local n = p.Name
			if string.sub(n, 1, 9) == "Head_Base" then
				p.Color = skin.color
				-- 헤드 몸통은 빛나지 않게 (Neon 이면 하얗게 번져서 모양이 안 보임) → 빛은 테두리 띠·보석이 담당
				p.Material = head.Material == Enum.Material.Neon and Enum.Material.SmoothPlastic or head.Material
			elseif string.sub(n, 1, 11) == "Head_Accent" then
				p.Color = accent:Lerp(Color3.new(0, 0, 0), 0.25)
				p.Material = rarityIndex >= 4 and Enum.Material.Foil or Enum.Material.Metal
			elseif string.sub(n, 1, 5) == "Neon_" then
				p.Color = glow
			elseif string.sub(n, 1, 8) == "Club_Gem" then
				p.Color = glow
				p.Transparency = rarityIndex >= 3 and 0 or 1
				meshGem = true
			end
			local sa = p:FindFirstChildOfClass("SurfaceAppearance")
			if sa and (n:sub(1, 9) == "Head_Base" or n:sub(1, 11) == "Head_Accent") then
				pcall(function()
					sa.Color = p.Color
				end)
			end
		end
		if meshGem then
			gem.Transparency = 1
		end
	else
		head.Transparency = 0
	end
	gem.Color = glow
	-- 샤프트: 일반은 은색, 희귀부터 스킨 색이 살짝 섞임
	if shaft then
		shaft.Color = rarityIndex >= 2 and Color3.fromRGB(200, 205, 215):Lerp(accent, 0.55) or Color3.fromRGB(200, 205, 215)
	end
	-- 금속 띠: 스킨 색, 영웅부터 빛남, 전설부터 금색 테
	ferrule.Color = rarityIndex >= 4 and Color3.fromRGB(255, 215, 120) or accent
	ferrule.Material = rarityIndex >= 3 and Enum.Material.Neon or Enum.Material.Foil
	-- 샤프트 메시가 있으면 같은 색·재질 입히기 (손잡이는 메시 원래 고무 색 유지)
	for _, n in ipairs({ "Shaft", "Ferrule" }) do
		local base, look = model:FindFirstChild(n), model:FindFirstChild(n .. "Look")
		if base and look then
			look.Color = base.Color
			look.Material = base.Material
		end
	end
	model:SetAttribute("Skin", skinId)
end

-- 캐릭터에 골프채 붙이기 (이미 있으면 스킨만 갱신)
function Club.Give(player, skinId)
	local character = player.Character
	if not character then
		return
	end
	local model = character:FindFirstChild("GolfClub")
	if not model then
		local info = ClubRig.Info(character)
		if not info then
			warn("[Club] 캐릭터 관절을 찾지 못했어요:", player.Name)
			return
		end
		local geo = ClubRig.Geometry(info, Config.Club.stanceOffset)
		model = makeClub(geo)
		local shaft = model.PrimaryPart
		local pivot = CFrame.new(info.pivot)
		local offset = CFrame.new(0, model:GetAttribute("ShaftCenter"), 0)
		shaft.CFrame = info.torso.CFrame * pivot * CFrame.Angles(math.rad(geo.tilt), 0, 0) * offset:Inverse()
		local motor = Instance.new("Motor6D")
		motor.Name = "ClubMotor"
		motor.Part0 = info.torso
		motor.Part1 = shaft
		motor.C0 = pivot
		motor.C1 = offset
		motor.Parent = info.torso
		model:SetAttribute("Tilt", geo.tilt)
		model:SetAttribute("GripDist", geo.grip)
		model.Parent = character
	end
	applySkin(model, skinId)
end

-- 팀 색 골프 모자 (경기 중에만). 둥근 윗부분 + 앞 챙
function Club.GiveCap(player, color)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	Club.RemoveCap(player)
	local cap = Instance.new("Model")
	cap.Name = "TeamCap"
	local crown = Instance.new("Part")
	crown.Name = "Crown"
	crown.Size = Vector3.new(1.35, 0.7, 1.35)
	crown.Color = color
	crown.Material = Enum.Material.Fabric
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = crown
	local brim = Instance.new("Part")
	brim.Name = "Brim"
	brim.Size = Vector3.new(1.1, 0.12, 0.8)
	brim.Color = color:Lerp(Color3.new(0, 0, 0), 0.25)
	brim.Material = Enum.Material.Fabric
	local button = Instance.new("Part")
	button.Name = "Button"
	button.Shape = Enum.PartType.Ball
	button.Size = Vector3.one * 0.25
	button.Color = Color3.new(1, 1, 1)
	button.Material = Enum.Material.SmoothPlastic
	local top = head.Size.Y * 0.42
	-- 모델러 모자 (Assets > Team_Cap): 윗부분은 팀 색, 챙은 조금 어둡게
	local meshCap = AssetLib.Parts("Team_Cap", { teamColor = color })
	if meshCap then
		for _, item in ipairs(meshCap) do
			if string.sub(item.part.Name, 1, 8) == "Cap_Brim" then
				item.part.Color = color:Lerp(Color3.new(0, 0, 0), 0.35)
			end
			weldTo(head, item.part, CFrame.new(0, top - 0.3, 0.05) * item.offset)
			item.part.Parent = cap
		end
		crown:Destroy()
		brim:Destroy()
		button:Destroy()
		cap.Parent = character
		return
	end
	weldTo(head, crown, CFrame.new(0, top, 0.05))
	weldTo(head, brim, CFrame.new(0, top - 0.22, -0.72))
	weldTo(head, button, CFrame.new(0, top + 0.36, 0.05))
	crown.Parent = cap
	brim.Parent = cap
	button.Parent = cap
	cap.Parent = character
end

function Club.RemoveCap(player)
	local character = player.Character
	local cap = character and character:FindFirstChild("TeamCap")
	if cap then
		cap:Destroy()
	end
end

----------------------------------------------------------------------
-- 🦸 영웅 외형 (Assets > Hero_<영웅 id>): 이름 앞부분으로 붙는 자리를 정함
--   Head_  → 머리 정수리 (모델의 Point_Head 기준)
--   Back_ / Waist_ / Float_ → 몸통 등 (Point_Back 기준, Float_ 은 Point_Float 이 있으면 그 기준)
--   이름 안에 TeamColor_ = 팀 색 (로비에서는 영웅 색), Neon_<색> = 빛남
--   Pinwheel · ClockHand · Ring 이 들어간 부품은 빙글빙글, Float_ 은 둥실둥실 (클라이언트 ClubFX 가 움직임)
----------------------------------------------------------------------
local NEON_WORDS = {
	Orange = Color3.fromRGB(255, 140, 50), Cyan = Color3.fromRGB(60, 220, 255), Pink = Color3.fromRGB(255, 90, 180),
	Yellow = Color3.fromRGB(255, 230, 60), Purple = Color3.fromRGB(170, 90, 255), Gold = Color3.fromRGB(255, 205, 80),
	White = Color3.fromRGB(240, 245, 255), Green = Color3.fromRGB(80, 255, 140), Red = Color3.fromRGB(255, 70, 70),
}
local SPIN_WORDS = { "Pinwheel", "ClockHand", "Ring" }

function Club.RemoveHeroLook(player)
	local character = player.Character
	local look = character and character:FindFirstChild("HeroLook")
	if look then
		look:Destroy()
	end
end

function Club.GiveHeroLook(player, heroId, teamColor)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local torso = character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
	if not (head and torso) then
		return
	end
	Club.RemoveHeroLook(player)
	local hero = Config.Heroes[heroId]
	local h = hero and AssetLib.Spawn("Hero_" .. heroId, CFrame.new(), { anchored = false, collide = false })
	if not h then
		return
	end
	local pHead, pBack = h.points.Point_Head, h.points.Point_Back
	local pFloat = h.points.Point_Float or pBack
	local pWaist = h.points.Point_Waist or pBack
	-- 캐릭터 쪽 기준 자리: 머리 정수리 / 등 가운데 (R6 몸통은 가슴이 가운데보다 조금 위)
	local headAnchor = CFrame.new(0, head.Size.Y / 2, 0)
	local backAnchor = CFrame.new(0, torso.Name == "Torso" and 0.2 or 0, torso.Size.Z / 2)
	local folder = Instance.new("Model")
	folder.Name = "HeroLook"
	folder:SetAttribute("Hero", heroId)
	for _, p in ipairs(h.model:GetDescendants()) do
		if p:IsA("BasePart") and not p.Name:find("^Point_") then
			local n = p.Name
			local slot = n:match("^(%a+)_") or "Back"
			local base, anchor, ref = torso, backAnchor, pBack
			if slot == "Head" then
				base, anchor, ref = head, headAnchor, pHead
			elseif slot == "Float" then
				ref = pFloat
				p:SetAttribute("Bob", true)
			elseif slot == "Waist" then
				ref = pWaist
			end
			if not ref then
				continue
			end
			-- 색·재질
			if n:find("TeamColor_") then
				p.Color = teamColor or hero.color
				p.Material = Enum.Material.SmoothPlastic
			elseif n:find("Neon_") then
				p.Material = Enum.Material.Neon
				for word, c in pairs(NEON_WORDS) do
					if n:find("Neon_" .. word) then
						p.Color = c
					end
				end
			end
			for _, w in ipairs(SPIN_WORDS) do
				if n:find(w) then
					p:SetAttribute("Spin", 2.5) -- 초당 회전(라디안)
				end
			end
			-- 모델 기준점(Point_)에서의 상대 위치 그대로 캐릭터 기준 자리에 붙임
			local offset = ref:ToObjectSpace(p.CFrame)
			p.Anchored = false
			p.Parent = folder
			weldTo(base, p, anchor * offset)
		end
	end
	h.model:Destroy()
	folder.Parent = character
end

function Club.Remove(player)
	local character = player.Character
	if not character then
		return
	end
	local model = character:FindFirstChild("GolfClub")
	if model then
		model:Destroy()
	end
	for _, name in ipairs({ "UpperTorso", "Torso" }) do
		local torso = character:FindFirstChild(name)
		local motor = torso and torso:FindFirstChild("ClubMotor")
		if motor then
			motor:Destroy()
		end
	end
	character:SetAttribute("Charging", false)
end

return Club
