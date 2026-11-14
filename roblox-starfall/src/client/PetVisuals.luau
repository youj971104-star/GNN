-- 장착한 펫(별 요정)이 캐릭터 주변을 둥실둥실 따라다니게 그립니다.
-- 서버는 player 속성 "Pets" 에 펫 ID 만 넣고, 모양은 각 클라이언트가 그림 → 서버 부하 없음.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local PetVisuals = {}

local folder = Instance.new("Folder")
folder.Name = "PetVisuals"
folder.Parent = workspace

local rendered = {} -- [Player] = { key = "Twinkle,Comet", pets = { part, ... } }

local function makePet(petId)
	local def = Config.Pets[petId]
	if not def then
		return nil
	end
	local size = ({ Common = 1.4, Rare = 1.6, Epic = 1.9, Legendary = 2.3, Cosmic = 2.8 })[def.rarity] or 1.5

	local body = Instance.new("Part")
	body.Name = petId
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.one * size
	body.Color = def.color
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CastShadow = false

	for _, side in ipairs({ -1, 1 }) do
		local eye = Instance.new("Part")
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.one * (size * 0.22)
		eye.Color = Color3.fromRGB(30, 20, 50)
		eye.Material = Enum.Material.SmoothPlastic
		eye.Anchored = false
		eye.CanCollide = false
		eye.CanQuery = false
		eye.CanTouch = false
		eye.Massless = true
		eye.CFrame = body.CFrame * CFrame.new(side * size * 0.2, size * 0.1, -size * 0.42)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = eye
		weld.Parent = eye
		eye.Parent = body
	end

	if def.rarity ~= "Common" then
		local light = Instance.new("PointLight")
		light.Color = def.color
		light.Range = 6 + size * 2
		light.Brightness = 1.5
		light.Parent = body
	end
	if def.rarity == "Legendary" or def.rarity == "Cosmic" then
		local sparkle = Instance.new("Sparkles")
		sparkle.SparkleColor = def.color
		sparkle.Parent = body
	end
	body.Parent = folder
	return body
end

local function clear(player)
	local entry = rendered[player]
	if entry then
		for _, p in ipairs(entry.pets) do
			p:Destroy()
		end
		rendered[player] = nil
	end
end

local function sync(player)
	local key = player:GetAttribute("Pets") or ""
	local entry = rendered[player]
	if entry and entry.key == key then
		return
	end
	clear(player)
	local pets = {}
	for id in string.gmatch(key, "[^,]+") do
		local p = makePet(id)
		if p then
			table.insert(pets, p)
		end
	end
	rendered[player] = { key = key, pets = pets }
end

function PetVisuals.Start()
	local function watch(player)
		player:GetAttributeChangedSignal("Pets"):Connect(function()
			sync(player)
		end)
		sync(player)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(clear)

	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for player, entry in pairs(rendered) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local count = #entry.pets
			for i, pet in ipairs(entry.pets) do
				if root then
					-- 플레이어 뒤쪽 반원에 나란히 배치
					local spread = count > 1 and ((i - 1) / (count - 1) - 0.5) or 0
					local angle = spread * math.rad(140) -- 로컬 +Z 가 캐릭터 뒤쪽
					local offset = Vector3.new(math.sin(angle) * 5, 1.5 + math.sin(t * 3 + i) * 0.5, math.cos(angle) * 5)
					local target = root.CFrame * CFrame.new(offset)
					local goal = CFrame.lookAt(target.Position, target.Position + root.CFrame.LookVector)
					pet.CFrame = pet.CFrame:Lerp(goal, 0.15)
				else
					pet.CFrame = CFrame.new(0, -500, 0)
				end
			end
		end
	end)
end

return PetVisuals
