-- 플레이어 데이터 저장/불러오기
-- * UpdateAsync 로 저장 (덮어쓰기 경쟁 방지)
-- * 세션 잠금: 다른 서버가 아직 저장 중이면 잠시 기다렸다가 불러옴 → 아이템 복사 버그 방지
-- * Studio 에서 API 접근이 꺼져 있으면 저장 없이 임시 데이터로 동작

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DataService = {}

local STORE_NAME = "StarfallPlayerData_v1"
local LOCK_TIMEOUT = 15 * 60 -- 이 시간보다 오래된 잠금은 무시(서버가 죽은 경우)
local MAX_RECEIPTS = 100

local store
local storeOk = pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)

local profiles = {} -- [Player] = data
local loadedSignals = {} -- [Player] = BindableEvent

local function defaultData()
	return {
		version = 1,
		coins = 0,
		totalCoins = 0,
		rebirths = 0,
		upgrades = { Magnet = 0, Bag = 0, SpawnRate = 0, Luck = 0 },
		bag = { count = 0, value = 0 },
		pets = {}, -- { {uid="..", id="Twinkle"} }
		equipped = {}, -- { uid, uid, ... }
		nextPetUid = 1,
		daily = { lastDay = 0, streak = 0 },
		boosts = { luckUntil = 0 },
		receipts = {}, -- 처리한 구매 영수증 ID (중복 지급 방지)
		starsCollected = 0,
		playtime = 0,
	}
end

-- 새 필드가 추가되어도 예전 저장 데이터가 깨지지 않도록 기본값을 채움
local function reconcile(data, template)
	for k, v in pairs(template) do
		if data[k] == nil then
			if type(v) == "table" then
				data[k] = table.clone(v)
			else
				data[k] = v
			end
		elseif type(v) == "table" and type(data[k]) == "table" and next(v) ~= nil and #v == 0 then
			reconcile(data[k], v)
		end
	end
	return data
end

local function retry(fn, attempts)
	local lastErr
	for i = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		-- Studio 에서 API 접근이 꺼져 있으면 재시도해도 소용없으니 바로 포기
		if RunService:IsStudio() and string.find(tostring(result), "API", 1, true) then
			break
		end
		task.wait(1.5 * i)
	end
	return false, lastErr
end

local function key(player)
	return "u_" .. player.UserId
end

function DataService.Load(player)
	local data
	if storeOk and store then
		for attempt = 1, 5 do
			local locked = false
			local ok, result = retry(function()
				return store:UpdateAsync(key(player), function(old)
					old = old or defaultData()
					local lock = old._lock
					if lock and lock.job ~= game.JobId and os.time() - (lock.time or 0) < LOCK_TIMEOUT then
						locked = true
						return nil -- 바꾸지 않음
					end
					old._lock = { job = game.JobId, time = os.time() }
					return old
				end)
			end, 3)
			if not ok then
				warn("[DataService] 불러오기 실패:", result)
				break
			end
			if not locked then
				data = result
				break
			end
			if attempt == 5 then
				warn("[DataService] 다른 서버의 잠금이 풀리지 않아 강제로 가져옵니다:", player.Name)
				local ok2, result2 = retry(function()
					return store:UpdateAsync(key(player), function(old)
						old = old or defaultData()
						old._lock = { job = game.JobId, time = os.time() }
						return old
					end)
				end, 3)
				if ok2 then
					data = result2
				end
			else
				task.wait(3)
			end
		end
	end

	if not player.Parent then
		return nil
	end

	if data == nil then
		if storeOk and store and not RunService:IsStudio() then
			-- 실제 서버에서 데이터를 못 불러왔으면 빈 데이터로 덮어쓰지 않도록 내보냄
			player:Kick("데이터를 불러오지 못했어요. 잠시 후 다시 접속해 주세요.")
			return nil
		end
		data = defaultData()
		data._unsaved = true
	end

	reconcile(data, defaultData())
	profiles[player] = data
	if loadedSignals[player] then
		loadedSignals[player]:Fire(data)
	end
	return data
end

function DataService.Get(player)
	return profiles[player]
end

-- 데이터가 준비될 때까지 기다림 (구매 처리 등에서 사용)
function DataService.WaitFor(player, timeout)
	local data = profiles[player]
	if data then
		return data
	end
	local signal = loadedSignals[player]
	if not signal then
		signal = Instance.new("BindableEvent")
		loadedSignals[player] = signal
	end
	local result
	local conn = signal.Event:Connect(function(d)
		result = d
	end)
	local start = os.clock()
	while not result and player.Parent and os.clock() - start < (timeout or 20) do
		task.wait(0.1)
	end
	conn:Disconnect()
	return result
end

function DataService.Save(player, release)
	local data = profiles[player]
	if not data or data._unsaved or not (storeOk and store) then
		return true
	end
	local ok, err = retry(function()
		store:UpdateAsync(key(player), function(old)
			if old and old._lock and old._lock.job ~= game.JobId then
				-- 다른 서버가 잠금을 가져갔으면 덮어쓰지 않음
				return nil
			end
			local copy = table.clone(data)
			copy._lock = (not release) and { job = game.JobId, time = os.time() } or nil
			return copy
		end)
	end, 3)
	if not ok then
		warn("[DataService] 저장 실패:", player.Name, err)
	end
	return ok
end

function DataService.HasReceipt(data, receiptId)
	return table.find(data.receipts, receiptId) ~= nil
end

function DataService.AddReceipt(data, receiptId)
	table.insert(data.receipts, receiptId)
	while #data.receipts > MAX_RECEIPTS do
		table.remove(data.receipts, 1)
	end
end

function DataService.Release(player)
	DataService.Save(player, true)
	profiles[player] = nil
	if loadedSignals[player] then
		loadedSignals[player]:Destroy()
		loadedSignals[player] = nil
	end
end

function DataService.Start()
	-- 주기적 자동 저장
	task.spawn(function()
		while true do
			task.wait(90)
			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(DataService.Save, player, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for _, player in ipairs(Players:GetPlayers()) do
			pending += 1
			task.spawn(function()
				DataService.Save(player, true)
				pending -= 1
			end)
		end
		local start = os.clock()
		while pending > 0 and os.clock() - start < 25 do
			task.wait(0.2)
		end
	end)
end

return DataService
