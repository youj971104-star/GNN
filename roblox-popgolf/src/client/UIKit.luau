-- 코드로 UI 를 빠르게 만드는 공용 도구 모음
-- 패널(창), 알림, 공지 배너, 상점 카드 등을 제공합니다.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local UIKit = {}

UIKit.C = {
	bg = Color3.fromRGB(28, 24, 48),
	card = Color3.fromRGB(46, 40, 78),
	cardHi = Color3.fromRGB(68, 60, 112),
	accent = Color3.fromRGB(120, 140, 255),
	gold = Color3.fromRGB(255, 215, 90),
	green = Color3.fromRGB(80, 210, 120),
	red = Color3.fromRGB(235, 85, 95),
	gray = Color3.fromRGB(105, 100, 130),
	text = Color3.fromRGB(245, 242, 255),
	sub = Color3.fromRGB(185, 180, 215),
}
UIKit.FONT = Enum.Font.GothamBold
UIKit.FONT_TITLE = Enum.Font.FredokaOne

local C = UIKit.C

function UIKit.new(className, props, children)
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
local new = UIKit.new

function UIKit.corner(r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 10) })
end

function UIKit.stroke(color, thickness)
	return new("UIStroke", { Color = color or Color3.new(0, 0, 0), Thickness = thickness or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

function UIKit.label(props)
	local l = new("TextLabel", { BackgroundTransparency = 1, Font = UIKit.FONT, TextColor3 = C.text, TextScaled = true, Text = "" })
	for k, v in pairs(props) do
		if k ~= "Parent" then
			l[k] = v
		end
	end
	l.Parent = props.Parent
	return l
end

function UIKit.button(props, onClick)
	local b = new("TextButton", { AutoButtonColor = true, BackgroundColor3 = C.accent, Font = UIKit.FONT, TextColor3 = C.text, TextScaled = true, Text = "" }, { UIKit.corner(8) })
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

function UIKit.pop(obj)
	local scale = obj:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = obj })
	scale.Scale = 0.85
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- 화면 기본 틀: ScreenGui, 알림, 배너, 가운데 패널, 왼쪽 메뉴
function UIKit.Screen(name)
	local screen = {}
	local gui = new("ScreenGui", { Name = name, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = Players.LocalPlayer:WaitForChild("PlayerGui") })
	screen.gui = gui

	-- 알림
	local toastHolder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 104),
		Size = UDim2.fromOffset(440, 200),
		BackgroundTransparency = 1,
		Parent = gui,
	}, { new("UIListLayout", { Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center }) })
	function screen.toast(text, color, small)
		local t = UIKit.label({ Parent = toastHolder, Size = UDim2.fromOffset(small and 220 or 440, small and 24 or 32), Text = text, TextColor3 = color or C.text, TextStrokeTransparency = 0.2 })
		UIKit.pop(t)
		task.delay(small and 1.2 or 2.6, function()
			local tw = TweenService:Create(t, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 })
			tw:Play()
			tw.Completed:Wait()
			t:Destroy()
		end)
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

	-- 큰 공지
	local banner = UIKit.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.26),
		Size = UDim2.new(0.8, 0, 0, 48),
		Font = UIKit.FONT_TITLE,
		TextColor3 = C.gold,
		TextStrokeTransparency = 0,
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	})
	local token = 0
	function screen.banner(text, seconds, color)
		token += 1
		local my = token
		banner.Text = text
		banner.TextColor3 = color or C.gold
		banner.Visible = true
		UIKit.pop(banner)
		task.delay(math.min(seconds or 4, 8), function()
			if token == my then
				banner.Visible = false
			end
		end)
	end

	-- 가운데 패널
	local panel = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.new(0.62, 0, 0.66, 0),
		BackgroundColor3 = C.bg,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	}, { UIKit.corner(16), UIKit.stroke(C.accent, 3), new("UISizeConstraint", { MaxSize = Vector2.new(620, 460), MinSize = Vector2.new(300, 260) }) })
	local title = UIKit.label({ Parent = panel, Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -80, 0, 40), Font = UIKit.FONT_TITLE, TextXAlignment = Enum.TextXAlignment.Left })
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
	screen.content = content
	screen.current = nil
	screen.renderers = {}
	screen.titles = {}
	screen.onChange = nil

	function screen.render()
		if not screen.current or (screen.isReady and not screen.isReady()) then
			return
		end
		local scroll = content.CanvasPosition
		for _, c in ipairs(content:GetChildren()) do
			c:Destroy()
		end
		new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), Parent = content })
		new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
		local renderer = screen.renderers[screen.current]
		if renderer then
			renderer(content)
		end
		content.CanvasPosition = scroll
	end

	function screen.open(key)
		screen.current = key
		if not key then
			panel.Visible = false
			return
		end
		title.Text = screen.titles[key] or key
		panel.Visible = true
		content.CanvasPosition = Vector2.zero
		screen.render()
		UIKit.pop(panel)
	end

	UIKit.button({ Parent = panel, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(38, 38), BackgroundColor3 = C.red, Text = "✕", ZIndex = 11 }, function()
		screen.open(nil)
	end)

	-- 왼쪽 메뉴
	local menu = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(92, 480),
		BackgroundTransparency = 1,
		Parent = gui,
	}, { new("UIListLayout", { Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center }) })
	screen.menuFrame = menu -- 경기 중에 숨기거나 접을 때 사용
	screen.menuButtons = {}
	function screen.menu(key, text, color, titleText, renderer)
		screen.titles[key] = titleText
		screen.renderers[key] = renderer
		local b = UIKit.button({ Parent = menu, Size = UDim2.fromOffset(92, 62), BackgroundColor3 = color, Text = text }, function()
			screen.open(screen.current ~= key and key or nil)
		end)
		UIKit.stroke(Color3.fromRGB(15, 10, 30), 2).Parent = b
		local dot = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = C.red, Visible = false, Parent = b }, { UIKit.corner(8) })
		screen.menuButtons[key] = { button = b, dot = dot }
		return b
	end

	return screen
end

-- 패널 안 공통 요소들
function UIKit.section(parent, text, order)
	return UIKit.label({ Parent = parent, LayoutOrder = order, Size = UDim2.new(1, -8, 0, 26), Font = UIKit.FONT_TITLE, TextColor3 = C.gold, TextXAlignment = Enum.TextXAlignment.Left, Text = text })
end

function UIKit.paragraph(parent, text, order, height)
	return UIKit.label({ Parent = parent, LayoutOrder = order, Size = UDim2.new(1, -8, 0, height or 40), TextScaled = false, TextSize = 15, TextWrapped = true, TextColor3 = C.sub, Text = text })
end

-- 이름 / 설명 / 오른쪽 버튼 한 줄
function UIKit.row(parent, order, titleText, subText, buttonText, buttonColor, onClick)
	local row = new("Frame", { Parent = parent, LayoutOrder = order, Size = UDim2.new(1, -8, 0, 66), BackgroundColor3 = C.card }, { UIKit.corner(10) })
	UIKit.label({ Parent = row, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(0.62, -12, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, Text = titleText })
	UIKit.label({ Parent = row, Position = UDim2.fromOffset(12, 36), Size = UDim2.new(0.62, -12, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.sub, Text = subText or "" })
	local b = UIKit.button({ Parent = row, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.new(0.33, 0, 0, 44), BackgroundColor3 = buttonColor or C.green, Text = buttonText }, onClick)
	return row, b
end

-- 상점: 게임패스 + 개발자 상품 목록. extraText[key] 로 설명을 바꿀 수 있고, hidden[key] 면 숨김
function UIKit.shop(parent, config, passOrder, productOrder, ownedPasses, extraText, hidden)
	local player = Players.LocalPlayer
	local order = 1
	UIKit.section(parent, "게임패스 (영구)", order)
	for _, key in ipairs(passOrder) do
		local info = config.GamePasses[key]
		local owns = ownedPasses[key]
		local configured = info.id ~= 0
		order += 1
		UIKit.row(parent, order, info.name, (extraText and extraText[key]) or info.desc,
			owns and "✅ 보유 중" or (configured and (" " .. info.price .. " R$") or "ID 설정 필요"),
			(owns or not configured) and C.gray or C.green,
			function()
				if not owns and configured then
					MarketplaceService:PromptGamePassPurchase(player, info.id)
				end
			end)
	end
	order += 1
	UIKit.section(parent, "아이템", order)
	for _, key in ipairs(productOrder) do
		if not (hidden and hidden[key]) then
			local info = config.Products[key]
			local configured = info.id ~= 0
			order += 1
			UIKit.row(parent, order, info.name, (extraText and extraText[key]) or info.desc,
				configured and (" " .. info.price .. " R$") or "ID 설정 필요",
				configured and C.green or C.gray,
				function()
					if configured then
						MarketplaceService:PromptProductPurchase(player, info.id)
					end
				end)
		end
	end
end

return UIKit
