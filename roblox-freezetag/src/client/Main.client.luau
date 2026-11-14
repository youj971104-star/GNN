-- 🧊 얼음땡 술래잡기 클라이언트 UI

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
local roundInfo = { phase = "Waiting", timeLeft = 0, alive = 0, total = 0, need = 2 }
local roundEndsAt = 0
local screen = UIKit.Screen("FreezeTagUI")
screen.isReady = function()
	return state ~= nil
end

local function act(name, arg)
	local ok, msg = Action:InvokeServer(name, arg)
	if msg then
		screen.toast(msg, ok and C.green or C.red)
	end
end

local function prompt(key)
	local info = Config.Products[key]
	if info.id ~= 0 then
		MarketplaceService:PromptProductPurchase(player, info.id)
	else
		screen.toast("Config 에 " .. key .. " 상품 ID 를 넣어 주세요", C.red)
	end
end

----------------------------------------------------------------------
-- HUD
----------------------------------------------------------------------
local hud = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(330, 90),
	BackgroundColor3 = C.bg,
	BackgroundTransparency = 0.15,
	Parent = screen.gui,
}, { UIKit.corner(14), UIKit.stroke(Color3.fromRGB(140, 210, 255), 2) })
local phaseLabel = label({ Parent = hud, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 34), Font = UIKit.FONT_TITLE, Text = "대기 중..." })
local infoLabel = label({ Parent = hud, Position = UDim2.fromOffset(10, 40), Size = UDim2.new(1, -20, 0, 22), TextColor3 = C.sub, Text = "" })
local coinLabel = label({ Parent = hud, Position = UDim2.fromOffset(10, 64), Size = UDim2.new(1, -20, 0, 20), TextColor3 = C.gold, Text = "💰 0" })

local roleLabel = label({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.fromOffset(360, 40),
	Font = UIKit.FONT_TITLE,
	TextStrokeTransparency = 0.2,
	Text = "",
	Parent = screen.gui,
})

-- 얼었을 때만 나타나는 버튼 (충동 구매가 가장 큰 순간)
local thawButton = button({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.62),
	Size = UDim2.fromOffset(260, 64),
	BackgroundColor3 = Color3.fromRGB(255, 120, 60),
	Text = "🔥 스스로 녹기  " .. Config.Products.SelfThaw.price .. " R$",
	Visible = false,
	Parent = screen.gui,
}, function()
	prompt("SelfThaw")
end)
local frozenOverlay = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(150, 210, 255),
	BackgroundTransparency = 0.75,
	Visible = false,
	Parent = screen.gui,
})
label({ Parent = frozenOverlay, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.fromOffset(420, 50), Font = UIKit.FONT_TITLE, Text = "🧊 얼었어요! 친구를 기다려요" })

----------------------------------------------------------------------
-- 패널
----------------------------------------------------------------------
screen.menu("Shop", "💎\n상점", Color3.fromRGB(230, 80, 170), "💎 상점", function(parent)
	local extra = {}
	if state.shield then
		extra.IceShield = "✅ 방패 보유 중 · 하나 더 사도 1개만 유지돼요"
	end
	if state.forcedTagger then
		extra.BeTagger = "✅ 다음 라운드 술래 확정됨"
	end
	UIKit.shop(parent, Config, { "TaggerChance", "DoubleCoins", "VIP" }, { "IceShield", "BeTagger", "SelfThaw", "Coins" }, state.passes, extra)
end)

screen.menu("Trails", "✨\n트레일", Color3.fromRGB(90, 160, 255), "✨ 트레일 (코인)", function(parent)
	UIKit.paragraph(parent, "라운드에서 버티고, 얼리고, 친구를 구하면 코인을 받아요. 확률 없이 바로 구매!", 1)
	for i, id in ipairs(Config.TrailOrder) do
		local def = Config.Trails[id]
		local owned, equipped = state.trails[id], state.trail == id
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
		UIKit.row(parent, i + 1, def.name, "", text, color, function()
			if not equipped then
				act("BuyTrail", id)
			end
		end)
	end
end)

screen.menu("Stats", "📊\n기록", Color3.fromRGB(60, 190, 120), "📊 내 기록", function(parent)
	local lines = {
		{ "🏆 승리", state.wins },
		{ "🎮 플레이한 라운드", state.rounds },
		{ "🧊 얼린 횟수", state.freezes },
		{ "🔥 구해 준 횟수", state.thaws },
		{ "💰 코인 배율", string.format("x%.1f", state.coinMult) },
	}
	for i, l in ipairs(lines) do
		local row = new("Frame", { Parent = parent, LayoutOrder = i, Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = C.card }, { UIKit.corner(10) })
		label({ Parent = row, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(0.6, 0, 1, -12), TextXAlignment = Enum.TextXAlignment.Left, Text = l[1] })
		label({ Parent = row, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6), Size = UDim2.new(0.35, 0, 1, -12), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.gold, Text = tostring(l[2]) })
	end
end)

----------------------------------------------------------------------
-- 이벤트
----------------------------------------------------------------------
local function updateRole()
	local role = player:GetAttribute("Role")
	local frozen = player:GetAttribute("Frozen") == true
	if role == "Tagger" then
		roleLabel.Text = "🔴 술래 — 모두 얼려요!"
		roleLabel.TextColor3 = Color3.fromRGB(255, 110, 110)
	elseif role == "Runner" then
		roleLabel.Text = frozen and "🧊 얼음!" or "🔵 도망자 — 얼은 친구를 만져 녹여요"
		roleLabel.TextColor3 = Color3.fromRGB(140, 210, 255)
	else
		roleLabel.Text = roundInfo.phase == "Playing" and "👀 관전 중 · 다음 라운드에 참가해요" or ""
		roleLabel.TextColor3 = C.sub
	end
	local showFrozen = frozen and roundInfo.phase == "Playing"
	thawButton.Visible = showFrozen
	frozenOverlay.Visible = showFrozen
end
player:GetAttributeChangedSignal("Role"):Connect(updateRole)
player:GetAttributeChangedSignal("Frozen"):Connect(updateRole)

remotes:WaitForChild("State").OnClientEvent:Connect(function(s)
	state = s
	coinLabel.Text = "💰 " .. Format.Short(s.coins) .. (s.shield and "   🛡️" or "")
	screen.render()
end)

remotes:WaitForChild("Round").OnClientEvent:Connect(function(info)
	roundInfo = info
	roundEndsAt = os.clock() + info.timeLeft
	updateRole()
end)

remotes:WaitForChild("Notify").OnClientEvent:Connect(function(text, color)
	screen.toast(text, color)
end)
remotes:WaitForChild("Announce").OnClientEvent:Connect(function(text, seconds)
	screen.banner(text, seconds)
end)

-- 타이머 표시
task.spawn(function()
	while true do
		task.wait(0.25)
		local left = roundEndsAt - os.clock()
		local p = roundInfo.phase
		if p == "Waiting" then
			phaseLabel.Text = "⏳ 친구를 기다리는 중..."
			infoLabel.Text = string.format("%d명 이상 모이면 시작해요", roundInfo.need)
		elseif p == "Intermission" then
			phaseLabel.Text = "⏳ 곧 시작 " .. math.ceil(math.max(0, left))
			infoLabel.Text = "상점에서 방패를 챙겨 보세요 🛡️"
		elseif p == "Playing" then
			phaseLabel.Text = "🏃 " .. Format.Time(left)
			infoLabel.Text = string.format("🔵 남은 도망자 %d / %d", roundInfo.alive, roundInfo.total)
		else
			phaseLabel.Text = "🏁 라운드 종료"
			infoLabel.Text = ""
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
