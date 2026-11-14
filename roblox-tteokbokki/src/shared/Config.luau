-- 🍢 떡볶이 가게 타이쿤 설정
-- 버튼(발판)을 밟아 가게를 하나씩 짓고, 음식이 컨베이어를 타고 계산대로 가면 돈이 쌓입니다.

local Config = {}

Config.LotCount = 6
Config.ConveyorSpeed = 8
Config.ItemLifetime = 25
Config.MaxItemsPerLot = 60
Config.OfflineRate = 0.25 -- 접속 안 한 동안은 25% 속도로 벌어 둠
Config.OfflineCapHours = 2 -- 최대 2시간 (게임패스로 8시간)

-- 버튼 목록. pos 는 가게 터 중심 기준 위치(스터드)
-- kind: "base"(가게 기본), "dropper"(음식 생산), "upgrader"(지나가는 음식 가치 배수), "deco"(인테리어, 수입 +%)
Config.Buttons = {
	{ id = "Open", name = "가게 열기", cost = 0, kind = "base", requires = {} },
	{ id = "Tteok", name = "떡볶이 솥", cost = 25, kind = "dropper", requires = { "Open" }, z = -22, value = 3, interval = 2.0, color = Color3.fromRGB(230, 60, 40) },
	{ id = "Sign", name = "가게 간판", cost = 60, kind = "deco", requires = { "Open" }, bonus = 0.05 },
	{ id = "Eomuk", name = "어묵 꼬치", cost = 150, kind = "dropper", requires = { "Tteok" }, z = -16, value = 8, interval = 2.0, color = Color3.fromRGB(240, 200, 140) },
	{ id = "Table1", name = "테이블 1", cost = 250, kind = "deco", requires = { "Sign" }, bonus = 0.05 },
	{ id = "Sundae", name = "순대 찜기", cost = 600, kind = "dropper", requires = { "Eomuk" }, z = -10, value = 20, interval = 2.2, color = Color3.fromRGB(90, 50, 60) },
	{ id = "Sauce", name = "매콤 양념 소스", cost = 1000, kind = "upgrader", requires = { "Sundae" }, z = 16, mult = 1.5, color = Color3.fromRGB(255, 80, 40) },
	{ id = "Table2", name = "테이블 2", cost = 1500, kind = "deco", requires = { "Table1" }, bonus = 0.05 },
	{ id = "Twigim", name = "튀김기", cost = 3000, kind = "dropper", requires = { "Sundae" }, z = -4, value = 50, interval = 2.4, color = Color3.fromRGB(230, 170, 60) },
	{ id = "Roof", name = "줄무늬 지붕", cost = 4500, kind = "deco", requires = { "Table2" }, bonus = 0.10 },
	{ id = "Gimbap", name = "김밥 말이", cost = 9000, kind = "dropper", requires = { "Twigim" }, z = 2, value = 120, interval = 2.5, color = Color3.fromRGB(40, 60, 40) },
	{ id = "Cheese", name = "치즈 토핑", cost = 15000, kind = "upgrader", requires = { "Gimbap", "Sauce" }, z = 22, mult = 2, color = Color3.fromRGB(255, 220, 80) },
	{ id = "Table3", name = "테이블 3", cost = 22000, kind = "deco", requires = { "Roof" }, bonus = 0.05 },
	{ id = "Ramen", name = "라면 기계", cost = 40000, kind = "dropper", requires = { "Gimbap" }, z = 8, value = 300, interval = 2.8, color = Color3.fromRGB(255, 190, 90) },
	{ id = "Neon", name = "네온 간판", cost = 65000, kind = "deco", requires = { "Table3" }, bonus = 0.15 },
	{ id = "Bike", name = "배달 오토바이", cost = 100000, kind = "deco", requires = { "Ramen" }, bonus = 0.25 },
	{ id = "Gold", name = "황금 간판 (2호점 준비)", cost = 250000, kind = "deco", requires = { "Bike", "Neon", "Cheese" }, bonus = 0.5 },
}

Config.ButtonById = {}
for i, b in ipairs(Config.Buttons) do
	b.index = i
	Config.ButtonById[b.id] = b
end

-- 프랜차이즈(환생): 모든 버튼을 사면 가능. 가게가 초기화되고 수입 배율 영구 +50%
function Config.RebirthMultiplier(rebirths: number): number
	return 1 + rebirths * 0.5
end

----------------------------------------------------------------------
-- 수익화
----------------------------------------------------------------------
Config.GamePasses = {
	DoubleCash = { id = 0, name = "💰 수입 2배", desc = "모든 음식 판매 수입 2배", price = 199 },
	AutoCollect = { id = 0, name = "🧾 자동 수금", desc = "계산대에 갈 필요 없이 바로 지갑으로", price = 149 },
	FastCook = { id = 0, name = "🔥 빠른 조리", desc = "모든 기계가 2배 빨리 음식을 만듦", price = 249 },
	VIP = { id = 0, name = "👑 VIP", desc = "수입 +25%, 달리기 +25%, VIP 태그", price = 299 },
	LongOffline = { id = 0, name = "🌙 야간 영업", desc = "접속 안 한 동안 최대 8시간 벌어 둠 (기본 2시간)", price = 99 },
}

Config.Products = {
	CashSmall = { id = 0, name = "💵 돈 봉투", desc = "지금 진행도에 맞춘 돈", price = 39 },
	CashLarge = { id = 0, name = "💰 돈 가방", desc = "돈 봉투의 5배", price = 149 },
	Rush = { id = 0, name = "🎉 손님 폭주 (10분)", desc = "10분 동안 수입 3배", price = 49 },
	BuildNext = { id = 0, name = "🔨 바로 짓기", desc = "지금 살 수 있는 가장 싼 건물을 공짜로", price = 25 },
}

Config.PremiumCashBonus = 0.1
Config.RushDuration = 10 * 60

return Config
