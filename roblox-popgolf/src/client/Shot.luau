-- 조작 (휘두르기 하나로 공치기 + 사람 치기)
-- PC: 마우스 왼쪽 꾹 → 힘 모으기 (골프채가 뒤로 올라감) → 떼면 휘두르기
--     Q 대시 · E 스킬 · R 궁극기 · F 아이템
--     공은 카메라가 보는 방향으로 날아감. 힘을 모으면 진짜 골퍼처럼 목표를 왼쪽에 두고 옆으로 섬
--     → 공을 '내 오른쪽 앞'(바닥의 스윙 존 원)에 두고 치면 됨
-- 모바일: 화면의 ⛳ 버튼 꾹 → 떼기, 아이템 버튼

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SwingAnimator = require(script.Parent.SwingAnimator)

local Shot = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local CL = Config.Club

local enabled = false
local charging = false
local chargeStart = 0
local power = 0
local lastSwing = 0
local ui
local hasAimPlus = false

local arrow = Instance.new("Part")
arrow.Name = "AimArrow"
arrow.Anchored = true
arrow.CanCollide = false
arrow.CanQuery = false
arrow.CanTouch = false
arrow.CastShadow = false
arrow.Material = Enum.Material.Neon
arrow.Transparency = 0.2
local guide = arrow:Clone()
guide.Name = "AimGuide"
guide.Transparency = 0.75

-- 바닥에 그려지는 스윙 존 (공을 이 원 안에 두고 치기)
local zoneRing = Instance.new("Part")
zoneRing.Name = "SwingZone"
zoneRing.Shape = Enum.PartType.Cylinder
zoneRing.Anchored = true
zoneRing.CanCollide = false
zoneRing.CanQuery = false
zoneRing.CanTouch = false
zoneRing.CastShadow = false
zoneRing.Material = Enum.Material.Neon
zoneRing.Transparency = 0.65
zoneRing.Size = Vector3.new(0.05, CL.ballZone * 2, CL.ballZone * 2)

local function character()
	return player.Character
end

local function rootAndHumanoid()
	local c = character()
	return c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid")
end

local function aimDirection()
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
end

local function canAct()
	local root, humanoid = rootAndHumanoid()
	return enabled and root ~= nil and humanoid ~= nil and humanoid.Health > 0 and player:GetAttribute("Stunned") ~= true
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- 스윙 존 중심: 목표(dir)를 왼쪽에 두고 섰을 때 발 앞
local function zoneCenter(root, dir)
	return root.Position + dir:Cross(Vector3.new(0, 1, 0)) * CL.stanceOffset
end

-- 지금 휘두르면 맞을 공 (서버 판정과 같은 규칙), 그리고 근처(14 이내)에 공이 있는지
local function ballInReach(dir)
	local root = rootAndHumanoid()
	local folder = workspace:FindFirstChild("Balls")
	if not (root and folder) then
		return nil, false
	end
	local zone = zoneCenter(root, dir)
	local near = false
	for _, ball in ipairs(folder:GetChildren()) do
		if ball:IsA("BasePart") and ball:GetAttribute("Team") and not ball.Anchored then
			local pos = ball.Position
			if flat(pos - root.Position).Magnitude < 14 then
				near = true
			end
			local inZone = flat(pos - zone).Magnitude <= CL.ballZone or flat(pos - root.Position).Magnitude <= CL.nearRadius
			if inZone and math.abs(pos.Y - root.Position.Y) < 5 then
				return ball, true
			end
		end
	end
	return nil, near
end
Shot.BallInReach = ballInReach

function Shot.BeginCharge()
	if charging or not canAct() or os.clock() - lastSwing < CL.cooldown then
		return
	end
	charging = true
	chargeStart = os.clock()
	local _, humanoid = rootAndHumanoid()
	if humanoid then
		humanoid.AutoRotate = false -- 힘 모으는 동안은 카메라 방향을 바라봄
	end
	remotes.ChargeStart:FireServer()
end

function Shot.Release()
	if not charging then
		return
	end
	charging = false
	ui.setPower(0, false)
	SwingAnimator.SetLocalCharge(nil)
	if canAct() then
		lastSwing = os.clock()
		local p = power
		remotes.Swing:FireServer(aimDirection(), p)
		SwingAnimator.LocalSwing(p)
	end
	task.delay(0.35, function()
		local _, humanoid = rootAndHumanoid()
		if humanoid and not charging then
			humanoid.AutoRotate = true
		end
	end)
end

function Shot.UseItem()
	if enabled and not practice then
		remotes.UseItem:FireServer()
	end
end

-- Q: 대시 (이동 키를 누르는 방향, 아니면 앞으로)
function Shot.Dash()
	if not enabled or practice then
		return
	end
	local _, humanoid = rootAndHumanoid()
	local move = humanoid and humanoid.MoveDirection or Vector3.zero
	if move.Magnitude < 0.1 then
		move = aimDirection()
	end
	remotes.Dash:FireServer(move)
end

-- E: 스킬 (카메라 방향으로)
function Shot.Skill()
	if enabled and not practice then
		remotes.Skill:FireServer(aimDirection())
	end
end

-- R: 궁극기
function Shot.Ultimate()
	if enabled and not practice then
		remotes.Ultimate:FireServer()
	end
end

local practice = false -- 로비 연습 스윙 (모션·효과만)

function Shot.Update(info, aimPlus)
	hasAimPlus = aimPlus
	local playing = info.phase == "Playing" and player:GetAttribute("Team") ~= nil
	local c = character()
	practice = not playing and c ~= nil and c:FindFirstChild("GolfClub") ~= nil and info.phase ~= "Countdown"
	enabled = playing or practice
	if not enabled and charging then
		charging = false
		SwingAnimator.SetLocalCharge(nil)
		ui.setPower(0, false)
		local _, humanoid = rootAndHumanoid()
		if humanoid then
			humanoid.AutoRotate = true
		end
	end
end

function Shot.Start(callbacks)
	ui = callbacks
	SwingAnimator.Start()

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			Shot.BeginCharge()
		elseif input.KeyCode == Enum.KeyCode.Q then
			Shot.Dash()
		elseif input.KeyCode == Enum.KeyCode.E then
			Shot.Skill()
		elseif input.KeyCode == Enum.KeyCode.R then
			Shot.Ultimate()
		elseif input.KeyCode == Enum.KeyCode.F then
			Shot.UseItem()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			Shot.Release()
		end
	end)

	RunService.RenderStepped:Connect(function()
		local dir = aimDirection()
		local root = rootAndHumanoid()
		local target, near = nil, false
		if enabled and not practice then
			target, near = ballInReach(dir)
		end
		ui.setMode(enabled, target ~= nil, practice)

		-- 스윙 존 표시 (공이 근처에 있거나 힘을 모을 때)
		if enabled and not practice and root and (near or charging) then
			local c = zoneCenter(root, dir)
			local groundY = root.Position.Y - 2.9
			zoneRing.CFrame = CFrame.new(c.X, groundY, c.Z) * CFrame.Angles(0, 0, math.rad(90))
			zoneRing.Color = target and Color3.fromRGB(90, 255, 120) or Color3.new(1, 1, 1)
			zoneRing.Parent = workspace
		else
			zoneRing.Parent = nil
		end

		if charging then
			if not canAct() then
				-- 맞아서 넘어지면 힘 모으기 취소
				charging = false
				SwingAnimator.SetLocalCharge(nil)
				ui.setPower(0, false)
				return
			end
			power = ((os.clock() - chargeStart) / CL.chargeCycle) % 1
			power = power < 0.5 and power * 2 or (1 - power) * 2
			ui.setPower(power, true)
			SwingAnimator.SetLocalCharge(power)
			if root then
				-- 진짜 골퍼처럼: 목표(카메라 방향)를 왼쪽에 두고 공 쪽을 바라봄
				root.CFrame = CFrame.lookAt(root.Position, root.Position + dir:Cross(Vector3.new(0, 1, 0)))
			end
		end

		-- 조준 화살표: 맞을 공이 있으면 공에서, 없으면 내 발 앞에서
		if enabled and not practice and root and (charging or target) then
			local base = (target and target.Position or zoneCenter(root, dir)) - Vector3.new(0, target and 1 or 2.8, 0)
			local len = 3 + (charging and power or 0.25) * 16
			arrow.Size = Vector3.new(0.45, 0.12, len)
			arrow.CFrame = CFrame.lookAt(base + dir * (1.3 + len / 2), base + dir * (2 + len))
			arrow.Color = charging and Color3.fromHSV(0.33 - power * 0.33, 0.9, 1) or Color3.new(1, 1, 1)
			arrow.Parent = workspace
			if target then
				local glen = hasAimPlus and 40 or 18
				guide.Size = Vector3.new(0.18, 0.06, glen)
				guide.CFrame = CFrame.lookAt(base + dir * (1.3 + glen / 2), base + dir * (2 + glen))
				guide.Color = Color3.new(1, 1, 1)
				guide.Parent = workspace
			else
				guide.Parent = nil
			end
		else
			arrow.Parent = nil
			guide.Parent = nil
		end
	end)
end

return Shot
