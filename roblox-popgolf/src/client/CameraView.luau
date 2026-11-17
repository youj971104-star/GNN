-- 기본 카메라 시점: 캐릭터를 조금 위에서, 더 멀리서 봄 (코스·공·상대가 한눈에 들어오게)
-- 로블록스 기본 카메라는 그대로 쓰고(드래그로 돌리기·확대/축소 가능), 시작 거리·각도·최소 거리만 바꿈
-- 스폰할 때와 코스/로비로 순간이동할 때 다시 맞춤

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local CameraView = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local V = Config.Camera
local UP = Vector3.new(0, 1, 0)

local applying = false

-- 캐릭터 뒤쪽 위에서 내려다보는 자리로 카메라를 놓음
local function apply()
	if applying then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	applying = true
	camera.FieldOfView = V.fov
	-- 줌 거리를 강제로 맞춘 뒤 원래 범위로 풀어 줌 (기본 카메라가 그 거리를 기억함)
	player.CameraMaxZoomDistance = V.distance
	player.CameraMinZoomDistance = V.distance
	RunService.RenderStepped:Wait()
	RunService.RenderStepped:Wait()
	player.CameraMinZoomDistance = V.minZoom
	player.CameraMaxZoomDistance = V.maxZoom
	-- 각도: 캐릭터가 보는 방향 뒤에서 pitch 만큼 위로
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
	local focus = root.Position + UP * 1.5
	local p = math.rad(V.pitch)
	local pos = focus - flat * math.cos(p) * V.distance + UP * math.sin(p) * V.distance
	camera.CFrame = CFrame.lookAt(pos, focus)
	applying = false
end

function CameraView.Start()
	player.CameraMinZoomDistance = V.minZoom
	player.CameraMaxZoomDistance = V.maxZoom
	camera.FieldOfView = V.fov

	local lastPos
	player.CharacterAdded:Connect(function(char)
		lastPos = nil
		char:WaitForChild("HumanoidRootPart", 10)
		task.wait(0.2)
		apply()
	end)
	if player.Character then
		task.defer(apply)
	end

	-- 경기 시작·로비 복귀처럼 멀리 순간이동하면 시점을 다시 맞춤
	RunService.Heartbeat:Connect(function()
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		local pos = root.Position
		if lastPos and (pos - lastPos).Magnitude > 60 then
			task.spawn(apply)
		end
		lastPos = pos
	end)
end

return CameraView
