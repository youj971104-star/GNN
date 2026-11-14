-- 골프 스윙 모션 (모든 캐릭터, 각자 화면에서 재생)
-- 골프채 관절(ClubMotor) + 양팔(어깨) + 허리를 함께 돌려서 '진짜 휘두르는' 느낌을 만듭니다.
--
--   각도 θ (도): 음수 = 뒤로 올림(백스윙), 0 = 바로 아래(공 맞는 순간), 양수 = 앞으로 넘어감(팔로스루)
--   힘 모으기: 힘이 셀수록 θ 가 -25 → -155 로 높이 올라감 (게이지와 같이 오르내림)
--   휘두르기: 0.16초 동안 가속하며 +130 까지 → 잠깐 멈춤 → 제자리
--
-- 다른 사람의 모션은 서버가 캐릭터에 다는 속성(Charging, ChargeStart, SwingId, SwingPower)을 보고 재생하고,
-- 내 모션은 버튼을 누르는 즉시 재생합니다 (반응 지연 없음).
-- R15 아바타에 맞춰져 있습니다 (게임 설정 → 아바타 → R15 권장).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local SwingAnimator = {}

local player = Players.LocalPlayer

local REST = 10 -- 평소: 골프채가 살짝 앞을 향해 내려와 있음
local WIND_MIN, WIND_MAX = -25, -155 -- 힘 0% / 100% 일 때 백스윙 높이
local SWING_TIME = 0.16 -- 내려치는 시간
local HOLD_TIME = 0.14 -- 팔로스루 자세 유지
local FOLLOW = 120 -- 팔로스루 각도 (+ 힘에 따라 최대 30도 더)

local states = {} -- [Model(character)] = state
local localState = { mode = "idle", charge = 0 }

local function pingpong(x)
	local t = x % 1
	return t < 0.5 and t * 2 or (1 - t) * 2
end

local function joints(character)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local club = torso and torso:FindFirstChild("ClubMotor")
	if not club then
		return nil
	end
	local rightArm = character:FindFirstChild("RightUpperArm")
	local leftArm = character:FindFirstChild("LeftUpperArm")
	return {
		club = club,
		rShoulder = rightArm and rightArm:FindFirstChild("RightShoulder"),
		lShoulder = leftArm and leftArm:FindFirstChild("LeftShoulder"),
		waist = torso:FindFirstChild("Waist"),
	}
end

local function getState(character)
	local s = states[character]
	if not s then
		s = { theta = REST, mode = "idle", lastSwingId = character:GetAttribute("SwingId") or 0 }
		states[character] = s
	end
	return s
end

local function startSwing(s, power)
	s.mode = "swing"
	s.from = s.theta
	s.to = FOLLOW + 30 * power
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
		local s = getState(character)
		startSwing(s, power)
		s.lastSwingId = (character:GetAttribute("SwingId") or 0) + 1 -- 서버가 곧 올릴 번호는 무시
		localState.mode = "swing"
	end
end

local function update(character, isLocal)
	local j = joints(character)
	if not j then
		return
	end
	local s = getState(character)
	local now = os.clock()

	-- 다른 사람: 서버 속성으로 상태 결정
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
	else
		if s.mode ~= "swing" then
			s.mode = localState.mode == "charge" and "charge" or "idle"
			s.charge = localState.charge
		end
	end

	-- 각도 계산
	if s.mode == "swing" then
		local t = (now - s.start) / SWING_TIME
		if t < 1 then
			s.theta = s.from + (s.to - s.from) * t * t -- 점점 빨라지는 내려치기
		elseif t < 1 + HOLD_TIME / SWING_TIME then
			s.theta = s.to
		else
			s.mode = "idle"
			if isLocal then
				localState.mode = "idle"
			end
		end
	elseif s.mode == "charge" then
		local target = WIND_MIN + (WIND_MAX - WIND_MIN) * (s.charge or 0)
		s.theta += (target - s.theta) * 0.35
	else
		s.theta += (REST - s.theta) * 0.12
	end

	local th = math.rad(s.theta)
	j.club.Transform = CFrame.Angles(th, 0, 0)
	-- 양팔: 같은 각도로 돌고, 손이 가운데로 모이게 살짝 안쪽으로
	if j.rShoulder then
		j.rShoulder.Transform = CFrame.Angles(th, 0, 0) * CFrame.Angles(0, 0, math.rad(-18))
	end
	if j.lShoulder then
		j.lShoulder.Transform = CFrame.Angles(th, 0, 0) * CFrame.Angles(0, 0, math.rad(18))
	end
	-- 허리: 백스윙 땐 몸을 비틀고 뒤로 젖힘, 팔로스루 땐 앞으로 숙이며 반대로 비틈
	if j.waist then
		j.waist.Transform = CFrame.Angles(math.rad(-s.theta * 0.06), math.rad(s.theta * 0.18), 0)
	end
end

function SwingAnimator.Start()
	-- Stepped: 걷기 애니메이션이 적용된 뒤에 덮어써야 팔·허리 자세가 보임
	RunService.Stepped:Connect(function()
		for _, p in ipairs(Players:GetPlayers()) do
			local character = p.Character
			if character then
				update(character, p == player)
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
