-- 골프채: 가슴 위쪽(두 어깨 사이)에 관절(Motor6D "ClubMotor")로 붙입니다.
-- 이 관절이 '팔 + 골프채'를 한 덩어리로 돌리는 스윙 중심이고,
-- 손은 각 화면의 SwingAnimator 가 IK(관절 자동 맞춤)로 골프채 손잡이(GripL/GripR)에 붙여 줍니다.
--
-- 골프채 좌표: 샤프트 길이 방향 = 로컬 Y (손잡이가 +Y 쪽), 클럽 머리의 앞(공 치는 면) = 로컬 -X
-- 빛 입자·고리 같은 스킨 연출은 ClubFX 가 그립니다. 서버는 "Skin" 속성만 달아 둡니다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Club = {}

-- 스윙 중심: 두 어깨 사이 (R15 UpperTorso 기준)
-- 여기서 골프채 방향으로 약 2.0 지점이 손(손잡이), 4.6 지점이 클럽 머리 → 어드레스 때 머리가 발 앞 땅에 닿음
Club.PIVOT = CFrame.new(0, 0.4, -0.2)
Club.SHAFT_OFFSET = CFrame.new(0, 3.1, 0) -- 샤프트 중심이 스윙 중심에서 3.1 떨어짐

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
	weldTo(shaft, grip, CFrame.new(0, 0.95, 0))
	grip.Parent = model
	-- 손이 잡을 자리 (왼손이 위, 오른손이 아래 — 오른손잡이 골퍼)
	local gl = Instance.new("Attachment")
	gl.Name = "GripL"
	gl.Position = Vector3.new(0, 0.22, 0)
	gl.Parent = grip
	local gr = Instance.new("Attachment")
	gr.Name = "GripR"
	gr.Position = Vector3.new(0, -0.22, 0)
	gr.Parent = grip

	local ferrule = Instance.new("Part")
	ferrule.Name = "Ferrule"
	ferrule.Size = Vector3.new(0.3, 0.3, 0.3)
	ferrule.Color = Color3.fromRGB(170, 175, 185)
	ferrule.Material = Enum.Material.Foil
	weldTo(shaft, ferrule, CFrame.new(0, -1.2, 0))
	ferrule.Parent = model

	-- 머리: 앞뒤로 긴 드라이버 모양 (발끝 방향으로 뻗음, 치는 면은 목표 쪽)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(0.6, 0.7, 1.5)
	weldTo(shaft, head, CFrame.new(0, -1.45, -0.5))
	head.Parent = model

	local gem = Instance.new("Part")
	gem.Name = "Gem"
	gem.Shape = Enum.PartType.Ball
	gem.Size = Vector3.one * 0.4
	gem.Material = Enum.Material.Neon
	gem.Transparency = 1
	weldTo(shaft, gem, CFrame.new(-0.32, -1.4, -0.6))
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
