-- 2대2 팀 배틀 골프 규칙 (휘두르기 하나로 공치기 + 사람 치기)
-- * 꾹 누르면 힘을 모으고, 떼면 휘두름 → 몸 앞의 공(어느 팀 공이든)은 날아가고, 상대 선수는 넘어짐
-- * 공은 포물선으로 날아가고, 그린 위에서는 굴리는 퍼팅
-- * 타수 없음! 우리 공을 먼저 홀컵에 넣는 팀이 홀 승리 (상대 공을 쳐서 멀리 보내는 것도 작전)
-- * 시간이 끝나면 우리 공이 홀컵에 더 가까운 팀 승리
-- 모든 판정은 서버에서 합니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local Golf = {}

local UP = Vector3.new(0, 1, 0)
local B = Config.Ball
local CL = Config.Club

local ctx
local hole
local teams = {} -- [teamIndex] = { members, ball, sunk, lastSafe, restTimer, frozenUntil, lastHitter }
local playerTeam = {} -- [Player] = teamIndex
local pstate = {} -- [Player] = { stunUntil, shieldUntil, item, lastSwing, dashUntil }
local winner = nil
local active = false
local ballsFolder

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

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
local function surfaceUnder(ball)
	local hit = workspace:Raycast(ball.Position, Vector3.new(0, -(B.diameter / 2 + 0.7), 0), rayParams)
	return hit and hit.Instance.Name or nil
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

local function stun(player, velocity, by)
	local ps = pstate[player]
	local root, humanoid = rootOf(player)
	if not (ps and root and humanoid) then
		return false
	end
	if ps.shieldUntil > os.clock() then
		ctx.notify(player, "🛡️ 방패가 막아 줬어요!", Color3.fromRGB(140, 220, 255))
		return false
	end
	ps.stunUntil = os.clock() + CL.stunTime
	humanoid.PlatformStand = true
	fling(player, velocity)
	player:SetAttribute("Stunned", true)
	task.delay(CL.stunTime, function()
		if ps.stunUntil <= os.clock() + 0.05 then
			local _, h = rootOf(player)
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
	rayParams.FilterDescendantsInstances = { hole.folder }

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
			pstate[p] = { stunUntil = 0, shieldUntil = 0, item = nil, lastSwing = 0, dashUntil = 0 }
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
		pcall(function()
			t.ball:SetNetworkOwner(nil)
		end)
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
			shield = ps and ps.shieldUntil > os.clock(),
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

local function launchBall(t, dir, power, hitter)
	local pos = t.ball.Position
	local speed = B.maxSpeed * math.max(power, CL.minPower)
	local angle = B.launchAngle
	if onGreen(pos) then
		speed *= B.puttPower
		angle = B.puttAngle
	end
	local rad = math.rad(angle)
	t.ball:SetAttribute("Resting", false)
	t.restTimer = 0
	t.lastHitter = hitter
	t.ball.AssemblyLinearVelocity = dir * (math.cos(rad) * speed) + UP * (math.sin(rad) * speed)
	t.ball.AssemblyAngularVelocity = Vector3.new(dir.Z, 0, -dir.X) * -speed * 0.3 -- 앞으로 구르는 회전
end

function Golf.Swing(player, direction, power)
	local index = playerTeam[player]
	local ps = pstate[player]
	local character = player.Character
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
		-- 선수는 목표(dir)를 왼쪽에 두고 옆으로 섬 → 얼굴 방향 = dir × 위
		local facing = dir:Cross(UP)
		local zone = origin + facing * CL.stanceOffset

		-- 공 (우리 팀 공이든 상대 팀 공이든): 발 앞 스윙 존 안에 있으면 목표 방향으로 날아감
		for _, t in pairs(teams) do
			if not t.sunk and t.frozenUntil <= os.clock() then
				local pos = t.ball.Position
				local inZone = flat(pos - zone).Magnitude <= CL.ballZone or flat(pos - origin).Magnitude <= 2.2
				if inZone and math.abs(pos.Y - origin.Y) < 5 then
					launchBall(t, dir, power, player)
					hitSomething = true
				end
			end
		end

		-- 상대 선수: 골프채가 크게 도는 반경 안이면 맞음 (목표 방향으로 날아감)
		for _, enemy in ipairs(enemiesOf(player)) do
			local er = rootOf(enemy)
			if er then
				local offset = er.Position - origin
				if flat(offset).Magnitude <= CL.reach and math.abs(offset.Y) < 6 then
					local k = CL.knockback * (0.6 + power)
					stun(enemy, dir * k + UP * (20 + 25 * power), player)
					hitSomething = true
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
					end
				end)
				for _, m in ipairs(t.members) do
					ctx.notify(m, "🧊 우리 공이 5초 동안 얼었어요!", Color3.fromRGB(150, 210, 255))
				end
			end
		end
	elseif item == "Dash" then
		ps.dashUntil = os.clock() + 6
		if humanoid then
			humanoid.WalkSpeed = 40
		end
		task.delay(6, function()
			local _, h = rootOf(player)
			if h and pstate[player] and pstate[player].dashUntil <= os.clock() + 0.05 then
				h.WalkSpeed = CL.walkSpeed
			end
		end)
	elseif item == "Shield" then
		ps.shieldUntil = os.clock() + 8
		local character = player.Character
		if character then
			local ff = Instance.new("ForceField")
			ff.Visible = true
			ff.Parent = character
			task.delay(8, function()
				ff:Destroy()
			end)
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

local function tick(dt)
	local changed = false

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

function Golf.Start(context)
	ctx = context
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
