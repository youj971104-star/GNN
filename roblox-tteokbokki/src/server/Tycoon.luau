-- 가게 터 하나를 관리합니다: 버튼, 기계, 컨베이어, 음식 아이템, 계산대
-- 좌표는 가게 터 중심(바닥 윗면) 기준. +Z 방향이 컨베이어 진행 방향(계산대 쪽)

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local Tycoon = {}
Tycoon.__index = Tycoon

local LOT_SIZE = 84

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

local function billboard(adornee, text, color, size, offset)
	local gui = Instance.new("BillboardGui")
	gui.Size = size or UDim2.fromOffset(180, 50)
	gui.StudsOffset = offset or Vector3.new(0, 3, 0)
	gui.MaxDistance = 90
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	gui.Parent = adornee
	return label
end

local function short(n)
	local s = { "", "K", "M", "B", "T" }
	local i = 1
	while n >= 1000 and i < #s do
		n /= 1000
		i += 1
	end
	return (i == 1 and tostring(math.floor(n)) or string.format("%.1f%s", n, s[i]))
end

function Tycoon.new(index, origin)
	local self = setmetatable({}, Tycoon)
	self.index = index
	self.origin = origin
	self.owner = nil
	self.built = {} -- [id] = Model
	self.buttons = {} -- [id] = Part
	self.droppers = {} -- { def, timer }
	self.pending = 0

	local model = Instance.new("Model")
	model.Name = "Lot" .. index
	model.Parent = workspace:FindFirstChild("Lots")
	self.model = model

	part({ Name = "Ground", Size = Vector3.new(LOT_SIZE, 2, LOT_SIZE), CFrame = CFrame.new(origin - Vector3.new(0, 1, 0)), Color = Color3.fromRGB(110, 190, 100), Material = Enum.Material.Grass }, model)
	local signPost = part({ Name = "OwnerSign", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(origin + Vector3.new(0, 14, LOT_SIZE / 2 - 2)), Transparency = 1, CanCollide = false }, model)
	self.ownerLabel = billboard(signPost, "빈 가게 터", Color3.new(1, 1, 1), UDim2.fromOffset(300, 60))

	self.buildFolder = Instance.new("Folder")
	self.buildFolder.Name = "Built"
	self.buildFolder.Parent = model
	self.itemFolder = Instance.new("Folder")
	self.itemFolder.Name = "Items"
	self.itemFolder.Parent = model
	self.buttonFolder = Instance.new("Folder")
	self.buttonFolder.Name = "Buttons"
	self.buttonFolder.Parent = model
	return self
end

function Tycoon:at(x, y, z)
	return self.origin + Vector3.new(x, y, z)
end

function Tycoon:spawnCFrame()
	return CFrame.new(self:at(12, 4, 30))
end

----------------------------------------------------------------------
-- 버튼
----------------------------------------------------------------------
function Tycoon:buttonPosition(index)
	local col = (index - 1) % 3
	local row = math.floor((index - 1) / 3)
	return self:at(20 + col * 7, 0.25, -30 + row * 9)
end

function Tycoon:createButtons(onTouch)
	for _, def in ipairs(Config.Buttons) do
		local pad = part({
			Name = def.id,
			Size = Vector3.new(5, 0.5, 5),
			CFrame = CFrame.new(self:buttonPosition(def.index)),
			Color = Color3.fromRGB(80, 230, 120),
			Material = Enum.Material.Neon,
		}, nil)
		local text = def.cost == 0 and (def.name .. "\n무료") or (def.name .. "\n💰 " .. short(def.cost))
		billboard(pad, text, Color3.new(1, 1, 1), UDim2.fromOffset(150, 56), Vector3.new(0, 3, 0))
		pad.Touched:Connect(function(hit)
			onTouch(self, def.id, hit)
		end)
		self.buttons[def.id] = pad
	end
end

-- 조건을 만족한(앞 단계를 산) 버튼만 보이게
function Tycoon:refreshButtons(bought, cash)
	for _, def in ipairs(Config.Buttons) do
		local pad = self.buttons[def.id]
		local ready = self.owner ~= nil and not bought[def.id]
		if ready then
			for _, req in ipairs(def.requires) do
				if not bought[req] then
					ready = false
					break
				end
			end
		end
		pad.Parent = ready and self.buttonFolder or nil
		if ready then
			pad.Color = cash >= def.cost and Color3.fromRGB(80, 230, 120) or Color3.fromRGB(230, 90, 90)
		end
	end
end

----------------------------------------------------------------------
-- 건물 짓기
----------------------------------------------------------------------
local builders = {}

builders.base = function(self, def, folder)
	-- 가게 바닥 (타일)
	part({ Name = "Floor", Size = Vector3.new(56, 0.4, 70), CFrame = CFrame.new(self:at(-12, 0.2, 0)), Color = Color3.fromRGB(240, 230, 210), Material = Enum.Material.Marble }, folder)
	-- 컨베이어
	local conveyor = part({ Name = "Conveyor", Size = Vector3.new(4, 1, 54), CFrame = CFrame.new(self:at(0, 1, 0)), Color = Color3.fromRGB(50, 50, 55), Material = Enum.Material.DiamondPlate }, folder)
	conveyor.AssemblyLinearVelocity = Vector3.new(0, 0, Config.ConveyorSpeed)
	for _, side in ipairs({ -1, 1 }) do
		part({ Name = "Rail", Size = Vector3.new(0.4, 1.6, 54), CFrame = CFrame.new(self:at(side * 2.2, 1.6, 0)), Color = Color3.fromRGB(200, 200, 210), Material = Enum.Material.Metal }, folder)
	end
	-- 계산대 창구 (음식이 들어가면 돈으로 바뀜)
	local collector = part({ Name = "Collector", Size = Vector3.new(7, 6, 4), CFrame = CFrame.new(self:at(0, 3, 29)), Color = Color3.fromRGB(255, 120, 60), Material = Enum.Material.SmoothPlastic }, folder)
	billboard(collector, "🧾 계산대", Color3.new(1, 1, 1), UDim2.fromOffset(140, 40), Vector3.new(0, 4.5, 0))
	self.collector = collector
	-- 돈 받는 발판
	local register = part({ Name = "Register", Size = Vector3.new(6, 0.5, 6), CFrame = CFrame.new(self:at(9, 0.5, 30)), Color = Color3.fromRGB(255, 215, 90), Material = Enum.Material.Neon }, folder)
	self.register = register
	self.registerLabel = billboard(register, "💰 0", Color3.fromRGB(255, 230, 120), UDim2.fromOffset(160, 50))

	collector.Touched:Connect(function(hit)
		if hit.Parent == self.itemFolder then
			local value = hit:GetAttribute("Value") or 0
			hit:Destroy()
			if self.onCollect then
				self.onCollect(self, value)
			end
		end
	end)
	register.Touched:Connect(function(hit)
		if self.onRegister then
			self.onRegister(self, hit)
		end
	end)
end

builders.dropper = function(self, def, folder)
	local z = def.z
	part({ Name = "Machine", Size = Vector3.new(6, 5, 5), CFrame = CFrame.new(self:at(-7, 2.5, z)), Color = def.color, Material = Enum.Material.SmoothPlastic }, folder)
	part({ Name = "Pot", ClassName = "Part", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 4, 4), CFrame = CFrame.new(self:at(-7, 6, z)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(70, 70, 75), Material = Enum.Material.Metal }, folder)
	part({ Name = "Chute", Size = Vector3.new(6, 1, 2.5), CFrame = CFrame.new(self:at(-3, 6.5, z)), Color = Color3.fromRGB(200, 200, 210), Material = Enum.Material.Metal }, folder)
	local labelPart = part({ Name = "Label", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(self:at(-7, 9, z)), Transparency = 1, CanCollide = false }, folder)
	billboard(labelPart, def.name, Color3.new(1, 1, 1), UDim2.fromOffset(130, 34), Vector3.new(0, 1, 0))
	table.insert(self.droppers, { def = def, timer = 0 })
end

builders.upgrader = function(self, def, folder)
	local z = def.z
	for _, side in ipairs({ -1, 1 }) do
		part({ Name = "Pillar", Size = Vector3.new(1, 7, 1), CFrame = CFrame.new(self:at(side * 3, 3.5, z)), Color = Color3.fromRGB(80, 80, 90), Material = Enum.Material.Metal }, folder)
	end
	part({ Name = "Top", Size = Vector3.new(7, 1, 1.4), CFrame = CFrame.new(self:at(0, 7.5, z)), Color = def.color, Material = Enum.Material.Neon }, folder)
	local zone = part({ Name = "UpgradeZone", Size = Vector3.new(4, 4, 1), CFrame = CFrame.new(self:at(0, 3.5, z)), Color = def.color, Material = Enum.Material.ForceField, Transparency = 0.3, CanCollide = false }, folder)
	billboard(zone, def.name .. " x" .. def.mult, def.color, UDim2.fromOffset(150, 34), Vector3.new(0, 5, 0))
	zone.Touched:Connect(function(hit)
		local flag = "Up_" .. def.id
		if hit.Parent == self.itemFolder and not hit:GetAttribute(flag) then
			hit:SetAttribute(flag, true)
			hit:SetAttribute("Value", (hit:GetAttribute("Value") or 0) * def.mult)
			hit.Size = hit.Size * 1.12
		end
	end)
end

local decoBuilders = {}
decoBuilders.Sign = function(self, folder)
	local board = part({ Name = "SignBoard", Size = Vector3.new(22, 5, 1), CFrame = CFrame.new(self:at(-12, 12, 36)), Color = Color3.fromRGB(255, 240, 220), Material = Enum.Material.SmoothPlastic }, folder)
	for _, x in ipairs({ -22, -2 }) do
		part({ Name = "Post", Size = Vector3.new(1, 10, 1), CFrame = CFrame.new(self:at(x, 5, 36)), Color = Color3.fromRGB(120, 80, 50), Material = Enum.Material.Wood }, folder)
	end
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.PixelsPerStud = 30
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(220, 50, 40)
	t.Text = (self.owner and self.owner.DisplayName or "우리") .. "네 떡볶이"
	t.Parent = sg
	sg.Parent = board
	local front = sg:Clone()
	front.Face = Enum.NormalId.Front
	front.Parent = board
end
local function tableAt(self, folder, z)
	part({ Name = "TableTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 6, 6), CFrame = CFrame.new(self:at(-26, 3, z)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(230, 90, 70), Material = Enum.Material.SmoothPlastic }, folder)
	part({ Name = "TableLeg", Size = Vector3.new(0.8, 3, 0.8), CFrame = CFrame.new(self:at(-26, 1.5, z)), Color = Color3.fromRGB(60, 60, 60), Material = Enum.Material.Metal }, folder)
	for _, dx in ipairs({ -4.5, 4.5 }) do
		part({ Name = "Stool", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 2.4, 2.4), CFrame = CFrame.new(self:at(-26 + dx, 1, z)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(70, 130, 230), Material = Enum.Material.SmoothPlastic }, folder)
	end
end
decoBuilders.Table1 = function(self, folder)
	tableAt(self, folder, -20)
end
decoBuilders.Table2 = function(self, folder)
	tableAt(self, folder, -4)
end
decoBuilders.Table3 = function(self, folder)
	tableAt(self, folder, 12)
end
decoBuilders.Roof = function(self, folder)
	for i = 0, 6 do
		part({ Name = "Stripe", Size = Vector3.new(8, 0.6, 72), CFrame = CFrame.new(self:at(-36 + i * 8, 18, 0)), Color = (i % 2 == 0) and Color3.fromRGB(230, 60, 50) or Color3.new(1, 1, 1), Material = Enum.Material.Fabric }, folder)
	end
	for _, x in ipairs({ -39, 15 }) do
		for _, z in ipairs({ -34, 34 }) do
			part({ Name = "RoofPost", Size = Vector3.new(1, 18, 1), CFrame = CFrame.new(self:at(x, 9, z)), Color = Color3.fromRGB(120, 80, 50), Material = Enum.Material.Wood }, folder)
		end
	end
end
decoBuilders.Neon = function(self, folder)
	for _, o in ipairs({ { 0, 2.9, 23, 0.4 }, { 0, -2.9, 23, 0.4 }, { 11.2, 0, 0.4, 6 }, { -11.2, 0, 0.4, 6 } }) do
		part({ Name = "NeonTube", Size = Vector3.new(o[3], o[4], 0.4), CFrame = CFrame.new(self:at(-12 + o[1], 12 + o[2], 35.4)), Color = Color3.fromRGB(255, 80, 200), Material = Enum.Material.Neon, CanCollide = false }, folder)
	end
end
decoBuilders.Bike = function(self, folder)
	local base = self:at(-32, 0, 30)
	part({ Name = "Body", Size = Vector3.new(2, 2, 6), CFrame = CFrame.new(base + Vector3.new(0, 2.2, 0)), Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.SmoothPlastic }, folder)
	part({ Name = "Box", Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(base + Vector3.new(0, 4.2, -2)), Color = Color3.fromRGB(230, 60, 50), Material = Enum.Material.SmoothPlastic }, folder)
	for _, z in ipairs({ -2.6, 2.6 }) do
		part({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 2.4, 2.4), CFrame = CFrame.new(base + Vector3.new(0, 1.2, z)), Color = Color3.fromRGB(30, 30, 30), Material = Enum.Material.SmoothPlastic }, folder)
	end
end
decoBuilders.Gold = function(self, folder)
	local p = part({ Name = "GoldSign", Size = Vector3.new(10, 10, 1.5), CFrame = CFrame.new(self:at(-32, 7, -36)), Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.Foil }, folder)
	billboard(p, "🏆 2호점 준비 완료!", Color3.fromRGB(255, 220, 90), UDim2.fromOffset(240, 50), Vector3.new(0, 7, 0))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 210, 90)
	light.Range = 20
	light.Parent = p
end

builders.deco = function(self, def, folder)
	local fn = decoBuilders[def.id]
	if fn then
		fn(self, folder)
	end
end

function Tycoon:build(id)
	if self.built[id] then
		return
	end
	local def = Config.ButtonById[id]
	local folder = Instance.new("Model")
	folder.Name = id
	folder.Parent = self.buildFolder
	builders[def.kind](self, def, folder)
	self.built[id] = folder
end

----------------------------------------------------------------------
-- 주인 배정 / 해제
----------------------------------------------------------------------
function Tycoon:assign(player, bought)
	self.owner = player
	self.ownerLabel.Text = player.DisplayName .. "네 떡볶이 가게"
	-- 저장된 건물 다시 짓기 (버튼 순서대로)
	for _, def in ipairs(Config.Buttons) do
		if bought[def.id] then
			self:build(def.id)
		end
	end
end

function Tycoon:reset()
	for _, m in pairs(self.built) do
		m:Destroy()
	end
	self.built = {}
	self.droppers = {}
	self.itemFolder:ClearAllChildren()
	self.collector, self.register, self.registerLabel = nil, nil, nil
	self.pending = 0
end

function Tycoon:release()
	self:reset()
	self.owner = nil
	self.ownerLabel.Text = "빈 가게 터"
	for _, pad in pairs(self.buttons) do
		pad.Parent = nil
	end
end

----------------------------------------------------------------------
-- 생산
----------------------------------------------------------------------
function Tycoon:tick(dt, speedMult)
	if not self.owner or not self.collector then
		return
	end
	local count = #self.itemFolder:GetChildren()
	for _, d in ipairs(self.droppers) do
		d.timer += dt * speedMult
		if d.timer >= d.def.interval then
			d.timer -= d.def.interval
			if count < Config.MaxItemsPerLot then
				count += 1
				local item = Instance.new("Part")
				item.Name = d.def.id
				item.Size = Vector3.new(1.4, 1.4, 1.4)
				item.Color = d.def.color
				item.Material = Enum.Material.SmoothPlastic
				item.CFrame = CFrame.new(self:at(0, 3, d.def.z))
				item.CanQuery = false
				item:SetAttribute("Value", d.def.value)
				item:SetAttribute("Born", os.clock())
				item.Parent = self.itemFolder
				pcall(function()
					item:SetNetworkOwner(nil) -- 서버가 물리 담당 (조작 방지)
				end)
			end
		end
	end
	-- 오래된 음식 정리 (컨베이어 밖으로 떨어진 것 등)
	local now = os.clock()
	for _, item in ipairs(self.itemFolder:GetChildren()) do
		if now - (item:GetAttribute("Born") or now) > Config.ItemLifetime then
			item:Destroy()
		end
	end
end

function Tycoon:setPendingText(amount)
	if self.registerLabel then
		self.registerLabel.Text = "💰 " .. short(amount)
	end
end

-- 기본 상태에서의 초당 수입(배율 전) — 오프라인 수입 계산용
function Tycoon.IncomePerSecond(bought)
	local upgradeMult = 1
	for _, def in ipairs(Config.Buttons) do
		if bought[def.id] and def.kind == "upgrader" then
			upgradeMult *= def.mult
		end
	end
	local sum = 0
	for _, def in ipairs(Config.Buttons) do
		if bought[def.id] and def.kind == "dropper" then
			sum += def.value / def.interval
		end
	end
	return sum * upgradeMult
end

return Tycoon
