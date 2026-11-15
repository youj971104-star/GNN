-- 골프채: 가슴 앞 스윙 중심에 관절(Motor6D "ClubMotor")로 붙입니다.
-- 캐릭터마다 키·팔 길이를 재서(ClubRig) 골프채 길이와 기울기를 맞춤 → 어드레스 때 클럽 머리가 발 앞 땅(스윙 존)에 닿음
-- 팔은 각 화면의 SwingAnimator 가 손잡이 쪽으로 뻗게 계산 (R6·R15 모두)
--
-- 골프채 좌표: 샤프트 길이 방향 = 로컬 Y (손잡이가 +Y), 클럽 머리 치는 면 = 로컬 -X
-- 모델 속성(클라이언트가 읽음): Tilt(도), GripDist, Skin

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local ClubRig = require(ReplicatedStorage.Shared.ClubRig)

local Club = {}

local function weldTo(base, part, offset)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.CFrame = base.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = part
	w.Parent = part
end

-- geo: ClubRig.Geometry 결과 (headDist = 스윙 중심~클럽 머리, grip = 스윙 중심~손잡이)
local function makeClub(geo)
	local model = Instance.new("Model")
	model.Name = "GolfClub"

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
	head.Size = Vector3.new(0.6, 0.6, 1.4)
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
	model:SetAttribute("ShaftCenter", center)
	return model
end

local function applySkin(model, skinId)
	local skin = Config.Skins[skinId] or Config.Skins.White
	local head = model:FindFirstChild("Head")
	local gem = model:FindFirstChild("Gem")
	local ferrule = model:FindFirstChild("Ferrule")
	head.Color = skin.color
	head.Material = Enum.Material[skin.material] or Enum.Material.SmoothPlastic
	local rarityIndex = Config.RarityById[skin.rarity].index
	gem.Transparency = rarityIndex >= 3 and 0 or 1
	gem.Color = (skin.trail and skin.trail[#skin.trail]) or skin.color
	ferrule.Color = rarityIndex >= 4 and Color3.fromRGB(255, 215, 120) or Color3.fromRGB(170, 175, 185)
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
