-- 조작 (휘두르기 하나로 공치기 + 사람 치기)
-- PC: 마우스 왼쪽 꾹 → 힘 모으기 (골프채가 뒤로 올라감) → 떼면 휘두르기
--     카메라가 보는 방향으로 몸을 돌려서 침. E: 아이템
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

-- 지금 휘두르면 맞을 공 (몸 앞 reach 안)
local function ballInReach(dir)
	local root = rootAndHumanoid()
	local folder = workspace:FindFirstChild("Balls")
	if not (root and folder) then
		return nil
	end
	for _, ball in ipairs(folder:GetChildren()) do
		if ball:IsA("BasePart") and ball:GetAttribute("Team") and not ball.Anchored then
			local offset = ball.Position - root.Position
			local fo = Vector3.new(offset.X, 0, offset.Z)
			local inFront = fo.Magnitude < 2.4 or (fo.Magnitude > 0.01 and fo.Unit:Dot(dir) > 0.15)
			if fo.Magnitude <= CL.reach and inFront and math.abs(offset.Y) < 6 then
				return ball
			end
		end
	end
	return nil
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
	if enabled then
		remotes.UseItem:FireServer()
	end
end

function Shot.Update(info, aimPlus)
	hasAimPlus = aimPlus
	enabled = info.phase == "Playing" and player:GetAttribute("Team") ~= nil
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
		elseif input.KeyCode == Enum.KeyCode.E then
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
		local target = enabled and ballInReach(dir) or nil
		ui.setMode(enabled, target ~= nil)

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
				root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
			end
		end

		-- 조준 화살표: 맞을 공이 있으면 공에서, 없으면 내 발 앞에서
		if enabled and root and (charging or target) then
			local base = (target and target.Position or (root.Position + dir * 2)) - Vector3.new(0, target and 1 or 2.8, 0)
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
