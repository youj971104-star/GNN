-- 골프채: 몸통 앞(가슴)에 관절(Motor6D "ClubMotor")로 붙입니다.
-- 실제로 크게 휘두르는 모션은 각 플레이어 화면의 SwingAnimator 가 이 관절을 돌려서 만듭니다.
-- (도구(Tool)로 쥐면 손목만 까딱이는 느낌이라 관절 방식으로 바꿈)
-- 빛 입자·고리 같은 스킨 연출은 ClubFX 가 그립니다. 서버는 "Skin" 속성만 달아 둡니다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Club = {}

-- 관절 위치: 어깨 높이 가슴 앞. 팔(약 1.9)과 골프채가 이 점을 중심으로 같이 돌면서 휘둘러짐
-- (손이 이 점에서 1.9 아래, 골프채 머리가 바닥 근처에 오도록 맞춤)
Club.PIVOT = CFrame.new(0, 0.5, -0.35)
Club.SHAFT_OFFSET = CFrame.new(0, 2.6, 0) -- 샤프트 중심이 관절보다 2.6 아래

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

local function makeClub()
	local model = Instance.new("Model")
	model.Name = "GolfClub"

	local shaft = Instance.new("Part")
	shaft.Name = "Shaft"
	shaft.Size = Vector3.new(0.2, 2.6, 0.2)
	shaft.Color = Color3.fromRGB(195, 200, 210)
	shaft.Material = Enum.Material.Metal
	shaft.CanCollide = false
	shaft.CanQuery = false
	shaft.CanTouch = false
	shaft.Massless = true
	shaft.CastShadow = false
	shaft.Parent = model

	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(0.32, 0.9, 0.32)
	grip.Color = Color3.fromRGB(35, 35, 40)
	grip.Material = Enum.Material.Fabric
	weldTo(shaft, grip, CFrame.new(0, 0.85, 0))
	grip.Parent = model

	local ferrule = Instance.new("Part")
	ferrule.Name = "Ferrule"
	ferrule.Size = Vector3.new(0.3, 0.3, 0.3)
	ferrule.Color = Color3.fromRGB(170, 175, 185)
	ferrule.Material = Enum.Material.Foil
	weldTo(shaft, ferrule, CFrame.new(0, -1.2, 0))
	ferrule.Parent = model

	-- 머리: 옆으로 긴 드라이버 모양 (스윙 방향과 수직)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.5, 0.75, 0.6)
	weldTo(shaft, head, CFrame.new(0.45, -1.5, 0))
	head.Parent = model

	local gem = Instance.new("Part")
	gem.Name = "Gem"
	gem.Shape = Enum.PartType.Ball
	gem.Size = Vector3.one * 0.4
	gem.Material = Enum.Material.Neon
	gem.Transparency = 1
	weldTo(shaft, gem, CFrame.new(0.55, -1.45, -0.32))
	gem.Parent = model

	model.PrimaryPart = shaft
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

-- 캐릭터 몸통에 골프채 붙이기 (이미 있으면 스킨만 갱신)
function Club.Give(player, skinId)
	local character = player.Character
	if not character then
		return
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso then
		return
	end
	local model = character:FindFirstChild("GolfClub")
	if not model then
		model = makeClub()
		local shaft = model.PrimaryPart
		shaft.CFrame = torso.CFrame * Club.PIVOT * Club.SHAFT_OFFSET:Inverse()
		local motor = Instance.new("Motor6D")
		motor.Name = "ClubMotor"
		motor.Part0 = torso
		motor.Part1 = shaft
		motor.C0 = Club.PIVOT
		motor.C1 = Club.SHAFT_OFFSET
		motor.Parent = torso
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
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local motor = torso and torso:FindFirstChild("ClubMotor")
	if motor then
		motor:Destroy()
	end
	character:SetAttribute("Charging", false)
end

return Club
