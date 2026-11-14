-- ⛳ 펑! 골프 파티 클라이언트 UI

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local UIKit = require(script.Parent.UIKit)
local Shot = require(script.Parent.Shot)

local C = UIKit.C
local new, label, button = UIKit.new, UIKit.label, UIKit.button

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local Action = remotes:WaitForChild("Action")

local state -- 내 데이터
local info = { phase = "Waiting", hole = 0, holes = 3, timeLeft = 0, board = {}, balls = {}, playing = {}, theme = "", need = 1 }
local endsAt = 0
local screen = UIKit.Screen("PopGolfUI")
screen.isReady = function()
	return state ~= nil
end

local function act(name, arg)
	local ok, msg = Action:InvokeServer(name, arg)
	if msg then
		screen.toast(msg, ok and C.green or C.red)
	end
	return ok
end

local function rarityColor(id)
	return Config.RarityById[id].color
end

----------------------------------------------------------------------
-- HUD
----------------------------------------------------------------------
local hud = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(360, 74),
	BackgroundColor3 = C.bg,
	BackgroundTransparency = 0.15,
	Parent = screen.gui,
}, { UIKit.corner(14), UIKit.stroke(Color3.fromRGB(120, 220, 120), 2) })
local phaseLabel = label({ Parent = hud, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 34), Font = UIKit.FONT_TITLE, Text = "대기 중..." })
local subLabel = label({ Parent = hud, Position = UDim2.fromOffset(10, 42), Size = UDim2.new(1, -20, 0, 24), TextColor3 = C.sub, Text = "" })

local wallet = label({
	Position = UDim2.fromOffset(12, 12),
	Size = UDim2.fromOffset(300, 28),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = C.gold,
	TextStrokeTransparency = 0.3,
	Text = "",
	Parent = screen.gui,
})

-- 점수판 (오른쪽)
local board = new("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 60),
	Size = UDim2.fromOffset(230, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = C.bg,
	BackgroundTransparency = 0.25,
	Visible = false,
	Parent = screen.gui,
}, {
	UIKit.corner(10),
	new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
})

-- 파워 게이지
local powerBack = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -100),
	Size = UDim2.fromOffset(360, 26),
	BackgroundColor3 = Color3.fromRGB(20, 15, 40),
	Visible = false,
	Parent = screen.gui,
}, { UIKit.corner(13), UIKit.stroke(Color3.new(1, 1, 1), 2) })
local powerFill = new("Frame", { Parent = powerBack, Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.green }, { UIKit.corner(13) })
local powerText = label({ Parent = powerBack, Size = UDim2.fromScale(1, 1), ZIndex = 2, Text = "" })

-- 샷 버튼 (모바일용, PC 는 마우스 왼쪽 꾹)
local shotButton = new("TextButton", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -20, 1, -30),
	Size = UDim2.fromOffset(120, 120),
	BackgroundColor3 = C.green,
	Text = "⛳\n꾹 눌러 샷",
	Font = UIKit.FONT_TITLE,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
	Visible = false,
	Parent = screen.gui,
}, { UIKit.corner(60), UIKit.stroke(Color3.new(1, 1, 1), 3), new("UIPadding", { PaddingTop = UDim.new(0, 18), PaddingBottom = UDim.new(0, 18), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }) })
shotButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		Shot.BeginCharge()
	end
end)
shotButton.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		Shot.Release()
	end
end)

local itemButton = button({
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -150, 1, -40),
	Size = UDim2.fromOffset(130, 60),
	BackgroundColor3 = Color3.fromRGB(255, 170, 60),
	Text = "",
	Visible = false,
	Parent = screen.gui,
}, function()
	Shot.UseItem()
end)

local hint = label({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -136),
	Size = UDim2.fromOffset(520, 24),
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeTransparency = 0.3,
	Text = "",
	Parent = screen.gui,
})

Shot.Start({
	setPower = function(p, visible)
		powerBack.Visible = visible
		powerFill.Size = UDim2.fromScale(p, 1)
		powerFill.BackgroundColor3 = Color3.fromHSV(0.33 - p * 0.33, 0.85, 0.95)
		powerText.Text = math.floor(p * 100) .. "%"
	end,
	setCanShoot = function(can)
		shotButton.BackgroundColor3 = can and C.green or C.gray
		if info.phase == "Playing" and info.playing[tostring(player.UserId)] then
			hint.Text = can and "🖱️ 마우스 왼쪽을 꾹 눌렀다 떼면 샷 · 카메라 방향으로 날아가요" or "공이 멈추길 기다려요..."
		else
			hint.Text = ""
		end
	end,
})

----------------------------------------------------------------------
-- 메뉴: 캡슐 뽑기
----------------------------------------------------------------------
local function oddsBlock(parent, order, rows)
	for i, row in ipairs(rows) do
		local names = {}
		for _, id in ipairs(row.skins) do
			table.insert(names, Config.Skins[id].name)
		end
		local text = string.format("%s %s%%  (각 %.2f%%)\n%s", Config.RarityById[row.rarity].name, tostring(row.percent), row.each, table.concat(names, ", "))
		UIKit.label({
			Parent = parent,
			LayoutOrder = order + i,
			Size = UDim2.new(1, -8, 0, 40),
			TextScaled = false,
			TextSize = 14,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = rarityColor(row.rarity),
			Text = text,
		})
	end
end

screen.menu("Gacha", "🎰\n캡슐", Color3.fromRGB(255, 120, 180), "🎰 캡슐 뽑기 (공 꾸미기)", function(parent)
	UIKit.paragraph(parent, "캡슐에서는 공 꾸미기만 나와요. 실력에는 영향이 없어요! 중복은 🧩 조각이 되고, 조각으로 원하는 공을 직접 살 수 있어요.", 1, 44)

	UIKit.row(parent, 2, Config.Capsules.Basic.name, "🪙 " .. Config.Capsules.Basic.cost .. " · 게임에서 번 코인으로만",
		"1회 뽑기", state.coins >= Config.Capsules.Basic.cost and C.green or C.gray, function()
			act("Pull", { capsule = "Basic", count = 1 })
		end)

	if state.restricted then
		UIKit.paragraph(parent, "🔒 이 지역에서는 프리미엄 캡슐을 이용할 수 없어요.", 3)
	else
		local prem = Config.Capsules.Premium
		UIKit.row(parent, 3, prem.name, "💎 " .. prem.cost, "1회 뽑기", state.gems >= prem.cost and C.green or C.gray, function()
			act("Pull", { capsule = "Premium", count = 1 })
		end)
		UIKit.row(parent, 4, prem.name .. " 10연차", "💎 " .. prem.tenCost .. " · 영웅 이상 1개 보장", "10회 뽑기", state.gems >= prem.tenCost and C.green or C.gray, function()
			act("Pull", { capsule = "Premium", count = 10 })
		end)
		UIKit.paragraph(parent, string.format("✨ 전설 이상 확정까지 %d회 남음 (프리미엄 %d회마다 보장)", Config.Pity.legendaryAt - state.pity, Config.Pity.legendaryAt), 5, 24)
	end

	UIKit.section(parent, "📊 일반 캡슐 확률", 10)
	oddsBlock(parent, 10, state.oddsBasic)
	if not state.restricted then
		UIKit.section(parent, "📊 프리미엄 캡슐 확률", 30)
		oddsBlock(parent, 30, state.oddsPremium)
	end
end)

----------------------------------------------------------------------
-- 메뉴: 내 공 (컬렉션 / 조각 상점)
----------------------------------------------------------------------
screen.menu("Balls", "🎨\n내 공", Color3.fromRGB(90, 160, 255), "🎨 내 공 컬렉션", function(parent)
	local owned = 0
	for _ in pairs(state.skins) do
		owned += 1
	end
	UIKit.paragraph(parent, string.format("모은 공 %d / %d · 🧩 조각 %d개", owned, #Config.SkinOrder, state.shards), 1, 26)
	local grid = new("Frame", { Parent = parent, LayoutOrder = 2, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, {
		new("UIGridLayout", { CellSize = UDim2.fromOffset(112, 140), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, id in ipairs(Config.SkinOrder) do
		local skin = Config.Skins[id]
		local has = state.skins[id] == true
		local equipped = state.equipped == id
		local card = new("Frame", { Parent = grid, LayoutOrder = i, BackgroundColor3 = equipped and C.cardHi or C.card }, { UIKit.corner(10), UIKit.stroke(rarityColor(skin.rarity), equipped and 3 or 1.5) })
		new("Frame", { Parent = card, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = skin.color, BackgroundTransparency = has and 0 or 0.6 }, { UIKit.corner(22), UIKit.stroke(Color3.new(0, 0, 0), 1) })
		label({ Parent = card, Position = UDim2.fromOffset(4, 56), Size = UDim2.new(1, -8, 0, 22), Text = skin.name })
		label({ Parent = card, Position = UDim2.fromOffset(4, 78), Size = UDim2.new(1, -8, 0, 16), TextColor3 = rarityColor(skin.rarity), Text = Config.RarityById[skin.rarity].name })
		local text, color, fn
		if equipped then
			text, color = "장착 중", C.gray
		elseif has then
			text, color, fn = "장착", C.accent, function()
				act("Equip", id)
			end
		elseif skin.exclusive == "VIP" then
			text, color = "👑 VIP 전용", C.gray
		else
			local price = Config.ShardPrice[skin.rarity]
			text, color, fn = "🧩 " .. price, state.shards >= price and C.green or C.gray, function()
				act("BuyShard", id)
			end
		end
		button({ Parent = card, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(1, -12, 0, 34), BackgroundColor3 = color, Text = text }, fn)
	end
end)

----------------------------------------------------------------------
-- 메뉴: 상점 / 기록
----------------------------------------------------------------------
screen.menu("Shop", "💎\n상점", Color3.fromRGB(230, 80, 170), "💎 상점", function(parent)
	local hidden = {}
	local extra = {}
	if state.restricted then
		-- 젬은 프리미엄 캡슐에만 쓰이므로 제한 지역에서는 판매하지 않음
		hidden = { Gems110 = true, Gems500 = true, Gems1300 = true, Starter = true }
	end
	if state.starterBought then
		hidden.Starter = true
	end
	UIKit.shop(parent, Config, { "VIP", "AimPlus" }, { "Starter", "Gems110", "Gems500", "Gems1300" }, state.passes, extra, hidden)
	UIKit.paragraph(parent, "🪙 코인은 판매하지 않아요. 경기에서만 얻을 수 있어요!", 50, 26)
end)

screen.menu("Stats", "📊\n기록", Color3.fromRGB(60, 190, 120), "📊 내 기록", function(parent)
	local s = state.stats
	local rows = {
		{ "🏆 우승", s.wins },
		{ "🎮 경기 수", s.matches },
		{ "⛳ 넣은 홀", s.holes },
		{ "🎉 홀인원", s.holeInOnes },
		{ "📈 최고 점수", s.bestPoints },
		{ "🎰 뽑은 캡슐", s.pulls },
	}
	for i, r in ipairs(rows) do
		local row = new("Frame", { Parent = parent, LayoutOrder = i, Size = UDim2.new(1, -8, 0, 42), BackgroundColor3 = C.card }, { UIKit.corner(10) })
		label({ Parent = row, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(0.6, 0, 1, -12), TextXAlignment = Enum.TextXAlignment.Left, Text = r[1] })
		label({ Parent = row, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6), Size = UDim2.new(0.35, 0, 1, -12), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.gold, Text = tostring(r[2]) })
	end
end)

----------------------------------------------------------------------
-- 뽑기 결과 연출
----------------------------------------------------------------------
local resultOverlay = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.35,
	Visible = false,
	ZIndex = 30,
	Parent = screen.gui,
})
local resultGrid = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.48),
	Size = UDim2.fromOffset(620, 300),
	BackgroundTransparency = 1,
	ZIndex = 31,
	Parent = resultOverlay,
}, { new("UIGridLayout", { CellSize = UDim2.fromOffset(112, 136), CellPadding = UDim2.fromOffset(10, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }) })
button({ Parent = resultOverlay, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(200, 54), BackgroundColor3 = C.green, Text = "확인", ZIndex = 32 }, function()
	resultOverlay.Visible = false
end)

remotes:WaitForChild("GachaResult").OnClientEvent:Connect(function(results)
	for _, c in ipairs(resultGrid:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	resultOverlay.Visible = true
	for i, r in ipairs(results) do
		local skin = Config.Skins[r.skin]
		local card = new("Frame", { Parent = resultGrid, LayoutOrder = i, BackgroundColor3 = C.card, ZIndex = 32, Visible = false }, { UIKit.corner(12), UIKit.stroke(rarityColor(r.rarity), 3) })
		new("Frame", { Parent = card, ZIndex = 33, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(52, 52), BackgroundColor3 = skin.color }, { UIKit.corner(26) })
		label({ Parent = card, ZIndex = 33, Position = UDim2.fromOffset(4, 66), Size = UDim2.new(1, -8, 0, 22), Text = skin.name })
		label({ Parent = card, ZIndex = 33, Position = UDim2.fromOffset(4, 88), Size = UDim2.new(1, -8, 0, 18), TextColor3 = rarityColor(r.rarity), Text = Config.RarityById[r.rarity].name })
		label({ Parent = card, ZIndex = 33, Position = UDim2.fromOffset(4, 108), Size = UDim2.new(1, -8, 0, 20), TextColor3 = r.new and C.gold or C.sub, Text = r.new and "✨ NEW!" or ("🧩 +" .. r.shards) })
		-- 하나씩 뒤집히듯 나타나기
		task.delay(0.12 * i, function()
			card.Visible = true
			UIKit.pop(card)
		end)
	end
end)

----------------------------------------------------------------------
-- 서버 이벤트
----------------------------------------------------------------------
local function renderBoard()
	for _, c in ipairs(board:GetChildren()) do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local inMatch = info.phase ~= "Waiting" and info.phase ~= "Intermission"
	board.Visible = inMatch and #info.board > 0
	local holeStatus = {}
	for _, b in ipairs(info.balls) do
		holeStatus[b.userId] = b
	end
	label({ Parent = board, LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 22), Font = UIKit.FONT_TITLE, TextColor3 = C.gold, Text = "🏆 점수판" })
	for i, row in ipairs(info.board) do
		local b = holeStatus[row.userId]
		local status = ""
		if b then
			if b.sunk then
				status = string.format("✅ %d타", b.strokes)
			else
				status = string.format("%d타", b.strokes) .. (b.frozen and " 🧊" or "") .. (b.super and " ⚡" or "") .. (b.magnet and " 🧲" or "")
			end
		end
		label({
			Parent = board,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = row.userId == player.UserId and C.gold or C.text,
			Text = string.format("%d. %s  %d점  %s", i, row.name, row.total, status),
		})
	end
end

remotes:WaitForChild("Match").OnClientEvent:Connect(function(m)
	info = m
	endsAt = os.clock() + m.timeLeft
	local playing = m.playing[tostring(player.UserId)] == true
	local inHole = m.phase == "Countdown" or m.phase == "Playing"
	shotButton.Visible = playing and inHole
	local me
	for _, b in ipairs(m.balls) do
		if b.userId == player.UserId then
			me = b
		end
	end
	if playing and inHole and me and me.item then
		itemButton.Visible = true
		itemButton.Text = "E  " .. Config.Items[me.item].name
	else
		itemButton.Visible = false
	end
	local aimPlus = state and state.passes and state.passes.AimPlus == true
	Shot.Update(m, aimPlus)
	renderBoard()
end)

remotes:WaitForChild("State").OnClientEvent:Connect(function(s)
	state = s
	wallet.Text = string.format("🪙 %s   💎 %s   🧩 %s", Format.Short(s.coins), Format.Short(s.gems), Format.Short(s.shards))
	screen.render()
end)

remotes:WaitForChild("Notify").OnClientEvent:Connect(function(text, color)
	screen.toast(text, color)
end)
remotes:WaitForChild("Announce").OnClientEvent:Connect(function(text, seconds)
	screen.banner(text, seconds)
end)

-- 상단 문구 / 타이머
task.spawn(function()
	while true do
		task.wait(0.25)
		local left = math.max(0, endsAt - os.clock())
		local p = info.phase
		local playing = info.playing[tostring(player.UserId)] == true
		if p == "Waiting" then
			phaseLabel.Text = "⏳ 플레이어를 기다리는 중"
			subLabel.Text = "로비에서 캡슐을 뽑거나 공을 꾸며 보세요"
		elseif p == "Intermission" then
			phaseLabel.Text = "⛳ 곧 경기 시작 " .. math.ceil(left)
			subLabel.Text = string.format("홀 %d개 · 모두 동시에 플레이 · ❓ 상자로 방해하기!", info.holes)
		elseif p == "Countdown" then
			phaseLabel.Text = string.format("%d번 홀 · 준비 %d", info.hole, math.ceil(left))
			subLabel.Text = info.theme
		elseif p == "Playing" then
			phaseLabel.Text = string.format("⛳ %d / %d 홀  ⏱ %s", info.hole, info.holes, Format.Time(left))
			subLabel.Text = playing and info.theme or "👀 관전 중 · 다음 경기에 참가해요"
		elseif p == "HoleResult" then
			phaseLabel.Text = string.format("%d번 홀 끝!", info.hole)
			subLabel.Text = "다음 홀 준비 중..."
		else
			phaseLabel.Text = "🏁 경기 종료"
			subLabel.Text = "보상을 받았어요!"
		end
	end
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

