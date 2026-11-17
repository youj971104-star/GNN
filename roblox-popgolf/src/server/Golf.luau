-- 2대2 팀 배틀 골프 규칙 (휘두르기 하나로 공치기 + 사람 치기)
-- * 꾹 누르면 힘을 모으고, 떼면 휘두름 → 몸 앞의 공(어느 팀 공이든)은 날아가고, 상대 선수는 넘어짐
-- * 공은 포물선으로 날아가고, 그린 위에서는 굴리는 퍼팅
-- * 타수 없음! 우리 공을 먼저 홀컵에 넣는 팀이 홀 승리 (상대 공을 쳐서 멀리 보내는 것도 작전)
-- * 시간이 끝나면 우리 공이 홀컵에 더 가까운 팀 승리
-- 모든 판정은 서버에서 합니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local PhysicsService = game:GetService("PhysicsService")

local Config = require(ReplicatedStorage.Shared.Config)
local Ragdoll = require(script.Parent.Ragdoll)

local Golf = {}

local UP = Vector3.new(0, 1, 0)
local B = Config.Ball
local CL = Config.Club

local ctx
local hole
local teams = {} -- [teamIndex] = { members, ball, sunk, lastSafe, restTimer, frozenUntil, lastHitter }
local playerTeam = {} -- [Player] = teamIndex
local pstate = {} -- [Player] = { stunUntil, item, lastSwing, dodgeUntil, dashReady, skillReady, gauge, ultUntil, powerUntil, bubbleUntil, slowUntil }
local zones = {} -- 서리 지대 { part, center, radius, untilTime, owner }
local winner = nil
local active = false
local ballsFolder

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

-- 공이 땅에 묻혔는지 볼 때 쓰는 '바닥만' 레이캐스트 (지형 + 코스 바닥 부품, 나무·소품·물은 무시)
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.IgnoreWater = true
local GROUND_NAMES = { Fairway = true, Green = true, GreenFringe = true, Tee = true, CartPath = true }

----------------------------------------------------------------------
-- 도우미
----------------------------------------------------------------------
local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart"), character and character:FindFirstChildOfClass("Humanoid")
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- 공 아래 바닥 종류 (없으면 nil = 공중)
-- 지형 재질 → 바닥 종류 (러프=잔디 지형, 벙커=모래 지형, 연못=물)
local TERRAIN_SURFACE = {
	[Enum.Material.Grass] = "Rough",
	[Enum.Material.Sand] = "Sand",
	[Enum.Material.Water] = "Water",
	[Enum.Material.Rock] = "Rough",
}

local function surfaceUnder(ball)
	local hit = workspace:Raycast(ball.Position, Vector3.new(0, -(B.diameter / 2 + 0.7), 0), rayParams)
	if not hit then
		return nil
	end
	if hit.Instance:IsA("Terrain") then
		return TERRAIN_SURFACE[hit.Material] or "Rough"
	end
	return hit.Instance.Name
end

-- 공 물리는 항상 서버가 계산 (가까운 선수 컴퓨터가 맡으면 서버가 준 속도를 그 컴퓨터가 덮어써서 공이 안 나감)
local function serverOwn(ball)
	if ball.Anchored or not ball:IsDescendantOf(workspace) then
		return
	end
	-- 공은 다른 부품과 붙어 있으면 안 됨 (고정된 바닥과 붙으면 공 전체가 고정된 것처럼 꼼짝 안 함)
	for _, joint in ipairs(ball:GetJoints()) do
		if Config.DebugShots then
			print("[Shot] 공에 붙은 연결 제거:", joint:GetFullName(), joint.ClassName)
		end
		joint:Destroy()
	end
	local ok, err = pcall(function()
		if ball:GetNetworkOwner() ~= nil or ball:GetNetworkOwnershipAuto() then
			ball:SetNetworkOwner(nil)
		end
	end)
	if not ok then
		warn("[Golf] 공 네트워크 소유권을 서버로 못 바꿈:", ball.Name, err)
	end
end

local function stopBall(ball)
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
end

local function onGreen(pos)
	return flat(pos - hole.greenCenter).Magnitude < hole.greenRadius
end

-- 선수 캐릭터는 각자 컴퓨터가 물리를 담당하므로 잠깐 힘을 붙여서 날림
local function fling(player, velocity)
	local root = rootOf(player)
	if not root then
		return
	end
	local att = Instance.new("Attachment")
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = 1e6
	lv.VectorVelocity = velocity
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = root
	task.delay(0.18, function()
		lv:Destroy()
		att:Destroy()
	end)
end

local UL = Config.Ultimate

-- 쿨다운 표시용: 다시 쓸 수 있는 서버 시각을 선수 속성으로 (클라이언트 버튼에 남은 시간 표시)
local function setReady(player, name, seconds)
	player:SetAttribute(name .. "Ready", workspace:GetServerTimeNow() + seconds)
end

local function addGauge(player, amount)
	local ps = pstate[player]
	if not ps or ps.ultUntil > os.clock() then
		return
	end
	ps.gauge = math.min(UL.gaugeMax, ps.gauge + amount)
	player:SetAttribute("Gauge", math.floor(ps.gauge))
end

local function bump(instance, attr)
	instance:SetAttribute(attr, (instance:GetAttribute(attr) or 0) + 1)
end

-- 넘어뜨리기. 대시 회피 중이면 피하고, 버블 쉴드면 막음
local function stun(player, velocity, by, duration)
	local ps = pstate[player]
	local root, humanoid = rootOf(player)
	if not (ps and root and humanoid) then
		return false
	end
	local now = os.clock()
	if ps.dodgeUntil > now then
		ctx.notify(player, "💨 회피!", Color3.fromRGB(180, 240, 255))
		if by then
			ctx.notify(by, "💨 " .. player.DisplayName .. " 님이 대시로 피했어요!", Color3.fromRGB(200, 200, 200))
		end
		return false
	end
	if ps.bubbleUntil > now then
		return false
	end
	duration = duration or CL.stunTime
	ps.stunUntil = now + duration
	humanoid.PlatformStand = true
	Ragdoll.Set(player.Character, true) -- 흐느적 넘어짐
	fling(player, velocity)
	player:SetAttribute("Stunned", true)
	if player.Character then
		bump(player.Character, "KnockedId") -- 맞은 사람 화면 흔들기
	end
	ctx.impact(root.Position, Color3.fromRGB(255, 235, 200), false)
	task.delay(duration, function()
		if ps.stunUntil <= os.clock() + 0.05 then
			local _, h = rootOf(player)
			Ragdoll.Set(player.Character, false)
			if h then
				h.PlatformStand = false
				h:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
			player:SetAttribute("Stunned", false)
		end
	end)
	if by then
		ctx.notify(player, "💫 " .. by.DisplayName .. " 님에게 맞았어요!", Color3.fromRGB(255, 160, 120))
		ctx.onKnockout(by)
		addGauge(by, UL.perKnock)
	end
	return true
end

local function enemiesOf(player)
	local mine = playerTeam[player]
	local list = {}
	for p, t in pairs(playerTeam) do
		if t ~= mine and p.Parent then
			table.insert(list, p)
		end
	end
	return list
end

----------------------------------------------------------------------
-- 팀 공
----------------------------------------------------------------------
local function makeBall(index, position)
	local team = Config.Teams[index]
	local ball = Instance.new("Part")
	ball.Name = team.id .. "Ball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * B.diameter
	ball.Position = position
	ball.Color = team.color
	ball.Material = Enum.Material.SmoothPlastic
	ball.CustomPhysicalProperties = PhysicalProperties.new(2, 0.4, 0.35, 1, 1)
	ball.Anchored = true
	ball.CollisionGroup = "GolfBall" -- 선수 몸과는 안 부딪힘 (골프채로만 움직임)
	ball:SetAttribute("Team", index)

	local hl = Instance.new("Highlight")
	hl.FillTransparency = 0.5
	hl.FillColor = team.color
	hl.OutlineColor = Color3.new(1, 1, 1)
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = ball
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 30)
	gui.StudsOffset = Vector3.new(0, 2.8, 0)
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = team.color
	label.TextStrokeTransparency = 0.2
	label.Text = team.name .. " 공"
	label.Parent = gui
	gui.Parent = ball

	-- 날아갈 때 보이는 긴 꼬리
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.7, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.7, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.8
	trail.LightEmission = 0.6
	trail.Color = ColorSequence.new(team.color, Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Parent = ball

	ball.Parent = ballsFolder
	return ball
end

----------------------------------------------------------------------
-- 홀 시작 / 끝
----------------------------------------------------------------------
function Golf.BeginHole(newHole, teamLists)
	hole = newHole
	teams = {}
	playerTeam = {}
	winner = nil
	active = false
	ballsFolder:ClearAllChildren()
	rayParams.FilterDescendantsInstances = { hole.folder, workspace.Terrain }
	local ground = { workspace.Terrain }
	for _, d in ipairs(hole.folder:GetChildren()) do
		if d:IsA("BasePart") and GROUND_NAMES[d.Name] then
			table.insert(ground, d)
		end
	end
	groundParams.FilterDescendantsInstances = ground

	local teamCount = #teamLists
	for index, members in ipairs(teamLists) do
		local pos = ctx.ballStart(hole, index, teamCount)
		teams[index] = {
			members = members,
			ball = makeBall(index, pos),
			sunk = false,
			lastSafe = pos,
			restTimer = 0,
			frozenUntil = 0,
			lastHitter = nil,
		}
		for slot, p in ipairs(members) do
			playerTeam[p] = index
			pstate[p] = {
				stunUntil = 0,
				item = nil,
				lastSwing = 0,
				dodgeUntil = 0,
				dashReady = 0,
				skillReady = 0,
				gauge = 0,
				ultUntil = 0,
				powerUntil = 0,
				bubbleUntil = 0,
				slowUntil = 0,
			}
			p:SetAttribute("Gauge", 0)
			p:SetAttribute("DashReady", 0)
			p:SetAttribute("SkillReady", 0)
			Golf.PlacePlayer(p, slot)
		end
	end
end

function Golf.PlacePlayer(player, slot)
	local index = playerTeam[player]
	if not (hole and index) then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local cf
	if slot then
		cf = ctx.playerStart(hole, index, #teams, slot, #teams[index].members)
	else
		cf = CFrame.new(teams[index].ball.Position + UP * 4 + Vector3.new(math.random(-4, 4), 0, math.random(-4, 4)))
	end
	Ragdoll.Set(character, false)
	character:PivotTo(cf)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = CL.walkSpeed
		humanoid.PlatformStand = false
	end
end

function Golf.Go()
	active = true
	for _, t in pairs(teams) do
		t.ball.Anchored = false
		serverOwn(t.ball)
	end
end

function Golf.EndHole()
	active = false
	if winner then
		return winner, "sunk"
	end
	local best, bestDist, tie = nil, math.huge, false
	for index, t in pairs(teams) do
		local d = flat(t.ball.Position - hole.cup).Magnitude
		if d < bestDist - 0.5 then
			best, bestDist, tie = index, d, false
		elseif math.abs(d - bestDist) <= 0.5 then
			tie = true
		end
	end
	if tie then
		return nil, "tie"
	end
	return best, "closer"
end

function Golf.Winner()
	return winner
end

function Golf.Clear()
	active = false
	for _, z in ipairs(zones) do
		z.part:Destroy()
	end
	table.clear(zones)
	teams = {}
	playerTeam = {}
	winner = nil
	if ballsFolder then
		ballsFolder:ClearAllChildren()
	end
end

function Golf.RemovePlayer(player)
	local index = playerTeam[player]
	playerTeam[player] = nil
	pstate[player] = nil
	if index and teams[index] then
		local i = table.find(teams[index].members, player)
		if i then
			table.remove(teams[index].members, i)
		end
	end
end

function Golf.Snapshot()
	local teamInfo = {}
	for index, t in pairs(teams) do
		teamInfo[index] = {
			sunk = t.sunk,
			frozen = t.frozenUntil > os.clock(),
			dist = hole and math.floor(flat(t.ball.Position - hole.cup).Magnitude) or 0,
			onGreen = hole and onGreen(t.ball.Position) or false,
		}
	end
	local players = {}
	for p, index in pairs(playerTeam) do
		local ps = pstate[p]
		table.insert(players, {
			userId = p.UserId,
			name = p.DisplayName,
			team = index,
			item = ps and ps.item,
			shield = ps and ps.bubbleUntil > os.clock(),
		})
	end
	return { teams = teamInfo, players = players, length = hole and hole.length or 0 }
end

----------------------------------------------------------------------
-- 힘 모으기 / 휘두르기
----------------------------------------------------------------------
-- 다른 사람 화면에서도 골프채가 뒤로 올라가는 모습이 보이도록 캐릭터에 표시
function Golf.ChargeStart(player)
	local ps = pstate[player]
	local character = player.Character
	if not (active and ps and character) or ps.stunUntil > os.clock() then
		return
	end
	character:SetAttribute("ChargeStart", workspace:GetServerTimeNow())
	character:SetAttribute("Charging", true)
end

local function launchBall(t, dir, power, hitter, mult)
	local pos = t.ball.Position
	local speed = B.maxSpeed * math.max(power, CL.minPower) * (mult or 1)
	local angle = B.launchAngle
	if onGreen(pos) then
		speed *= B.puttPower
		angle = B.puttAngle
	end
	local rad = math.rad(angle)
	serverOwn(t.ball)
	t.ball:SetAttribute("Resting", false)
	t.restTimer = 0
	t.lastHitter = hitter
	t.launchedAt = os.clock()
	t.bonked = {} -- 이번 샷에 이미 맞은 선수
	-- 공이 바닥 부품에 파묻혀 '잠든' 상태면 속도만 바꿔서는 안 움직임 → 바닥 위로 살짝 들어 올려(위치 이동 = 물리 깨움) 겹침에서 빼냄
	local ball = t.ball
	local below = workspace:Raycast(ball.Position + UP * 3, -UP * (3 + B.diameter), rayParams)
	if below then
		local restY = below.Position.Y + B.diameter / 2 + 0.05
		if ball.Position.Y < restY then
			ball.CFrame = ball.CFrame + UP * (restY - ball.Position.Y)
		end
	end
	local velocity = dir * (math.cos(rad) * speed) + UP * (math.sin(rad) * speed)
	ball.AssemblyLinearVelocity = Vector3.zero
	ball:ApplyImpulse(velocity * ball.AssemblyMass) -- 충격으로 발사 (잠든 공도 확실히 깨움)
	ball.AssemblyLinearVelocity = velocity
	ball.AssemblyAngularVelocity = Vector3.new(dir.Z, 0, -dir.X) * -speed * 0.3 -- 앞으로 구르는 회전
end

function Golf.Swing(player, direction, power)
	local index = playerTeam[player]
	local ps = pstate[player]
	local character = player.Character
	if Config.DebugShots then
		print(string.format("[Shot] 서버가 스윙 받음: %s / 진행중=%s / 팀=%s / 힘=%s", player.Name, tostring(active), tostring(index), tostring(power)))
	end
	if not (active and index and ps and character) then
		return
	end
	if typeof(direction) ~= "Vector3" or type(power) ~= "number" or power ~= power then
		return
	end
	local now = os.clock()
	if ps.stunUntil > now or now - ps.lastSwing < CL.cooldown then
		character:SetAttribute("Charging", false)
		return
	end
	ps.lastSwing = now
	local dir = flat(direction)
	if dir.Magnitude < 0.01 then
		return
	end
	dir = dir.Unit
	power = math.clamp(power, 0, 1)

	-- 모든 화면에서 휘두르는 모션 재생
	character:SetAttribute("Charging", false)
	character:SetAttribute("SwingPower", power)
	character:SetAttribute("SwingId", (character:GetAttribute("SwingId") or 0) + 1)

	-- 내려치는 순간에 맞춰 판정
	task.delay(CL.impactDelay, function()
		local root = rootOf(player)
		if not (active and root) then
			return
		end
		local origin = root.Position
		local hitSomething = false
		local t0 = os.clock()
		-- 파워 드라이브 / 메테오 스윙
		local mult = 1
		if ps.powerUntil > t0 then
			mult = 1.45
			ps.powerUntil = 0
			player:SetAttribute("Powered", false)
		end
		local ult = ps.ultUntil > t0
		if ult then
			ps.ultUntil = 0
			player:SetAttribute("UltActive", false)
			ctx.shockwave(origin, UL.radius, Config.Teams[index].color)
			ctx.announce("☄️ " .. player.DisplayName .. " 님의 메테오 스윙!", 2)
		end
		-- 선수는 목표(dir)를 왼쪽에 두고 옆으로 섬 → 얼굴 방향 = dir × 위
		local facing = dir:Cross(UP)
		local zone = origin + facing * CL.stanceOffset

		-- 공 (우리 팀 공이든 상대 팀 공이든): 발 앞 스윙 존 안이면 목표 방향으로 (메테오는 반경 전체)
		for _, t in pairs(teams) do
			if not t.sunk and t.frozenUntil <= os.clock() then
				local pos = t.ball.Position
				local inZone = flat(pos - zone).Magnitude <= CL.ballZone or flat(pos - origin).Magnitude <= 2.2
				if ult then
					inZone = flat(pos - origin).Magnitude <= UL.radius
				end
				if Config.DebugShots then
					print(string.format("[Shot] %s 스윙 → %s 공: 존까지 %.1f / 몸까지 %.1f / 높이차 %.1f / 고정=%s / 판정=%s",
						player.Name, t.ball.Name, flat(pos - zone).Magnitude, flat(pos - origin).Magnitude, math.abs(pos.Y - origin.Y), tostring(t.ball.Anchored), tostring(inZone and math.abs(pos.Y - origin.Y) < 6)))
				end
				if inZone and math.abs(pos.Y - origin.Y) < 6 then
					launchBall(t, dir, ult and math.max(power, 0.8) or power, player, ult and UL.launchMult or mult)
					if Config.DebugShots then
						local b = t.ball
						local owner = "?"
						pcall(function()
							local o = b:GetNetworkOwner()
							owner = o and o.Name or "서버"
						end)
						local touching = {}
						for _, part in ipairs(workspace:GetPartBoundsInRadius(b.Position, B.diameter / 2 + 0.05)) do
							if part ~= b and part.CanCollide then
								table.insert(touching, part:GetFullName())
							end
						end
						print(string.format("[Shot] 발사: 속도 %.0f (힘 %.2f) / 소유자=%s / 겹친 부품=%s", b.AssemblyLinearVelocity.Magnitude, power, owner, #touching > 0 and table.concat(touching, ", ") or "없음"))
						local connected = {}
						for _, cp in ipairs(b:GetConnectedParts(true)) do
							if cp ~= b then
								table.insert(connected, cp:GetFullName())
							end
						end
						print(string.format("[Shot] 공 상태: 땅에묶임=%s / 연결수=%d / 연결된부품=%s / 묶음대표=%s / 충돌그룹=%s / 질량=%.2f",
							tostring(b:IsGrounded()), #b:GetJoints(), #connected > 0 and table.concat(connected, ", ") or "없음",
							b.AssemblyRootPart and b.AssemblyRootPart:GetFullName() or "?", b.CollisionGroup, b.AssemblyMass))
						task.spawn(function()
							game:GetService("RunService").Heartbeat:Wait()
							print(string.format("[Shot] 한 프레임 뒤: 속도 %.0f", b.AssemblyLinearVelocity.Magnitude))
						end)
						task.delay(0.1, function()
							print(string.format("[Shot] 0.1초 뒤: 속도 %.0f / 위치 %s / 고정=%s", b.AssemblyLinearVelocity.Magnitude, tostring(b.Position), tostring(b.Anchored)))
						end)
					end
					addGauge(player, UL.perBallHit)
					ctx.onBallHit(player)
					ctx.impact(t.ball.Position, Config.Teams[index].color, ult or mult > 1)
					hitSomething = true
				end
			end
		end

		-- 상대 선수: 골프채가 크게 도는 반경 안이면 맞음 (버블 쉴드면 내가 튕겨 나감)
		local reach = ult and UL.radius or CL.reach
		for _, enemy in ipairs(enemiesOf(player)) do
			local er = rootOf(enemy)
			local eps = pstate[enemy]
			if er and eps then
				local offset = er.Position - origin
				if flat(offset).Magnitude <= reach and math.abs(offset.Y) < 6 then
					if eps.bubbleUntil > os.clock() then
						-- 버블 쉴드 반사
						stun(player, -dir * 55 + UP * 30, enemy)
						ctx.notify(player, "🫧 " .. enemy.DisplayName .. " 님의 버블에 튕겨 나갔어요!", Color3.fromRGB(150, 230, 255))
					else
						local k = CL.knockback * (0.6 + power) * (ult and 1.6 or mult)
						local away = ult and flat(offset).Magnitude > 0.1 and flat(offset).Unit or dir
						stun(enemy, away * k + UP * (20 + 25 * power), player, ult and UL.stunTime or nil)
						hitSomething = true
					end
				end
			end
		end

		if hitSomething then
			character:SetAttribute("HitId", (character:GetAttribute("HitId") or 0) + 1)
			ctx.onChange()
		end
	end)
end

----------------------------------------------------------------------
-- 아이템
----------------------------------------------------------------------
local function rollItem()
	local sum = 0
	for _, id in ipairs(Config.ItemOrder) do
		sum += Config.Items[id].weight
	end
	local r = math.random() * sum
	for _, id in ipairs(Config.ItemOrder) do
		r -= Config.Items[id].weight
		if r <= 0 then
			return id
		end
	end
	return Config.ItemOrder[1]
end

local function explode(position, thrower)
	local fx = Instance.new("Explosion")
	fx.Position = position
	fx.BlastRadius = 0
	fx.BlastPressure = 0
	fx.DestroyJointRadiusPercent = 0
	fx.Parent = workspace
	local splash = Instance.new("Part")
	splash.Shape = Enum.PartType.Ball
	splash.Anchored = true
	splash.CanCollide = false
	splash.CanQuery = false
	splash.Material = Enum.Material.Glass
	splash.Color = Color3.fromRGB(120, 200, 255)
	splash.Transparency = 0.3
	splash.Size = Vector3.one * 2
	splash.Position = position
	splash.Parent = workspace
	TweenService:Create(splash, TweenInfo.new(0.35), { Size = Vector3.one * 28, Transparency = 1 }):Play()
	task.delay(0.4, function()
		splash:Destroy()
	end)
	for _, enemy in ipairs(enemiesOf(thrower)) do
		local er = rootOf(enemy)
		if er and (er.Position - position).Magnitude < 15 then
			local away = flat(er.Position - position)
			away = away.Magnitude > 0.1 and away.Unit or Vector3.new(1, 0, 0)
			stun(enemy, away * 60 + UP * 45, thrower)
		end
	end
	local mine = playerTeam[thrower]
	for i, t in pairs(teams) do
		if i ~= mine and not t.sunk and t.frozenUntil <= os.clock() and (t.ball.Position - position).Magnitude < 15 then
			local away = flat(t.ball.Position - position)
			away = away.Magnitude > 0.1 and away.Unit or Vector3.new(1, 0, 0)
			t.ball:SetAttribute("Resting", false)
			t.restTimer = 0
			t.lastHitter = thrower
			t.ball.AssemblyLinearVelocity += away * 55 + UP * 35
		end
	end
end

local function throwBomb(player)
	local root = rootOf(player)
	if not root then
		return
	end
	local look = flat(root.CFrame.LookVector).Unit
	local bomb = Instance.new("Part")
	bomb.Name = "WaterBomb"
	bomb.Shape = Enum.PartType.Ball
	bomb.Size = Vector3.one * 1.8
	bomb.Color = Color3.fromRGB(90, 180, 255)
	bomb.Material = Enum.Material.Glass
	bomb.CanCollide = false
	bomb.Position = root.Position + look * 3 + UP * 2
	bomb.Parent = workspace
	bomb.AssemblyLinearVelocity = look * 65 + UP * 32
	pcall(function()
		bomb:SetNetworkOwner(nil)
	end)
	task.spawn(function()
		local start = os.clock()
		while bomb.Parent and os.clock() - start < 1.8 do
			task.wait(0.05)
			if os.clock() - start > 0.2 and workspace:Raycast(bomb.Position, Vector3.new(0, -1.3, 0), rayParams) then
				break
			end
		end
		local pos = bomb.Position
		bomb:Destroy()
		explode(pos, player)
	end)
end

function Golf.UseItem(player)
	local index = playerTeam[player]
	local ps = pstate[player]
	if not (active and index and ps and ps.item) or ps.stunUntil > os.clock() then
		return
	end
	local item = ps.item
	ps.item = nil
	local _, humanoid = rootOf(player)

	if item == "Bomb" then
		throwBomb(player)
	elseif item == "Freeze" then
		for i, t in pairs(teams) do
			if i ~= index and not t.sunk then
				t.frozenUntil = os.clock() + 5
				stopBall(t.ball)
				t.ball.Anchored = true
				local ice = Instance.new("Part")
				ice.Size = Vector3.one * (B.diameter + 1.8)
				ice.CFrame = t.ball.CFrame
				ice.Anchored = true
				ice.CanCollide = false
				ice.Material = Enum.Material.Ice
				ice.Color = Color3.fromRGB(170, 220, 255)
				ice.Transparency = 0.4
				ice.Parent = ballsFolder
				task.delay(5, function()
					ice:Destroy()
					if t.ball.Parent and not t.sunk then
						t.ball.Anchored = false
						serverOwn(t.ball)
					end
				end)
				for _, m in ipairs(t.members) do
					ctx.notify(m, "🧊 우리 공이 5초 동안 얼었어요!", Color3.fromRGB(150, 210, 255))
				end
			end
		end
	elseif item == "Gust" then
		for _, enemy in ipairs(enemiesOf(player)) do
			local a = math.random() * math.pi * 2
			stun(enemy, Vector3.new(math.cos(a), 0, math.sin(a)) * 25 + UP * 75, player)
		end
	end
	ctx.notify(player, Config.Items[item].name .. " 사용!", Color3.fromRGB(255, 230, 120))
	ctx.onChange()
end

----------------------------------------------------------------------
-- 매 프레임
----------------------------------------------------------------------
----------------------------------------------------------------------
-- 대시 (Q)
----------------------------------------------------------------------
local DS = Config.Dash

function Golf.Dash(player, moveDir)
	local ps = pstate[player]
	local root, humanoid = rootOf(player)
	if not (active and ps and root and humanoid) then
		return
	end
	local now = os.clock()
	if now < ps.dashReady or ps.stunUntil > now then
		return
	end
	local dir = typeof(moveDir) == "Vector3" and flat(moveDir) or Vector3.zero
	if dir.Magnitude < 0.1 then
		dir = flat(root.CFrame.LookVector)
	end
	dir = dir.Unit
	ps.dashReady = now + DS.cooldown
	ps.dodgeUntil = now + DS.dodge
	setReady(player, "Dash", DS.cooldown)
	local inAir = humanoid.FloorMaterial == Enum.Material.Air
	local speed = DS.speed * (inAir and DS.airBonus or 1)
	local att = Instance.new("Attachment")
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = 1e6
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane -- 위아래는 그대로, 앞뒤좌우만 밀기
	lv.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	lv.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	lv.PlaneVelocity = Vector2.new(dir.X * speed, dir.Z * speed)
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = root
	task.delay(DS.duration, function()
		lv:Destroy()
		att:Destroy()
	end)
	if player.Character then
		bump(player.Character, "DashId") -- 잔상 효과
	end
end

----------------------------------------------------------------------
-- 스킬 (E)
----------------------------------------------------------------------
local function tackle(player, dir)
	local root = rootOf(player)
	if not root then
		return
	end
	local att = Instance.new("Attachment")
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = 1e6
	lv.VectorVelocity = dir * 85 + UP * 4
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = root
	local hit = {}
	task.spawn(function()
		local start = os.clock()
		while os.clock() - start < 0.32 do
			task.wait(0.03)
			local r = rootOf(player)
			if not r then
				break
			end
			for _, enemy in ipairs(enemiesOf(player)) do
				local er = rootOf(enemy)
				if er and not hit[enemy] and (er.Position - r.Position).Magnitude < 5 then
					hit[enemy] = true
					stun(enemy, dir * 70 + UP * 35, player)
				end
			end
		end
		lv:Destroy()
		att:Destroy()
	end)
	if player.Character then
		bump(player.Character, "DashId")
	end
end

local function recall(player)
	local index = playerTeam[player]
	local t = teams[index]
	local root = rootOf(player)
	if not (t and root) or t.sunk or t.frozenUntil > os.clock() then
		return false
	end
	local offset = flat(root.Position - t.ball.Position)
	if offset.Magnitude > 45 then
		ctx.notify(player, "🧲 우리 공이 너무 멀어요 (45 안)", Color3.fromRGB(255, 160, 160))
		return false
	end
	t.ball:SetAttribute("Resting", false)
	t.restTimer = 0
	local speed = math.min(offset.Magnitude * 1.6, 70)
	t.ball.AssemblyLinearVelocity = (offset.Magnitude > 0.1 and offset.Unit or Vector3.zero) * speed + UP * 22
	return true
end

local function bubble(player, ps)
	ps.bubbleUntil = os.clock() + 3
	local root = rootOf(player)
	if not root then
		return
	end
	local orb = Instance.new("Part")
	orb.Name = "Bubble"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.one * 8
	orb.Material = Enum.Material.ForceField
	orb.Color = Config.Skills.Bubble.color
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false
	orb.Massless = true
	orb.CFrame = root.CFrame
	local w = Instance.new("Weld")
	w.Part0 = root
	w.Part1 = orb
	w.Parent = orb
	orb.Parent = player.Character
	task.delay(3, function()
		orb:Destroy()
	end)
end

local function frostZone(player, dir)
	local root = rootOf(player)
	if not root then
		return
	end
	local center = flat(root.Position + dir * 14) + Vector3.new(0, root.Position.Y - 2.8, 0)
	local radius = 10
	local part = Instance.new("Part")
	part.Name = "FrostZone"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Size = Vector3.new(0.3, radius * 2, radius * 2)
	part.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	part.Material = Enum.Material.Ice
	part.Color = Config.Skills.FrostZone.color
	part.Transparency = 0.3
	part.Parent = ballsFolder
	table.insert(zones, { part = part, center = center, radius = radius, untilTime = os.clock() + 4, owner = player })
end

function Golf.UseSkill(player, aim)
	local ps = pstate[player]
	local root = rootOf(player)
	if not (active and ps and root) then
		return
	end
	local now = os.clock()
	if now < ps.skillReady or ps.stunUntil > now then
		return
	end
	local skillId = ctx.skillOf(player)
	local skill = Config.Skills[skillId]
	if not skill then
		return
	end
	local dir = typeof(aim) == "Vector3" and flat(aim) or Vector3.zero
	if dir.Magnitude < 0.1 then
		dir = flat(root.CFrame.LookVector)
	end
	dir = dir.Unit

	local ok = true
	if skillId == "Tackle" then
		tackle(player, dir)
	elseif skillId == "Recall" then
		ok = recall(player)
	elseif skillId == "Bubble" then
		bubble(player, ps)
	elseif skillId == "FrostZone" then
		frostZone(player, dir)
	elseif skillId == "PowerDrive" then
		ps.powerUntil = now + 5
		player:SetAttribute("Powered", true)
		task.delay(5, function()
			if ps.powerUntil <= os.clock() then
				player:SetAttribute("Powered", false)
			end
		end)
	end
	if ok then
		ps.skillReady = now + skill.cooldown
		setReady(player, "Skill", skill.cooldown)
		if player.Character then
			bump(player.Character, "SkillId")
		end
		ctx.notify(player, skill.name .. "!", skill.color)
		ctx.onChange()
	end
end

----------------------------------------------------------------------
-- 궁극기 (R): 게이지가 다 차면 켜고, 다음 스윙이 메테오 스윙
----------------------------------------------------------------------
function Golf.UseUltimate(player)
	local ps = pstate[player]
	if not (active and ps) or ps.gauge < UL.gaugeMax or ps.stunUntil > os.clock() then
		return
	end
	ps.gauge = 0
	player:SetAttribute("Gauge", 0)
	ps.ultUntil = os.clock() + UL.window
	player:SetAttribute("UltActive", true)
	ctx.notify(player, UL.name .. " 준비! " .. UL.window .. "초 안에 휘둘러요!", Color3.fromRGB(255, 200, 80))
	task.delay(UL.window, function()
		if ps.ultUntil > 0 and ps.ultUntil <= os.clock() then
			ps.ultUntil = 0
			player:SetAttribute("UltActive", false)
		end
	end)
end

local function resetBall(t, message)
	stopBall(t.ball)
	t.ball.CFrame = CFrame.new(t.lastSafe + UP * 1.5)
	for _, m in ipairs(t.members) do
		ctx.notify(m, message, Color3.fromRGB(255, 160, 140))
	end
end

local function sink(index, t)
	t.sunk = true
	winner = winner or index
	local ball = t.ball
	ball.Anchored = true
	TweenService:Create(ball, TweenInfo.new(0.35), { Position = hole.cup - UP * 1.5, Transparency = 1 }):Play()
	local team = Config.Teams[index]
	local hitter = t.lastHitter
	ctx.onSunk(index, hitter)
	if hitter and playerTeam[hitter] ~= index then
		ctx.announce(string.format("😱 %s 님이 상대 공을 넣어 줬어요! %s 홀인!", hitter.DisplayName, team.name), 4)
	else
		ctx.announce(string.format("⛳ %s 홀인!%s", team.name, hitter and (" (" .. hitter.DisplayName .. ")") or ""), 4)
	end
	ctx.onChange()
end

local gaugeTimer = 0
local function tickZones()
	local now = os.clock()
	for i = #zones, 1, -1 do
		local z = zones[i]
		if now > z.untilTime or not z.part.Parent then
			z.part:Destroy()
			table.remove(zones, i)
		else
			-- 상대 선수 느리게
			for _, enemy in ipairs(enemiesOf(z.owner)) do
				local er, eh = rootOf(enemy)
				local eps = pstate[enemy]
				if er and eh and eps and flat(er.Position - z.center).Magnitude < z.radius then
					eps.slowUntil = now + 0.3
					eh.WalkSpeed = CL.walkSpeed * 0.45
				end
			end
			-- 구역 안의 공은 금방 멈춤
			for _, t in pairs(teams) do
				if not t.sunk and not t.ball.Anchored and flat(t.ball.Position - z.center).Magnitude < z.radius then
					local v = t.ball.AssemblyLinearVelocity
					t.ball.AssemblyLinearVelocity = Vector3.new(v.X * 0.7, v.Y, v.Z * 0.7)
				end
			end
		end
	end
	-- 느려짐 풀기
	for p, ps in pairs(pstate) do
		if ps.slowUntil > 0 and ps.slowUntil < now then
			ps.slowUntil = 0
			local _, h = rootOf(p)
			if h then
				h.WalkSpeed = CL.walkSpeed
			end
		end
	end
end

local function tick(dt)
	local changed = false
	tickZones()
	gaugeTimer += dt
	if gaugeTimer >= 1 then
		gaugeTimer -= 1
		for p in pairs(playerTeam) do
			addGauge(p, UL.perSecond)
		end
	end

	for index, t in pairs(teams) do
		local ball = t.ball
		if t.sunk or not ball.Parent or ball.Anchored then
			continue
		end
		local pos = ball.Position
		if pos.Y < -20 then
			resetBall(t, "💨 우리 공이 코스 밖으로! 마지막 자리로 돌아와요")
			changed = true
			continue
		end
		-- 땅에 묻힘 방지: 위에서 바닥을 재서 공 아랫면이 바닥보다 내려가 있으면 바닥 위로 올림
		-- (빠른 공이 지형 표면을 살짝 뚫고 들어가 그대로 갇히는 문제)
		do
			local r = B.diameter / 2
			local top = workspace:Raycast(pos + UP * 40, -UP * 80, groundParams)
			if top and top.Position.Y - (pos.Y - r) > 0.25 then
				local v0 = ball.AssemblyLinearVelocity
				ball.CFrame = CFrame.new(Vector3.new(pos.X, top.Position.Y + r + 0.05, pos.Z)) * ball.CFrame.Rotation
				ball.AssemblyLinearVelocity = Vector3.new(v0.X, v0.Y < 0 and -v0.Y * 0.3 or v0.Y, v0.Z)
				pos = ball.Position
			end
		end
		local surface = surfaceUnder(ball)
		if surface == "Water" then
			resetBall(t, "💦 풍덩! 우리 공이 연못에 빠졌어요")
			changed = true
			continue
		end
		local v = ball.AssemblyLinearVelocity
		if surface then
			local drag = B.drag[surface] or B.drag.Rough
			local factor = drag ^ (dt / 0.1)
			ball.AssemblyLinearVelocity = Vector3.new(v.X * factor, v.Y, v.Z * factor)
			ball.AssemblyAngularVelocity *= factor
		end

		-- 날아가는 공에 상대 선수가 맞으면 넘어짐 (친 사람의 상대 팀만, 샷마다 한 번)
		if t.lastHitter and t.bonked and v.Magnitude > B.bonkSpeed and os.clock() - (t.launchedAt or 0) > 0.08 then
			for _, enemy in ipairs(enemiesOf(t.lastHitter)) do
				local er = rootOf(enemy)
				if er and not t.bonked[enemy] and (er.Position - pos).Magnitude < B.bonkRadius then
					t.bonked[enemy] = true
					local push = Vector3.new(v.X, 0, v.Z)
					push = push.Magnitude > 0.1 and push.Unit or UP
					if stun(enemy, push * (25 + v.Magnitude * 0.4) + UP * 28, t.lastHitter) then
						ctx.notify(t.lastHitter, "🎯 공으로 " .. enemy.DisplayName .. " 님을 맞혔어요!", Color3.fromRGB(255, 220, 120))
						-- 맞은 공은 힘이 꺾여 튕김
						ball.AssemblyLinearVelocity = Vector3.new(-v.X * 0.25, math.abs(v.Y) * 0.3 + 6, -v.Z * 0.25)
						v = ball.AssemblyLinearVelocity
					end
				end
			end
		end

		-- 홀인: 홀컵 위에서 너무 빠르지 않으면 쏙
		local cupDist = flat(hole.cup - pos).Magnitude
		if cupDist < B.cupRadius and pos.Y < 2.6 and v.Magnitude < B.cupMaxSpeed then
			sink(index, t)
			continue
		end

		-- 멈춤 (느리게 끝없이 구르는 것 방지) + 안전한 위치 기억
		if surface and v.Magnitude < B.stopSpeed then
			t.restTimer += dt
			if t.restTimer > 0.3 then
				stopBall(ball)
				t.lastSafe = pos
			end
		else
			t.restTimer = 0
		end
	end

	-- 선수: 아이템 상자 줍기, 코스 밖으로 떨어지면 팀 공 옆으로
	for player in pairs(playerTeam) do
		local ps = pstate[player]
		local root = rootOf(player)
		if ps and root then
			if root.Position.Y < -25 then
				Golf.PlacePlayer(player, nil)
			elseif not ps.item then
				for _, box in ipairs(hole.boxes) do
					if box:GetAttribute("Active") and (box.Position - root.Position).Magnitude < 4.5 then
						ps.item = rollItem()
						box:SetAttribute("Active", false)
						box.Transparency = 1
						local gui = box:FindFirstChildOfClass("BillboardGui")
						if gui then
							gui.Enabled = false
						end
						task.delay(Config.Course.itemBoxRespawn, function()
							if box.Parent then
								box:SetAttribute("Active", true)
								box.Transparency = 0.15
								if gui then
									gui.Enabled = true
								end
							end
						end)
						ctx.notify(player, "❓ " .. Config.Items[ps.item].name .. " 획득! (E 키 / 아이템 버튼)", Color3.fromRGB(255, 220, 90))
						changed = true
						break
					end
				end
			end
		end
	end
	if changed then
		ctx.onChange()
	end
end

-- 충돌 그룹: 공은 선수 몸(골프채 포함)을 그냥 통과 → 걸어가다 몸에 닿아 공이 밀리는 일 없음
-- (공으로 사람 맞히기 · 골프채 타격은 충돌이 아니라 거리로 판정하므로 그대로 동작)
local function setupCollisionGroups()
	pcall(function()
		PhysicsService:RegisterCollisionGroup("GolfBall")
		PhysicsService:RegisterCollisionGroup("GolfPlayer")
	end)
	PhysicsService:CollisionGroupSetCollidable("GolfBall", "GolfPlayer", false)
	PhysicsService:CollisionGroupSetCollidable("GolfBall", "GolfBall", true)
	local function tag(part)
		if part:IsA("BasePart") then
			part.CollisionGroup = "GolfPlayer"
		end
	end
	local function onCharacter(character)
		for _, d in ipairs(character:GetDescendants()) do
			tag(d)
		end
		character.DescendantAdded:Connect(tag) -- 나중에 붙는 골프채·모자·레그돌 부품도
	end
	local function onPlayer(player)
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			onCharacter(player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
end

function Golf.Start(context)
	ctx = context
	setupCollisionGroups()
	ballsFolder = Instance.new("Folder")
	ballsFolder.Name = "Balls"
	ballsFolder.Parent = workspace
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.05)
			local now = os.clock()
			local dt = now - last
			last = now
			if active and hole then
				tick(dt)
			end
		end
	end)
	Players.PlayerRemoving:Connect(Golf.RemovePlayer)
end

return Golf
