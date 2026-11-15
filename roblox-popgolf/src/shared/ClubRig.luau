-- 캐릭터 체형 재기 (R6 / R15 / 키 큰 아바타 모두)
-- 서버(Club): 골프채 길이·기울기를 이 사람 키에 맞게 만들 때
-- 클라이언트(SwingAnimator): 팔을 골프채 손잡이로 뻗게 계산할 때

local ClubRig = {}

ClubRig.PIVOT_Z = -0.35 -- 스윙 중심: 가슴 앞쪽
ClubRig.HEAD_HEIGHT = 0.4 -- 어드레스 때 클럽 머리 중심 높이 (땅 위)

local function rot(cf)
	return cf - cf.Position
end
ClubRig.Rot = rot

-- 벡터 a 를 b 로 돌리는 최소 회전
function ClubRig.RotFromTo(a, b)
	a, b = a.Unit, b.Unit
	local dot = math.clamp(a:Dot(b), -1, 1)
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-5 then
		if dot > 0 then
			return CFrame.new()
		end
		local perp = math.abs(a.X) < 0.9 and Vector3.new(1, 0, 0) or Vector3.new(0, 0, 1)
		return CFrame.fromAxisAngle(a:Cross(perp).Unit, math.pi)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

-- 캐릭터 정보. 관절이 없으면 nil
function ClubRig.Info(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) then
		return nil
	end
	local r15 = humanoid.RigType == Enum.HumanoidRigType.R15
	local info = { r15 = r15, arms = {} }

	if r15 then
		local upperTorso = character:FindFirstChild("UpperTorso")
		local lowerTorso = character:FindFirstChild("LowerTorso")
		local rootJoint = lowerTorso and lowerTorso:FindFirstChild("Root")
		local waist = upperTorso and upperTorso:FindFirstChild("Waist")
		if not (upperTorso and rootJoint and waist) then
			return nil
		end
		info.torso = upperTorso
		for _, side in ipairs({ "Right", "Left" }) do
			local upper = character:FindFirstChild(side .. "UpperArm")
			local lower = character:FindFirstChild(side .. "LowerArm")
			local hand = character:FindFirstChild(side .. "Hand")
			local shoulder = upper and upper:FindFirstChild(side .. "Shoulder")
			local elbow = lower and lower:FindFirstChild(side .. "Elbow")
			local wrist = hand and hand:FindFirstChild(side .. "Wrist")
			if not (shoulder and elbow and wrist) then
				return nil
			end
			info.arms[side] = {
				shoulder = shoulder,
				elbow = elbow,
				wrist = wrist,
				-- 위팔: 어깨 관절 → 팔꿈치 관절 (위팔 좌표)
				upperVec = elbow.C0.Position - shoulder.C1.Position,
				-- 아래팔+손: 팔꿈치 관절 → 손 중심 (아래팔 좌표)
				lowerVec = (wrist.C0.Position - elbow.C1.Position) - wrist.C1.Position,
			}
			local arm = info.arms[side]
			arm.a = arm.upperVec.Magnitude
			arm.b = arm.lowerVec.Magnitude
		end
		-- 서 있을 때 상체 중심 높이 (땅 기준)
		local torsoUp = (rootJoint.C0.Position - rootJoint.C1.Position).Y + (waist.C0.Position - waist.C1.Position).Y
		info.torsoHeight = humanoid.HipHeight + root.Size.Y / 2 + torsoUp
	else
		local torso = character:FindFirstChild("Torso")
		if not torso then
			return nil
		end
		info.torso = torso
		for _, side in ipairs({ "Right", "Left" }) do
			local shoulder = torso:FindFirstChild(side .. " Shoulder")
			local arm = character:FindFirstChild(side .. " Arm")
			if not (shoulder and arm) then
				return nil
			end
			-- R6 팔: 어깨 관절 → 손(팔 아래쪽 끝 근처)
			local handLocal = Vector3.new(0, -arm.Size.Y / 2 + 0.15, 0)
			info.arms[side] = {
				shoulder = shoulder,
				upperVec = handLocal - shoulder.C1.Position,
			}
			info.arms[side].a = info.arms[side].upperVec.Magnitude
			info.arms[side].b = 0
		end
		info.torsoHeight = root.Size.Y / 2 + 2 -- R6 다리 길이 2
	end

	local right = info.arms.Right
	info.shoulderY = right.shoulder.C0.Position.Y
	info.armLen = right.a + right.b
	info.pivot = Vector3.new(0, info.shoulderY - 0.3, ClubRig.PIVOT_Z) -- 상체 좌표
	info.pivotHeight = info.torsoHeight + info.pivot.Y
	return info
end

-- 이 사람에게 맞는 골프채 치수 (stance: 몸에서 공까지 앞쪽 거리)
function ClubRig.Geometry(info, stance)
	local down = math.max(1, info.pivotHeight - ClubRig.HEAD_HEIGHT)
	local fwd = math.max(0.5, stance + ClubRig.PIVOT_Z)
	local headDist = math.sqrt(down * down + fwd * fwd)
	local tilt = math.deg(math.atan2(fwd, down))
	local grip = math.clamp(info.armLen * 0.85, 0.9, headDist - 1.4) -- 손이 쥐는 지점까지 거리
	return { headDist = headDist, tilt = tilt, grip = grip }
end

return ClubRig
