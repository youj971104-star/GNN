-- 별똥별 타이쿤 클라이언트: 화면 UI, 효과, 상점 연결
-- UI 를 전부 코드로 만들어서 Studio 에서 따로 꾸미지 않아도 바로 플레이할 수 있습니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local TextChatService = game:GetService("TextChatService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local PetVisuals = require(script.Parent.PetVisuals)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local Action = remotes:WaitForChild("Action")

local state = nil -- 서버가 보내 준 최신 스냅샷
local currentPanel = nil -- "Upgrades" | "Pets" | "Shop" | "Rebirth" | "Daily"

----------------------------------------------------------------------
-- 색 / 폰트
----------------------------------------------------------------------
local C = {
	bg = Color3.fromRGB(28, 22, 54),
	card = Color3.fromRGB(45, 36, 86),
	cardHi = Color3.fromRGB(66, 54, 120),
	accent = Color3.fromRGB(150, 120, 255),
	gold = Color3.fromRGB(255, 215, 90),
	green = Color3.fromRGB(80, 220, 120),
	red = Color3.fromRGB(240, 90, 100),
	gray = Color3.fromRGB(110, 105, 135),
	text = Color3.fromRGB(245, 242, 255),
	sub = Color3.fromRGB(185, 178, 220),
}
local FONT = Enum.Font.GothamBold
local FONT_TITLE = Enum.Font.FredokaOne

local RARITY_COLOR = {}
local RARITY_NAME = {}
for _, r in ipairs(Config.Rarities) do
	RARITY_COLOR[r.id] = r.color
	RARITY_NAME[r.id] = r.name
end

----------------------------------------------------------------------
-- UI 헬퍼
----------------------------------------------------------------------
local function new(className, props, children)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 10) })
end

local function stroke(color, thickness)
	return new("UIStroke", { Color = color or Color3.new(0, 0, 0), Thickness = thickness or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function label(props)
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = C.text,
		TextScaled = true,
		Text = "",
	})
	for k, v in pairs(props) do
		if k ~= "Parent" then
			l[k] = v
		end
	end
	l.Parent = props.Parent
	return l
end

local function button(props, onClick)
	local b = new("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = C.accent,
		Font = FONT,
		TextColor3 = C.text,
		TextScaled = true,
		Text = "",
	}, { corner(8) })
	new("UITextSizeConstraint", { MaxTextSize = 22, Parent = b })
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), Parent = b })
	for k, v in pairs(props) do
		if k ~= "Parent" then
			b[k] = v
		end
	end
	b.Parent = props.Parent
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

local function pop(guiObject)
	local scale = guiObject:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = guiObject })
	scale.Scale = 0.85
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

----------------------------------------------------------------------
-- 화면 뼈대
----------------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = "StarfallUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

-- 상단 HUD
local hud = new("Frame", {
	Name = "HUD",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(300, 86),
	BackgroundColor3 = C.bg,
	BackgroundTransparency = 0.15,
	Parent = gui,
}, { corner(14), stroke(C.accent, 2) })

local coinLabel = label({
	Parent = hud,
	Position = UDim2.fromOffset(10, 6),
	Size = UDim2.new(1, -20, 0, 34),
	Font = FONT_TITLE,
	TextColor3 = C.gold,
	Text = "⭐ 0",
})

local bagBack = new("Frame", {
	Parent = hud,
	Position = UDim2.fromOffset(12, 46),
	Size = UDim2.new(1, -24, 0, 18),
	BackgroundColor3 = Color3.fromRGB(20, 15, 40),
}, { corner(9) })
local bagFill = new("Frame", {
	Parent = bagBack,
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = C.green,
}, { corner(9) })
local bagLabel = label({
	Parent = bagBack,
	Size = UDim2.fromScale(1, 1),
	Text = "🎒 0 / 20",
	ZIndex = 2,
})
local multLabel = label({
	Parent = hud,
	Position = UDim2.fromOffset(12, 66),
	Size = UDim2.new(1, -24, 0, 16),
	TextColor3 = C.sub,
	Text = "코인 배율 x1",
})

-- 부스트 표시 (오른쪽 위)
local boostFrame = new("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 60),
	Size = UDim2.fromOffset(190, 70),
	BackgroundTransparency = 1,
	Parent = gui,
}, { new("UIListLayout", { Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Right }) })
local meteorLabel = label({ Parent = boostFrame, Size = UDim2.fromOffset(190, 26), TextColor3 = Color3.fromRGB(255, 150, 200), Visible = false })
local luckLabel = label({ Parent = boostFrame, Size = UDim2.fromOffset(190, 26), TextColor3 = Color3.fromRGB(140, 255, 160), Visible = false })

-- 왼쪽 메뉴 버튼
local menu = new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 10, 0.5, 0),
	Size = UDim2.fromOffset(92, 390),
	BackgroundTransparency = 1,
	Parent = gui,
}, { new("UIListLayout", { Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center }) })

local menuButtons = {}
local openPanel -- 아래에서 정의

local function menuButton(key, text, color)
	local b = button({ Parent = menu, Size = UDim2.fromOffset(92, 62), BackgroundColor3 = color, Text = text }, function()
		if currentPanel == key then
			openPanel(nil)
		else
			openPanel(key)
		end
	end)
	stroke(Color3.fromRGB(20, 10, 40), 2).Parent = b
	local dot = new("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = C.red,
		Visible = false,
		Parent = b,
	}, { corner(8) })
	menuButtons[key] = { button = b, dot = dot }
	return b
end

menuButton("Upgrades", "⬆️\n업그레이드", Color3.fromRGB(90, 140, 255))
menuButton("Pets", "🥚\n펫", Color3.fromRGB(255, 150, 80))
menuButton("Shop", "💎\n상점", Color3.fromRGB(230, 80, 170))
menuButton("Rebirth", "🔄\n환생", Color3.fromRGB(130, 90, 230))
menuButton("Daily", "🎁\n출석", Color3.fromRGB(60, 190, 120))

local sellAnywhere = button({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.fromOffset(160, 48),
	BackgroundColor3 = C.green,
	Text = "💰 지금 판매",
	Visible = false,
	Parent = gui,
}, function()
	Action:InvokeServer("Sell")
end)

-- 가운데 패널
local panel = new("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.53),
	Size = UDim2.new(0.62, 0, 0.66, 0),
	BackgroundColor3 = C.bg,
	Visible = false,
	Parent = gui,
}, {
	corner(16),
	stroke(C.accent, 3),
	new("UISizeConstraint", { MaxSize = Vector2.new(620, 460), MinSize = Vector2.new(300, 260) }),
})
local panelTitle = label({
	Parent = panel,
	Position = UDim2.fromOffset(16, 8),
	Size = UDim2.new(1, -80, 0, 40),
	Font = FONT_TITLE,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
})
button({
	Parent = panel,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.fromOffset(38, 38),
	BackgroundColor3 = C.red,
	Text = "✕",
}, function()
	openPanel(nil)
end)
local content = new("ScrollingFrame", {
	Parent = panel,
	Position = UDim2.fromOffset(12, 56),
	Size = UDim2.new(1, -24, 1, -68),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
})

-- 알림 (토스트)
local toastHolder = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 102),
	Size = UDim2.fromOffset(420, 200),
	BackgroundTransparency = 1,
	Parent = gui,
}, { new("UIListLayout", { Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center }) })

local function toast(text, color, small)
	local t = label({
		Parent = toastHolder,
		Size = UDim2.fromOffset(small and 200 or 420, small and 24 or 32),
		Text = text,
		TextColor3 = color or C.text,
		TextStrokeTransparency = 0.2,
	})
	pop(t)
	task.delay(small and 1.2 or 2.6, function()
		local tw = TweenService:Create(t, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 })
		tw:Play()
		tw.Completed:Wait()
		t:Destroy()
	end)
	-- 너무 많이 쌓이면 오래된 것부터 지움
	local labels = {}
	for _, c in ipairs(toastHolder:GetChildren()) do
		if c:IsA("TextLabel") then
			table.insert(labels, c)
		end
	end
	if #labels > 5 then
		labels[1]:Destroy()
	end
end

-- 큰 공지 배너
local banner = label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.25),
	Size = UDim2.new(0.8, 0, 0, 46),
	Font = FONT_TITLE,
	TextColor3 = C.gold,
	TextStrokeTransparency = 0,
	Visible = false,
	Parent = gui,
})
local bannerToken = 0
local function showBanner(text, seconds)
	bannerToken += 1
	local my = bannerToken
	banner.Text = text
	banner.Visible = true
	pop(banner)
	task.delay(math.min(seconds or 4, 6), function()
		if bannerToken == my then
			banner.Visible = false
		end
	end)
end

-- 펫 뽑기 연출
local hatchOverlay = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.4,
	Visible = false,
	ZIndex = 20,
	Parent = gui,
})
local hatchCircle = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	Size = UDim2.fromOffset(170, 170),
	ZIndex = 21,
	Parent = hatchOverlay,
}, { corner(85), stroke(Color3.new(1, 1, 1), 4) })
local hatchName = label({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.62),
	Size = UDim2.fromOffset(420, 48),
	Font = FONT_TITLE,
	ZIndex = 21,
	Parent = hatchOverlay,
})
local hatchRarity = label({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.7),
	Size = UDim2.fromOffset(420, 30),
	ZIndex = 21,
	Parent = hatchOverlay,
})

local function playHatch(petId)
	local def = Config.Pets[petId]
	if not def then
		return
	end
	hatchCircle.BackgroundColor3 = def.color
	hatchName.Text = def.name .. " 획득!"
	hatchName.TextColor3 = def.color
	hatchRarity.Text = string.format("%s · 코인 +%d%%", RARITY_NAME[def.rarity] or def.rarity, math.floor(def.bonus * 100 + 0.5))
	hatchOverlay.Visible = true
	pop(hatchCircle)
	pop(hatchName)
	task.delay(1.6, function()
		hatchOverlay.Visible = false
	end)
end

----------------------------------------------------------------------
-- 별 줍기 효과 (+숫자가 떠오름)
----------------------------------------------------------------------
local function collectEffect(position, rarityId, value)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Position = position
	anchor.Parent = workspace

	local bb = new("BillboardGui", {
		Size = UDim2.fromOffset(110, 40),
		AlwaysOnTop = true,
		Adornee = anchor,
		Parent = anchor,
	})
	local l = label({
		Parent = bb,
		Size = UDim2.fromScale(1, 1),
		Font = FONT_TITLE,
		Text = "+" .. Format.Short(value),
		TextColor3 = RARITY_COLOR[rarityId] or C.gold,
		TextStrokeTransparency = 0.2,
	})
	TweenService:Create(bb, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 5, 0) }):Play()
	TweenService:Create(l, TweenInfo.new(0.9), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1)
end

----------------------------------------------------------------------
-- 패널 내용 그리기
----------------------------------------------------------------------
local function clearContent()
	for _, c in ipairs(content:GetChildren()) do
		c:Destroy()
	end
end

local function list(padding)
	return new("UIListLayout", { Padding = UDim.new(0, padding or 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
end

local function sectionTitle(text, order)
	return label({
		Parent = content,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 26),
		Font = FONT_TITLE,
		TextColor3 = C.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
	})
end

local function fmtUpgradeValue(id, v)
	if id == "SpawnRate" then
		return string.format("%.2f초", v)
	elseif id == "Luck" then
		return string.format("x%.2f", v)
	elseif id == "Magnet" then
		return string.format("%.1f", v)
	end
	return tostring(math.floor(v))
end

local renderers = {}

function renderers.Upgrades()
	list(8)
	for i, id in ipairs(Config.UpgradeOrder) do
		local def = Config.Upgrades[id]
		local u = state.upgrades[id]
		local row = new("Frame", { Parent = content, LayoutOrder = i, Size = UDim2.new(1, -8, 0, 70), BackgroundColor3 = C.card }, { corner(10) })
		label({ Parent = row, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(0.6, -12, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, Text = string.format("%s  Lv.%d/%d", def.name, u.level, u.max) })
		local detail = u.level >= u.max and ("최대: " .. fmtUpgradeValue(id, u.value))
			or (fmtUpgradeValue(id, u.value) .. "  →  " .. fmtUpgradeValue(id, u.nextValue))
		label({ Parent = row, Position = UDim2.fromOffset(12, 38), Size = UDim2.new(0.6, -12, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.sub, Text = detail })
		local maxed = u.level >= u.max
		local affordable = state.coins >= u.cost
		button({
			Parent = row,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0.36, 0, 0, 46),
			BackgroundColor3 = maxed and C.gray or (affordable and C.green or C.gray),
			Text = maxed and "MAX" or ("⭐ " .. Format.Short(u.cost)),
		}, function()
			if maxed then
				return
			end
			local ok, msg = Action:InvokeServer("BuyUpgrade", id)
			if not ok and msg then
				toast(msg, C.red)
			end
		end)
	end
end

function renderers.Pets()
	list(10)
	sectionTitle("알 뽑기 (확률 공개)", 1)

	local eggRow = new("Frame", { Parent = content, LayoutOrder = 2, Size = UDim2.new(1, -8, 0, 190), BackgroundTransparency = 1 }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }),
	})
	for i, eggId in ipairs(Config.EggOrder) do
		local egg = Config.Eggs[eggId]
		local card = new("Frame", { Parent = eggRow, LayoutOrder = i, Size = UDim2.new(1 / #Config.EggOrder, -6, 1, 0), BackgroundColor3 = C.card }, { corner(10) })
		label({ Parent = card, Position = UDim2.fromOffset(6, 4), Size = UDim2.new(1, -12, 0, 26), Font = FONT_TITLE, Text = "🥚 " .. egg.name })
		local odds = {}
		for _, e in ipairs(egg.chances) do
			local p = Config.Pets[e.pet]
			table.insert(odds, string.format("%s %s%%", p.name, tostring(e.chance)))
		end
		label({
			Parent = card,
			Position = UDim2.fromOffset(6, 32),
			Size = UDim2.new(1, -12, 0, 100),
			TextColor3 = C.sub,
			TextScaled = false,
			TextSize = 13,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = table.concat(odds, "\n"),
		})
		button({
			Parent = card,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -16, 0, 42),
			BackgroundColor3 = state.coins >= egg.cost and C.green or C.gray,
			Text = "⭐ " .. Format.Short(egg.cost),
		}, function()
			local ok, msg = Action:InvokeServer("Hatch", eggId)
			if not ok and msg then
				toast(msg, C.red)
			end
		end)
	end

	local equippedSet = {}
	for _, uid in ipairs(state.equipped) do
		equippedSet[uid] = true
	end
	sectionTitle(string.format("내 펫 %d/%d · 장착 %d/%d · 펫 배율 x%.2f", #state.pets, Config.MaxPetInventory, #state.equipped, state.stats.slots, state.stats.petMult), 3)
	button({ Parent = content, LayoutOrder = 4, Size = UDim2.new(0, 180, 0, 38), BackgroundColor3 = C.accent, Text = "✨ 최고 펫 장착" }, function()
		Action:InvokeServer("EquipBest")
	end)

	local grid = new("Frame", { Parent = content, LayoutOrder = 5, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, {
		new("UIGridLayout", { CellSize = UDim2.fromOffset(104, 104), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local sorted = table.clone(state.pets)
	table.sort(sorted, function(a, b)
		local ea, eb = equippedSet[a.uid] and 1 or 0, equippedSet[b.uid] and 1 or 0
		if ea ~= eb then
			return ea > eb
		end
		return Config.Pets[a.id].bonus > Config.Pets[b.id].bonus
	end)
	for i, pet in ipairs(sorted) do
		local def = Config.Pets[pet.id]
		local equipped = equippedSet[pet.uid]
		local card = button({
			Parent = grid,
			LayoutOrder = i,
			BackgroundColor3 = equipped and C.cardHi or C.card,
			Text = "",
		}, function()
			Action:InvokeServer(equipped and "Unequip" or "Equip", pet.uid)
		end)
		stroke(equipped and C.green or def.color, equipped and 3 or 1.5).Parent = card
		new("Frame", { Parent = card, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = def.color }, { corner(20) })
		label({ Parent = card, Position = UDim2.new(0, 0, 0, 48), Size = UDim2.new(1, 0, 0, 22), Text = def.name })
		label({ Parent = card, Position = UDim2.new(0, 0, 0, 70), Size = UDim2.new(1, 0, 0, 18), TextColor3 = def.color, Text = "+" .. math.floor(def.bonus * 100 + 0.5) .. "%" })
		if not equipped then
			button({ Parent = card, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -2, 0, 2), Size = UDim2.fromOffset(24, 24), BackgroundColor3 = C.red, Text = "✕" }, function()
				Action:InvokeServer("ReleasePet", pet.uid)
			end)
		end
	end
	if #sorted == 0 then
		label({ Parent = content, LayoutOrder = 6, Size = UDim2.new(1, 0, 0, 30), TextColor3 = C.sub, Text = "아직 펫이 없어요. 알을 뽑아 보세요!" })
	end
end

local function shopCard(order, info, kind, ownedFlag, extraText)
	local card = new("Frame", { Parent = content, LayoutOrder = order, Size = UDim2.new(1, -8, 0, 66), BackgroundColor3 = C.card }, { corner(10) })
	label({ Parent = card, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(0.62, -12, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, Text = info.name })
	label({
		Parent = card,
		Position = UDim2.fromOffset(12, 36),
		Size = UDim2.new(0.62, -12, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.sub,
		Text = extraText or info.desc,
	})
	local configured = info.id ~= 0
	local text
	if ownedFlag then
		text = "✅ 보유 중"
	elseif not configured then
		text = "ID 설정 필요"
	else
		text = " " .. info.price .. " R$"
	end
	button({
		Parent = card,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0.33, 0, 0, 44),
		BackgroundColor3 = ownedFlag and C.gray or (configured and C.green or C.gray),
		Text = text,
	}, function()
		if ownedFlag or not configured then
			return
		end
		if kind == "pass" then
			MarketplaceService:PromptGamePassPurchase(player, info.id)
		else
			MarketplaceService:PromptProductPurchase(player, info.id)
		end
	end)
end

local PASS_ORDER = { "DoubleCoins", "AutoSell", "Lucky", "VIP", "PetSlots" }
local PRODUCT_ORDER = { "MeteorShower", "LuckBoost", "CoinsSmall", "CoinsLarge" }

function renderers.Shop()
	list(8)
	local order = 1
	sectionTitle("게임패스 (영구)", order)
	for _, key in ipairs(PASS_ORDER) do
		order += 1
		shopCard(order, Config.GamePasses[key], "pass", state.passes[key])
	end
	order += 1
	sectionTitle("아이템 (1회용)", order)
	for _, key in ipairs(PRODUCT_ORDER) do
		local isCoins = key == "CoinsSmall" or key == "CoinsLarge"
		-- 확률형 아이템이 제한된 지역에선 코인 판매를 숨김 (코인으로 알을 뽑을 수 있으므로)
		if not (isCoins and state.paidRandomRestricted) then
			order += 1
			local extra = nil
			if key == "CoinsSmall" then
				extra = "코인 " .. Format.Short(state.packSmall) .. " 개"
			elseif key == "CoinsLarge" then
				extra = "코인 " .. Format.Short(state.packLarge) .. " 개 (6배!)"
			end
			shopCard(order, Config.Products[key], "product", false, extra)
		end
	end
end

function renderers.Rebirth()
	list(12)
	label({
		Parent = content,
		LayoutOrder = 1,
		Size = UDim2.new(1, -8, 0, 60),
		TextScaled = false,
		TextSize = 16,
		TextWrapped = true,
		TextColor3 = C.sub,
		Text = "환생하면 코인과 업그레이드가 초기화되지만, 코인 배율이 영원히 올라가요! 펫은 그대로 남아요.",
	})
	label({
		Parent = content,
		LayoutOrder = 2,
		Size = UDim2.new(1, -8, 0, 44),
		Font = FONT_TITLE,
		TextColor3 = C.gold,
		Text = string.format("환생 %d회 · 배율 x%.1f  →  x%.1f", state.rebirths, state.rebirthMult, state.rebirthNextMult),
	})
	local progress = math.clamp(state.coins / state.rebirthCost, 0, 1)
	local back = new("Frame", { Parent = content, LayoutOrder = 3, Size = UDim2.new(1, -8, 0, 28), BackgroundColor3 = Color3.fromRGB(20, 15, 40) }, { corner(14) })
	new("Frame", { Parent = back, Size = UDim2.fromScale(progress, 1), BackgroundColor3 = C.accent }, { corner(14) })
	label({ Parent = back, Size = UDim2.fromScale(1, 1), ZIndex = 2, Text = Format.Short(state.coins) .. " / " .. Format.Short(state.rebirthCost) })
	button({
		Parent = content,
		LayoutOrder = 4,
		Size = UDim2.new(1, -8, 0, 56),
		BackgroundColor3 = progress >= 1 and C.green or C.gray,
		Text = "🔄 환생하기",
	}, function()
		local ok, msg = Action:InvokeServer("Rebirth")
		if not ok and msg then
			toast(msg, C.red)
		end
	end)
end

function renderers.Daily()
	list(12)
	local row = new("Frame", { Parent = content, LayoutOrder = 1, Size = UDim2.new(1, -8, 0, 84), BackgroundTransparency = 1 }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
	})
	for day, base in ipairs(Config.DailyRewards) do
		local current = day == state.daily.day
		local cell = new("Frame", {
			Parent = row,
			LayoutOrder = day,
			Size = UDim2.new(1 / #Config.DailyRewards, -6, 1, 0),
			BackgroundColor3 = current and C.cardHi or C.card,
		}, { corner(8) })
		if current then
			stroke(C.gold, 2).Parent = cell
		end
		label({ Parent = cell, Position = UDim2.fromOffset(2, 6), Size = UDim2.new(1, -4, 0, 26), Text = day .. "일" })
		label({ Parent = cell, Position = UDim2.fromOffset(2, 40), Size = UDim2.new(1, -4, 0, 30), TextColor3 = C.gold, Text = Format.Short(base * (state.rebirths + 1)) })
	end
	button({
		Parent = content,
		LayoutOrder = 2,
		Size = UDim2.new(1, -8, 0, 56),
		BackgroundColor3 = state.daily.available and C.green or C.gray,
		Text = state.daily.available and ("🎁 받기 (+" .. Format.Short(state.daily.reward) .. ")") or "내일 다시 와요!",
	}, function()
		local ok, msg = Action:InvokeServer("ClaimDaily")
		if msg then
			toast(msg, ok and C.green or C.red)
		end
	end)
	label({
		Parent = content,
		LayoutOrder = 3,
		Size = UDim2.new(1, -8, 0, 40),
		TextScaled = false,
		TextSize = 14,
		TextWrapped = true,
		TextColor3 = C.sub,
		Text = "매일 접속하면 보상이 커져요. 하루라도 빠지면 1일차부터 다시 시작해요.",
	})
end

local TITLES = { Upgrades = "⬆️ 업그레이드", Pets = "🥚 별 요정 (펫)", Shop = "💎 상점", Rebirth = "🔄 환생", Daily = "🎁 출석 보상" }

local function renderPanel()
	if not currentPanel or not state then
		return
	end
	local scroll = content.CanvasPosition
	clearContent()
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), Parent = content })
	renderers[currentPanel]()
	content.CanvasPosition = scroll
end

openPanel = function(key)
	currentPanel = key
	if not key then
		panel.Visible = false
		return
	end
	panelTitle.Text = TITLES[key]
	panel.Visible = true
	content.CanvasPosition = Vector2.zero
	renderPanel()
	pop(panel)
end

----------------------------------------------------------------------
-- 서버 → 클라이언트
----------------------------------------------------------------------
local function updateBag(count, _value, cap)
	local ratio = cap > 0 and math.clamp(count / cap, 0, 1) or 0
	bagFill.Size = UDim2.fromScale(ratio, 1)
	bagFill.BackgroundColor3 = ratio >= 1 and C.red or (ratio > 0.75 and C.gold or C.green)
	bagLabel.Text = string.format("🎒 %d / %d", count, cap)
end

local localTimers = { meteorEnd = 0, luckEnd = 0 }

remotes:WaitForChild("State").OnClientEvent:Connect(function(snapshot)
	state = snapshot
	coinLabel.Text = "⭐ " .. Format.Short(snapshot.coins)
	multLabel.Text = string.format("코인 배율 x%.2f · 행운 x%.2f", snapshot.stats.coinMult, snapshot.stats.luck)
	updateBag(snapshot.bagCount, snapshot.bagValue, snapshot.stats.bagCap)
	localTimers.meteorEnd = os.clock() + snapshot.meteorLeft
	localTimers.luckEnd = os.clock() + snapshot.luckBoostLeft
	sellAnywhere.Visible = snapshot.passes.AutoSell == true
	menuButtons.Daily.dot.Visible = snapshot.daily.available
	menuButtons.Rebirth.dot.Visible = snapshot.coins >= snapshot.rebirthCost
	renderPanel()
end)

remotes:WaitForChild("Bag").OnClientEvent:Connect(function(count, value, cap)
	if state then
		state.bagCount = count
		state.bagValue = value
	end
	updateBag(count, value, cap)
end)

remotes:WaitForChild("Collect").OnClientEvent:Connect(collectEffect)

remotes:WaitForChild("Notify").OnClientEvent:Connect(function(text, color, size)
	toast(text, color, size == "small")
end)

remotes:WaitForChild("Announce").OnClientEvent:Connect(function(text, seconds)
	showBanner(text, seconds)
end)

remotes:WaitForChild("Hatched").OnClientEvent:Connect(playHatch)

-- 부스트 남은 시간 표시
task.spawn(function()
	while true do
		task.wait(0.5)
		local m = localTimers.meteorEnd - os.clock()
		meteorLabel.Visible = m > 0
		if m > 0 then
			meteorLabel.Text = "☄️ 유성우 " .. Format.Time(m)
		end
		local l = localTimers.luckEnd - os.clock()
		luckLabel.Visible = l > 0
		if l > 0 then
			luckLabel.Text = "🍀 행운 x3 " .. Format.Time(l)
		end
	end
end)

----------------------------------------------------------------------
-- VIP 채팅 태그
----------------------------------------------------------------------
TextChatService.OnIncomingMessage = function(message)
	local props = Instance.new("TextChatMessageProperties")
	local source = message.TextSource
	if source then
		local sender = Players:GetPlayerByUserId(source.UserId)
		if sender and sender:GetAttribute("VIP") then
			props.PrefixText = "<font color='#FFD75A'>[VIP]</font> " .. message.PrefixText
		end
	end
	return props
end

PetVisuals.Start()
