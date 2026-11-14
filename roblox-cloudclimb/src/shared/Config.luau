-- ☁️ 구름 오비 (Cloud Climb Obby) 설정

local Config = {}

Config.StageCount = 100 -- 체크포인트 수. 마지막 다음 칸이 '정상'
Config.Seed = 20261114 -- 맵 모양을 정하는 숫자. 바꾸면 완전히 다른 코스가 나옴 (모든 서버가 같은 코스)
Config.StageRise = 4 -- 스테이지마다 올라가는 높이
Config.RespawnTime = 1.5
-- Studio 테스트 전용: true 면 ◀ ▶ 스테이지 선택기로 아직 안 깬 스테이지에도 갈 수 있음 (실제 서버에선 꺼짐)
Config.StudioFreeStageSelect = true

----------------------------------------------------------------------
-- 난이도 (숫자만 바꿔서 조절)
-- 각 항목의 { 쉬울 때, 어려울 때 } 값 사이를 스테이지가 올라갈수록 이동합니다.
----------------------------------------------------------------------
Config.Difficulty = {
	-- 난이도 곡선. 1 = 일정하게 어려워짐, 2 = 초반은 아주 쉽고 후반에 확 어려워짐
	curve = 1.8,
	-- 장애물이 처음 나오는 스테이지 (숫자를 키우면 더 늦게 등장)
	unlock = { jumps = 1, beam = 1, truss = 4, lavaStrip = 8, spinner = 20, moving = 28, vanish = 36 },
	-- 이 스테이지까지는 스테이지당 장애물 2개, 이후 3개
	twoObstaclesUntil = 25,

	jumpGap = { 3, 7.5 }, -- 점프 발판 사이 거리 (기본 캐릭터는 약 10까지 뛸 수 있음)
	jumpPadSize = { 6, 3.8 }, -- 점프 발판 크기
	beamWidth = { 3, 1.2 }, -- 좁은 다리 폭
	lavaBars = { 1, 4 }, -- 용암 줄 개수
	spinnerSpeed = { 0.9, 2.6 }, -- 회전 막대 속도
	spinnerLength = { 11, 22 }, -- 회전 막대 길이 (발판 폭이 16이라 짧으면 가장자리로 피해 갈 수 있음)
	movingSpeed = { 4, 9 }, -- 움직이는 발판 속도
	vanishGap = { 3, 5.5 }, -- 사라지는 발판 사이 거리
}

-- 10 스테이지마다 바뀌는 구역 테마
Config.Zones = {
	{ name = "초록 들판", color = Color3.fromRGB(120, 210, 110), accent = Color3.fromRGB(255, 255, 255) },
	{ name = "솜사탕 구름", color = Color3.fromRGB(255, 190, 220), accent = Color3.fromRGB(255, 255, 255) },
	{ name = "하늘 호수", color = Color3.fromRGB(110, 190, 255), accent = Color3.fromRGB(220, 245, 255) },
	{ name = "레몬 바람", color = Color3.fromRGB(255, 230, 110), accent = Color3.fromRGB(255, 255, 230) },
	{ name = "노을 언덕", color = Color3.fromRGB(255, 150, 90), accent = Color3.fromRGB(255, 220, 180) },
	{ name = "무지개 다리", color = Color3.fromRGB(190, 130, 255), accent = Color3.fromRGB(255, 200, 255) },
	{ name = "번개 구름", color = Color3.fromRGB(120, 120, 160), accent = Color3.fromRGB(255, 240, 120) },
	{ name = "오로라", color = Color3.fromRGB(90, 230, 190), accent = Color3.fromRGB(200, 255, 240) },
	{ name = "별빛 길", color = Color3.fromRGB(70, 70, 140), accent = Color3.fromRGB(255, 240, 160) },
	{ name = "우주 끝", color = Color3.fromRGB(40, 30, 70), accent = Color3.fromRGB(255, 120, 220) },
}

function Config.ZoneFor(stage: number)
	local i = math.clamp(math.floor((stage - 1) / 10) + 1, 1, #Config.Zones)
	return Config.Zones[i], i
end

-- 새 스테이지를 처음 깰 때 받는 코인
function Config.StageReward(stage: number, rebirths: number): number
	return math.floor((5 + stage) * (1 + rebirths * 0.5))
end

----------------------------------------------------------------------
-- 수익화 (크리에이터 대시보드에서 만든 ID 입력, 0 = 미설정)
----------------------------------------------------------------------
Config.GamePasses = {
	Speed = { id = 0, name = "⚡ 스피드", desc = "달리기 속도 16 → 22", price = 99 },
	HighJump = { id = 0, name = "🦘 점프 업", desc = "점프 높이 +30%", price = 149 },
	DoubleCoins = { id = 0, name = "💰 코인 2배", desc = "스테이지 보상 코인 2배", price = 99 },
	VIP = { id = 0, name = "👑 VIP", desc = "VIP 전용 황금 트레일 + 채팅 태그 + 코인 +50%", price = 249 },
}

Config.Products = {
	SkipStage = { id = 0, name = "⏭️ 스테이지 건너뛰기", desc = "다음 스테이지로 바로 이동", price = 19 },
	Skip5 = { id = 0, name = "⏩ 5단계 건너뛰기", desc = "5 스테이지를 한 번에!", price = 79 },
	Coins = { id = 0, name = "💰 코인 500", desc = "트레일 상점에서 쓰는 코인", price = 39 },
}

Config.PremiumCoinBonus = 0.2

----------------------------------------------------------------------
-- 트레일 (게임 코인으로 사는 꾸미기, 확률 요소 없음)
----------------------------------------------------------------------
Config.TrailOrder = { "Cloud", "Mint", "Sunset", "Ocean", "Fire", "Rainbow", "Galaxy", "Gold" }
Config.Trails = {
	Cloud = { name = "구름", cost = 0, colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(220, 230, 255) } },
	Mint = { name = "민트", cost = 150, colors = { Color3.fromRGB(150, 255, 210), Color3.fromRGB(80, 220, 180) } },
	Sunset = { name = "노을", cost = 400, colors = { Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 90, 120) } },
	Ocean = { name = "바다", cost = 800, colors = { Color3.fromRGB(90, 200, 255), Color3.fromRGB(40, 80, 220) } },
	Fire = { name = "불꽃", cost = 1500, colors = { Color3.fromRGB(255, 230, 80), Color3.fromRGB(255, 60, 30) } },
	Rainbow = { name = "무지개", cost = 3000, colors = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 220, 80), Color3.fromRGB(80, 220, 120), Color3.fromRGB(80, 160, 255), Color3.fromRGB(190, 100, 255) } },
	Galaxy = { name = "은하", cost = 6000, colors = { Color3.fromRGB(60, 20, 120), Color3.fromRGB(255, 120, 220), Color3.fromRGB(120, 220, 255) } },
	Gold = { name = "황금 (VIP)", cost = -1, colors = { Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 170, 40) } }, -- -1 = VIP 전용
}

return Config
