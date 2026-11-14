-- 🍢 떡볶이 가게 타이쿤 클라이언트 UI

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
local rushEnd = 0
local screen = UIKit.Screen("TteokbokkiUI")
screen.isReady = function()
	return state ~= nil
end

local function act(name, arg)
	local ok, msg = Action:InvokeServer(name, arg)
	if msg then
		screen.toast(msg, ok and C.green or C.red)
	end
end

----------------------------------------------------------------------
-- HUD
----------------------------------------------------------------------
local hud = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(320, 90),
	BackgroundColor3 = C.bg,
	BackgroundTransparency = 0.15,
	Parent = screen.gui,
}, { UIKit.corner(14), UIKit.stroke(Color3.fromRGB(255, 120, 80), 2) })
local cashLabel = label({ Parent = hud, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 36), Font = UIKit.FONT_TITLE, TextColor3 = C.gold, Text = "💰 0" })
local incomeLabel = label({ Parent = hud, Position = UDim2.fromOffset(10, 42), Size = UDim2.new(1, -20, 0, 20), TextColor3 = C.sub, Text = "" })
local barBack = new("Frame", { Parent = hud, Position = UDim2.fromOffset(12, 66), Size = UDim2.new(1, -24, 0, 16), BackgroundColor3 = Color3.fromRGB(20, 15, 40) }, { UIKit.corner(8) })
local barFill = new("Frame", { Parent = barBack, Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 120, 80) }, { UIKit.corner(8) })
local barLabel = label({ Parent = barBack, Size = UDim2.fromScale(1, 1), ZIndex = 2, Text = "" })

local rushLabel = label({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 60),
	Size = UDim2.fromOffset(200, 28),
	TextColor3 = Color3.fromRGB(255, 160, 220),
	Visible = false,
	Parent = screen.gui,
})

-- 오른쪽: 바로 짓기 (진행이 막힐 때 누르는 버튼)
button({
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(120, 70),
	BackgroundColor3 = Color3.fromRGB(255, 140, 60),
	Text = "🔨\n바로 짓기",
	Parent = screen.gui,
}, function()
	local info = Config.Products.BuildNext
	if info.id ~= 0 then
		MarketplaceService:PromptProductPurchase(player, info.id)
	else
		screen.toast("Config 에 BuildNext 상품 ID 를 넣어 주세요", C.red)
	end
end)

----------------------------------------------------------------------
-- 패널
----------------------------------------------------------------------
screen.menu("Shop", "💎\n상점", Color3.fromRGB(230, 80, 170), "💎 상점", function(parent)
	UIKit.shop(parent, Config, { "DoubleCash", "AutoCollect", "FastCook", "VIP", "LongOffline" }, { "Rush", "BuildNext", "CashSmall", "CashLarge" }, state.passes, {
		CashSmall = "💰 " .. Format.Short(state.packSmall) .. " (다음 건물 값)",
		CashLarge = "💰 " .. Format.Short(state.packLarge) .. " (5배!)",
	})
end)

screen.menu("Build", "🏗️\n건물", Color3.fromRGB(255, 150, 80), "🏗️ 건물 목록", function(parent)
	UIKit.paragraph(parent, "가게 앞 초록 발판을 밟으면 지어져요. 빨간 발판은 돈이 부족한 거예요.", 1)
	for _, def in ipairs(Config.Buttons) do
		local kindText = ({ base = "기본", dropper = "음식 기계", upgrader = "토핑 (가치 x" .. tostring(def.mult) .. ")", deco = "인테리어 (수입 +" .. math.floor((def.bonus or 0) * 100) .. "%)" })[def.kind]
		local row = new("Frame", { Parent = parent, LayoutOrder = def.index + 1, Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = C.card }, { UIKit.corner(10) })
		label({ Parent = row, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(0.55, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Text = def.name })
		label({ Parent = row, Position = UDim2.fromOffset(12, 24), Size = UDim2.new(0.55, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.sub, Text = kindText })
		label({ Parent = row, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.new(0.4, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.gold, Text = def.cost == 0 and "무료" or ("💰 " .. Format.Short(def.cost)) })
	end
end)

screen.menu("Rebirth", "🏪\n프랜차이즈", Color3.fromRGB(130, 90, 230), "🏪 프랜차이즈 (환생)", function(parent)
	UIKit.paragraph(parent, "모든 건물을 지으면 새 지점을 열 수 있어요. 가게와 돈은 초기화되지만 수입 배율이 영원히 올라가요!", 1, 56)
	label({ Parent = parent, LayoutOrder = 2, Size = UDim2.new(1, -8, 0, 40), Font = UIKit.FONT_TITLE, TextColor3 = C.gold, Text = string.format("%d호점 · 배율 x%.1f → x%.1f", state.rebirths + 1, 1 + state.rebirths * 0.5, state.nextRebirthMult) })
	button({ Parent = parent, LayoutOrder = 3, Size = UDim2.new(1, -8, 0, 56), BackgroundColor3 = state.canRebirth and C.green or C.gray, Text = state.canRebirth and "🏪 새 지점 열기" or string.format("건물 %d / %d", state.bought, state.total) }, function()
		act("Rebirth")
	end)
end)

----------------------------------------------------------------------
-- 이벤트
----------------------------------------------------------------------
remotes:WaitForChild("State").OnClientEvent:Connect(function(s)
	state = s
	cashLabel.Text = "💰 " .. Format.Short(s.cash)
	incomeLabel.Text = string.format("초당 약 %s · 배율 x%.2f", Format.Short(s.income), s.mult)
	barFill.Size = UDim2.fromScale(s.bought / s.total, 1)
	barLabel.Text = string.format("🏗️ %d / %d", s.bought, s.total)
	rushEnd = os.clock() + s.rushLeft
	screen.menuButtons.Rebirth.dot.Visible = s.canRebirth
	screen.render()
end)

remotes:WaitForChild("Notify").OnClientEvent:Connect(function(text, color)
	screen.toast(text, color)
end)
remotes:WaitForChild("Announce").OnClientEvent:Connect(function(text, seconds)
	screen.banner(text, seconds)
end)
remotes:WaitForChild("Offline").OnClientEvent:Connect(function(amount, seconds, capHours)
	local hours = seconds / 3600
	screen.banner(string.format("🌙 쉬는 동안 %s 벌었어요! (%.1f시간)", Format.Short(amount), hours), 6)
	if capHours < 8 then
		task.delay(6.5, function()
			screen.toast("🌙 야간 영업 패스를 사면 최대 8시간까지 벌어 둬요", C.sub)
		end)
	end
end)

task.spawn(function()
	while true do
		task.wait(0.5)
		local left = rushEnd - os.clock()
		rushLabel.Visible = left > 0
		if left > 0 then
			rushLabel.Text = "🎉 손님 폭주 x3 " .. Format.Time(left)
		end
	end
end)

TextChatService.OnIncomingMessage = function(message)
	local props = Instance.new("TextChatMessageProperties")
	local source = message.TextSource
	local sender = source and Players:GetPlayerByUserId(source.UserId)
	if sender and sender:GetAttribute("VIP") then
		props.PrefixText = "<font color='#FFD75A'>[VIP]</font> " .. message.PrefixText
	end
	return props
end
