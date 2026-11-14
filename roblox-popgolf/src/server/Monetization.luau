-- 게임패스 / 개발자 상품 처리 (공용 모듈)
-- Config.GamePasses, Config.Products 의 id 로 동작합니다.
-- ProcessReceipt: 지급 + 저장이 끝난 뒤에만 PurchaseGranted → 돈만 빠지고 못 받는 일 방지

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)

local Monetization = {}

local ctx
local owned = {} -- [Player] = { PassKey = true }

local function findKey(list, id)
	for k, info in pairs(list) do
		if info.id ~= 0 and info.id == id then
			return k
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

local function grantPass(player, key, fromPurchase)
	owned[player] = owned[player] or {}
	if owned[player][key] then
		return
	end
	owned[player][key] = true
	player:SetAttribute("Pass_" .. key, true)
	if ctx.onPass then
		ctx.onPass(player, key)
	end
	if fromPurchase then
		ctx.notify(player, Config.GamePasses[key].name .. " 구매 완료! 고마워요 💜", Color3.fromRGB(255, 220, 120))
	end
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
					grantPass(player, key, false)
				end
			end)
		end
	end
end

function Monetization.RemovePlayer(player)
	owned[player] = nil
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
	local key = findKey(Config.Products, receipt.ProductId)
	local handler = key and ctx.productHandlers[key]
	if not handler then
		warn("[Monetization] 알 수 없는 상품 ID:", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, err = pcall(handler, player, data)
	if not ok then
		warn("[Monetization] 지급 오류:", err)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	DataService.AddReceipt(data, receipt.PurchaseId)
	if not DataService.Save(player, false) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	ctx.refresh(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- context = { notify, refresh, productHandlers = { Key = function(player, data) end }, onPass = function(player, key) }
function Monetization.Start(context)
	ctx = context
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased then
			local key = findKey(Config.GamePasses, passId)
			if key then
				grantPass(player, key, true)
			end
		end
	end)
end

return Monetization
