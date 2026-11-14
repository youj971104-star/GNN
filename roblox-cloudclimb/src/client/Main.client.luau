-- ☁️ 구름 오비 클라이언트 UI

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local UIKit = require(script.Parent.UIKit)

local C = UIKit.C
local new, label, button = UIKit.new, UIKit.label, UIKit.button

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local Action = remotes:WaitForChild("Action")

local state
local screen = UIKit.Screen("CloudClimbUI")
screen.isReady = function()
	return state ~= nil
end
local viewStage = 1 -- 스테이지 선택기에서 보고 있는 번호

local function act(name, arg)
	local ok, msg = Action:InvokeServer(name, arg)
	if msg then
		screen.toast(msg, ok and C.green or C.red)
	end
	return ok
end

----------------------------------------------------------------------
-- HUD
----------------------------------------------------------------------
local hud = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(320, 88),
	BackgroundColor3 = C.bg,
	BackgroundTransparency = 0.15,
	Parent = screen.gui,
}, { UIKit.corner(14), UIKit.stroke(C.accent, 2) })
local stageLabel = label({ Parent = hud, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 32), Font = UIKit.FONT_TITLE, Text = "🚩 1 / 100" })
local zoneLabel = label({ Parent = hud, Position = UDim2.fromOffset(10, 36), Size = UDim2.new(1, -20, 0, 18), TextColor3 = C.sub, Text = "" })
local barBack = new("Frame", { Parent = hud, Position = UDim2.fromOffset(12, 58), Size = UDim2.new(0.62, -12, 0, 20), BackgroundColor3 = Color3.fromRGB(20, 15, 40) }, { UIKit.corner(10) })
local barFill = new("Frame", { Parent = barBack, Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.green }, { UIKit.corner(10) })
local coinLabel = label({ Parent = hud, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 56), Size = UDim2.new(0.36, -8, 0, 24), TextColor3 = C.gold, Text = "💰 0" })

-- 스테이지 건너뛰기 (가장 잘 보이는 오른쪽에 배치)
button({
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(120, 70),
	BackgroundColor3 = Color3.fromRGB(255, 140, 60),
	Text = "⏭️\n건너뛰기",
	Parent = screen.gui,
}, function()
	local info = Config.Products.SkipStage
	if info.id ~= 0 then
		MarketplaceService:PromptProductPurchase(player, info.id)
	else
		screen.toast("Config 에 SkipStage 상품 ID 를 넣어 주세요", C.red)
	end
end)

-- 스테이지 선택기 (깬 스테이지 안에서 자유롭게 이동)
local selector = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.fromOffset(300, 54),
	BackgroundColor3 = C.bg,
	BackgroundTransparency = 0.15,
	Parent = screen.gui,
}, { UIKit.corner(12), UIKit.stroke(C.accent, 2) })
local selectorLabel = label({ Parent = selector, Position = UDim2.new(0, 60, 0, 6), Size = UDim2.new(1, -120, 1, -12), Text = "스테이지 1" })
local function step(delta)
	if not state then
		return
	end
	viewStage = math.clamp(viewStage + delta, 1, state.selectMax or state.highest)
	selectorLabel.Text = "스테이지 " .. viewStage
	act("SetStage", viewStage)
end
button({ Parent = selector, Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(48, 42), Text = "◀" }, function()
	step(-1)
end)
button({ Parent = selector, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(48, 42), Text = "▶" }, function()
	step(1)
end)

----------------------------------------------------------------------
-- 패널
----------------------------------------------------------------------
screen.menu("Shop", "💎\n상점", Color3.fromRGB(230, 80, 170), "💎 상점", function(parent)
	UIKit.shop(parent, Config, { "Speed", "HighJump", "DoubleCoins", "VIP" }, { "SkipStage", "Skip5", "Coins" }, state.passes)
end)

screen.menu("Trails", "✨\n트레일", Color3.fromRGB(90, 160, 255), "✨ 트레일 (코인)", function(parent)
	UIKit.paragraph(parent, "코인은 새 스테이지를 깰 때마다 받아요. 확률 없이 원하는 걸 바로 살 수 있어요!", 1)
	for i, id in ipairs(Config.TrailOrder) do
		local def = Config.Trails[id]
		local owned = state.trails[id]
		local equipped = state.trail == id
		local text, color
		if equipped then
			text, color = "장착 중", C.gray
		elseif owned then
			text, color = "장착", C.accent
		elseif def.cost < 0 then
			text, color = "VIP 전용", C.gray
		else
			text, color = "💰 " .. Format.Short(def.cost), state.coins >= def.cost and C.green or C.gray
		end
		local row = UIKit.row(parent, i + 1, def.name, def.cost > 0 and ("가격 " .. Format.Short(def.cost)) or "", text, color, function()
			if not equipped then
				act("BuyTrail", id)
			end
		end)
		local swatch = new("Frame", { Parent = row, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.45, 0, 0.5, 0), Size = UDim2.fromOffset(60, 16), BackgroundColor3 = Color3.new(1, 1, 1) }, { UIKit.corner(8) })
		local kps = {}
		for k, c in ipairs(def.colors) do
			table.insert(kps, ColorSequenceKeypoint.new((k - 1) / math.max(1, #def.colors - 1), c))
		end
		if #kps == 1 then
			table.insert(kps, ColorSequenceKeypoint.new(1, def.colors[1]))
		end
		new("UIGradient", { Color = ColorSequence.new(kps), Parent = swatch })
	end
end)

screen.menu("Rebirth", "🔄\n환생", Color3.fromRGB(130, 90, 230), "🔄 환생", function(parent)
	local finish = state.stageCount + 1
	UIKit.paragraph(parent, "정상(🏆)에 도착하면 환생할 수 있어요. 스테이지가 1로 돌아가지만 코인 배율이 +0.5 영구로 올라가고, 이름 옆 환생 숫자가 늘어나요!", 1, 60)
	label({ Parent = parent, LayoutOrder = 2, Size = UDim2.new(1, -8, 0, 40), Font = UIKit.FONT_TITLE, TextColor3 = C.gold, Text = string.format("환생 %d회 · 코인 배율 x%.1f", state.rebirths, state.coinMult) })
	button({ Parent = parent, LayoutOrder = 3, Size = UDim2.new(1, -8, 0, 56), BackgroundColor3 = state.highest >= finish and C.green or C.gray, Text = state.highest >= finish and "🔄 환생하기" or ("정상까지 " .. (finish - state.highest) .. " 스테이지") }, function()
		act("Rebirth")
	end)
	UIKit.paragraph(parent, string.format("지금까지 넘어진 횟수: %d번 😅", state.deaths), 4)
end)

----------------------------------------------------------------------
-- 서버 이벤트
----------------------------------------------------------------------
remotes:WaitForChild("State").OnClientEvent:Connect(function(s)
	state = s
	viewStage = s.current
	local shown = math.min(s.current, s.stageCount)
	stageLabel.Text = s.highest > s.stageCount and "🏆 정상 정복!" or string.format("🚩 %d / %d", shown, s.stageCount)
	local zone = Config.ZoneFor(shown)
	zoneLabel.Text = zone.name .. (s.rebirths > 0 and ("  ·  🔄 " .. s.rebirths) or "")
	barFill.Size = UDim2.fromScale(math.clamp((s.highest - 1) / s.stageCount, 0, 1), 1)
	barFill.BackgroundColor3 = zone.color
	coinLabel.Text = "💰 " .. Format.Short(s.coins)
	selectorLabel.Text = "스테이지 " .. s.current
	screen.menuButtons.Rebirth.dot.Visible = s.highest > s.stageCount
	screen.render()
end)

remotes:WaitForChild("Notify").OnClientEvent:Connect(function(text, color)
	screen.toast(text, color)
end)
remotes:WaitForChild("Announce").OnClientEvent:Connect(function(text, seconds)
	screen.banner(text, seconds)
end)

-- VIP 채팅 태그
TextChatService.OnIncomingMessage = function(message)
	local props = Instance.new("TextChatMessageProperties")
	local source = message.TextSource
	local sender = source and Players:GetPlayerByUserId(source.UserId)
	if sender and sender:GetAttribute("VIP") then
		props.PrefixText = "<font color='#FFD75A'>[VIP]</font> " .. message.PrefixText
	end
	return props
end
