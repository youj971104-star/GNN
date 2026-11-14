-- 🧊 얼음땡 술래잡기 (Freeze Tag) 설정

local Config = {}

Config.MinPlayers = 2 -- 라운드를 시작할 최소 인원
Config.Intermission = 15 -- 대기 시간(초)
Config.RoundTime = 120 -- 라운드 시간(초)
Config.TaggerReleaseDelay = 5 -- 술래가 움직이기 시작하기까지(초)
Config.PlayersPerTagger = 4 -- 4명당 술래 1명
Config.TagDistance = 5 -- 이 거리 안에 들어오면 얼림/녹임
Config.ThawCooldown = 3 -- 얼고 나서 이 시간 동안은 못 녹임 (바로 녹이기 반복 방지)
Config.RunnerSpeed = 16
Config.TaggerSpeed = 18

-- 코인 보상
Config.Rewards = {
	surviveTick = 2, -- 도망자: 10초 버틸 때마다
	thaw = 15, -- 얼은 친구 녹이기
	freeze = 10, -- 술래: 얼릴 때마다
	win = 30, -- 이긴 팀 전원
	play = 5, -- 참가 보상
}

----------------------------------------------------------------------
-- 수익화
----------------------------------------------------------------------
Config.GamePasses = {
	TaggerChance = { id = 0, name = "🔴 술래 확률 UP", desc = "술래로 뽑힐 확률 3배", price = 99 },
	DoubleCoins = { id = 0, name = "💰 코인 2배", desc = "모든 코인 보상 2배", price = 149 },
	VIP = { id = 0, name = "👑 VIP", desc = "VIP 태그 + 전용 트레일 + 코인 +50%", price = 249 },
}

Config.Products = {
	SelfThaw = { id = 0, name = "🔥 스스로 녹기", desc = "얼었을 때 바로 녹아요 (라운드 중)", price = 15 },
	IceShield = { id = 0, name = "🛡️ 얼음 방패", desc = "한 번 얼지 않아요 (쓸 때까지 유지)", price = 25 },
	BeTagger = { id = 0, name = "😈 다음 술래 확정", desc = "다음 라운드에 꼭 술래가 돼요", price = 29 },
	Coins = { id = 0, name = "💰 코인 500", desc = "트레일 상점에서 쓰는 코인", price = 39 },
}

Config.PremiumCoinBonus = 0.2

----------------------------------------------------------------------
-- 트레일 (코인으로 구매, 확률 없음)
----------------------------------------------------------------------
Config.TrailOrder = { "Snow", "Mint", "Berry", "Lava", "Aurora", "Gold" }
Config.Trails = {
	Snow = { name = "눈송이", cost = 0, colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 230, 255) } },
	Mint = { name = "민트", cost = 200, colors = { Color3.fromRGB(150, 255, 210), Color3.fromRGB(80, 220, 180) } },
	Berry = { name = "딸기우유", cost = 500, colors = { Color3.fromRGB(255, 180, 210), Color3.fromRGB(255, 90, 140) } },
	Lava = { name = "용암", cost = 1200, colors = { Color3.fromRGB(255, 230, 80), Color3.fromRGB(255, 60, 30) } },
	Aurora = { name = "오로라", cost = 3000, colors = { Color3.fromRGB(90, 255, 190), Color3.fromRGB(110, 140, 255), Color3.fromRGB(230, 120, 255) } },
	Gold = { name = "황금 (VIP)", cost = -1, colors = { Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 170, 40) } },
}

return Config
