-- 골프 스윙 모션 (모든 캐릭터, 각자 화면에서 재생)
--
-- 진짜 골프처럼: 선수는 공을 앞에 두고 '옆으로' 서고(목표는 선수의 왼쪽), 골프채는 기울어진 면을 따라
--   어드레스(발 앞 공) → 백스윙(오른쪽 어깨 위) → 다운스윙(공) → 팔로스루(왼쪽 어깨 위) 로 돕니다.
-- 골프채는 가슴의 ClubMotor 관절로 돌리고, 손은 IKControl 로 손잡이(GripL/GripR)를 항상 쥐게 합니다.
-- 허리(Waist)는 백스윙 때 오른쪽으로 비틀었다가 임팩트 후 왼쪽으로 풀림.
--
--   스윙 각도 φ (도): 0 = 어드레스(공), + = 백스윙(오른쪽 위), - = 팔로스루(왼쪽 위)
--
-- 다른 사람의 모션은 서버가 캐릭터에 다는 속성(Charging, ChargeStart, SwingId, SwingPower)으로 재생하고,
-- 내 모션은 버튼을 누르는 즉시 재생합니다.  ※ R15 아바타 필요 (게임 설정 → 아바타 → R15)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local SwingAnimator = {}

local player = Players.LocalPlayer

----------------------------------------------------------------------
-- 조절용 숫자
----------------------------------------------------------------------
local ADDRESS_TILT = 32 -- 어드레스 때 골프채가 몸 앞쪽으로 기운 각도 (클수록 공이 발에서 멀어짐)
local REST = 8 -- 평소 자세 (어드레스에서 살짝 백스윙 쪽)
local BACK_MIN, BACK_MAX = 45, 175 -- 힘 0% / 100% 일 때 백스윙 높이
local FOLLOW = 140 -- 팔로스루 (힘에 따라 최대 +25)
local SWING_TIME = 0.16 -- 다운스윙~팔로스루 시간
local HOLD_TIME = 0.22 -- 피니시 자세 유지
local WAIST_TWIST = 0.32 -- 허리가 골프채 각도를 따라 비트는 비율

-- 어드레스 방향 d0 = 몸 앞 아래쪽, 스윙 면은 d0 와 몸의 좌우 축(X)을 품는 기울어진 면
local tilt = math.rad(ADDRESS_TILT)
local d0 = Vector3.new(0, -math.cos(tilt), -math.sin(tilt))
local AXIS = d0:Cross(Vector3.new(1, 0, 0)).Unit -- 이 축으로 + 회전하면 골프채가 오른쪽(백스윙)으로 감
local ADDRESS = CFrame.Angles(tilt, 0, 0) -- 샤프트의 아래(-Y) 방향을 d0 로

local states = {} -- [character] = state
local localState = { mode = "idle", charge = 0 }

local function pingpong(x)
	local t = x % 1
	return t < 0.5 and t * 2 or (1 - t) * 2
end

local function joints(character)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local motor = torso and torso:FindFirstChild("ClubMotor")
	if not motor then
		return nil
	end
	return { club = motor, waist = torso:FindFirstChild("Waist") }
end

-- 양손을 골프채 손잡이에 붙이는 IK (캐릭터마다 한 번)
local function clearIK(s)
	if s.ik then
		for _, ik in ipairs(s.ik) do
			ik:Destroy()
		end
		s.ik = nil
	end
end

local function ensureIK(character, s)
	if s.ik then
		local target = s.ik[1].Target
		if s.ik[1].Parent and target and target:IsDescendantOf(character) then
			return
		end
		clearIK(s) -- 골프채가 바뀌었거나 사라짐 → 다시 만들기
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local club = character:FindFirstChild("GolfClub")
	local grip = club and club:FindFirstChild("Grip")
	if not (humanoid and grip) then
		return
	end
	s.ik = {}
	for _, side in ipairs({ { "Right", "GripR" }, { "Left", "GripL" } }) do
		local upper = character:FindFirstChild(side[1] .. "UpperArm")
		local hand = character:FindFirstChild(side[1] .. "Hand")
		local target = grip:FindFirstChild(side[2])
		if upper and hand and target then
			local ik = Instance.new("IKControl")
			ik.Name = "ClubIK_" .. side[1]
			ik.Type = Enum.IKControlType.Position
			ik.ChainRoot = upper
			ik.EndEffector = hand
			ik.Target = target
			ik.Weight = 1
			ik.Priority = 10
			ik.SmoothTime = 0
			ik.Parent = humanoid
			table.insert(s.ik, ik)
		end
	end
	if #s.ik == 0 then
		s.ik = nil
	end
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

-- 내 캐릭터용 (Controls 에서 호출)
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

-- 스윙 시간 중 공이 맞는 순간(φ=0)까지 걸리는 비율 — 서버 판정 타이밍 맞추는 데 참고
function SwingAnimator.ImpactFraction(fromPhi, toPhi)
	return math.sqrt(fromPhi / (fromPhi - toPhi))
end

local function update(character, isLocal)
	local j = joints(character)
	local s = getState(character)
	if not j then
		clearIK(s) -- 골프채가 없으면(로비) 손을 자유롭게
		return
	end
	ensureIK(character, s)
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
			s.phi = s.to -- 피니시 자세
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

	j.club.Transform = CFrame.fromAxisAngle(AXIS, math.rad(s.phi)) * ADDRESS
	if j.waist then
		-- 백스윙: 가슴이 오른쪽으로 돎(음수 Y 회전) / 팔로스루: 목표(왼쪽)로 돎
		j.waist.Transform = CFrame.Angles(0, math.rad(-s.phi * WAIST_TWIST), 0)
	end
end

function SwingAnimator.Start()
	-- Stepped: 걷기 애니메이션이 적용된 뒤에 덮어씀
	RunService.Stepped:Connect(function()
		for _, p in ipairs(Players:GetPlayers()) do
			local character = p.Character
			if character then
				update(character, p == player)
			end
		end
		for character, s in pairs(states) do
			if not character.Parent then
				clearIK(s)
				states[character] = nil
			end
		end
	end)
end

return SwingAnimator
