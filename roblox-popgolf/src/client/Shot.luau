-- 샷 조작: 카메라가 내 공을 따라가고, 바라보는 방향으로 조준
-- PC: 마우스 왼쪽 버튼을 꾹 눌렀다 떼기 / 모바일: 화면의 ⛳ 샷 버튼을 꾹 눌렀다 떼기
-- 파워 게이지는 0 → 100% → 0 으로 왔다 갔다 (타이밍 맞추는 재미)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shot = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local CYCLE = 1.1 -- 파워 게이지 한 번 왕복 시간(초)

local enabled = false -- 내가 이번 홀에 참가 중이고 플레이 단계인가
local charging = false
local chargeStart = 0
local power = 0
local ui -- { setPower(p, visible), setCanShoot(bool) }
local hasAimPlus = false
local myStatus = {} -- 서버 스냅샷 중 내 공 정보

local arrow = Instance.new("Part")
arrow.Name = "AimArrow"
arrow.Anchored = true
arrow.CanCollide = false
arrow.CanQuery = false
arrow.CanTouch = false
arrow.CastShadow = false
arrow.Material = Enum.Material.Neon
arrow.Color = Color3.fromRGB(255, 255, 255)
arrow.Size = Vector3.new(0.35, 0.1, 6)

local guide = arrow:Clone()
guide.Name = "AimGuide"
guide.Transparency = 0.7
guide.Size = Vector3.new(0.15, 0.05, 12)

local function myBall()
	local folder = workspace:FindFirstChild("Balls")
	return folder and folder:FindFirstChild(tostring(player.UserId))
end

local function aimDirection()
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function canShoot()
	local ball = myBall()
	return enabled
		and ball ~= nil
		and ball:GetAttribute("Resting") == true
		and not ball.Anchored
		and not myStatus.sunk
		and not myStatus.frozen
end

function Shot.BeginCharge()
	if canShoot() then
		charging = true
		chargeStart = os.clock()
	end
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

function Shot.UseItem()
	if enabled then
		remotes.UseItem:FireServer()
	end
end

-- 경기 상태가 바뀔 때마다 Main 에서 호출
function Shot.Update(info, aimPlus)
	hasAimPlus = aimPlus
	local playing = info.playing[tostring(player.UserId)] == true
	local inHole = info.phase == "Countdown" or info.phase == "Playing" or info.phase == "HoleResult"
	enabled = playing and info.phase == "Playing"
	myStatus = {}
	for _, b in ipairs(info.balls) do
		if b.userId == player.UserId then
			myStatus = b
		end
	end

	-- 카메라: 경기 중엔 내 공, 아니면 캐릭터
	local ball = myBall()
	if playing and inHole and ball then
		if camera.CameraSubject ~= ball then
			camera.CameraSubject = ball
			player.CameraMaxZoomDistance = 80
		end
	else
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and camera.CameraSubject ~= humanoid then
			camera.CameraSubject = humanoid
		end
		charging = false
	end
end

function Shot.Start(uiCallbacks)
	ui = uiCallbacks

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
		local ball = myBall()
		local ready = canShoot()
		ui.setCanShoot(ready)

		if charging then
			local t = ((os.clock() - chargeStart) / CYCLE) % 1
			power = t < 0.5 and t * 2 or (1 - t) * 2 -- 0→1→0
			ui.setPower(power, true)
		end

		if ready and ball then
			local dir = aimDirection()
			local base = ball.Position - Vector3.new(0, 0.9, 0)
			local len = 3 + (charging and power or 0.3) * 12
			arrow.Size = Vector3.new(0.35, 0.1, len)
			arrow.CFrame = CFrame.lookAt(base + dir * (1.2 + len / 2), base + dir * (2 + len))
			arrow.Color = charging and Color3.fromHSV(0.33 - power * 0.33, 0.9, 1) or Color3.new(1, 1, 1)
			arrow.Parent = workspace

			local glen = hasAimPlus and 30 or 14
			guide.Size = Vector3.new(0.15, 0.05, glen)
			guide.CFrame = CFrame.lookAt(base + dir * (1.2 + glen / 2), base + dir * (2 + glen))
			guide.Parent = workspace
		else
			arrow.Parent = nil
			guide.Parent = nil
		end
	end)
end

return Shot
