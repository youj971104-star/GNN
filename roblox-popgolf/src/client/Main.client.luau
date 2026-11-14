-- ⛳ 펑! 골프 파티 클라이언트 UI (2대2 팀 배틀 골프)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local UIKit = require(script.Parent.UIKit)
local Shot = require(script.Parent.Shot)
local ClubFX = require(script.Parent.ClubFX)

local C = UIKit.C
local new, label, button = UIKit.new, UIKit.label, UIKit.button

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local Action = remotes:WaitForChild("Action")

-- 골프채를 1/2 키로 빼지 못하게 가방(백팩) 줄은 숨김
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local state
local info = { phase = "Waiting", hole = 0, holes = 3, timeLeft = 0, teams = {}, golf = { teams = {}, players = {} }, theme = "", need = 1 }
local endsAt = 0
ClubFX.Start()
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
-- HUD: 위쪽 팀 점수판
----------------------------------------------------------------------
local hud = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(440, 96),
	BackgroundColor3 = C.bg,
	BackgroundTransparency = 0.15,
	Parent = screen.gui,
}, { UIKit.corner(14), UIKit.stroke(Color3.new(1, 1, 1), 2) })
local phaseLabel = label({ Parent = hud, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 26), TextColor3 = C.sub, Text = "대기 중..." })
local scoreLabel = label({ Parent = hud, Position = UDim2.fromOffset(10, 30), Size = UDim2.new(1, -20, 0, 36), Font = UIKit.FONT_TITLE, Text = "" })
local teamLabel = label({ Parent = hud, Position = UDim2.fromOffset(10, 68), Size = UDim2.new(1, -20, 0, 22), Text = "" })

local wallet = label({
	Position = UDim2.fromOffset(12, 12),
	Size = UDim2.fromOffset(300, 28),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = C.gold,
	TextStrokeTransparency = 0.3,
	Parent = screen.gui,
})

-- 오른쪽: 선수 목록 (팀, 아이템, 방패)
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

----------------------------------------------------------------------
-- 아래쪽: 파워 게이지, 안내, 버튼
----------------------------------------------------------------------
local powerBack = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -110),
	Size = UDim2.fromOffset(380, 28),
	BackgroundColor3 = Color3.fromRGB(20, 15, 40),
	Visible = false,
	Parent = screen.gui,
}, { UIKit.corner(14), UIKit.stroke(Color3.new(1, 1, 1), 2) })
local powerFill = new("Frame", { Parent = powerBack, Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.green }, { UIKit.corner(14) })
local powerText = label({ Parent = powerBack, Size = UDim2.fromScale(1, 1), ZIndex = 2 })

local hint = label({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -146),
	Size = UDim2.fromOffset(560, 26),
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeTransparency = 0.3,
	Parent = screen.gui,
})

local function roundButton(text, color, position, size)
	return new("TextButton", {
		AnchorPoint = Vector2.new(1, 1),
		Position = position,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		Text = text,
		Font = UIKit.FONT_TITLE,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Visible = false,
		Parent = screen.gui,
	}, { UIKit.corner(size / 2), UIKit.stroke(Color3.new(1, 1, 1), 3), new("UIPadding", { PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 16), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }) })
end

local shotButton = roundButton("🏌️\n꾹 눌렀다\n떼기", C.green, UDim2.new(1, -20, 1, -30), 120)
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
	Position = UDim2.new(1, -20, 1, -160),
	Size = UDim2.fromOffset(170, 52),
	BackgroundColor3 = Color3.fromRGB(255, 170, 60),
	Visible = false,
	Parent = screen.gui,
}, Shot.UseItem)

Shot.Start({
	setPower = function(p, visible)
		powerBack.Visible = visible
		powerFill.Size = UDim2.fromScale(p, 1)
		powerFill.BackgroundColor3 = Color3.fromHSV(0.33 - p * 0.33, 0.85, 0.95)
		powerText.Text = math.floor(p * 100) .. "%"
	end,
	setMode = function(playing, ballNear)
		shotButton.Visible = playing
		shotButton.BackgroundColor3 = ballNear and C.green or Color3.fromRGB(255, 130, 80)
		if not playing then
			hint.Text = ""
		elseif player:GetAttribute("Stunned") then
			hint.Text = "💫 넘어졌어요! 잠깐만..."
		elseif ballNear then
			hint.Text = "⛳ 공이 사정권! 꾹 눌러 힘을 모았다가 떼면 카메라 방향으로 날아가요"
		else
			hint.Text = "🏃 우리 공을 쫓아가요 · 상대가 가까우면 휘둘러서 넘어뜨리기 · 상대 공을 쳐 내는 것도 작전! · E: 아이템"
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
		UIKit.label({
			Parent = parent,
			LayoutOrder = order + i,
			Size = UDim2.new(1, -8, 0, 40),
			TextScaled = false,
			TextSize = 14,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = rarityColor(row.rarity),
			Text = string.format("%s %s%%  (각 %.2f%%)\n%s", Config.RarityById[row.rarity].name, tostring(row.percent), row.each, table.concat(names, ", ")),
		})
	end
end

screen.menu("Gacha", "🎰\n캡슐", Color3.fromRGB(255, 120, 180), "🎰 캡슐 뽑기 (골프채 꾸미기)", function(parent)
	UIKit.paragraph(parent, "캡슐에서는 골프채 꾸미기만 나와요. 실력에는 영향이 없어요! 중복은 🧩 조각이 되고, 조각으로 원하는 골프채를 직접 살 수 있어요.", 1, 44)
	UIKit.row(parent, 2, Config.Capsules.Basic.name, "🪙 " .. Config.Capsules.Basic.cost .. " · 게임에서 번 코인으로만", "1회 뽑기",
		state.coins >= Config.Capsules.Basic.cost and C.green or C.gray, function()
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

-- 스킨 연출 요약 아이콘 (✨ 입자 · 🔮 빛구슬 · ⭕ 고리 · 🌈 무지개 · 💥 충격파)
local function fxIcons(skinId)
	local fx = Config.GetFx(skinId)
	local icons = {}
	if fx.aura then
		table.insert(icons, fx.texture == "fire" and "🔥" or (fx.texture == "smoke" and "❄️" or "✨"))
	end
	if fx.orbit then
		table.insert(icons, "🔮" .. fx.orbit.count)
	end
	if fx.ring then
		table.insert(icons, "⭕")
	end
	if fx.rainbow then
		table.insert(icons, "🌈")
	end
	if fx.burst.shock then
		table.insert(icons, "💥")
	end
	return table.concat(icons, " ")
end

----------------------------------------------------------------------
-- 메뉴: 내 골프채 (컬렉션 / 조각 상점)
----------------------------------------------------------------------
screen.menu("Clubs", "🏌️\n골프채", Color3.fromRGB(90, 160, 255), "🏌️ 내 골프채 컬렉션", function(parent)
	local owned = 0
	for _ in pairs(state.skins) do
		owned += 1
	end
	UIKit.paragraph(parent, string.format("모은 골프채 %d / %d · 🧩 조각 %d개", owned, #Config.SkinOrder, state.shards), 1, 26)
	local grid = new("Frame", { Parent = parent, LayoutOrder = 2, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, {
		new("UIGridLayout", { CellSize = UDim2.fromOffset(120, 170), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, id in ipairs(Config.SkinOrder) do
		local skin = Config.Skins[id]
		local has = state.skins[id] == true
		local equipped = state.equipped == id
		local card = new("Frame", { Parent = grid, LayoutOrder = i, BackgroundColor3 = equipped and C.cardHi or C.card }, { UIKit.corner(10), UIKit.stroke(rarityColor(skin.rarity), equipped and 3 or 1.5) })
		-- 빙글빙글 도는 3D 미리보기 (없는 건 흐리게)
		ClubFX.Preview(card, id, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(96, 64), ImageTransparency = has and 0 or 0.55 })
		ClubFX.Shine(card:FindFirstChildOfClass("UIStroke"), skin.rarity)
		label({ Parent = card, Position = UDim2.fromOffset(4, 68), Size = UDim2.new(1, -8, 0, 22), Text = skin.name })
		label({ Parent = card, Position = UDim2.fromOffset(4, 90), Size = UDim2.new(1, -8, 0, 16), TextColor3 = rarityColor(skin.rarity), Text = Config.RarityById[skin.rarity].name })
		label({ Parent = card, Position = UDim2.fromOffset(4, 106), Size = UDim2.new(1, -8, 0, 18), Text = fxIcons(id) })
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
-- 메뉴: 상점 / 기록 / 조작법
----------------------------------------------------------------------
screen.menu("Shop", "💎\n상점", Color3.fromRGB(230, 80, 170), "💎 상점", function(parent)
	local hidden = {}
	if state.restricted then
		hidden = { Gems110 = true, Gems500 = true, Gems1300 = true, Starter = true }
	end
	if state.starterBought then
		hidden.Starter = true
	end
	UIKit.shop(parent, Config, { "VIP", "AimPlus" }, { "Starter", "Gems110", "Gems500", "Gems1300" }, state.passes, {}, hidden)
	UIKit.paragraph(parent, "🪙 코인은 판매하지 않아요. 경기에서만 얻을 수 있어요!", 50, 26)
end)

screen.menu("Stats", "📊\n기록", Color3.fromRGB(60, 190, 120), "📊 내 기록", function(parent)
	local s = state.stats
	local rows = {
		{ "🏆 승리", s.wins },
		{ "🎮 경기 수", s.matches },
		{ "⛳ 이긴 홀", s.holesWon },
		{ "⛳ 우리 공 넣은 횟수", s.sinks or 0 },
		{ "💫 넘어뜨린 횟수", s.knockouts },
		{ "🎰 뽑은 캡슐", s.pulls },
	}
	for i, r in ipairs(rows) do
		local row = new("Frame", { Parent = parent, LayoutOrder = i, Size = UDim2.new(1, -8, 0, 42), BackgroundColor3 = C.card }, { UIKit.corner(10) })
		label({ Parent = row, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(0.6, 0, 1, -12), TextXAlignment = Enum.TextXAlignment.Left, Text = r[1] })
		label({ Parent = row, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6), Size = UDim2.new(0.35, 0, 1, -12), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.gold, Text = tostring(r[2]) })
	end
end)

screen.menu("Help", "❔\n방법", Color3.fromRGB(120, 120, 150), "❔ 하는 방법", function(parent)
	local lines = {
		"🔴🔵 2대2 팀전! 팀마다 공이 하나. 타수는 없어요 — 우리 공을 먼저 홀컵에 넣는 팀이 그 홀을 이겨요.",
		"🏌️ 마우스 왼쪽(모바일은 버튼)을 꾹 누르면 골프채가 뒤로 올라가며 힘이 모이고, 떼면 휘둘러요. 힘 게이지가 왔다 갔다 하니 타이밍!",
		"💥 휘두르면 앞에 있는 건 다 맞아요: 공은 카메라 방향으로 높이 날아가고(그린 위에선 굴러가는 퍼팅), 상대 선수는 날아가 넘어져요.",
		"😈 상대 팀 공도 칠 수 있어요! 홀컵에서 멀리 쳐 내 버리세요. 대신 잘못 쳐서 넣어 주면 상대 팀 득점!",
		"👫 한 명은 우리 공을 몰고 가고, 한 명은 상대를 넘어뜨리거나 상대 공을 쳐 내는 작전이 좋아요.",
		"❓ 페어웨이 위 상자 = 아이템! E 키로 사용: 💣 물풍선 · 🧊 얼음(상대 공 정지) · 👟 대시 · 🛡️ 방패 · 🌬️ 돌풍",
		"🌳 러프(진한 풀)·🏖️ 벙커(모래)에선 공이 잘 안 굴러가요. 💦 연못에 빠지면 마지막으로 멈췄던 자리로!",
		"⏱️ 시간이 끝나면 홀컵에 우리 공이 더 가까운 팀 승리. 홀 3개 중 더 많이 이긴 팀 우승!",
		"💡 Shift 키(마우스 고정)를 켜면 조준이 편해요.",
	}
	for i, l in ipairs(lines) do
		UIKit.paragraph(parent, l, i, 48)
	end
end)

----------------------------------------------------------------------
-- 뽑기 결과 연출
----------------------------------------------------------------------
local resultOverlay = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, Visible = false, ZIndex = 30, Parent = screen.gui })
local resultGrid = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.46),
	Size = UDim2.fromOffset(620, 330),
	BackgroundTransparency = 1,
	ZIndex = 31,
	Parent = resultOverlay,
}, { new("UIGridLayout", { CellSize = UDim2.fromOffset(112, 150), CellPadding = UDim2.fromOffset(10, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }) })
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
	-- 전설 이상이 나오면 화면이 번쩍!
	local best = 1
	for _, r in ipairs(results) do
		best = math.max(best, Config.RarityById[r.rarity].index)
	end
	if best >= 4 then
		local flashColor = best >= 5 and Color3.fromRGB(255, 120, 200) or Color3.fromRGB(255, 200, 80)
		resultOverlay.BackgroundColor3 = flashColor
		resultOverlay.BackgroundTransparency = 0
		game:GetService("TweenService"):Create(resultOverlay, TweenInfo.new(0.8), { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35 }):Play()
		screen.banner(best >= 5 and "🌈 신화 등장!!" or "✨ 전설 등장!", 2.5, flashColor)
	else
		resultOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
		resultOverlay.BackgroundTransparency = 0.35
	end
	for i, r in ipairs(results) do
		local skin = Config.Skins[r.skin]
		local card = new("Frame", { Parent = resultGrid, LayoutOrder = i, BackgroundColor3 = C.card, ZIndex = 32, Visible = false }, { UIKit.corner(12), UIKit.stroke(rarityColor(r.rarity), 3) })
		ClubFX.Preview(card, r.skin, { ZIndex = 33, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(96, 64) })
		ClubFX.Shine(card:FindFirstChildOfClass("UIStroke"), r.rarity)
		label({ Parent = card, ZIndex = 33, Position = UDim2.fromOffset(4, 70), Size = UDim2.new(1, -8, 0, 22), Text = skin.name })
		label({ Parent = card, ZIndex = 33, Position = UDim2.fromOffset(4, 92), Size = UDim2.new(1, -8, 0, 18), TextColor3 = rarityColor(r.rarity), Text = Config.RarityById[r.rarity].name })
		label({ Parent = card, ZIndex = 33, Position = UDim2.fromOffset(4, 110), Size = UDim2.new(1, -8, 0, 16), Text = fxIcons(r.skin) })
		label({ Parent = card, ZIndex = 33, Position = UDim2.fromOffset(4, 128), Size = UDim2.new(1, -8, 0, 18), TextColor3 = r.new and C.gold or C.sub, Text = r.new and "✨ NEW!" or ("🧩 +" .. r.shards) })
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
	board.Visible = inMatch and #info.golf.players > 0
	local order = 0
	for index, team in ipairs(Config.Teams) do
		local t = info.golf.teams[index]
		if t then
			order += 1
			local status = t.sunk and "✅ 홀인!" or string.format("홀컵까지 %d%s", t.dist, t.onGreen and " · 🟢 그린 위" or "")
			label({ Parent = board, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 22), Font = UIKit.FONT_TITLE, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = team.color, Text = team.name .. (t.frozen and " 🧊" or "") })
			order += 1
			label({ Parent = board, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.sub, Text = status })
			for _, p in ipairs(info.golf.players) do
				if p.team == index then
					order += 1
					local extra = (p.item and (" " .. Config.Items[p.item].name) or "") .. (p.shield and " 🛡️" or "")
					label({ Parent = board, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = p.userId == player.UserId and C.gold or C.text, Text = "  · " .. p.name .. extra })
				end
			end
		end
	end
end

remotes:WaitForChild("Match").OnClientEvent:Connect(function(m)
	info = m
	endsAt = os.clock() + m.timeLeft
	-- 위쪽 점수
	local red, blue = m.teams[1], m.teams[2]
	if red and blue then
		scoreLabel.Text = string.format("🔴 %d  :  %d 🔵", red.holeWins, blue.holeWins)
	elseif red then
		scoreLabel.Text = "🔴 연습 경기"
	else
		scoreLabel.Text = "⛳ 펑! 골프 파티"
	end
	local myTeam = player:GetAttribute("Team")
	if myTeam then
		teamLabel.Text = "나는 " .. Config.Teams[myTeam].name
		teamLabel.TextColor3 = Config.Teams[myTeam].color
	else
		teamLabel.Text = (m.phase == "Waiting" or m.phase == "Intermission") and "" or "👀 관전 중 · 다음 경기에 참가해요"
		teamLabel.TextColor3 = C.sub
	end
	-- 내 아이템
	local myItem
	for _, p in ipairs(m.golf.players) do
		if p.userId == player.UserId then
			myItem = p.item
		end
	end
	itemButton.Visible = m.phase == "Playing" and myItem ~= nil
	if myItem then
		itemButton.Text = "E  " .. Config.Items[myItem].name
	end
	Shot.Update(m, state and state.passes and state.passes.AimPlus == true)
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

task.spawn(function()
	while true do
		task.wait(0.25)
		local left = math.max(0, endsAt - os.clock())
		local p = info.phase
		if p == "Waiting" then
			phaseLabel.Text = "⏳ 플레이어를 기다리는 중 (2대2는 4명)"
		elseif p == "Intermission" then
			phaseLabel.Text = "⛳ 곧 경기 시작 " .. math.ceil(left) .. " · 팀은 무작위로 나뉘어요"
		elseif p == "Countdown" then
			phaseLabel.Text = string.format("%d번 홀 · %s · 준비 %d", info.hole, info.theme, math.ceil(left))
		elseif p == "Playing" then
			phaseLabel.Text = string.format("⛳ %d / %d 홀 · %s · ⏱ %s", info.hole, info.holes, info.theme, Format.Time(left))
		elseif p == "HoleResult" then
			phaseLabel.Text = string.format("%d번 홀 끝! 다음 홀 준비 중...", info.hole)
		else
			phaseLabel.Text = "🏁 경기 종료 · 보상을 받았어요!"
		end
	end
end)

TextChatService.OnIncomingMessage = function(message)
	local props = Instance.new("TextChatMessageProperties")
	local source = message.TextSource
	local sender = source and Players:GetPlayerByUserId(source.UserId)
	if sender then
		local team = sender:GetAttribute("Team")
		local prefix = message.PrefixText
		if team then
			local c = Config.Teams[team].color
			prefix = string.format("<font color='#%02X%02X%02X'>[%s]</font> ", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255), team == 1 and "레드" or "블루") .. prefix
		end
		if sender:GetAttribute("VIP") then
			prefix = "<font color='#FFD75A'>[VIP]</font> " .. prefix
		end
		props.PrefixText = prefix
	end
	return props
end
