-- 골프채: 캐릭터 손에 쥐어 주고, 스킨 색·재질을 입히고, 휘두르는 모습을 보여 줍니다.
-- 빛 입자·빛구슬·고리 같은 화려한 연출은 각 플레이어 화면(client/ClubFX)이 그립니다.
-- 서버는 골프채에 "Skin" 속성만 달아 두면 됨 → 서버 부담 없음

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Club = {}

local REST_GRIP = CFrame.new(0, 0, -1.6) * CFrame.Angles(math.rad(-20), 0, 0)
local SWING_GRIPS = {
	CFrame.new(0, 0, -1.6) * CFrame.Angles(math.rad(-80), 0, 0), -- 뒤로 젖히기
	CFrame.new(0, 0, -1.6) * CFrame.Angles(math.rad(70), 0, 0), -- 휘두르기
}

local function weldTo(base, part, offset)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CFrame = base.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = part
	w.Parent = part
end

local function makeTool()
	local tool = Instance.new("Tool")
	tool.Name = "GolfClub"
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true -- 클릭 처리는 직접 (샷/휘두르기 구분)
	tool.RequiresHandle = true
	tool.Grip = REST_GRIP

	-- 샤프트(손잡이 막대)
	local shaft = Instance.new("Part")
	shaft.Name = "Handle"
	shaft.Size = Vector3.new(0.22, 0.22, 4.2)
	shaft.Color = Color3.fromRGB(190, 195, 205)
	shaft.Material = Enum.Material.Metal
	shaft.CanCollide = false
	shaft.Massless = true
	shaft.Parent = tool

	-- 그립 (손 쪽 고무)
	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(0.32, 0.32, 1.1)
	grip.Color = Color3.fromRGB(35, 35, 40)
	grip.Material = Enum.Material.Fabric
	weldTo(shaft, grip, CFrame.new(0, 0, 1.6))
	grip.Parent = tool

	-- 금속 띠 (머리와 샤프트 이음새)
	local ferrule = Instance.new("Part")
	ferrule.Name = "Ferrule"
	ferrule.Shape = Enum.PartType.Cylinder
	ferrule.Size = Vector3.new(0.35, 0.34, 0.34)
	ferrule.Color = Color3.fromRGB(255, 215, 120)
	ferrule.Material = Enum.Material.Foil
	weldTo(shaft, ferrule, CFrame.new(0, 0, -1.95) * CFrame.Angles(0, math.rad(90), 0))
	ferrule.Parent = tool

	-- 머리 (스킨 색)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(0.55, 0.75, 1.5)
	weldTo(shaft, head, CFrame.new(0, -0.25, -2.25))
	head.Parent = tool

	-- 머리에 박힌 보석 (영웅 등급 이상에서 보임)
	local gem = Instance.new("Part")
	gem.Name = "Gem"
	gem.Shape = Enum.PartType.Ball
	gem.Size = Vector3.one * 0.38
	gem.Material = Enum.Material.Neon
	gem.Transparency = 1
	weldTo(head, gem, CFrame.new(0.3, 0.05, 0))
	gem.Parent = tool

	return tool
end

local function applySkin(tool, skinId)
	local skin = Config.Skins[skinId] or Config.Skins.White
	local head = tool:FindFirstChild("Head")
	local gem = tool:FindFirstChild("Gem")
	local ferrule = tool:FindFirstChild("Ferrule")
	if not head then
		return
	end
	head.Color = skin.color
	head.Material = Enum.Material[skin.material] or Enum.Material.SmoothPlastic
	local rarityIndex = Config.RarityById[skin.rarity].index
	if gem then
		gem.Transparency = rarityIndex >= 3 and 0 or 1
		gem.Color = (skin.trail and skin.trail[#skin.trail]) or skin.color
	end
	if ferrule then
		ferrule.Color = rarityIndex >= 4 and Color3.fromRGB(255, 215, 120) or Color3.fromRGB(170, 175, 185)
	end
	tool:SetAttribute("Skin", skinId) -- 클라이언트 ClubFX 가 이걸 보고 연출을 붙임
end

-- 캐릭터에게 골프채를 쥐어 줌 (이미 있으면 스킨만 갱신)
function Club.Give(player, skinId)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local tool = character:FindFirstChild("GolfClub") or player.Backpack:FindFirstChild("GolfClub")
	if not tool then
		tool = makeTool()
		tool.Parent = player.Backpack
	end
	applySkin(tool, skinId)
	if tool.Parent ~= character then
		humanoid:EquipTool(tool)
	end
end

function Club.Remove(player)
	for _, container in ipairs({ player.Character, player:FindFirstChild("Backpack") }) do
		if container then
			local tool = container:FindFirstChild("GolfClub")
			if tool then
				tool:Destroy()
			end
		end
	end
end

-- 휘두르는 모습 (Grip 을 빠르게 바꿈). Swinging 속성이 켜지면 클라이언트가 폭발 연출을 터뜨림
function Club.SwingVisual(player)
	local character = player.Character
	local tool = character and character:FindFirstChild("GolfClub")
	if not tool or tool:GetAttribute("Swinging") then
		return
	end
	tool:SetAttribute("Swinging", true)
	tool.Grip = SWING_GRIPS[1]
	task.delay(0.08, function()
		tool.Grip = SWING_GRIPS[2]
		task.delay(0.15, function()
			tool.Grip = REST_GRIP
			tool:SetAttribute("Swinging", false)
		end)
	end)
end

return Club
