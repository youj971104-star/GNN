-- 조작
-- PC
--   우리 팀 공 옆: 마우스 왼쪽 꾹 → 떼면 샷 (카메라가 보는 방향으로)
--   그 밖:        마우스 왼쪽 클릭 → 골프채 휘두르기 (상대 선수 넘어뜨리기 / 상대 공 쳐 내기)
--   F: 언제든 휘두르기 · E: 아이템
-- 모바일: 화면의 ⛳ 샷(꾹) / 🏌️ 휘두르기 / 아이템 버튼

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Shot = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local CYCLE = 1.1 -- 파워 게이지 왕복 시간
local enabled = false
local charging = false
local chargeStart = 0
local power = 0
local ui
local hasAimPlus = false
local myTeamFrozen = false

local arrow = Instance.new("Part")
arrow.Name = "AimArrow"
arrow.Anchored = true
arrow.CanCollide = false
arrow.CanQuery = false
arrow.CanTouch = false
arrow.CastShadow = false
arrow.Material = Enum.Material.Neon
arrow.Size = Vector3.new(0.4, 0.1, 6)
local guide = arrow:Clone()
guide.Name = "AimGuide"
guide.Transparency = 0.7

local function myTeam()
	return player:GetAttribute("Team")
end

local function myBall()
	local team = myTeam()
	local folder = workspace:FindFirstChild("Balls")
	if not (team and folder) then
		return nil
	end
	return folder:FindFirstChild(Config.Teams[team].id .. "Ball")
end

local function root()
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

local function aimDirection()
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
end

-- 지금 샷을 칠 수 있는가 (우리 공 옆, 공이 멈춰 있음, 내가 넘어져 있지 않음)
local function canShoot()
	local ball, r = myBall(), root()
	return enabled
		and ball ~= nil
		and r ~= nil
		and ball:GetAttribute("Resting") == true
		and not ball.Anchored
		and not myTeamFrozen
		and player:GetAttribute("Stunned") ~= true
		and (r.Position - ball.Position).Magnitude <= Config.Club.shotRange
end
Shot.CanShoot = canShoot

function Shot.BeginCharge()
	if canShoot() then
		charging = true
		chargeStart = os.clock()
		return true
	end
	return false
end

function Shot.Release()
	if not charging then
		return
	end
	charging = false
	ui.setPower(0, false)
	if canShoot() then
		remotes.Shoot:FireServer(aimDirection(), math.max(power, 0.05))
	end
end

function Shot.Swing()
	if enabled then
		remotes.Swing:FireServer()
	end
end

function Shot.UseItem()
	if enabled then
		remotes.UseItem:FireServer()
	end
end

function Shot.Update(info, aimPlus)
	hasAimPlus = aimPlus
	enabled = info.phase == "Playing" and myTeam() ~= nil
	local team = myTeam()
	local t = team and info.golf.teams[team]
	myTeamFrozen = t ~= nil and t.frozen == true
	if not enabled then
		charging = false
	end
end

function Shot.Start(callbacks)
	ui = callbacks

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- 공 옆이면 샷 준비, 아니면 휘두르기
			if not Shot.BeginCharge() then
				Shot.Swing()
			end
		elseif input.KeyCode == Enum.KeyCode.F then
			Shot.Swing()
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
		local ready = canShoot()
		ui.setMode(enabled, ready)
		if charging then
			local t = ((os.clock() - chargeStart) / CYCLE) % 1
			power = t < 0.5 and t * 2 or (1 - t) * 2
			ui.setPower(power, true)
		end
		local ball = myBall()
		if ready and ball then
			local dir = aimDirection()
			local base = ball.Position - Vector3.new(0, 0.95, 0)
			local len = 3 + (charging and power or 0.3) * 14
			arrow.Size = Vector3.new(0.4, 0.1, len)
			arrow.CFrame = CFrame.lookAt(base + dir * (1.3 + len / 2), base + dir * (2 + len))
			arrow.Color = charging and Color3.fromHSV(0.33 - power * 0.33, 0.9, 1) or Color3.new(1, 1, 1)
			arrow.Parent = workspace
			local glen = hasAimPlus and 34 or 16
			guide.Size = Vector3.new(0.15, 0.05, glen)
			guide.CFrame = CFrame.lookAt(base + dir * (1.3 + glen / 2), base + dir * (2 + glen))
			guide.Parent = workspace
		else
			arrow.Parent = nil
			guide.Parent = nil
			if charging and not ready then
				charging = false
				ui.setPower(0, false)
			end
		end
	end)
end

return Shot
