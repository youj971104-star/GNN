-- 공, 샷, 홀인 판정, 배틀 아이템
-- 모든 판정은 서버가 합니다. 클라이언트는 "이 방향, 이 세기로 쳐 주세요"만 보냅니다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local Golf = {}

local UP = Vector3.new(0, 1, 0)
local B = Config.Ball

local ctx
local hole -- CourseBuilder 가 만든 현재 홀
local states = {} -- [Player] = 공 상태
local finishOrder = {}
local active = false
local ballsFolder

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

----------------------------------------------------------------------
-- 공 만들기 (스킨 적용)
----------------------------------------------------------------------
local function applySkin(ball, skinId)
	local skin = Config.Skins[skinId] or Config.Skins.White
	ball.Color = skin.color
	ball.Material = Enum.Material[skin.material] or Enum.Material.SmoothPlastic
	if skin.trail then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.6, 0)
		a0.Parent = ball
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.6, 0)
		a1.Parent = ball
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.5
		trail.LightEmission = 0.6
		trail.Transparency = NumberSequence.new(0.1, 1)
		local kps = {}
		for i, c in ipairs(skin.trail) do
			table.insert(kps, ColorSequenceKeypoint.new((i - 1) / math.max(1, #skin.trail - 1), c))
		end
		trail.Color = ColorSequence.new(kps)
		trail.Parent = ball
	end
	if skin.effect == "Sparkles" then
		local s = Instance.new("Sparkles")
		s.SparkleColor = skin.color
		s.Parent = ball
	elseif skin.effect == "Fire" then
		local f = Instance.new("Fire")
		f.Size = 2
		f.Heat = 2
		f.Color = skin.color
		f.Parent = ball
	elseif skin.effect == "Smoke" then
		local sm = Instance.new("Smoke")
		sm.Size = 0.6
		sm.Opacity = 0.15
		sm.RiseVelocity = 1
		sm.Parent = ball
	elseif skin.effect == "Light" then
		local l = Instance.new("PointLight")
		l.Color = skin.color
		l.Range = 10
		l.Brightness = 2
		l.Parent = ball
	end
end

local function makeBall(player, position, skinId)
	local ball = Instance.new("Part")
	ball.Name = tostring(player.UserId)
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * B.diameter
	ball.Position = position
	ball.CustomPhysicalProperties = PhysicalProperties.new(2, 0.35, 0.45, 1, 1)
	ball.Anchored = true -- 카운트다운 동안 고정
	ball:SetAttribute("Owner", player.UserId)
	ball:SetAttribute("Resting", true)
	applySkin(ball, skinId)

	-- 공 위 이름표
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 26)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = player.DisplayName
	label.Parent = gui
	gui.Parent = ball

	ball.Parent = ballsFolder
	return ball
end

local function speedOf(ball)
	return ball.AssemblyLinearVelocity.Magnitude
end

local function grounded(ball)
	local result = workspace:Raycast(ball.Position, Vector3.new(0, -(B.diameter / 2 + 0.6), 0), rayParams)
	return result ~= nil
end

local function stop(ball)
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
end

----------------------------------------------------------------------
-- 홀 시작 / 끝
----------------------------------------------------------------------
function Golf.BeginHole(newHole, players, skinOf)
	hole = newHole
	states = {}
	finishOrder = {}
	active = false
	ballsFolder:ClearAllChildren()
	rayParams.FilterDescendantsInstances = { hole.folder }

	for i, player in ipairs(players) do
		local pos = ctx.teePosition(hole, i, #players)
		local ball = makeBall(player, pos, skinOf(player))
		states[player] = {
			ball = ball,
			strokes = 0,
			sunk = false,
			lastRest = pos,
			restTimer = 0,
			lastShot = 0,
			item = nil,
			frozenUntil = 0,
			superShot = false,
			magnetUntil = 0,
		}
	end
end

-- 카운트다운이 끝나면 공을 풀어 줌
function Golf.Go()
	active = true
	for _, s in pairs(states) do
		s.ball.Anchored = false
		pcall(function()
			s.ball:SetNetworkOwner(nil) -- 서버가 물리 담당 (조작 방지)
		end)
	end
end

function Golf.EndHole()
	active = false
	local results = {}
	for player, s in pairs(states) do
		local place = table.find(finishOrder, player)
		table.insert(results, {
			player = player,
			strokes = s.strokes,
			place = place,
			points = place and (Config.PlacePoints[place] or 1) or 0,
		})
	end
	table.sort(results, function(a, b)
		if (a.place ~= nil) ~= (b.place ~= nil) then
			return a.place ~= nil
		end
		if a.place and b.place then
			return a.place < b.place
		end
		return a.strokes < b.strokes
	end)
	return results
end

function Golf.Clear()
	active = false
	states = {}
	if ballsFolder then
		ballsFolder:ClearAllChildren()
	end
end

function Golf.RemovePlayer(player)
	local s = states[player]
	if s then
		s.ball:Destroy()
		states[player] = nil
	end
end

-- 모두 넣었거나 기권했는가
function Golf.AllDone()
	for _, s in pairs(states) do
		if not s.sunk and s.strokes < Config.MaxStrokes then
			return false
		end
		if not s.sunk and s.strokes >= Config.MaxStrokes and not s.ball:GetAttribute("Resting") then
			return false -- 마지막 샷이 아직 굴러가는 중
		end
	end
	return true
end

-- 화면 표시용 요약
function Golf.Snapshot()
	local list = {}
	for player, s in pairs(states) do
		table.insert(list, {
			userId = player.UserId,
			name = player.DisplayName,
			strokes = s.strokes,
			sunk = s.sunk,
			place = table.find(finishOrder, player),
			item = s.item,
			frozen = s.frozenUntil > os.clock(),
			super = s.superShot,
			magnet = s.magnetUntil > os.clock(),
		})
	end
	return list
end

function Golf.IsPlaying(player)
	return states[player] ~= nil
end

----------------------------------------------------------------------
-- 샷
----------------------------------------------------------------------
function Golf.Shoot(player, direction, power)
	local s = states[player]
	if not (active and s) or s.sunk then
		return
	end
	if typeof(direction) ~= "Vector3" or type(power) ~= "number" or power ~= power then
		return
	end
	if not s.ball:GetAttribute("Resting") or s.frozenUntil > os.clock() then
		return
	end
	if s.strokes >= Config.MaxStrokes or os.clock() - s.lastShot < 0.4 then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 then
		return
	end
	flat = flat.Unit
	power = math.clamp(power, 0.05, 1)
	local speed = B.maxShotSpeed * power
	if s.superShot then
		speed *= 1.6
		s.superShot = false
	end
	s.lastRest = s.ball.Position
	s.lastShot = os.clock()
	s.strokes += 1
	s.restTimer = 0
	s.ball:SetAttribute("Resting", false)
	s.ball.AssemblyLinearVelocity = flat * speed + UP * speed * B.loft
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

local function push(target, velocity)
	if target.sunk or target.frozenUntil > os.clock() then
		return
	end
	target.ball:SetAttribute("Resting", false)
	target.restTimer = 0
	target.ball.AssemblyLinearVelocity += velocity
end

local function freezeVisual(target, seconds)
	local ice = Instance.new("Part")
	ice.Name = "Ice"
	ice.Size = Vector3.one * (B.diameter + 1.2)
	ice.CFrame = target.ball.CFrame
	ice.Anchored = true
	ice.CanCollide = false
	ice.Material = Enum.Material.Ice
	ice.Color = Color3.fromRGB(170, 220, 255)
	ice.Transparency = 0.4
	ice.Parent = ballsFolder
	target.ball.Anchored = true
	task.delay(seconds, function()
		ice:Destroy()
		if target.ball.Parent and not target.sunk then
			target.ball.Anchored = false
		end
	end)
end

function Golf.UseItem(player)
	local s = states[player]
	if not (active and s and s.item) or s.sunk then
		return
	end
	local item = s.item
	s.item = nil
	local myPos = s.ball.Position

	if item == "Bomb" then
		for other, o in pairs(states) do
			if other ~= player then
				local offset = o.ball.Position - myPos
				if offset.Magnitude < 25 then
					local away = Vector3.new(offset.X, 0, offset.Z)
					away = away.Magnitude > 0.1 and away.Unit or Vector3.new(1, 0, 0)
					push(o, away * 70 + UP * 25)
					ctx.notify(other, "💣 " .. player.DisplayName .. " 님의 폭탄!", Color3.fromRGB(255, 140, 90))
				end
			end
		end
		local boom = Instance.new("Explosion")
		boom.Position = myPos
		boom.BlastRadius = 0 -- 연출만 (실제 힘은 위에서 직접 줌)
		boom.BlastPressure = 0
		boom.DestroyJointRadiusPercent = 0
		boom.Parent = workspace
	elseif item == "Freeze" then
		-- 홀컵에 가장 가까운 상대
		local best, bestDist = nil, math.huge
		for other, o in pairs(states) do
			if other ~= player and not o.sunk then
				local d = (o.ball.Position - hole.cup).Magnitude
				if d < bestDist then
					best, bestDist = other, d
				end
			end
		end
		if best then
			local o = states[best]
			o.frozenUntil = os.clock() + 4
			freezeVisual(o, 4)
			ctx.notify(best, "🧊 " .. player.DisplayName .. " 님이 공을 얼렸어요! (4초)", Color3.fromRGB(150, 210, 255))
		end
	elseif item == "Super" then
		s.superShot = true
	elseif item == "Magnet" then
		s.magnetUntil = os.clock() + 8
	elseif item == "Twister" then
		for other, o in pairs(states) do
			if other ~= player then
				local a = math.random() * math.pi * 2
				push(o, Vector3.new(math.cos(a), 0, math.sin(a)) * 55 + UP * 20)
				ctx.notify(other, "🌀 " .. player.DisplayName .. " 님의 회오리!", Color3.fromRGB(200, 160, 255))
			end
		end
	end
	ctx.notify(player, Config.Items[item].name .. " 사용!", Color3.fromRGB(255, 230, 120))
	ctx.onChange()
end

----------------------------------------------------------------------
-- 매 프레임 처리: 굴러가는 저항, 멈춤, 장외, 홀인, 상자, 가속 발판, 자석
----------------------------------------------------------------------
local function sink(player, s)
	s.sunk = true
	table.insert(finishOrder, player)
	local ball = s.ball
	ball.Anchored = true
	ball:SetAttribute("Resting", true)
	TweenService:Create(ball, TweenInfo.new(0.35), { Position = hole.cup - UP * 1.5, Transparency = 1 }):Play()
	local place = #finishOrder
	if s.strokes == 1 then
		ctx.announce("🎉 홀인원!! " .. player.DisplayName .. " 🎉", 4)
		ctx.onHoleInOne(player)
	else
		ctx.announce(string.format("⛳ %s 님 홀인! (%d타 · %d등)", player.DisplayName, s.strokes, place), 2.5)
	end
	ctx.onChange()
end

local function tick(dt)
	local now = os.clock()
	local factor = B.rollingDrag ^ (dt / 0.1)
	local changed = false
	for player, s in pairs(states) do
		local ball = s.ball
		if s.sunk or not ball.Parent or ball.Anchored then
			continue
		end
		local pos = ball.Position

		-- 장외(바닥 밖으로 떨어짐) → 마지막 친 자리로, 벌타 +1
		if pos.Y < -15 then
			stop(ball)
			ball.CFrame = CFrame.new(s.lastRest + UP * 1)
			s.strokes += 1
			ball:SetAttribute("Resting", true)
			ctx.notify(player, "💦 장외! 벌타 +1", Color3.fromRGB(255, 140, 140))
			changed = true
			continue
		end

		local v = ball.AssemblyLinearVelocity
		local onGround = grounded(ball)
		if onGround then
			ball.AssemblyLinearVelocity = Vector3.new(v.X * factor, v.Y, v.Z * factor)
			ball.AssemblyAngularVelocity *= factor
		end

		-- 자석: 홀컵 쪽으로 살살 끌어당김
		local toCup = Vector3.new(hole.cup.X - pos.X, 0, hole.cup.Z - pos.Z)
		local cupDist = toCup.Magnitude
		if s.magnetUntil > now and cupDist < 16 and cupDist > 0.1 then
			ball.AssemblyLinearVelocity += toCup.Unit * 3
			s.ball:SetAttribute("Resting", false)
		end

		-- 홀인
		local radius = B.cupRadius * (s.magnetUntil > now and 2 or 1)
		if cupDist < radius and pos.Y < 3 and speedOf(ball) < B.cupMaxSpeed then
			sink(player, s)
			continue
		end

		-- 멈춤 판정 (0.3초 이상 느리면 다음 샷 가능)
		if onGround and speedOf(ball) < B.stopSpeed then
			s.restTimer += dt
			if s.restTimer > 0.3 and not ball:GetAttribute("Resting") then
				stop(ball)
				ball:SetAttribute("Resting", true)
				changed = true
			end
		else
			s.restTimer = 0
			if ball:GetAttribute("Resting") and speedOf(ball) > B.stopSpeed * 2 then
				ball:SetAttribute("Resting", false) -- 다른 공에 맞아서 움직임
			end
		end

		-- ❓ 상자
		if not s.item then
			for _, box in ipairs(hole.boxes) do
				if box:GetAttribute("Active") and (box.Position - pos).Magnitude < 3.2 then
					s.item = rollItem()
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
					ctx.notify(player, "❓ " .. Config.Items[s.item].name .. " 획득! (E 또는 아이템 버튼)", Color3.fromRGB(255, 220, 90))
					changed = true
					break
				end
			end
		end

		-- 가속 발판
		for _, b in ipairs(hole.boosters) do
			local rel = b.part.CFrame:PointToObjectSpace(pos)
			if math.abs(rel.X) < 3.2 and math.abs(rel.Z) < 4.2 and rel.Y < 2 then
				if (s.boostedAt or 0) < now - 0.6 then
					s.boostedAt = now
					ball.AssemblyLinearVelocity += b.dir * 45
					ball:SetAttribute("Resting", false)
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
