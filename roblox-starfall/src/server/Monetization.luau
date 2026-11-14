-- 게임패스 / 개발자 상품(Developer Products) 처리
-- ProcessReceipt 규칙: 지급 + 저장이 확실히 끝난 뒤에만 PurchaseGranted 를 돌려줌.
-- 실패하면 NotProcessedYet → 로블록스가 다음 접속 때 다시 호출해 줌 (돈만 빠지고 아이템 못 받는 일 방지).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)

local Monetization = {}

local ctx
local owned = {} -- [Player] = { DoubleCoins = true, ... }

local productHandlers = {}

local function productKeyById(productId)
	for key, info in pairs(Config.Products) do
		if info.id ~= 0 and info.id == productId then
			return key
		end
	end
	return nil
end

local function passKeyById(passId)
	for key, info in pairs(Config.GamePasses) do
		if info.id ~= 0 and info.id == passId then
			return key
		end
	end
	return nil
end

function Monetization.Owns(player, passKey)
	local set = owned[player]
	return set ~= nil and set[passKey] == true
end

function Monetization.GetOwned(player)
	return owned[player] or {}
end

local function onPassGranted(player, key)
	owned[player] = owned[player] or {}
	owned[player][key] = true
	if key == "VIP" then
		player:SetAttribute("VIP", true)
	end
	ctx.notify(player, Config.GamePasses[key].name .. " 구매 완료! 고마워요 💜", Color3.fromRGB(255, 220, 120))
	ctx.refresh(player)
end

function Monetization.LoadPlayer(player)
	owned[player] = {}
	for key, info in pairs(Config.GamePasses) do
		if info.id ~= 0 then
			task.spawn(function()
				local ok, has = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, info.id)
				end)
				if ok and has and owned[player] then
					owned[player][key] = true
					if key == "VIP" then
						player:SetAttribute("VIP", true)
					end
					ctx.refresh(player)
				end
			end)
		end
	end
end

function Monetization.RemovePlayer(player)
	owned[player] = nil
end

----------------------------------------------------------------------
-- 상품별 지급 로직
----------------------------------------------------------------------
productHandlers.CoinsSmall = function(player, data)
	local amount = Config.GetCoinPackAmount(data.rebirths, false)
	ctx.addCoins(player, data, amount)
	ctx.notify(player, "코인 +" .. ctx.short(amount) .. " 💰", Color3.fromRGB(255, 220, 120))
end

productHandlers.CoinsLarge = function(player, data)
	local amount = Config.GetCoinPackAmount(data.rebirths, true)
	ctx.addCoins(player, data, amount)
	ctx.notify(player, "코인 +" .. ctx.short(amount) .. " 💰💰", Color3.fromRGB(255, 220, 120))
end

productHandlers.LuckBoost = function(player, data)
	local now = os.time()
	data.boosts.luckUntil = math.max(data.boosts.luckUntil, now) + Config.LuckBoostDuration
	ctx.notify(player, "행운 물약 사용! 행운 x3 🍀", Color3.fromRGB(140, 255, 160))
end

productHandlers.MeteorShower = function(player, _data)
	ctx.startMeteorShower(player)
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = DataService.WaitFor(player, 20)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if DataService.HasReceipt(data, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local key = productKeyById(receipt.ProductId)
	local handler = key and productHandlers[key]
	if not handler then
		warn("[Monetization] 알 수 없는 상품 ID:", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, err = pcall(handler, player, data)
	if not ok then
		warn("[Monetization] 지급 중 오류:", err)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	DataService.AddReceipt(data, receipt.PurchaseId)
	if not DataService.Save(player, false) then
		-- 저장 실패: 메모리엔 이미 지급됐으니, 같은 영수증이 다시 오면 위 HasReceipt 에서 걸러짐
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	ctx.refresh(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function Monetization.Start(context)
	ctx = context
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased then
			local key = passKeyById(passId)
			if key then
				onPassGranted(player, key)
			end
		end
	end)
end

return Monetization
