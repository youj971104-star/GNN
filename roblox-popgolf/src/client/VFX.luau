-- 전투 연출 (각자 화면에서 그림 → 서버 부담 없음)
-- * 대시·태클 잔상 (몸 모양의 팀 색 잔상이 빠르게 사라짐)
-- * 타격감: 내가 맞히면 화면 살짝 흔들림, 내가 맞으면 크게 흔들리고 붉게 번쩍
-- * 팀 색 외곽선: 같은 팀·상대 팀을 한눈에 구분
-- * 파워 드라이브(반짝임), 궁극기 준비(불꽃 오라) 표시

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local VFX = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local folder = Instance.new("Folder")
folder.Name = "VFX"
folder.Parent = workspace

local shake = 0 -- 남은 흔들림 세기

local function teamColor(p)
	local t = p and p:GetAttribute("Team")
	return t and Config.Teams[t].color or Color3.fromRGB(255, 255, 255)
end

-- 잔상: 몸의 각 부분을 반투명 네온으로 복사해서 사라지게
local function afterimage(character, color)
	for _, partName in ipairs({ "Head", "UpperTorso", "LowerTorso", "Torso", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }) do
		local src = character:FindFirstChild(partName)
		if src and src:IsA("BasePart") then
			local ghost = Instance.new("Part")
			ghost.Anchored = true
			ghost.CanCollide = false
			ghost.CanQuery = false
			ghost.CanTouch = false
			ghost.CastShadow = false
			ghost.Material = Enum.Material.Neon
			ghost.Color = color
			ghost.Transparency = 0.45
			ghost.Size = src.Size
			ghost.CFrame = src.CFrame
			ghost.Parent = folder
			TweenService:Create(ghost, TweenInfo.new(0.35), { Transparency = 1, Size = src.Size * 1.15 }):Play()
			Debris:AddItem(ghost, 0.4)
		end
	end
end

-- 화면 붉게 번쩍 (내가 맞았을 때)
local flashGui = Instance.new("ScreenGui")
flashGui.Name = "HitFlash"
flashGui.IgnoreGuiInset = true
flashGui.ResetOnSpawn = false
flashGui.Parent = player:WaitForChild("PlayerGui")
local flash = Instance.new("Frame")
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.Parent = flashGui

local function hurtFlash()
	flash.BackgroundTransparency = 0.6
	TweenService:Create(flash, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
end

-- 캐릭터마다 연결
local function watchCharacter(p, character)
	-- 팀 외곽선
	local hl = Instance.new("Highlight")
	hl.Name = "TeamOutline"
	hl.FillTransparency = 1
	hl.OutlineTransparency = 1
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = character

	local function refreshTeam()
		local t = p:GetAttribute("Team")
		hl.OutlineTransparency = t and 0.25 or 1
		hl.OutlineColor = teamColor(p)
	end
	p:GetAttributeChangedSignal("Team"):Connect(refreshTeam)
	refreshTeam()

	character:GetAttributeChangedSignal("DashId"):Connect(function()
		afterimage(character, teamColor(p))
		task.delay(0.07, afterimage, character, teamColor(p))
	end)
	character:GetAttributeChangedSignal("SkillId"):Connect(function()
		afterimage(character, Color3.fromRGB(255, 255, 255))
	end)
	if p == player then
		character:GetAttributeChangedSignal("HitId"):Connect(function()
			shake = math.max(shake, 0.35) -- 맞혔을 때: 짧은 손맛
		end)
		character:GetAttributeChangedSignal("KnockedId"):Connect(function()
			shake = math.max(shake, 1)
			hurtFlash()
		end)
	end

	-- 파워 드라이브 반짝임 / 궁극기 오라
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	local att = Instance.new("Attachment")
	att.Parent = root
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(Config.Skills.PowerDrive.color)
	sparkle.Rate = 25
	sparkle.Lifetime = NumberRange.new(0.3, 0.6)
	sparkle.Speed = NumberRange.new(2, 4)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new(0.5, 0)
	sparkle.LightEmission = 1
	sparkle.Enabled = false
	sparkle.Parent = att
	local aura = Instance.new("ParticleEmitter")
	aura.Texture = "rbxasset://textures/particles/fire_main.dds"
	aura.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 80, 40))
	aura.Rate = 45
	aura.Lifetime = NumberRange.new(0.4, 0.8)
	aura.Speed = NumberRange.new(1, 3)
	aura.Acceleration = Vector3.new(0, 8, 0)
	aura.SpreadAngle = Vector2.new(60, 60)
	aura.Size = NumberSequence.new(1.6, 0)
	aura.LightEmission = 1
	aura.Enabled = false
	aura.Parent = att
	local function refreshBuffs()
		sparkle.Enabled = p:GetAttribute("Powered") == true
		aura.Enabled = p:GetAttribute("UltActive") == true
	end
	p:GetAttributeChangedSignal("Powered"):Connect(refreshBuffs)
	p:GetAttributeChangedSignal("UltActive"):Connect(refreshBuffs)
	refreshBuffs()
end

function VFX.Start()
	local function watchPlayer(p)
		p.CharacterAdded:Connect(function(c)
			watchCharacter(p, c)
		end)
		if p.Character then
			task.spawn(watchCharacter, p, p.Character)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)

	-- 화면 흔들림 (카메라를 살짝 흔들고 바로 줄어듦)
	RunService.RenderStepped:Connect(function(dt)
		if shake > 0.01 then
			local m = shake * 0.35
			camera.CFrame = camera.CFrame * CFrame.Angles(math.rad((math.random() - 0.5) * m * 4), math.rad((math.random() - 0.5) * m * 4), 0)
			shake = math.max(0, shake - dt * 3.5)
		end
	end)
end

return VFX
