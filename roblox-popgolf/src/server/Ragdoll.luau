-- 넘어질 때 흐느적거리는 '레그돌' 효과
-- 관절(Motor6D)을 잠시 끄고 같은 자리에 볼 소켓(구슬 관절)을 달아서 팔다리가 물리대로 휘청이게 함
-- 캐릭터 물리는 그 선수 컴퓨터가 계산하므로, 클라이언트(VFX)가 "Ragdoll" 속성을 보고 휴머노이드를 물리 상태로 바꿈
-- R15 · R6 · 커스텀 아바타 모두 Motor6D 기준이라 그대로 동작

local Ragdoll = {}

local FOLDER = "RagdollJoints"

-- 뿌리 관절(몸통과 HumanoidRootPart 연결)은 그대로 둠: 끄면 몸이 HumanoidRootPart 와 떨어져 카메라·위치가 꼬임
-- 골프채 관절(ClubMotor)도 그대로 둠: 골프채는 손에 붙은 채로
local function isRootJoint(motor)
	return motor.Name == "Root" or motor.Name == "RootJoint" or motor.Name == "ClubMotor"
end

function Ragdoll.Set(character, on)
	if not character or not character.Parent then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local existing = character:FindFirstChild(FOLDER)
	if on then
		if existing then
			return
		end
		local folder = Instance.new("Folder")
		folder.Name = FOLDER
		for _, motor in ipairs(character:GetDescendants()) do
			if motor:IsA("Motor6D") and not isRootJoint(motor) and motor.Part0 and motor.Part1 then
				local a0 = Instance.new("Attachment")
				a0.Name = "RagdollA0"
				a0.CFrame = motor.C0
				a0.Parent = motor.Part0
				local a1 = Instance.new("Attachment")
				a1.Name = "RagdollA1"
				a1.CFrame = motor.C1
				a1.Parent = motor.Part1
				local socket = Instance.new("BallSocketConstraint")
				socket.Attachment0 = a0
				socket.Attachment1 = a1
				socket.LimitsEnabled = true
				socket.UpperAngle = 60
				socket.TwistLimitsEnabled = true
				socket.TwistLowerAngle = -40
				socket.TwistUpperAngle = 40
				socket.Parent = folder
				-- 나중에 지우기 쉽게 붙인 부착점을 소켓 아래에 기록
				local ref0 = Instance.new("ObjectValue")
				ref0.Value = a0
				ref0.Parent = socket
				local ref1 = Instance.new("ObjectValue")
				ref1.Value = a1
				ref1.Parent = socket
				motor.Enabled = false
				motor:SetAttribute("RagdollOff", true)
			end
		end
		-- 팔다리가 땅을 뚫고 빠지지 않게 충돌 켜기 (원래 값 기억)
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Parent == character then
				if part:GetAttribute("RagdollCollide") == nil then
					part:SetAttribute("RagdollCollide", part.CanCollide)
				end
				part.CanCollide = true
			end
		end
		humanoid.AutoRotate = false
		folder.Parent = character
		character:SetAttribute("Ragdoll", true)
	else
		if existing then
			for _, socket in ipairs(existing:GetChildren()) do
				for _, ref in ipairs(socket:GetChildren()) do
					if ref:IsA("ObjectValue") and ref.Value then
						ref.Value:Destroy()
					end
				end
			end
			existing:Destroy()
		end
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("Motor6D") and d:GetAttribute("RagdollOff") then
				d.Enabled = true
				d:SetAttribute("RagdollOff", nil)
			elseif d:IsA("BasePart") and d:GetAttribute("RagdollCollide") ~= nil then
				d.CanCollide = d:GetAttribute("RagdollCollide")
				d:SetAttribute("RagdollCollide", nil)
			end
		end
		humanoid.AutoRotate = true
		character:SetAttribute("Ragdoll", false)
	end
end

return Ragdoll
