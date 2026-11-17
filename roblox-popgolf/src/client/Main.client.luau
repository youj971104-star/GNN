-- ⛳ 팝골프 클라이언트 UI (2대2 팀 배틀 골프)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local UIKit = require(script.Parent.UIKit)
local Shot = require(script.Parent.Shot)
local ClubFX = require(script.Parent.ClubFX)
local VFX = require(script.Parent.VFX)
local CameraView = require(script.Parent.CameraView)
CameraView.Start()

local C = UIKit.C
local new, label, button = UIKit.new, UIKit.label, UIKit.button

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local Action = remotes:WaitForChild("Action")

-- 골프채를 1/2 키로 빼지 못하게 가방(백팩) 줄은 숨김
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
-- 휴대폰·태블릿 (터치만 있고 키보드 없음)
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local state
local info = { phase = "Waiting", hole = 0, holes = 3, timeLeft = 0, teams = {}, golf = { teams = {}, players = {} }, theme = "", need = 1 }
local endsAt = 0
ClubFX.Start()
VFX.Start()
local screen = UIKit.Screen("PopGolfUI")
-- 빌드 표시 (테스트할 때 최신 코드가 들어갔는지 확인용, 왼쪽 아래 작은 글씨)
do
	local tag = Instance.new("TextLabel")
	tag.Name = "BuildTag"
	tag.BackgroundTransparency = 1
	tag.AnchorPoint = Vector2.new(0, 1)
	tag.Position = UDim2.new(0, 6, 1, -2)
	tag.Size = UDim2.fromOffset(120, 14)
	tag.TextXAlignment = Enum.TextXAlignment.Left
	tag.TextSize = 11
	tag.TextColor3 = Color3.new(1, 1, 1)
	tag.TextTransparency = 0.4
	tag.Text = "build " .. tostring(Config.Build)
	tag.Parent = screen.gui
end
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
-- HUD: 위쪽 점수판  [ 레드 n ] [ 타이머 ] [ n 블루 ]
----------------------------------------------------------------------
local NAVY = Color3.fromRGB(18, 22, 48)
local CYAN = Color3.fromRGB(60, 230, 255)

-- 그림 아이콘 (Config.Icons 에 ID 가 있으면 그림, 없으면 이모지)
local function iconInto(parent, key, emoji, props)
	local id = Config.Icons[key]
	local obj
	if id and id ~= 0 then
		obj = new("ImageLabel", { BackgroundTransparency = 1, Image = "rbxassetid://" .. id, ScaleType = Enum.ScaleType.Fit })
	else
		obj = label({ Text = emoji })
	end
	for k, v in pairs(props or {}) do
		obj[k] = v
	end
	obj.Parent = parent
	return obj
end

-- HUD 디자인 이미지 (Config.UIImages). ID 가 있으면 그 이미지를 판으로 깔고 글자·막대만 위에 얹음
local function uiImage(key)
	local id = Config.UIImages and Config.UIImages[key]
	return id and id ~= 0 and ("rbxassetid://" .. id) or nil
end
local function skinImage(parent, key, z)
	return new("ImageLabel", {
		Name = key,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = uiImage(key),
		ScaleType = Enum.ScaleType.Stretch,
		ZIndex = z or 1,
		Parent = parent,
	})
end
-- 판 이미지 안의 칸 위치 (이미지 크기에 대한 비율, 디자인 PNG에서 잰 값)
local function rect(x0, y0, x1, y1)
	return UDim2.fromScale(x0, y0), UDim2.fromScale(x1 - x0, y1 - y0)
end

-- 위쪽 HUD는 로블록스 상단 버튼 줄(메뉴·채팅 버튼 높이)까지 끌어올림: 화면 가운데·오른쪽은 비어 있음
local TOP = -GuiService:GetGuiInset().Y + 6
local hud = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, TOP),
	Size = isMobile and UDim2.fromOffset(230, 80) or UDim2.fromOffset(340, 92),
	BackgroundTransparency = 1,
	Parent = screen.gui,
})
local SCORE_H = isMobile and 40 or 48
local scoreBar = new("Frame", { Parent = hud, Size = UDim2.new(1, 0, 0, SCORE_H), BackgroundTransparency = 1 })
local function teamBlock(xScale, anchorX, team, title)
	local f = new("Frame", {
		Parent = scoreBar,
		AnchorPoint = Vector2.new(anchorX, 0),
		Position = UDim2.fromScale(xScale, 0),
		Size = UDim2.new(0.3, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
	}, { UIKit.corner(12), UIKit.stroke(Color3.new(1, 1, 1), 2) })
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(team.color:Lerp(Color3.new(1, 1, 1), 0.2), team.color:Lerp(Color3.new(0, 0, 0), 0.35)), Parent = f })
	label({ Parent = f, Position = UDim2.fromScale(0, 0.04), Size = UDim2.fromScale(1, 0.3), Text = title, TextColor3 = Color3.new(1, 1, 1) })
	return label({ Parent = f, Position = UDim2.fromScale(0, 0.3), Size = UDim2.fromScale(1, 0.7), Font = UIKit.FONT_TITLE, Text = "0", TextStrokeTransparency = 0.3 }), f
end
local redNum, redFrame = teamBlock(0, 0, Config.Teams[1], "레드")
local blueNum, blueFrame = teamBlock(1, 1, Config.Teams[2], "블루")
local timerBox = new("Frame", {
	Parent = scoreBar,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.new(0.38, 0, 1, 0),
	BackgroundColor3 = NAVY,
}, { UIKit.corner(12), UIKit.stroke(CYAN, 2) })
local timerLabel = label({ Parent = timerBox, Position = UDim2.fromScale(0, 0.02), Size = UDim2.fromScale(1, 0.66), Font = UIKit.FONT_TITLE, Text = "--:--", TextColor3 = Color3.new(1, 1, 1) })
local scoreLabel = label({ Parent = timerBox, Position = UDim2.fromScale(0, 0.66), Size = UDim2.fromScale(1, 0.3), TextColor3 = CYAN, Text = "" }) -- 모드·홀 표시
-- 디자인: 깃발 알약 (왼쪽 = 모드·홀, 가운데 세로줄, 오른쪽 = 남은 시간). 알약은 가로:세로 = 4:1
if uiImage("HoleStatusPill") then
	local pillW = SCORE_H * 4
	local teamW = math.floor(SCORE_H * 1.35)
	hud.Size = UDim2.fromOffset(pillW + teamW * 2 + 8, hud.Size.Y.Offset)
	redFrame.Size = UDim2.new(0, teamW, 1, 0)
	blueFrame.Size = UDim2.new(0, teamW, 1, 0)
	timerBox.Size = UDim2.new(0, pillW, 1, 0)
	timerBox.BackgroundTransparency = 1
	timerBox:FindFirstChildOfClass("UIStroke").Enabled = false
	skinImage(timerBox, "HoleStatusPill", 1)
	timerLabel.Position, timerLabel.Size = rect(0.53, 0.2, 0.93, 0.8)
	timerLabel.ZIndex = 2
	scoreLabel.Position, scoreLabel.Size = rect(0.21, 0.26, 0.47, 0.74)
	scoreLabel.TextColor3 = Color3.new(1, 1, 1)
	scoreLabel.ZIndex = 2
end
local phaseLabel = label({ Parent = hud, Position = UDim2.fromOffset(0, SCORE_H + 2), Size = UDim2.new(1, 0, 0, isMobile and 16 or 20), TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.3, Text = "대기 중..." })
local teamLabel = label({ Parent = hud, Position = UDim2.fromOffset(0, SCORE_H + (isMobile and 18 or 22)), Size = UDim2.new(1, 0, 0, isMobile and 15 or 18), TextStrokeTransparency = 0.3, Text = "" })

-- 오른쪽 위: 재화 알약
local walletPill = new("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, TOP + 2),
	Size = UDim2.fromOffset(isMobile and 180 or 260, isMobile and 28 or 32),
	BackgroundColor3 = NAVY,
	BackgroundTransparency = 0.1,
	Parent = screen.gui,
}, { UIKit.corner(14), UIKit.stroke(Color3.fromRGB(255, 200, 70), 2) })
local wallet = label({
	Parent = walletPill,
	Position = UDim2.fromOffset(10, 4),
	Size = UDim2.new(1, -20, 1, -8),
	TextColor3 = Color3.fromRGB(255, 225, 140),
	Text = "",
})

-- 오른쪽: 선수 목록 (팀, 아이템, 방패)
local board = new("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, TOP + (isMobile and 36 or 42)),
	Size = UDim2.fromOffset(isMobile and 150 or 210, 0),
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

-- 디자인: 실시간 현황판 (머리 줄 + 빨강·파랑·빨강·파랑 4줄)
-- 1줄 레드 팀 공, 2줄 블루 팀 공, 3줄 레드 선수, 4줄 블루 선수
local rank
if uiImage("LiveMatchRankBoard") then
	local w = isMobile and 150 or 210
	local frame = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = board.Position,
		Size = UDim2.fromOffset(w, math.floor(w / 0.913)),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen.gui,
	})
	skinImage(frame, "LiveMatchRankBoard", 1)
	rank = { frame = frame, rows = {} }
	local hp, hs = rect(0.09, 0.07, 0.91, 0.15)
	rank.header = label({ Parent = frame, Position = hp, Size = hs, Font = UIKit.FONT_TITLE, Text = "실시간 현황", TextColor3 = Color3.new(1, 1, 1), ZIndex = 2 })
	for i, y in ipairs({ 0.207, 0.389, 0.572, 0.754 }) do
		local pos, size = rect(0.09, y + 0.025, 0.91, y + 0.123)
		rank.rows[i] = label({ Parent = frame, Position = pos, Size = size, Text = "", TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2 })
	end
end

----------------------------------------------------------------------
-- 아래쪽: 파워 게이지, 안내, 버튼
----------------------------------------------------------------------
local powerBack = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -150),
	Size = UDim2.fromOffset(380, 28),
	BackgroundColor3 = Color3.fromRGB(20, 15, 40),
	Visible = false,
	Parent = screen.gui,
}, { UIKit.corner(14), UIKit.stroke(Color3.new(1, 1, 1), 2) })
local powerFill = new("Frame", { Parent = powerBack, Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.green }, { UIKit.corner(14) })
local powerText = label({ Parent = powerBack, Size = UDim2.fromScale(1, 1), ZIndex = 2 })

local hint = label({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -186),
	Size = isMobile and UDim2.new(0.6, 0, 0, 22) or UDim2.fromOffset(560, 26),
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeTransparency = 0.3,
	Parent = screen.gui,
})
-- 안내 문구: 내용이 바뀔 때만 잠깐 보였다가(2초) 스르륵 사라짐. 같은 문구가 계속 들어와도 다시 띄우지 않음
local HINT_SECONDS = 2
local hintToken = 0
local function setHint(text)
	if text == hint:GetAttribute("Last") then
		return
	end
	hint:SetAttribute("Last", text)
	hintToken += 1
	local my = hintToken
	hint.Text = text
	hint.TextTransparency = 0
	hint.TextStrokeTransparency = 0.3
	if text == "" then
		return
	end
	task.delay(HINT_SECONDS, function()
		if hintToken ~= my then
			return
		end
		game:GetService("TweenService"):Create(hint, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end

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

local shotButton = roundButton("🏌️\n꾹 눌렀다\n떼기", C.green, UDim2.new(1, -20, 1, -30), 100)
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

-- 점프 버튼 (휴대폰: 샷 버튼 바로 옆. 로블록스 기본 점프 버튼은 숨김)
local jumpButton = roundButton("⬆\n점프", Color3.fromRGB(80, 150, 255), UDim2.new(1, -20, 1, -30), 58)
jumpButton:FindFirstChildOfClass("UIPadding").PaddingTop = UDim.new(0, 8)
jumpButton:FindFirstChildOfClass("UIPadding").PaddingBottom = UDim.new(0, 8)
jumpButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		-- humanoid.Jump = true 는 로블록스 기본 조작 모듈이 매 프레임 덮어써서(휴대폰) 안 먹힘 → 상태를 직접 '점프'로 바꿈
		if h and not player:GetAttribute("Stunned") and h.FloorMaterial ~= Enum.Material.Air and h:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
			h:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end
end)

-- 휴대폰: 오른쪽 아래 엄지 자리에 샷 버튼, 그 둘레에 점프·대시·스킬·궁극기 (작게)
-- 기준: 오른쪽 아래 모서리에서 떨어진 거리(가운데 기준). SHOT = 샷 버튼 크기
local SHOT, SMALL, JUMP = 84, 50, 56
local function aroundShot(gui, size, dx, dy)
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Size = UDim2.fromOffset(size, size)
	gui.Position = UDim2.new(1, -dx, 1, -dy)
end
if isMobile then
	aroundShot(shotButton, SHOT, 62, 58)
	shotButton:FindFirstChildOfClass("UIPadding").PaddingTop = UDim.new(0, 10)
	shotButton:FindFirstChildOfClass("UIPadding").PaddingBottom = UDim.new(0, 10)
	aroundShot(jumpButton, JUMP, 156, 40)
	itemButton.AnchorPoint = Vector2.new(1, 1)
	itemButton.Position = UDim2.new(1, -198, 1, -16)
	itemButton.Size = UDim2.fromOffset(110, 36)
	powerBack.Position = UDim2.new(0.5, 0, 1, -34)
	powerBack.Size = UDim2.new(0.34, 0, 0, 16)
	hint.Position = UDim2.new(0.5, 0, 1, -54)
	hint.Size = UDim2.new(0.5, 0, 0, 16)
	-- 로블록스 기본 점프 버튼 숨기기 (우리 점프 버튼과 자리가 겹침)
	task.spawn(function()
		local pg = player:WaitForChild("PlayerGui")
		while true do
			local touch = pg:FindFirstChild("TouchGui")
			local frame = touch and touch:FindFirstChild("TouchControlFrame")
			local jb = frame and frame:FindFirstChild("JumpButton")
			if jb and jb.Visible then
				jb.Visible = false
			end
			task.wait(1)
		end
	end)
else
	jumpButton.Parent = nil -- PC 는 스페이스바
end

-- 디자인: 스윙 힘 게이지 (파랑→초록→노랑→빨강 막대 + 하얀 칸). 가로:세로 = 4:1
-- 아직 안 찬 부분은 어둡게 덮고, 지금 힘 위치에 하얀 세로선이 움직임
local powerSkin
if uiImage("SwingPowerGauge") then
	powerBack.BackgroundTransparency = 1
	powerBack:FindFirstChildOfClass("UIStroke").Enabled = false
	-- 휴대폰: 맨 아래 가운데 / PC: 능력 버튼 줄 바로 위 (안내 문구와 안 겹치게)
	powerBack.Size = isMobile and UDim2.fromOffset(190, 47) or UDim2.fromOffset(300, 75)
	powerBack.Position = isMobile and UDim2.new(0.5, 0, 1, -10) or UDim2.new(0.5, 0, 1, -100)
	powerFill.Visible = false
	skinImage(powerBack, "SwingPowerGauge", 1)
	local X0, X1, Y0, Y1 = 0.054, 0.947, 0.305, 0.695 -- 이미지 안 색 막대 칸
	local cover = new("Frame", { Parent = powerBack, BackgroundColor3 = Color3.fromRGB(20, 24, 40), BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 2 }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	-- 하얀 칸 = 퍼펙트 구간 (Config.Club.perfect). 세로선이 칸 안에 들어오면 칸이 금색으로 빛남
	local PZ = Config.Club.perfect
	local zx0, zx1 = X0 + (X1 - X0) * PZ[1], X0 + (X1 - X0) * PZ[2]
	local zone = new("Frame", { Parent = powerBack, BackgroundColor3 = Color3.fromRGB(255, 225, 90), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3 })
	zone.Position, zone.Size = rect(zx0, 0.25, zx1, 0.75)
	local zoneStroke = new("UIStroke", { Parent = zone, Color = Color3.fromRGB(255, 225, 90), Thickness = 3, Transparency = 1 })
	local perfectTag = label({ Parent = powerBack, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale((zx0 + zx1) / 2, 0.06), Size = UDim2.fromScale(0.3, 0.3), Font = UIKit.FONT_TITLE, Text = "PERFECT", TextColor3 = Color3.fromRGB(255, 230, 90), TextStrokeTransparency = 0.2, Visible = false, ZIndex = 4 })
	local marker = new("Frame", { Parent = powerBack, AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 3 })
	powerText.Position, powerText.Size = rect(X0, Y0 + 0.05, X1, Y1 - 0.05)
	powerText.ZIndex = 4
	powerText.TextStrokeTransparency = 0.2
	powerSkin = function(p)
		p = math.clamp(p, 0, 1)
		local x = X0 + (X1 - X0) * p
		cover.Position, cover.Size = rect(x, Y0, X1, Y1)
		cover.Visible = p < 0.999
		marker.Position = UDim2.fromScale(x, Y0 - 0.06)
		marker.Size = UDim2.new(0, 3, Y1 - Y0 + 0.12, 0)
		local inZone = p >= PZ[1] and p <= PZ[2]
		zone.BackgroundTransparency = inZone and 0.55 or 1
		zoneStroke.Transparency = inZone and 0 or 1
		perfectTag.Visible = inZone
	end
end

-- 디자인: 샷 버튼 (빨간 원 + 별). 공이 원 안에 없으면 살짝 어둡게
local shotSkin
if uiImage("ClubAttackButton") then
	shotButton.BackgroundTransparency = 1
	shotButton.Text = ""
	shotButton:FindFirstChildOfClass("UIStroke").Enabled = false
	shotButton:FindFirstChildOfClass("UIPadding"):Destroy()
	shotSkin = skinImage(shotButton, "ClubAttackButton", 1)
end

----------------------------------------------------------------------
-- 경기 중에는 메뉴를 접어서 조작에 집중 (☰ 버튼으로 필요할 때만 열기)
----------------------------------------------------------------------
local menuToggle = button({
	Position = UDim2.fromOffset(12, 46),
	Size = UDim2.fromOffset(isMobile and 64 or 92, 40),
	BackgroundColor3 = Color3.fromRGB(70, 70, 100),
	Text = "📋 메뉴",
	Visible = false,
	Parent = screen.gui,
}, function()
	local show = not screen.menuFrame.Visible
	screen.menuFrame.Visible = show
	if not show then
		screen.open(nil)
	end
end)

----------------------------------------------------------------------
-- 능력 버튼: 대시(Q) · 스킬(E) · 궁극기(R) — 쿨다운이 버튼 위에 덮였다 줄어듦
----------------------------------------------------------------------
local abilityButtons = {}
local function abilityButton(key, icon, onPress, name, iconKey)
	local size = isMobile and SMALL or 58
	local b = new("TextButton", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = NAVY,
		Text = "",
		AutoButtonColor = true,
		Visible = false,
		Parent = screen.gui,
	}, { UIKit.corner(size / 2), UIKit.stroke(CYAN, 2) })
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(70, 80, 150), Color3.fromRGB(20, 22, 50)), Parent = b })
	local iconLabel = iconInto(b, iconKey or key, icon, { Size = UDim2.fromScale(0.66, 0.66), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), ZIndex = 3 })
	-- 키 표시 칩 (PC)
	local keyLabel = label({ Parent = b, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, 2), Size = UDim2.fromOffset(22, 18), Text = isMobile and "" or key, BackgroundTransparency = isMobile and 1 or 0, BackgroundColor3 = Color3.fromRGB(240, 240, 250), TextColor3 = NAVY, ZIndex = 5 })
	if not isMobile then
		new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = keyLabel })
		-- 이름표 (버튼 위)
		label({ Parent = b, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -2), Size = UDim2.fromOffset(90, 18), Text = name or "", TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.3, ZIndex = 5 })
	end
	-- 쿨다운 덮개 (아래에서 위로 차 있는 어두운 막)
	local clip = new("Frame", { Parent = b, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 2 }, { UIKit.corner(size / 2) })
	local cover = new("Frame", { Parent = clip, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, ZIndex = 2 })
	local cdText = label({ Parent = b, Size = UDim2.fromScale(1, 1), Text = "", Font = UIKit.FONT_TITLE, ZIndex = 4, TextStrokeTransparency = 0.2 })
	b.Activated:Connect(onPress)
	local entry = { button = b, icon = iconLabel, key = keyLabel, cover = cover, cdText = cdText }
	table.insert(abilityButtons, entry)
	return entry
end

local dashBtn = abilityButton("Q", "💨", Shot.Dash, "대시", "Dash")
local skillBtn = abilityButton("E", "💥", Shot.Skill, "스킬", "Skill_")
local ultBtn = abilityButton("R", "☄️", Shot.Ultimate, "궁극기", "Ultimate")

if isMobile then
	-- 샷 버튼 둘레 (왼쪽 위 → 위): 대시 · 스킬 · 궁극기
	aroundShot(dashBtn.button, SMALL, 146, 110)
	aroundShot(skillBtn.button, SMALL, 100, 146)
	aroundShot(ultBtn.button, SMALL, 38, 156)
else
	-- PC: 화면 아래 가운데 한 줄
	for i, e in ipairs(abilityButtons) do
		e.button.AnchorPoint = Vector2.new(0.5, 1)
		e.button.Position = UDim2.new(0.5, (i - 2) * 76, 1, -20)
	end
end

-- 궁극기 게이지 바 (살짝 기울어진 띠)
local gaugeBar = new("Frame", {
	-- 휴대폰: 궁극기 버튼 위에 작은 띠 / PC: 능력 버튼 줄 위
	AnchorPoint = isMobile and Vector2.new(1, 1) or Vector2.new(0.5, 1),
	Position = isMobile and UDim2.new(1, -12, 1, -194) or UDim2.new(0.5, 0, 1, -92),
	Size = isMobile and UDim2.fromOffset(150, 14) or UDim2.fromOffset(220, 18),
	BackgroundColor3 = NAVY,
	Rotation = -2,
	Visible = false,
	Parent = screen.gui,
}, { UIKit.corner(6), UIKit.stroke(Color3.fromRGB(255, 200, 70), 2) })
local gaugeFill = new("Frame", { Parent = gaugeBar, Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1) }, { UIKit.corner(6) })
new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 120, 40), Color3.fromRGB(255, 220, 90)), Parent = gaugeFill })
local gaugeText = label({ Parent = gaugeBar, Size = UDim2.fromScale(1, 1), ZIndex = 3, Text = "", TextStrokeTransparency = 0.2 })

-- 디자인: 내 정보 판 (아바타 동그라미 + 초록 막대 = 궁극기 게이지 + 파랑 막대 = 대시 준비)
-- 이 판이 있으면 가운데 궁극기 띠는 숨김 (같은 정보)
local phud
if uiImage("PlayerHPHUD") then
	local w = isMobile and 170 or 250
	local frame = new("Frame", {
		AnchorPoint = isMobile and Vector2.new(0, 0) or Vector2.new(0, 1),
		Position = isMobile and UDim2.fromOffset(12, 92) or UDim2.new(0, 12, 1, -12),
		Size = UDim2.fromOffset(w, w / 4),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen.gui,
	})
	skinImage(frame, "PlayerHPHUD", 1)
	local ap, as = rect(0.047, 0.21, 0.19, 0.79)
	local avatar = new("ImageLabel", { Parent = frame, Position = ap, Size = as, BackgroundTransparency = 1, ZIndex = 2 }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	task.spawn(function()
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok then
			avatar.Image = img
		end
	end)
	-- 막대 위 '빈 부분' 가림막 (오른쪽부터 덮음)
	local function bar(x0, y0, x1, y1, text)
		local cover = new("Frame", { Parent = frame, BackgroundColor3 = Color3.fromRGB(28, 33, 55), BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 2 }, { new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		local tp, ts = rect(x0 + 0.02, y0, x1 - 0.02, y1)
		local t = label({ Parent = frame, Position = tp, Size = ts, Text = text, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.3, ZIndex = 3 })
		return function(p, txt)
			p = math.clamp(p, 0, 1)
			local x = x0 + (x1 - x0) * p
			cover.Position, cover.Size = rect(x, y0, x1, y1)
			cover.Visible = p < 0.999
			if txt then
				t.Text = txt
			end
		end
	end
	phud = {
		frame = frame,
		ult = bar(0.227, 0.29, 0.942, 0.5, ""),
		dash = bar(0.227, 0.58, 0.864, 0.75, ""),
	}
end

local function setCooldown(entry, remaining, total)
	if remaining > 0.05 then
		entry.cover.Size = UDim2.fromScale(1, math.clamp(remaining / total, 0, 1))
		entry.cdText.Text = tostring(math.ceil(remaining))
	else
		entry.cover.Size = UDim2.fromScale(1, 0)
		entry.cdText.Text = ""
	end
end

task.spawn(function()
	while true do
		task.wait(0.1)
		local now = workspace:GetServerTimeNow()
		setCooldown(dashBtn, (player:GetAttribute("DashReady") or 0) - now, Config.Dash.cooldown)
		local skillId = state and state.skill or Config.DefaultSkill
		local skill = Config.Skills[skillId]
		if skillBtn.icon:IsA("TextLabel") then
			local id = Config.Icons[skillId]
			if id and id ~= 0 then
				-- 스킬 그림 아이콘이 등록돼 있으면 그림으로 교체
				local img = iconInto(skillBtn.button, skillId, "", { Size = skillBtn.icon.Size, AnchorPoint = skillBtn.icon.AnchorPoint, Position = skillBtn.icon.Position, ZIndex = 3 })
				skillBtn.icon:Destroy()
				skillBtn.icon = img
				skillBtn.iconSkill = skillId
			else
				skillBtn.icon.Text = skill and string.match(skill.name, "^(%S+)") or "⚡"
			end
		elseif skillBtn.iconSkill ~= skillId and Config.Icons[skillId] and Config.Icons[skillId] ~= 0 then
			skillBtn.icon.Image = "rbxassetid://" .. Config.Icons[skillId]
			skillBtn.iconSkill = skillId
		end
		setCooldown(skillBtn, (player:GetAttribute("SkillReady") or 0) - now, skill and skill.cooldown or 10)
		-- 궁극기: 게이지가 아래에서 위로 '비어 있는 만큼' 덮임
		local gauge = player:GetAttribute("Gauge") or 0
		local full = gauge >= Config.Ultimate.gaugeMax
		if player:GetAttribute("UltActive") then
			ultBtn.cover.Size = UDim2.fromScale(1, 0)
			ultBtn.cdText.Text = "GO!"
			ultBtn.button.BackgroundColor3 = Color3.fromRGB(255, 120, 40)
		else
			ultBtn.cover.Size = UDim2.fromScale(1, 1 - gauge / Config.Ultimate.gaugeMax)
			ultBtn.cdText.Text = full and "" or (math.floor(gauge) .. "%")
			ultBtn.button.BackgroundColor3 = full and Color3.fromRGB(255, 190, 60) or NAVY
		end
		if phud then
			local dashLeft = (player:GetAttribute("DashReady") or 0) - now
			phud.ult(gauge / Config.Ultimate.gaugeMax, player:GetAttribute("UltActive") and "궁극기 발동!" or (full and "궁극기 준비 완료" or ("궁극기 " .. math.floor(gauge) .. "%")))
			phud.dash(1 - math.max(0, dashLeft) / Config.Dash.cooldown, dashLeft > 0 and string.format("대시 %.1f", dashLeft) or "대시 준비")
		end
		-- 기울어진 궁극기 게이지 바
		gaugeFill.Size = UDim2.fromScale(math.clamp(gauge / Config.Ultimate.gaugeMax, 0, 1), 1)
		gaugeText.Text = string.format("%s  %s", Config.Ultimate.name, player:GetAttribute("UltActive") and "발동!" or (full and "준비 완료 [R]" or (math.floor(gauge) .. "%")))
	end
end)

local function setAbilitiesVisible(on)
	for _, e in ipairs(abilityButtons) do
		e.button.Visible = on
	end
	gaugeBar.Visible = on and not phud
	if phud then
		phud.frame.Visible = on
	end
end

----------------------------------------------------------------------
-- 로비: 큰 PLAY 버튼 + 일일 미션 패널
----------------------------------------------------------------------
local queued = false
local playButton = new("TextButton", {
	-- 오른쪽 아래 샷 버튼 바로 위 (가운데는 캐릭터가 보이게 비워 둠)
	AnchorPoint = Vector2.new(1, 1),
	Position = isMobile and UDim2.new(1, -16, 1, -116) or UDim2.new(1, -20, 1, -142),
	Size = UDim2.fromOffset(isMobile and 170 or 220, isMobile and 44 or 56),
	BackgroundColor3 = Color3.new(1, 1, 1),
	Text = "PLAY",
	Font = UIKit.FONT_TITLE,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(20, 60, 20),
	Parent = screen.gui,
}, { UIKit.corner(14), UIKit.stroke(Color3.fromRGB(20, 40, 20), 3), new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })
local playGradient = new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(170, 255, 90), Color3.fromRGB(70, 200, 60)), Parent = playButton })
-- 모드별 대기 인원 (서버가 보내 줌, 키는 "2"/"3"/"4")
local function waitingIn(size)
	local by = info.queuedBy
	return by and by[tostring(size)] or 0
end

local function refreshPlay()
	if queued then
		playButton.Text = string.format("%d대%d %d/%d · 취소", queued, queued, waitingIn(queued), queued * 2)
		playGradient.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(240, 130, 40))
	else
		playButton.Text = "PLAY"
		playGradient.Color = ColorSequence.new(Color3.fromRGB(170, 255, 90), Color3.fromRGB(70, 200, 60))
	end
end

----------------------------------------------------------------------
-- 모드 고르기 창: 2대2 · 3대3 · 4대4 카드 (PLAY 를 누르면 열림)
----------------------------------------------------------------------
local MODE_STYLE = {
	[2] = { Color3.fromRGB(255, 140, 90), Color3.fromRGB(235, 70, 80) },
	[3] = { Color3.fromRGB(90, 225, 190), Color3.fromRGB(30, 150, 190) },
	[4] = { Color3.fromRGB(215, 120, 255), Color3.fromRGB(140, 60, 220) },
}
local GOLD_NUM = ColorSequence.new(Color3.fromRGB(255, 225, 90), Color3.fromRGB(255, 150, 40))
local modeOverlay = new("TextButton", { -- 바깥(어두운 곳)을 누르면 닫힘
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45,
	Text = "",
	AutoButtonColor = false,
	Visible = false,
	ZIndex = 40,
	Parent = screen.gui,
})
local CARD_W, CARD_H = isMobile and 150 or 210, isMobile and 120 or 160
local modePanel = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(CARD_W * 3 + 16 * 4, CARD_H + (isMobile and 70 or 90)),
	BackgroundColor3 = Color3.fromRGB(150, 170, 190),
	BackgroundTransparency = 0.25,
	ZIndex = 41,
	Parent = modeOverlay,
}, { UIKit.corner(18), UIKit.stroke(Color3.new(1, 1, 1), 3) })
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(120, 140, 170), Color3.fromRGB(60, 75, 100)), Parent = modePanel })
local modeTitle = label({
	Parent = modePanel,
	Position = UDim2.fromOffset(0, isMobile and 8 or 12),
	Size = UDim2.new(1, 0, 0, isMobile and 36 or 48),
	Font = UIKit.FONT_TITLE,
	Text = "팀 선택",
	TextColor3 = Color3.new(1, 1, 1),
	ZIndex = 42,
})
new("UIStroke", { Color = Color3.fromRGB(20, 25, 50), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = modeTitle }) -- 글자 테두리
-- 닫기
button({ Parent = modePanel, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = C.red, Text = "X", ZIndex = 43 }, function()
	modeOverlay.Visible = false
end)
local cardRow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.fromOffset(CARD_W * 3 + 16 * 2, CARD_H),
	BackgroundTransparency = 1,
	ZIndex = 42,
	Parent = modePanel,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 16), SortOrder = Enum.SortOrder.LayoutOrder }) })

local modeCards = {}
local joinMode
for order, size in ipairs(Config.MatchModes) do
	local style = MODE_STYLE[size] or MODE_STYLE[2]
	local card = new("TextButton", {
		LayoutOrder = order,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Text = "",
		AutoButtonColor = true,
		ZIndex = 43,
		Parent = cardRow,
	}, { UIKit.corner(16), UIKit.stroke(Color3.fromRGB(40, 25, 50), 3) })
	-- 색 그라데이션은 뒤판에만 (카드 자체에 걸면 위 글자까지 물듦)
	local back = new("Frame", { Parent = card, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 43 }, { UIKit.corner(16) })
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(style[1], style[2]), Parent = back })
	-- 반짝이는 하이라이트 점
	new("Frame", { Parent = card, Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(14, 9), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.35, ZIndex = 44 }, { UIKit.corner(5) })
	-- 큰 숫자 "2v2" (금색 + 진한 테두리)
	local num = label({
		Parent = card,
		Position = UDim2.fromScale(0.05, 0.08),
		Size = UDim2.fromScale(0.9, 0.5),
		Font = UIKit.FONT_TITLE,
		Text = string.format("%dv%d", size, size),
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 45,
	})
	new("UIGradient", { Rotation = 90, Color = GOLD_NUM, Parent = num })
	new("UIStroke", { Color = Color3.fromRGB(40, 30, 60), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = num }) -- 글자 테두리
	label({
		Parent = card,
		Position = UDim2.fromScale(0.05, 0.6),
		Size = UDim2.fromScale(0.9, 0.2),
		Font = UIKit.FONT_TITLE,
		Text = "매칭",
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.2,
		ZIndex = 45,
	})
	local count = label({
		Parent = card,
		Position = UDim2.fromScale(0.05, 0.8),
		Size = UDim2.fromScale(0.9, 0.15),
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.3,
		ZIndex = 45,
	})
	card.Activated:Connect(function()
		joinMode(size)
	end)
	modeCards[size] = { card = card, count = count }
end

local function refreshModeCards()
	for size, c in pairs(modeCards) do
		local n = waitingIn(size)
		c.count.Text = (queued == size and "✅ 대기 중 " or "대기 ") .. n .. " / " .. size * 2 .. "명"
		local stroke = c.card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = queued == size and Color3.fromRGB(255, 240, 120) or Color3.fromRGB(40, 25, 50)
			stroke.Thickness = queued == size and 5 or 3
		end
	end
end

function joinMode(size)
	local ok = Action:InvokeServer("Queue", size)
	if ok then
		queued = size
		refreshPlay()
		refreshModeCards()
		modeOverlay.Visible = false
		screen.toast(string.format("⛳ %d대%d 대기열에 들어갔어요! 인원이 모이면 시작해요", size, size), C.green)
	end
end

modeOverlay.Activated:Connect(function()
	modeOverlay.Visible = false
end)

playButton.Activated:Connect(function()
	if queued then
		-- 대기 중이면 취소
		local ok = Action:InvokeServer("Queue", false)
		if ok then
			queued = false
			refreshPlay()
			refreshModeCards()
			screen.toast("대기열에서 나왔어요", C.sub)
		end
	else
		refreshModeCards()
		modeOverlay.Visible = true
		UIKit.pop(modePanel)
	end
end)

local questPanel = new("Frame", {
	AnchorPoint = isMobile and Vector2.new(0, 0) or Vector2.new(0, 0.5),
	Position = isMobile and UDim2.new(0, 12, 0, 8) or UDim2.new(0, 12, 0.45, 0),
	Size = UDim2.fromOffset(isMobile and 150 or 210, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = NAVY,
	BackgroundTransparency = 0.15,
	Parent = screen.gui,
}, {
	UIKit.corner(12),
	UIKit.stroke(CYAN, 1.5),
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
})
local function renderQuests()
	for _, c in ipairs(questPanel:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local QH = isMobile and 0.7 or 1 -- 휴대폰은 줄 높이를 줄임
	label({ Parent = questPanel, LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 24 * QH), Font = UIKit.FONT_TITLE, TextXAlignment = Enum.TextXAlignment.Left, Text = "📋 일일 미션" })
	local q = state and state.quests or {}
	local today = os.time() // 86400
	for i, key in ipairs(Config.QuestOrder) do
		local def = Config.Quests[key]
		local fresh = q.day == today
		local n = fresh and (q[key] or 0) or 0
		local done = fresh and q.done and q.done[key]
		local row = new("Frame", { Parent = questPanel, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 40 * QH), BackgroundTransparency = 1 })
		label({ Parent = row, Size = UDim2.new(0.62, 0, 0, 20 * QH), TextXAlignment = Enum.TextXAlignment.Left, Text = (done and "✅ " or "") .. def.name })
		label({ Parent = row, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.38, 0, 0, 20 * QH), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(255, 220, 120), Text = "💰" .. (def.coins or 0) .. (def.gems and (" 💎" .. def.gems) or "") })
		local back = new("Frame", { Parent = row, Position = UDim2.fromOffset(0, 24 * QH), Size = UDim2.new(1, 0, 0, 12 * QH), BackgroundColor3 = Color3.fromRGB(10, 12, 30) }, { UIKit.corner(6) })
		new("Frame", { Parent = back, Size = UDim2.fromScale(math.clamp(n / def.goal, 0, 1), 1), BackgroundColor3 = done and C.green or CYAN }, { UIKit.corner(6) })
		label({ Parent = back, Size = UDim2.fromScale(1, 1), ZIndex = 2, Text = n .. " / " .. def.goal })
	end
end

-- 메뉴 줄 배치: 로비 = 화면 아래 가로 줄 / 경기 중 = 왼쪽 세로 (☰ 로 열기)
local function menuHorizontal(on)
	local f = screen.menuFrame
	local layout = f:FindFirstChildOfClass("UIListLayout")
	if on and isMobile then
		-- 휴대폰 로비: 왼쪽 아래 작은 가로 줄 (오른쪽 아래는 샷·점프·PLAY 버튼 자리)
		f.AnchorPoint = Vector2.new(0, 1)
		f.Position = UDim2.new(0, 12, 1, -10)
		f.Size = UDim2.fromOffset(420, 54)
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	elseif on then
		-- PC 로비: 왼쪽 아래 가로 줄
		f.AnchorPoint = Vector2.new(0, 1)
		f.Position = UDim2.new(0, 14, 1, -12)
		f.Size = UDim2.fromOffset(560, 60)
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	else
		f.AnchorPoint = Vector2.new(0, 0.5)
		f.Position = UDim2.new(0, 10, 0.5, 0)
		f.Size = UDim2.fromOffset(isMobile and 60 or 92, 480)
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
	end
end

local wasInGame = false
local layoutReady = false
local function applyLayout(inGame)
	if layoutReady and inGame == wasInGame then
		return
	end
	layoutReady = true
	wasInGame = inGame
	if inGame then
		-- 경기 시작: 메뉴 접고, 열려 있던 창 닫기
		screen.open(nil)
		menuHorizontal(false)
		screen.menuFrame.Visible = false
		menuToggle.Visible = true
		playButton.Visible = false
		questPanel.Visible = false
		setAbilitiesVisible(true)
		hint.Position = isMobile and UDim2.new(0.5, 0, 1, -54) or UDim2.new(0.5, 0, 1, -186)
	else
		-- 로비: PLAY 버튼, 미션, 아래 메뉴 줄
		menuHorizontal(true)
		screen.menuFrame.Visible = true
		menuToggle.Visible = false
		playButton.Visible = true
		questPanel.Visible = true
		setAbilitiesVisible(false)
		hint.Position = isMobile and UDim2.new(0.5, 0, 1, -72) or UDim2.new(0.5, 0, 1, -82) -- 아래 메뉴 줄 위
	end
end

Shot.Start({
	setPower = function(p, visible)
		powerBack.Visible = visible
		powerFill.Size = UDim2.fromScale(p, 1)
		if powerSkin then
			powerSkin(p)
		end
		powerFill.BackgroundColor3 = Color3.fromHSV(0.33 - p * 0.33, 0.85, 0.95)
		powerText.Text = math.floor(p * 100) .. "%"
	end,
	setMode = function(playing, ballNear, practice)
		shotButton.Visible = playing
		jumpButton.Visible = playing
		shotButton.BackgroundColor3 = ballNear and C.green or Color3.fromRGB(255, 130, 80)
		if shotSkin then
			shotSkin.ImageColor3 = ballNear and Color3.new(1, 1, 1) or Color3.fromRGB(170, 170, 170)
		end
		if practice then
			setHint("🏌️ 연습 스윙: 꾹 눌렀다 떼서 골프채 효과 확인")
		elseif not playing then
			setHint("")
		elseif player:GetAttribute("Stunned") then
			setHint("💫 넘어졌어요! 잠깐만...")
		elseif ballNear then
			setHint("⛳ 공이 초록 원 안에! 꾹 눌러 힘을 모았다가 떼면 카메라 방향으로 날아가요")
		else
			setHint("🏃 카메라를 칠 방향으로 돌리고, 공이 바닥의 원(내 오른쪽 앞)에 오게 서요 · 휘둘러서 상대 넘어뜨리기 · Q 대시 · E 스킬 · R 궁극기 · F 아이템")
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
	UIKit.row(parent, 2, Config.Capsules.Basic.name, "💰 " .. Config.Capsules.Basic.cost .. " · 게임에서 번 코인으로만", "1회 뽑기",
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
screen.menu("Skills", "⚡\n스킬", Color3.fromRGB(255, 170, 50), "⚡ 스킬 고르기 (E)", function(parent)
	UIKit.paragraph(parent, "스킬은 모두 무료예요! 하나를 골라 장착하면 경기에서 E 키(모바일은 버튼)로 써요. 대시(Q)와 궁극기(R)는 모두 같아요.", 1, 44)
	for i, id in ipairs(Config.SkillOrder) do
		local skill = Config.Skills[id]
		local equipped = state.skill == id
		UIKit.row(parent, i + 1, skill.name .. "  ⏱" .. skill.cooldown .. "초", skill.desc, equipped and "장착 중" or "장착", equipped and C.gray or C.green, function()
			if not equipped then
				act("SelectSkill", id)
			end
		end)
	end
	UIKit.section(parent, Config.Ultimate.name .. " (R)", 20)
	UIKit.paragraph(parent, Config.Ultimate.desc .. ". 공을 치거나(+" .. Config.Ultimate.perBallHit .. ") 상대를 넘어뜨리면(+" .. Config.Ultimate.perKnock .. ") 게이지가 차요.", 21, 44)
end)

screen.menu("Shop", "💎\n상점", Color3.fromRGB(230, 80, 170), "💎 상점", function(parent)
	local hidden = {}
	if state.restricted then
		hidden = { Gems110 = true, Gems500 = true, Gems1300 = true, Starter = true }
	end
	if state.starterBought then
		hidden.Starter = true
	end
	UIKit.shop(parent, Config, { "VIP", "AimPlus" }, { "Starter", "Gems110", "Gems500", "Gems1300" }, state.passes, {}, hidden)
	UIKit.paragraph(parent, "💰 코인은 판매하지 않아요. 경기에서만 얻을 수 있어요!", 50, 26)
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
		"🔴🔵 팀전! 인원에 맞춰 2대2 · 3대3 · 4대4로 자동으로 나뉘어요. 팀마다 공이 하나, 타수는 없어요 — 우리 공을 먼저 홀컵에 넣는 팀이 그 홀을 이겨요.",
		"🏌️ 마우스 왼쪽(모바일은 버튼)을 꾹 누르면 진짜 골퍼처럼 옆으로 서서 골프채를 뒤로 올리고, 떼면 휘둘러요. 힘 게이지가 왔다 갔다 하니 타이밍!",
		"🎯 공은 카메라가 보는 방향으로 날아가요. 카메라를 칠 방향으로 돌리고, 공이 바닥에 보이는 원(내 오른쪽 앞) 안에 오게 서세요. 원이 초록색이면 맞아요!",
		"💥 휘두르면 앞에 있는 건 다 맞아요: 공은 카메라 방향으로 높이 날아가고(그린 위에선 굴러가는 퍼팅), 상대 선수는 날아가 넘어져요.",
		"😈 상대 팀 공도 칠 수 있어요! 홀컵에서 멀리 쳐 내 버리세요. 대신 잘못 쳐서 넣어 주면 상대 팀 득점!",
		"👫 한 명은 우리 공을 몰고 가고, 한 명은 상대를 넘어뜨리거나 상대 공을 쳐 내는 작전이 좋아요.",
		"💨 Q 대시: 순간 돌진! 대시 직후 잠깐은 휘두르기를 피할 수 있어요 (회피). 공중에서 쓰면 더 멀리.",
		"⚡ E 스킬: 로비의 ⚡ 스킬 메뉴에서 하나를 골라요 — 돌진 태클 · 볼 리콜 · 버블 쉴드 · 서리 지대 · 파워 드라이브",
		"☄️ R 궁극기: 공을 치거나 상대를 넘어뜨리면 게이지가 차요. 가득 찼을 때 R 을 누르면 다음 스윙이 주변 전부를 날려 버리는 메테오 스윙!",
		"❓ 페어웨이 위 상자 = 아이템! F 키로 사용: 💣 물풍선 · 🧊 얼음(상대 공 정지) · 🌬️ 돌풍",
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
	if rank then
		board.Visible = false
		rank.frame.Visible = inMatch and #info.golf.players > 0
		for index = 1, 2 do
			local team = Config.Teams[index]
			local t = info.golf.teams[index]
			rank.rows[index].Text = t and string.format("%s  %s%s", team.name, t.sunk and "✅ 홀인!" or ("홀컵까지 " .. t.dist), t.frozen and " 🧊" or "") or (team.name .. "  -")
			local names = {}
			for _, p in ipairs(info.golf.players) do
				if p.team == index then
					local me = p.userId == player.UserId
					table.insert(names, (me and "★" or "") .. p.name .. (p.shield and "🛡️" or ""))
				end
			end
			rank.rows[index + 2].Text = #names > 0 and table.concat(names, ", ") or "-"
		end
		return
	end
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
				-- 휴대폰은 화면이 작아서 팀 줄만 보여 줌 (내 이름 줄은 아이템 확인용으로 남김)
				if p.team == index and (not isMobile or p.userId == player.UserId) then
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
	local inGame = player:GetAttribute("Team") ~= nil and (m.phase == "Countdown" or m.phase == "Playing" or m.phase == "HoleResult")
	applyLayout(inGame)
	-- 위쪽 점수
	local red, blue = m.teams[1], m.teams[2]
	redNum.Text = red and tostring(red.holeWins) or "0"
	blueNum.Text = blue and tostring(blue.holeWins) or "0"
	if red and blue then
		scoreLabel.Text = string.format("%s · %d/%d홀", m.mode or "", math.max(m.hole, 1), m.holes)
	elseif red then
		scoreLabel.Text = "연습 경기"
	else
		scoreLabel.Text = string.format("대기 %d명", m.queued or 0)
	end
	refreshPlay()
	if modeOverlay.Visible then
		refreshModeCards()
	end
	-- 경기 전용 서버: PLAY(매칭)는 로비 서버에서만
	if m.role == "match" then
		playButton.Visible = false
		modeOverlay.Visible = false
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
		itemButton.Text = (isMobile and "" or "F  ") .. Config.Items[myItem].name
	end
	Shot.Update(m, state and state.passes and state.passes.AimPlus == true)
	renderBoard()
end)

----------------------------------------------------------------------
-- 🛠 운영자 메뉴 (운영자 계정에만 보임. 실제 지급 권한은 서버가 다시 확인)
----------------------------------------------------------------------
local adminTarget = player.UserId
local adminAmount = 1000
local adminMenuMade = false
local function adminAct(req)
	req.target = adminTarget
	local ok, msg = Action:InvokeServer("Admin", req)
	screen.toast(msg or (ok and "완료" or "실패"), ok and C.green or C.red)
end
local function makeAdminMenu()
	if adminMenuMade then
		return
	end
	adminMenuMade = true
	local b = screen.menu("Admin", "🛠\n운영자", Color3.fromRGB(255, 90, 90), "🛠 운영자 도구", function(parent)
		-- 1) 대상 고르기
		UIKit.section(parent, "1. 누구에게?", 1)
		local list = new("Frame", { Parent = parent, LayoutOrder = 2, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, {
			new("UIGridLayout", { CellSize = UDim2.fromOffset(150, 36), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for i, p in ipairs(Players:GetPlayers()) do
			local selected = p.UserId == adminTarget
			button({ Parent = list, LayoutOrder = i, BackgroundColor3 = selected and C.green or C.card, Text = (selected and "✅ " or "") .. p.DisplayName .. (p == player and " (나)" or "") }, function()
				adminTarget = p.UserId
				screen.render()
			end)
		end
		-- 2) 재화
		UIKit.section(parent, "2. 재화 지급 (빼려면 -100 처럼 마이너스)", 3)
		local row = new("Frame", { Parent = parent, LayoutOrder = 4, Size = UDim2.new(1, -8, 0, 44), BackgroundTransparency = 1 }, {
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
		})
		local box = new("TextBox", { Parent = row, LayoutOrder = 1, Size = UDim2.fromOffset(120, 44), BackgroundColor3 = C.card, TextColor3 = C.text, Font = UIKit.FONT, TextScaled = true, Text = tostring(adminAmount), PlaceholderText = "수량", ClearTextOnFocus = false }, { UIKit.corner(8) })
		box.FocusLost:Connect(function()
			adminAmount = tonumber(box.Text) or adminAmount
			box.Text = tostring(adminAmount)
		end)
		for i, cur in ipairs({ { "coins", "💰 코인" }, { "gems", "💎 젬" }, { "shards", "🧩 조각" } }) do
			button({ Parent = row, LayoutOrder = i + 1, Size = UDim2.fromOffset(110, 44), BackgroundColor3 = C.accent, Text = cur[2] }, function()
				adminAmount = tonumber(box.Text) or adminAmount
				adminAct({ cmd = "currency", [cur[1]] = adminAmount })
			end)
		end
		-- 3) 골프채
		UIKit.section(parent, "3. 골프채 지급", 5)
		button({ Parent = parent, LayoutOrder = 6, Size = UDim2.new(1, -8, 0, 40), BackgroundColor3 = Color3.fromRGB(255, 170, 50), Text = "🏌️ 모든 골프채 한 번에 지급" }, function()
			adminAct({ cmd = "allskins" })
		end)
		local grid = new("Frame", { Parent = parent, LayoutOrder = 7, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, {
			new("UIGridLayout", { CellSize = UDim2.fromOffset(150, 40), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for i, id in ipairs(Config.SkinOrder) do
			local skin = Config.Skins[id]
			local gb = button({ Parent = grid, LayoutOrder = i, BackgroundColor3 = C.card, TextColor3 = rarityColor(skin.rarity), Text = skin.name }, function()
				adminAct({ cmd = "skin", skin = id })
			end)
			UIKit.stroke(rarityColor(skin.rarity), 1.5).Parent = gb
		end
		-- 4) 테스트
		UIKit.section(parent, "4. 테스트", 8)
		button({ Parent = parent, LayoutOrder = 9, Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = C.green, Text = "▶ 게임 즉시 시작 (대기 시간 건너뛰기)" }, function()
			adminAct({ cmd = "startnow" })
		end)
		local tp = Players:GetPlayerByUserId(adminTarget)
		local on = tp and tp:GetAttribute("NoCooldown") == true
		button({ Parent = parent, LayoutOrder = 10, Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = on and Color3.fromRGB(255, 170, 50) or C.card, Text = on and "⚡ 쿨타임 없음: 켜짐 (누르면 끔)" or "⚡ 쿨타임 없음: 꺼짐 (누르면 켬 · 대시·스킬·궁극기 무한)" }, function()
			adminAct({ cmd = "nocd" })
			task.delay(0.3, screen.render)
		end)
		UIKit.paragraph(parent, "지급·테스트 기록은 서버 Output 에 [Admin] 으로 남아요. 받은 사람에게는 '운영자 선물' 알림이 떠요. 쿨타임 없음은 위에서 고른 사람에게 적용돼요.", 11, 56)
	end)
	if isMobile then
		b.Size = UDim2.fromOffset(60, 50)
	else
		b.Size = UDim2.fromOffset(76, 60)
	end
end
-- 운영자 패널 대상 목록은 사람이 들어오고 나갈 때 새로 그림
Players.PlayerAdded:Connect(function()
	if screen.current == "Admin" then
		screen.render()
	end
end)
Players.PlayerRemoving:Connect(function()
	if screen.current == "Admin" then
		task.defer(screen.render)
	end
end)

remotes:WaitForChild("State").OnClientEvent:Connect(function(s)
	state = s
	if s.isAdmin then
		makeAdminMenu()
	end
	wallet.Text = string.format("💰 %s   💎 %s   🧩 %s", Format.Short(s.coins), Format.Short(s.gems), Format.Short(s.shards))
	local q = type(s.queued) == "number" and s.queued or false
	if q ~= queued then
		queued = q
		refreshPlay()
	end
	renderQuests()
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
		timerLabel.Text = (p == "Playing" or p == "Countdown" or p == "Intermission") and Format.Time(left) or "--:--"
		if p == "Waiting" and info.role == "match" then
			phaseLabel.Text = "🏁 경기 끝! 로비로 돌아가는 중..."
		elseif p == "Waiting" then
			phaseLabel.Text = queued and string.format("⏳ %d대%d 인원을 기다리는 중 (%d/%d)", queued, queued, waitingIn(queued), queued * 2) or "▶ PLAY 를 눌러 2대2 · 3대3 · 4대4 중 골라요"
		elseif p == "Intermission" then
			local ps = info.pendingSize
			if info.role == "match" then
				phaseLabel.Text = string.format("⚔️ %d대%d 경기장 · 선수들이 모이는 중 %d", ps or 2, ps or 2, math.ceil(left))
				continue
			end
			phaseLabel.Text = ps and string.format("⛳ 곧 %d대%d 경기 시작 %d%s", ps, ps, math.ceil(left), queued and queued ~= ps and string.format(" · 내 %d대%d 는 다음 판", queued, queued) or "") or ("⛳ 곧 경기 시작 " .. math.ceil(left))
		elseif p == "Countdown" then
			phaseLabel.Text = string.format("%d번 홀 · %s · 준비 %d", info.hole, info.theme, math.ceil(left))
		elseif p == "Playing" then
			phaseLabel.Text = string.format("⛳ %d번 홀 · %s", info.hole, info.theme)
		elseif p == "HoleResult" then
			phaseLabel.Text = string.format("%d번 홀 끝! 다음 홀 준비 중...", info.hole)
		else
			phaseLabel.Text = "🏁 경기 종료 · 보상을 받았어요!"
		end
	end
end)

-- 메뉴 버튼 꾸미기: 남색 판 + 색 테두리 + 아이콘 (Config.Icons 에 그림이 있으면 그림)
local NAV_ICON = { Gacha = "NavGacha", Clubs = "NavClubs", Skills = "NavSkills", Shop = "NavShop", Stats = "NavStats" }
for key, m in pairs(screen.menuButtons) do
	local b = m.button
	b.Size = isMobile and UDim2.fromOffset(60, 50) or UDim2.fromOffset(76, 60)
	local accent = b.BackgroundColor3
	b.BackgroundColor3 = NAVY
	local stroke = b:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = accent
		stroke.Thickness = 2.5
	end
	-- 버튼 자체에 그라데이션을 걸면 안의 아이콘·글자까지 어둡게 물들어서, 그라데이션은 뒤에 깐 판에만 검
	b.BackgroundColor3 = Color3.fromRGB(52, 60, 125)
	b.TextColor3 = Color3.new(1, 1, 1)
	local back = new("Frame", { Parent = b, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 0 }, { UIKit.corner(8) })
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(85, 100, 190), Color3.fromRGB(40, 46, 105)), Parent = back })
	local iconId = NAV_ICON[key] and Config.Icons[NAV_ICON[key]]
	if iconId and iconId ~= 0 then
		local title = string.match(b.Text, "\n(.+)$") or ""
		b.Text = ""
		iconInto(b, NAV_ICON[key], "", { Size = UDim2.fromScale(0.62, 0.62), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.02), ZIndex = 2 })
		label({ Parent = b, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, 0, 0.32, 0), Text = title, Font = UIKit.FONT_TITLE, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.4, ZIndex = 2 })
	else
		-- 아이콘 그림이 없는 버튼(방법 등): 글자를 뒤판 위 라벨로 옮김 (버튼 자체 글자는 뒤판에 가려짐)
		local text = b.Text
		b.Text = ""
		local l = label({ Parent = b, Size = UDim2.fromScale(1, 1), Text = text, Font = UIKit.FONT_TITLE, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.4, ZIndex = 2 })
		new("UIPadding", { Parent = l, PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) })
		new("UITextSizeConstraint", { Parent = l, MaxTextSize = 22 })
	end
end
applyLayout(false)

-- 로비 시설(캡슐 머신·진열대·스킬 보드·상점)에 다가가 E 를 누르면 해당 메뉴 열기
game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt, who)
	if who ~= player then
		return
	end
	local key = prompt:GetAttribute("OpenMenu")
	if key and screen.renderers[key] then
		screen.menuFrame.Visible = true
		screen.open(key)
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
