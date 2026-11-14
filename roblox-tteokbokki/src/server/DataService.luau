-- 플레이어 데이터 저장/불러오기 (공용 모듈)
-- * UpdateAsync 로 저장 (덮어쓰기 경쟁 방지)
-- * 세션 잠금: 다른 서버가 아직 저장 중이면 잠시 기다렸다가 불러옴 → 아이템 복사 버그 방지
-- * Studio 에서 API 접근이 꺼져 있으면 저장 없이 임시 데이터로 동작
-- 사용법: DataService.Configure("저장소이름", function() return {기본데이터} end) 후 Start()

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DataService = {}

local LOCK_TIMEOUT = 15 * 60
local MAX_RECEIPTS = 100

local store
local storeOk = false
local defaultData = function()
	return {}
end

local profiles = {}
local loadedSignals = {}

function DataService.Configure(storeName, defaultFn)
	defaultData = function()
		local d = defaultFn()
		d.receipts = d.receipts or {}
		return d
	end
	storeOk = pcall(function()
		store = DataStoreService:GetDataStore(storeName)
	end)
end

local function deepCopy(t)
	local c = {}
	for k, v in pairs(t) do
		c[k] = type(v) == "table" and deepCopy(v) or v
	end
	return c
end

-- 새 필드가 추가되어도 예전 데이터가 깨지지 않게 기본값을 채움
local function reconcile(data, template)
	for k, v in pairs(template) do
		if data[k] == nil then
			data[k] = type(v) == "table" and deepCopy(v) or v
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

local function claim(player, force)
	local locked = false
	local ok, result = retry(function()
		return store:UpdateAsync(key(player), function(old)
			old = old or defaultData()
			local lock = old._lock
			if not force and lock and lock.job ~= game.JobId and os.time() - (lock.time or 0) < LOCK_TIMEOUT then
				locked = true
				return nil
			end
			old._lock = { job = game.JobId, time = os.time() }
			return old
		end)
	end, 3)
	return ok, result, locked
end

function DataService.Load(player)
	local data
	if storeOk and store then
		for attempt = 1, 5 do
			local ok, result, locked = claim(player, attempt == 5)
			if not ok then
				warn("[DataService] 불러오기 실패:", result)
				break
			end
			if not locked then
				data = result
				break
			end
			task.wait(3)
		end
	end
	if not player.Parent then
		return nil
	end
	if data == nil then
		if storeOk and store and not RunService:IsStudio() then
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

function DataService.WaitFor(player, timeout)
	if profiles[player] then
		return profiles[player]
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
