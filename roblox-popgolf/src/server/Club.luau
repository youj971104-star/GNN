-- 골프채: 캐릭터 손에 쥐어 주고, 스킨(가챠로 얻는 꾸미기)을 입히고, 휘두르는 모습을 보여 줍니다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Club = {}

local REST_GRIP = CFrame.new(0, 0, -1.6) * CFrame.Angles(math.rad(-20), 0, 0)
local SWING_GRIPS = {
	CFrame.new(0, 0, -1.6) * CFrame.Angles(math.rad(-80), 0, 0), -- 뒤로 젖히기
	CFrame.new(0, 0, -1.6) * CFrame.Angles(math.rad(70), 0, 0), -- 휘두르기
}

local function applySkin(tool, skinId)
	local skin = Config.Skins[skinId] or Config.Skins.White
	local head = tool:FindFirstChild("Head")
	local shaft = tool:FindFirstChild("Handle")
	if not (head and shaft) then
		return
	end
	head.Color = skin.color
	head.Material = Enum.Material[skin.material] or Enum.Material.SmoothPlastic
	for _, c in ipairs(head:GetChildren()) do
		if not c:IsA("WeldConstraint") and not c:IsA("Attachment") then
			c:Destroy()
		end
	end
	if skin.trail then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.4, 0)
		a0.Parent = head
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.4, 0)
		a1.Parent = head
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.25
		trail.LightEmission = 0.7
		trail.Transparency = NumberSequence.new(0.1, 1)
		local kps = {}
		for i, c in ipairs(skin.trail) do
			table.insert(kps, ColorSequenceKeypoint.new((i - 1) / math.max(1, #skin.trail - 1), c))
		end
		trail.Color = ColorSequence.new(kps)
		trail.Parent = head
	end
	if skin.effect == "Sparkles" then
		local s = Instance.new("Sparkles")
		s.SparkleColor = skin.color
		s.Parent = head
	elseif skin.effect == "Fire" then
		local f = Instance.new("Fire")
		f.Size = 1.5
		f.Heat = 1
		f.Color = skin.color
		f.Parent = head
	elseif skin.effect == "Smoke" then
		local sm = Instance.new("Smoke")
		sm.Size = 0.4
		sm.Opacity = 0.15
		sm.RiseVelocity = 1
		sm.Parent = head
	elseif skin.effect == "Light" then
		local l = Instance.new("PointLight")
		l.Color = skin.color
		l.Range = 8
		l.Brightness = 2
		l.Parent = head
	end
end

local function makeTool()
	local tool = Instance.new("Tool")
	tool.Name = "GolfClub"
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true -- 클릭 처리는 직접 (샷/휘두르기 구분)
	tool.RequiresHandle = true
	tool.Grip = REST_GRIP

	local shaft = Instance.new("Part")
	shaft.Name = "Handle"
	shaft.Size = Vector3.new(0.25, 0.25, 4.2)
	shaft.Color = Color3.fromRGB(60, 60, 70)
	shaft.Material = Enum.Material.Metal
	shaft.CanCollide = false
	shaft.Massless = true
	shaft.Parent = tool

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(0.5, 0.7, 1.4)
	head.CanCollide = false
	head.Massless = true
	head.CFrame = shaft.CFrame * CFrame.new(0, -0.2, -2.1)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = shaft
	weld.Part1 = head
	weld.Parent = head
	head.Parent = tool
	return tool
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

-- 휘두르는 모습 (Grip 을 빠르게 바꿈)
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
