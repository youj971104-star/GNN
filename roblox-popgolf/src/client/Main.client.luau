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
	return label({ Parent = f, Position = UDim2.fromScale(0, 0.3), Size = UDim2.fromScale(1, 0.7), Font = UIKit.FONT_TITLE, Text = "0", TextStrokeTransparency = 0.3 })
end
local redNum = teamBlock(0, 0, Config.Teams[1], "레드")
local blueNum = teamBlock(1, 1, Config.Teams[2], "블루")
local timerBox = new("Frame", {
	Parent = scoreBar,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.new(0.38, 0, 1, 0),
	BackgroundColor3 = NAVY,
}, { UIKit.corner(12), UIKit.stroke(CYAN, 2) })
local timerLabel = label({ Parent = timerBox, Position = UDim2.fromScale(0, 0.02), Size = UDim2.fromScale(1, 0.66), Font = UIKit.FONT_TITLE, Text = "--:--", TextColor3 = Color3.new(1, 1, 1) })
local scoreLabel = label({ Parent = timerBox, Position = UDim2.fromScale(0, 0.66), Size = UDim2.fromScale(1, 0.3), TextColor3 = CYAN, Text = "" }) -- 모드·홀 표시
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
		-- 기울어진 궁극기 게이지 바
		gaugeFill.Size = UDim2.fromScale(math.clamp(gauge / Config.Ultimate.gaugeMax, 0, 1), 1)
		gaugeText.Text = string.format("%s  %s", Config.Ultimate.name, player:GetAttribute("UltActive") and "발동!" or (full and "준비 완료 [R]" or (math.floor(gauge) .. "%")))
	end
end)

local function setAbilitiesVisible(on)
	for _, e in ipairs(abilityButtons) do
		e.button.Visible = on
	end
	gaugeBar.Visible = on
end

----------------------------------------------------------------------
-- 로비: 큰 PLAY 버튼 + 일일 미션 패널
----------------------------------------------------------------------
local queued = false
local playButton = new("TextButton", {
	-- 휴대폰: 오른쪽 아래 샷·점프 버튼 바로 위 / PC: 아래 가운데
	AnchorPoint = isMobile and Vector2.new(1, 1) or Vector2.new(0.5, 1),
	Position = isMobile and UDim2.new(1, -16, 1, -116) or UDim2.new(0.5, 0, 1, -104),
	Size = UDim2.fromOffset(isMobile and 170 or 280, isMobile and 44 or 64),
	BackgroundColor3 = Color3.new(1, 1, 1),
	Text = "PLAY",
	Font = UIKit.FONT_TITLE,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(20, 60, 20),
	Parent = screen.gui,
}, { UIKit.corner(14), UIKit.stroke(Color3.fromRGB(20, 40, 20), 3), new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })
local playGradient = new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(170, 255, 90), Color3.fromRGB(70, 200, 60)), Parent = playButton })
local function refreshPlay(count)
	if queued then
		playButton.Text = string.format("대기 %s· 취소", count and (count .. "명 ") or "")
		playGradient.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(240, 130, 40))
	else
		playButton.Text = "PLAY"
		playGradient.Color = ColorSequence.new(Color3.fromRGB(170, 255, 90), Color3.fromRGB(70, 200, 60))
	end
end
playButton.Activated:Connect(function()
	local want = not queued
	local ok = Action:InvokeServer("Queue", want)
	if ok then
		queued = want
		refreshPlay(nil)
		screen.toast(want and "⛳ 대기열에 들어갔어요! 인원이 모이면 시작해요" or "대기열에서 나왔어요", want and C.green or C.sub)
	end
end)

local questPanel = new("Frame", {
	AnchorPoint = isMobile and Vector2.new(0, 0) or Vector2.new(0, 0.5),
	Position = isMobile and UDim2.new(0, 12, 0, 8) or UDim2.new(0, 12, 0.45, 0),
	Size = UDim2.fromOffset(isMobile and 150 or 240, 0),
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
		f.AnchorPoint = Vector2.new(0.5, 1)
		f.Position = UDim2.new(0.5, 0, 1, -12)
		f.Size = UDim2.fromOffset(600, 70)
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
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
		if isMobile then
			hint.Position = UDim2.new(0.5, 0, 1, -54)
		end
	else
		-- 로비: PLAY 버튼, 미션, 아래 메뉴 줄
		menuHorizontal(true)
		screen.menuFrame.Visible = true
		menuToggle.Visible = false
		playButton.Visible = true
		questPanel.Visible = true
		setAbilitiesVisible(false)
		if isMobile then
			hint.Position = UDim2.new(0.5, 0, 1, -72) -- 아래 메뉴 줄 위
		end
	end
end

Shot.Start({
	setPower = function(p, visible)
		powerBack.Visible = visible
		powerFill.Size = UDim2.fromScale(p, 1)
		powerFill.BackgroundColor3 = Color3.fromHSV(0.33 - p * 0.33, 0.85, 0.95)
		powerText.Text = math.floor(p * 100) .. "%"
	end,
	setMode = function(playing, ballNear, practice)
		shotButton.Visible = playing
		jumpButton.Visible = playing
		shotButton.BackgroundColor3 = ballNear and C.green or Color3.fromRGB(255, 130, 80)
		if practice then
			hint.Text = isMobile and "🏌️ 연습 스윙: 꾹 눌렀다 떼서 골프채 효과 확인" or "🏌️ 연습 스윙: 꾹 눌렀다 떼서 장착한 골프채 효과를 확인해 보세요 (🏌️ 골프채 메뉴에서 장착)"
		elseif not playing then
			hint.Text = ""
		elseif player:GetAttribute("Stunned") then
			hint.Text = "💫 넘어졌어요! 잠깐만..."
		elseif ballNear then
			hint.Text = "⛳ 공이 초록 원 안에! 꾹 눌러 힘을 모았다가 떼면 카메라 방향으로 날아가요"
		else
			hint.Text = "🏃 카메라를 칠 방향으로 돌리고, 공이 바닥의 원(내 오른쪽 앞)에 오게 서요 · 휘둘러서 상대 넘어뜨리기 · Q 대시 · E 스킬 · R 궁극기 · F 아이템"
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
	if queued then
		refreshPlay(m.queued)
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

remotes:WaitForChild("State").OnClientEvent:Connect(function(s)
	state = s
	wallet.Text = string.format("💰 %s   💎 %s   🧩 %s", Format.Short(s.coins), Format.Short(s.gems), Format.Short(s.shards))
	if s.queued ~= nil and s.queued ~= queued then
		queued = s.queued
		refreshPlay(nil)
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
		if p == "Waiting" then
			phaseLabel.Text = queued and "⏳ 인원을 기다리는 중 · 4명 2대2 / 6명 3대3 / 8명 4대4" or "▶ PLAY 를 누르면 경기 대기열에 들어가요"
		elseif p == "Intermission" then
			phaseLabel.Text = "⛳ 곧 경기 시작 " .. math.ceil(left) .. " · 인원에 맞춰 팀이 무작위로 나뉘어요 (최대 4대4)"
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
	if isMobile then
		b.Size = UDim2.fromOffset(60, 50)
	end
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
