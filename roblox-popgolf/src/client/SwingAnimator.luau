-- 골프 스윙 모션 (모든 캐릭터, 각자 화면에서 재생) — R6 / R15 모두
--
-- 진짜 골프처럼: 공을 발 앞에 두고 옆으로 서고(목표는 선수의 왼쪽), 골프채는 기울어진 면을 따라
--   어드레스(발 앞 공) → 백스윙(오른쪽 어깨 위) → 다운스윙(공) → 팔로스루(왼쪽 어깨 위) 로 돕니다.
-- 골프채는 가슴의 ClubMotor 관절로 돌리고, 팔은 매 프레임 직접 계산해서 두 손이 손잡이를 쥐게 합니다.
--   R15: 위팔·아래팔 두 마디로 팔꿈치까지 계산 (2-본 IK)
--   R6 : 팔 한 덩어리를 손잡이 쪽으로 뻗음
--
--   스윙 각도 φ (도): 0 = 어드레스(공), + = 백스윙(오른쪽 위), - = 팔로스루(왼쪽 위)
-- 다른 사람 모션은 서버가 캐릭터에 다는 속성(Charging, ChargeStart, SwingId, SwingPower)으로 재생,
-- 내 모션은 버튼을 누르는 즉시 재생.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ClubRig = require(ReplicatedStorage.Shared.ClubRig)

local SwingAnimator = {}

local player = Players.LocalPlayer
local Rot, RotFromTo = ClubRig.Rot, ClubRig.RotFromTo

----------------------------------------------------------------------
-- 조절용 숫자
----------------------------------------------------------------------
local REST = 6 -- 평소 자세 (어드레스에서 살짝 백스윙 쪽)
local BACK_MIN, BACK_MAX = 45, 170 -- 힘 0% / 100% 일 때 백스윙 높이
local FOLLOW = 140 -- 팔로스루 (힘에 따라 최대 +25)
local SWING_TIME = 0.16 -- 다운스윙~팔로스루 시간
local HOLD_TIME = 0.22 -- 피니시 자세 유지
local WAIST_TWIST = 0.3 -- 허리가 골프채 각도를 따라 비트는 비율 (R15)
local HAND_GAP = 0.2 -- 두 손 사이 간격 (왼손 위, 오른손 아래)

local states = {} -- [character] = state
local warned = setmetatable({}, { __mode = "k" })
local localState = { mode = "idle", charge = 0 }

local function pingpong(x)
	local t = x % 1
	return t < 0.5 and t * 2 or (1 - t) * 2
end

local function getState(character)
	local s = states[character]
	if not s then
		s = { phi = REST, mode = "idle", lastSwingId = character:GetAttribute("SwingId") or 0 }
		states[character] = s
	end
	return s
end

local function startSwing(s, power)
	s.mode = "swing"
	s.from = s.phi
	s.to = -(FOLLOW + 25 * power)
	s.start = os.clock()
end

function SwingAnimator.SetLocalCharge(charge)
	if charge then
		localState.mode = "charge"
		localState.charge = charge
	elseif localState.mode == "charge" then
		localState.mode = "idle"
	end
end

function SwingAnimator.LocalSwing(power)
	local character = player.Character
	if character then
		startSwing(getState(character), power)
		localState.mode = "swing"
	end
end

----------------------------------------------------------------------
-- 팔 계산 (모든 벡터는 상체 좌표)
----------------------------------------------------------------------
local function solveArm(info, side, target)
	local arm = info.arms[side]
	local shoulder = arm.shoulder
	local C0r, C1r = Rot(shoulder.C0), Rot(shoulder.C1)
	local rest = C0r * C1r:Inverse() -- 가만히 있을 때 팔 회전
	local S = shoulder.C0.Position
	local restUpper = rest:VectorToWorldSpace(arm.upperVec)

	if not info.r15 then
		local Ru = RotFromTo(restUpper, target - S)
		shoulder.Transform = C0r:Inverse() * Ru * C0r
		return
	end

	-- R15: 팔꿈치 위치 계산 (코사인 법칙)
	local a, b = arm.a, arm.b
	local toT = target - S
	local c = math.clamp(toT.Magnitude, math.abs(a - b) + 0.05, a + b - 0.02)
	local u = toT.Unit
	-- 팔꿈치가 향하는 쪽: 아래 + 바깥 + 살짝 뒤
	local pole = Vector3.new(side == "Right" and 0.7 or -0.7, -1, 0.35)
	local p = pole - u * pole:Dot(u)
	if p.Magnitude < 1e-3 then
		p = Vector3.new(0, -1, 0)
	end
	p = p.Unit
	local cosA = math.clamp((a * a + c * c - b * b) / (2 * a * c), -1, 1)
	local elbowPos = S + u * (a * cosA) + p * (a * math.sqrt(1 - cosA * cosA))

	local Ru = RotFromTo(restUpper, elbowPos - S)
	shoulder.Transform = C0r:Inverse() * Ru * C0r
	local Ra = Ru * rest -- 위팔의 실제 회전

	local elbow = arm.elbow
	local E0r, E1r = Rot(elbow.C0), Rot(elbow.C1)
	local restLower = (Ra * E0r * E1r:Inverse()):VectorToWorldSpace(arm.lowerVec)
	local Rl = RotFromTo(restLower, target - elbowPos)
	local base = Ra * E0r
	elbow.Transform = base:Inverse() * Rl * base
	arm.wrist.Transform = CFrame.new()
end

----------------------------------------------------------------------
-- 매 프레임
----------------------------------------------------------------------
local function update(character, isLocal)
	local club = character:FindFirstChild("GolfClub")
	local s = getState(character)
	if not club then
		s.info = nil
		return
	end
	if not s.info or s.club ~= club then
		s.info = ClubRig.Info(character)
		s.club = club
	end
	local info = s.info
	local motor = info and info.torso:FindFirstChild("ClubMotor")
	if not motor then
		return
	end
	local now = os.clock()

	if not isLocal then
		local swingId = character:GetAttribute("SwingId") or 0
		if swingId ~= s.lastSwingId then
			s.lastSwingId = swingId
			startSwing(s, character:GetAttribute("SwingPower") or 0.5)
		elseif s.mode ~= "swing" then
			if character:GetAttribute("Charging") then
				local started = character:GetAttribute("ChargeStart") or workspace:GetServerTimeNow()
				s.mode = "charge"
				s.charge = pingpong((workspace:GetServerTimeNow() - started) / Config.Club.chargeCycle)
			else
				s.mode = "idle"
			end
		end
	elseif s.mode ~= "swing" then
		s.mode = localState.mode == "charge" and "charge" or "idle"
		s.charge = localState.charge
	end

	if s.mode == "swing" then
		local t = (now - s.start) / SWING_TIME
		if t < 1 then
			s.phi = s.from + (s.to - s.from) * t * t -- 점점 빨라지는 다운스윙
		elseif t < 1 + HOLD_TIME / SWING_TIME then
			s.phi = s.to
		else
			s.mode = "idle"
			if isLocal then
				localState.mode = "idle"
			end
		end
	elseif s.mode == "charge" then
		local target = BACK_MIN + (BACK_MAX - BACK_MIN) * (s.charge or 0)
		s.phi += (target - s.phi) * 0.3
	else
		s.phi += (REST - s.phi) * 0.12
	end

	-- 골프채: 어드레스 기울기(tilt) + 스윙 면을 따라 φ 회전
	local tilt = math.rad(club:GetAttribute("Tilt") or 30)
	local d0 = Vector3.new(0, -math.cos(tilt), -math.sin(tilt))
	local axis = d0:Cross(Vector3.new(1, 0, 0)).Unit -- + 회전이면 오른쪽(백스윙)으로
	local clubRot = CFrame.fromAxisAngle(axis, math.rad(s.phi)) * CFrame.Angles(tilt, 0, 0)
	motor.Transform = clubRot

	-- 두 손 목표: 손잡이 위(왼손)·아래(오른손)
	local d = clubRot:VectorToWorldSpace(Vector3.new(0, -1, 0))
	local pivot = motor.C0.Position
	local grip = club:GetAttribute("GripDist") or 1.8
	solveArm(info, "Left", pivot + d * (grip - HAND_GAP))
	solveArm(info, "Right", pivot + d * (grip + HAND_GAP))

	-- 허리 비틀기 (R15)
	if info.r15 then
		local waist = info.torso:FindFirstChild("Waist")
		if waist then
			waist.Transform = CFrame.Angles(0, math.rad(-s.phi * WAIST_TWIST), 0)
		end
	end
end

function SwingAnimator.Start()
	-- Stepped: 걷기 애니메이션이 적용된 뒤에 덮어씀 (팔·허리 자세가 보이게)
	RunService.Stepped:Connect(function()
		for _, p in ipairs(Players:GetPlayers()) do
			local character = p.Character
			if character then
				local ok, err = pcall(update, character, p == player)
				if not ok and not warned[character] then
					warned[character] = true -- 같은 오류를 매 프레임 찍지 않게 한 번만
					warn("[SwingAnimator]", p.Name, err)
				end
			end
		end
		for character in pairs(states) do
			if not character.Parent then
				states[character] = nil
			end
		end
	end)
end

return SwingAnimator
