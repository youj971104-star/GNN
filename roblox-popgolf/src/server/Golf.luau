-- 2대2 팀 배틀 골프의 핵심 규칙
-- * 팀마다 공 하나. 팀원 누구든 공 옆(Club.shotRange)에서 꾹 눌러 샷
-- * 짧게 클릭하면 골프채 휘두르기: 앞의 상대 선수는 넘어지고, 상대 공은 쳐 내짐
-- * ❓ 상자 아이템으로 방해
-- * 먼저 홀컵에 넣은 팀이 홀 승리. 시간이 끝나면 홀컵에 더 가까운 팀 승리
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
local teams = {} -- [teamIndex] = { members = {Player}, ball = Part, strokes, sunk, lastRest, restTimer, frozenUntil }
local playerTeam = {} -- [Player] = teamIndex
local pstate = {} -- [Player] = { stunUntil, shieldUntil, item, lastSwing, lastShot, dashUntil }
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

local function grounded(ball)
	return workspace:Raycast(ball.Position, Vector3.new(0, -(B.diameter / 2 + 0.6), 0), rayParams) ~= nil
end

local function stopBall(ball)
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
end

-- 선수 캐릭터는 각자 컴퓨터가 물리를 담당하므로, 서버에서 날릴 땐 잠깐 힘(LinearVelocity)을 붙임
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
	ball.CustomPhysicalProperties = PhysicalProperties.new(2, 0.35, 0.45, 1, 1)
	ball.Anchored = true
	ball:SetAttribute("Team", index)
	ball:SetAttribute("Resting", true)

	-- 벽 너머에서도 보이는 팀 색 테두리 + 이름표
	local hl = Instance.new("Highlight")
	hl.FillTransparency = 0.6
	hl.FillColor = team.color
	hl.OutlineColor = Color3.new(1, 1, 1)
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = ball
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(110, 28)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
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

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.6, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.6, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.4
	trail.Color = ColorSequence.new(team.color)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Parent = ball

	ball.Parent = ballsFolder
	return ball
end

----------------------------------------------------------------------
-- 홀 시작 / 끝
----------------------------------------------------------------------
-- teamLists = { {Player, Player}, {Player, Player} }
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
			strokes = 0,
			sunk = false,
			lastRest = pos,
			restTimer = 0,
			frozenUntil = 0,
		}
		for slot, p in ipairs(members) do
			playerTeam[p] = index
			pstate[p] = { stunUntil = 0, shieldUntil = 0, item = nil, lastSwing = 0, lastShot = 0, dashUntil = 0 }
			Golf.PlacePlayer(p, slot)
		end
	end
end

-- 홀 시작 / 리스폰 때 우리 팀 공 근처로
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
		cf = ctx.playerStart(hole, index, #teams, slot)
	else
		local ball = teams[index].ball
		cf = CFrame.new(ball.Position + UP * 4 + Vector3.new(math.random(-3, 3), 0, math.random(-3, 3)))
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

-- 홀 승리 팀 (먼저 넣은 팀, 아니면 홀컵에 더 가까운 팀)
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

function Golf.TeamOf(player)
	return playerTeam[player]
end

function Golf.Snapshot()
	local teamInfo = {}
	for index, t in pairs(teams) do
		teamInfo[index] = {
			strokes = t.strokes,
			sunk = t.sunk,
			frozen = t.frozenUntil > os.clock(),
			dist = hole and math.floor(flat(t.ball.Position - hole.cup).Magnitude) or 0,
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
	return { teams = teamInfo, players = players }
end

----------------------------------------------------------------------
-- 샷 (우리 팀 공 옆에서 꾹 눌렀다 떼기)
----------------------------------------------------------------------
function Golf.Shoot(player, direction, power)
	local index = playerTeam[player]
	local ps = pstate[player]
	local t = index and teams[index]
	if not (active and t and ps) or t.sunk then
		return
	end
	if typeof(direction) ~= "Vector3" or type(power) ~= "number" or power ~= power then
		return
	end
	if ps.stunUntil > os.clock() or os.clock() - ps.lastShot < 0.5 then
		return
	end
	if not t.ball:GetAttribute("Resting") or t.frozenUntil > os.clock() then
		return
	end
	local root = rootOf(player)
	if not root or (root.Position - t.ball.Position).Magnitude > CL.shotRange + 1 then
		return
	end
	local dir = flat(direction)
	if dir.Magnitude < 0.01 then
		return
	end
	dir = dir.Unit
	power = math.clamp(power, 0.05, 1)
	local speed = B.maxShotSpeed * power
	ps.lastShot = os.clock()
	t.lastRest = t.ball.Position
	t.strokes += 1
	t.restTimer = 0
	t.ball:SetAttribute("Resting", false)
	t.ball.AssemblyLinearVelocity = dir * speed + UP * speed * B.loft
	ctx.swingVisual(player)
	ctx.onChange()
end

----------------------------------------------------------------------
-- 휘두르기 (짧게 클릭)
----------------------------------------------------------------------
function Golf.Swing(player)
	local index = playerTeam[player]
	local ps = pstate[player]
	if not (active and index and ps) then
		return
	end
	local now = os.clock()
	if ps.stunUntil > now or now - ps.lastSwing < CL.swingCooldown then
		return
	end
	ps.lastSwing = now
	local root = rootOf(player)
	if not root then
		return
	end
	ctx.swingVisual(player)
	local look = flat(root.CFrame.LookVector).Unit
	local origin = root.Position

	-- 앞의 상대 선수
	for _, enemy in ipairs(enemiesOf(player)) do
		local er = rootOf(enemy)
		if er then
			local offset = er.Position - origin
			if offset.Magnitude <= CL.swingRange and flat(offset).Unit:Dot(look) > 0.2 then
				stun(enemy, look * CL.knockback + UP * 30, player)
			end
		end
	end
	-- 앞의 상대 공 (상대 타수는 안 늘어남)
	for i, t in pairs(teams) do
		if i ~= index and not t.sunk and t.frozenUntil <= now then
			local offset = t.ball.Position - origin
			if offset.Magnitude <= CL.swingRange and flat(offset).Magnitude > 0.1 and flat(offset).Unit:Dot(look) > 0.1 then
				t.ball:SetAttribute("Resting", false)
				t.restTimer = 0
				t.ball.AssemblyLinearVelocity = look * CL.enemyBallHit + UP * 8
				ctx.notify(player, "🏌️ 상대 공을 쳐 냈어요!", Color3.fromRGB(255, 230, 120))
			end
		end
	end
	ctx.onChange()
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
	fx.BlastRadius = 0 -- 연출만 (실제 힘은 아래에서 직접)
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
	TweenService:Create(splash, TweenInfo.new(0.35), { Size = Vector3.one * 26, Transparency = 1 }):Play()
	task.delay(0.4, function()
		splash:Destroy()
	end)

	for _, enemy in ipairs(enemiesOf(thrower)) do
		local er = rootOf(enemy)
		if er and (er.Position - position).Magnitude < 14 then
			local away = flat(er.Position - position)
			away = away.Magnitude > 0.1 and away.Unit or Vector3.new(1, 0, 0)
			stun(enemy, away * 60 + UP * 45, thrower)
		end
	end
	local mine = playerTeam[thrower]
	for i, t in pairs(teams) do
		if i ~= mine and not t.sunk and t.frozenUntil <= os.clock() and (t.ball.Position - position).Magnitude < 14 then
			local away = flat(t.ball.Position - position)
			away = away.Magnitude > 0.1 and away.Unit or Vector3.new(1, 0, 0)
			t.ball:SetAttribute("Resting", false)
			t.restTimer = 0
			t.ball.AssemblyLinearVelocity += away * 60 + UP * 20
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
	bomb.Size = Vector3.one * 1.6
	bomb.Color = Color3.fromRGB(90, 180, 255)
	bomb.Material = Enum.Material.Glass
	bomb.CanCollide = false
	bomb.Position = root.Position + look * 3 + UP * 2
	bomb.Parent = workspace
	bomb.AssemblyLinearVelocity = look * 55 + UP * 28
	pcall(function()
		bomb:SetNetworkOwner(nil)
	end)
	task.spawn(function()
		local start = os.clock()
		while bomb.Parent and os.clock() - start < 1.6 do
			task.wait(0.05)
			local hit = workspace:Raycast(bomb.Position, Vector3.new(0, -1.2, 0), rayParams)
			if hit and os.clock() - start > 0.2 then
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
				ice.Size = Vector3.one * (B.diameter + 1.6)
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
			humanoid.WalkSpeed = 32
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
local function sink(index, t)
	t.sunk = true
	winner = winner or index
	local ball = t.ball
	ball.Anchored = true
	ball:SetAttribute("Resting", true)
	TweenService:Create(ball, TweenInfo.new(0.35), { Position = hole.cup - UP * 1.5, Transparency = 1 }):Play()
	local team = Config.Teams[index]
	ctx.onSunk(index, t.strokes)
	if t.strokes == 1 then
		ctx.announce("🎉 홀인원!! " .. team.name .. " 🎉", 4)
	else
		ctx.announce(string.format("⛳ %s 홀인! (%d타)", team.name, t.strokes), 3)
	end
	ctx.onChange()
end

local function tick(dt)
	local now = os.clock()
	local factor = B.rollingDrag ^ (dt / 0.1)
	local changed = false

	for index, t in pairs(teams) do
		local ball = t.ball
		if t.sunk or not ball.Parent or ball.Anchored then
			continue
		end
		local pos = ball.Position
		if pos.Y < -15 then
			stopBall(ball)
			ball.CFrame = CFrame.new(t.lastRest + UP * 1)
			t.strokes += 1
			ball:SetAttribute("Resting", true)
			for _, m in ipairs(t.members) do
				ctx.notify(m, "💦 우리 공 장외! 벌타 +1", Color3.fromRGB(255, 140, 140))
			end
			changed = true
			continue
		end
		local v = ball.AssemblyLinearVelocity
		local onGround = grounded(ball)
		if onGround then
			ball.AssemblyLinearVelocity = Vector3.new(v.X * factor, v.Y, v.Z * factor)
			ball.AssemblyAngularVelocity *= factor
		end
		local cupDist = flat(hole.cup - pos).Magnitude
		if cupDist < B.cupRadius and pos.Y < 3.5 and v.Magnitude < B.cupMaxSpeed then
			sink(index, t)
			continue
		end
		if onGround and v.Magnitude < B.stopSpeed then
			t.restTimer += dt
			if t.restTimer > 0.3 and not ball:GetAttribute("Resting") then
				stopBall(ball)
				ball:SetAttribute("Resting", true)
				changed = true
			end
		else
			t.restTimer = 0
			if ball:GetAttribute("Resting") and v.Magnitude > B.stopSpeed * 2 then
				ball:SetAttribute("Resting", false)
			end
		end
		for _, b in ipairs(hole.boosters) do
			local rel = b.part.CFrame:PointToObjectSpace(pos)
			if math.abs(rel.X) < 3.2 and math.abs(rel.Z) < 4.2 and rel.Y < 2 and (t.boostedAt or 0) < now - 0.6 then
				t.boostedAt = now
				ball.AssemblyLinearVelocity += b.dir * 45
				ball:SetAttribute("Resting", false)
			end
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
