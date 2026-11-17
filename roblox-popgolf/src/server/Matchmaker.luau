-- 서버 간 매칭 (로비 서버 ↔ 경기 전용 서버)
--
-- 흐름
--  1) 로비 서버: 유저가 2대2/3대3/4대4 를 고르면 모드별 공용 대기열(MemoryStore)에 이름을 올림
--  2) 모든 로비 서버 중 한 곳이 '매칭 담당'(리더)이 되어 2초마다 대기열을 확인
--     - 모드 인원이 꽉 차면(2대2=4명…) 또는 가장 오래 기다린 사람이 fillTime 초를 넘기면 그 인원으로 경기 결정
--     - 경기 전용 서버(예약 서버)를 만들고, 각 유저가 있는 로비 서버 앞으로 '이동 지시'를 남김
--  3) 각 로비 서버는 자기 서버 앞 이동 지시를 읽고 해당 유저들을 경기 서버로 텔레포트
--  4) 경기 서버는 텔레포트 데이터(모드·팀 배정)로 경기를 하고, 끝나면 모두 로비(일반 서버)로 돌려보냄
--
-- Studio 에서는 텔레포트가 안 되므로 Main 이 예전처럼 한 서버 안 매칭을 씀 (Matchmaker.Enabled() == false)

local Players = game:GetService("Players")
local MemoryStoreService = game:GetService("MemoryStoreService")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Matchmaker = {}

local CS = Config.CrossServer
local QUEUE_TTL = 60 -- 대기열 항목 유효 시간 (로비 서버가 계속 갱신, 서버가 죽으면 자동으로 사라짐)
local ASSIGN_TTL = 120
local LEADER_TTL = 12

local queues = {} -- [size] = MemoryStoreSortedMap
local meta -- 리더 표시 · 모드별 인원
local assign -- [로비 서버 JobId] = 이동 지시 목록

local ctx -- { notify, onTeleportFailed, prepareTeleport }
local globalCounts = {} -- ["2"] = n ...
local isLeader = false

local function now()
	return DateTime.now().UnixTimestampMillis / 1000
end

local function try(fn, ...)
	local ok, result = pcall(fn, ...)
	if not ok then
		warn("[Matchmaker]", result)
	end
	return ok, result
end

-- 경기 전용 서버인지 (예약 서버 = 개인 서버 주인 없음)
function Matchmaker.IsMatchServer()
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

-- 서버 간 매칭 사용 여부 (게시된 로비 서버에서만)
function Matchmaker.Enabled()
	return CS.enabled and not RunService:IsStudio() and not Matchmaker.IsMatchServer() and game.PlaceId ~= 0
end

function Matchmaker.Counts()
	return globalCounts
end

----------------------------------------------------------------------
-- 대기열 등록 / 취소 (로비 서버)
----------------------------------------------------------------------
local queuedAt = {} -- [Player] = { size, t }

function Matchmaker.Join(player, size)
	-- 다른 모드에 있었으면 먼저 그 대기열에서 뺌 (같은 키를 지우고 쓰는 순서가 꼬이지 않게 기다림)
	local prev = queuedAt[player]
	if prev and prev.size ~= size then
		queuedAt[player] = nil
		try(function()
			queues[prev.size]:RemoveAsync(tostring(player.UserId))
		end)
	end
	local t = now()
	queuedAt[player] = { size = size, t = t }
	local ok = try(function()
		queues[size]:SetAsync(tostring(player.UserId), { u = player.UserId, job = game.JobId, t = t }, QUEUE_TTL, t)
	end)
	return ok
end

function Matchmaker.Leave(player)
	local q = queuedAt[player]
	queuedAt[player] = nil
	if q then
		task.spawn(try, function()
			queues[q.size]:RemoveAsync(tostring(player.UserId))
		end)
	end
end

-- 대기 중인 사람의 항목 유효 시간 연장. 리더가 이미 가져간(지운) 항목은 다시 만들지 않음 (중복 매칭 방지)
local function heartbeat()
	for player, q in pairs(queuedAt) do
		if player.Parent then
			try(function()
				queues[q.size]:UpdateAsync(tostring(player.UserId), function(old)
					if old == nil then
						return nil
					end
					return old, q.t
				end, QUEUE_TTL)
			end)
		else
			queuedAt[player] = nil
		end
	end
end

----------------------------------------------------------------------
-- 리더: 대기열 보고 경기 만들기
----------------------------------------------------------------------
local function claimLeader()
	local ok, result = try(function()
		return meta:UpdateAsync("leader", function(old)
			local t = now()
			if old == nil or old.job == game.JobId or (old.until_ or 0) < t then
				return { job = game.JobId, until_ = t + LEADER_TTL }
			end
			return nil
		end, LEADER_TTL + 5)
	end)
	isLeader = ok and type(result) == "table" and result.job == game.JobId
end

local function makeTeams(entries)
	for i = #entries, 2, -1 do
		local j = math.random(1, i)
		entries[i], entries[j] = entries[j], entries[i]
	end
	local teams = { {}, {} }
	for i, e in ipairs(entries) do
		table.insert(teams[((i - 1) % 2) + 1], e.u)
	end
	if #teams[2] == 0 then
		teams[2] = nil
	end
	return teams
end

local function startMatch(size, entries)
	-- 대기열에서 먼저 빼기 (다른 경기에 또 뽑히지 않게)
	for _, e in ipairs(entries) do
		try(function()
			queues[size]:RemoveAsync(tostring(e.u))
		end)
	end
	local ok, code = try(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	if not ok then
		return
	end
	local data = {
		matchId = HttpService:GenerateGUID(false),
		size = size,
		teams = makeTeams(table.clone(entries)),
	}
	-- 로비 서버별로 묶어서 이동 지시 남기기
	local byJob = {}
	for _, e in ipairs(entries) do
		byJob[e.job] = byJob[e.job] or {}
		table.insert(byJob[e.job], e.u)
	end
	for job, users in pairs(byJob) do
		try(function()
			assign:UpdateAsync(job, function(old)
				old = old or {}
				table.insert(old, { users = users, code = code, data = data })
				return old
			end, ASSIGN_TTL)
		end)
	end
	print(string.format("[Matchmaker] %d대%d 경기 생성: %d명", size, size, #entries))
end

local function leaderTick()
	local counts = {}
	local t = now()
	for _, size in ipairs(Config.MatchModes) do
		local ok, items = try(function()
			return queues[size]:GetRangeAsync(Enum.SortDirection.Ascending, 100)
		end)
		local entries = {}
		if ok and items then
			for _, item in ipairs(items) do
				if type(item.value) == "table" and item.value.u then
					table.insert(entries, item.value)
				end
			end
		end
		local want = size * 2
		-- 꽉 찬 경기는 몇 판이든 바로 만들고, 남은 사람은 오래 기다렸으면 모인 인원으로 시작
		while #entries >= want do
			local group = {}
			for _ = 1, want do
				table.insert(group, table.remove(entries, 1))
			end
			startMatch(size, group)
		end
		if #entries >= 1 and t - (entries[1].t or t) >= CS.fillTime then
			startMatch(size, entries)
			entries = {}
		end
		counts[tostring(size)] = #entries
	end
	globalCounts = counts
	try(function()
		meta:SetAsync("counts", counts, 30)
	end)
end

----------------------------------------------------------------------
-- 로비 서버: 내 서버 앞 이동 지시 처리
----------------------------------------------------------------------
local function pollAssignments()
	local taken
	local ok = try(function()
		assign:UpdateAsync(game.JobId, function(old)
			taken = old
			if old == nil or #old == 0 then
				return nil
			end
			return {}
		end, ASSIGN_TTL)
	end)
	if not ok or not taken then
		return
	end
	for _, a in ipairs(taken) do
		local players = {}
		for _, uid in ipairs(a.users) do
			local p = Players:GetPlayerByUserId(uid)
			if p and queuedAt[p] then
				queuedAt[p] = nil
				table.insert(players, p)
			end
		end
		if #players > 0 then
			for _, p in ipairs(players) do
				ctx.notify(p, string.format("⚔️ %d대%d 경기를 찾았어요! 경기장으로 이동해요...", a.data.size, a.data.size), Color3.fromRGB(120, 255, 160))
				p:SetAttribute("Queued", nil)
				ctx.prepareTeleport(p)
			end
			local options = Instance.new("TeleportOptions")
			options.ReservedServerAccessCode = a.code
			options:SetTeleportData(a.data)
			local sent = try(function()
				TeleportService:TeleportAsync(game.PlaceId, players, options)
			end)
			if not sent then
				for _, p in ipairs(players) do
					ctx.onTeleportFailed(p, a.data.size)
				end
			end
		end
	end
end

-- 운영자 '즉시 시작': 이 로비 서버의 선수들로 바로 경기 서버를 만들어 보냄 (대기열·매칭 담당을 거치지 않음)
function Matchmaker.ForceStart(size, players)
	local entries = {}
	for _, p in ipairs(players) do
		local q = queuedAt[p]
		queuedAt[p] = nil
		if q then
			task.spawn(try, function()
				queues[q.size]:RemoveAsync(tostring(p.UserId))
			end)
		end
		table.insert(entries, { u = p.UserId })
	end
	local ok, code = try(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	if not ok then
		return false
	end
	local data = { matchId = HttpService:GenerateGUID(false), size = size, teams = makeTeams(entries) }
	for _, p in ipairs(players) do
		p:SetAttribute("Queued", nil)
		ctx.prepareTeleport(p)
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = code
	options:SetTeleportData(data)
	local sent = try(function()
		TeleportService:TeleportAsync(game.PlaceId, players, options)
	end)
	if not sent then
		for _, p in ipairs(players) do
			ctx.onTeleportFailed(p, size)
		end
	end
	return sent
end

----------------------------------------------------------------------
-- 경기 서버 → 로비로 돌려보내기
----------------------------------------------------------------------
function Matchmaker.ReturnToLobby(players)
	if #players == 0 then
		return
	end
	for _, p in ipairs(players) do
		ctx.prepareTeleport(p)
	end
	local ok = try(function()
		TeleportService:TeleportAsync(game.PlaceId, players)
	end)
	if not ok then
		for _, p in ipairs(players) do
			p:Kick("로비로 돌아가지 못했어요. 다시 접속해 주세요.")
		end
	end
end

-- 경기 서버에 들어온 사람의 텔레포트 데이터 (모드·팀 배정)
function Matchmaker.JoinData(player)
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	local data = ok and joinData and joinData.TeleportData
	if type(data) == "table" and data.size and data.teams then
		return data
	end
	return nil
end

----------------------------------------------------------------------
function Matchmaker.Start(context)
	ctx = context
	if not Matchmaker.Enabled() then
		return
	end
	for _, size in ipairs(Config.MatchModes) do
		queues[size] = MemoryStoreService:GetSortedMap("PopGolfQueue_" .. size)
	end
	meta = MemoryStoreService:GetSortedMap("PopGolfMeta")
	assign = MemoryStoreService:GetSortedMap("PopGolfAssign")

	-- 텔레포트 실패 (상대 서버 문제 등): 다시 대기열로
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		warn("[Matchmaker] 텔레포트 실패:", player.Name, result, message)
		ctx.onTeleportFailed(player, nil)
	end)
	Players.PlayerRemoving:Connect(Matchmaker.Leave)

	task.spawn(function()
		local beat = 0
		while true do
			task.wait(2)
			claimLeader()
			if isLeader then
				leaderTick()
			else
				local ok, counts = try(function()
					return meta:GetAsync("counts")
				end)
				if ok and type(counts) == "table" then
					globalCounts = counts
				end
			end
			pollAssignments()
			beat += 2
			if beat >= 10 then
				beat = 0
				heartbeat()
			end
		end
	end)
end

return Matchmaker
