--!strict
-- Economy.lua
-- Single source of truth for all economy values, pricing, and reward tables

local Economy = {}

-- Conversion rate: 1 Robux = 15 Coins
Economy.COINS_PER_ROBUX = 15

-- =============================================================
-- MATCH EARNINGS
-- =============================================================
-- Average match: ~500 coins. Good win: ~750.
Economy.MATCH_BASE_REWARD = 250        -- Just for participating
Economy.MATCH_WIN_BONUS = 250          -- Extra for winning
Economy.COINS_PER_KILL = 25
Economy.COINS_PER_DEMOLITION = 5       -- Breaking soft walls
Economy.COINS_PER_POWERUP = 10

-- Win streak multipliers (applied to total match earnings)
Economy.WIN_STREAK_MULTIPLIERS = {
	[2] = 1.25,   -- 2 wins in a row
	[3] = 1.5,    -- 3 wins
	[5] = 1.75,   -- 5 wins
	[10] = 2.0,   -- 10+ wins
}

-- =============================================================
-- ITEM PRICES (direct purchase in rotating shop)
-- =============================================================
Economy.ITEM_PRICES = {
	Common = 1500,
	Uncommon = 3000,
	Rare = 5000,
	Epic = 15000,
	Legendary = 50000,
}

-- =============================================================
-- CAPSULE PRICES (coins) — Legendary is Robux-only
-- =============================================================
Economy.CAPSULE_PRICES = {
	Uncommon = 2500,
	Rare = 7500,
	Epic = 20000,
}

-- =============================================================
-- CAPSULE DEV PRODUCTS (Robux purchases via MarketplaceService)
-- =============================================================
Economy.CAPSULE_DEV_PRODUCTS = {
	Uncommon       = { productId = 3587317828, robux = 10 },
	Rare           = { productId = 3587318172, robux = 25 },
	Epic           = { productId = 3587320706, robux = 40 },
	Random         = { productId = 3587327622, robux = 25 },
	Legendary1     = { productId = 3587322155, robux = 60 },
	Legendary3     = { productId = 3587324705, robux = 150 },
	Legendary5     = { productId = 3587325065, robux = 300 },
}

-- Bonus item chance: opening a capsule has this % chance to also drop
-- one item from the next rarity tier up
Economy.CAPSULE_BONUS_CHANCE = 10 -- 10% chance for a higher-rarity item

-- =============================================================
-- RANDOM CAPSULE ODDS (weighted rarity distribution)
-- =============================================================
Economy.RANDOM_CAPSULE_WEIGHTS = {
	{ rarity = "Common",    weight = 35 },
	{ rarity = "Uncommon",  weight = 30 },
	{ rarity = "Rare",      weight = 20 },
	{ rarity = "Epic",      weight = 12 },
	{ rarity = "Legendary", weight = 3 },
}

-- =============================================================
-- CURRENCY PACKAGES (robux -> coins)
-- =============================================================
-- Bigger packages give bonus coins to incentivize larger purchases
Economy.CURRENCY_PACKAGES = {
	{ id = "pack_100",  coins = 1500,  robux = 100  },  -- base rate
	{ id = "pack_300",  coins = 5000,  robux = 300  },  -- +11% bonus
	{ id = "pack_650",  coins = 12500, robux = 650  },  -- +28% bonus
	{ id = "pack_1200", coins = 30000, robux = 1200 },  -- +67% bonus
}

-- =============================================================
-- 7-DAY DAILY REWARDS (loops after day 7)
-- =============================================================
-- Types: "coins", "capsule", "title", "explosion", "celebration"
Economy.DAILY_REWARDS = {
	[1] = { coins = 500 },
	[2] = { coins = 750, bonus = { type = "title", value = "random" } },
	[3] = { capsule = "Common" },
	[4] = { coins = 1500 },
	[5] = { capsule = "Rare" },
	[6] = { coins = 2000, bonus = { type = "explosion", value = "random" } },
	[7] = { coins = 3000, capsule = "Epic" },
}

-- =============================================================
-- QUESTS
-- =============================================================
-- Daily: 3 random from pool, reset every 24h
Economy.DAILY_QUEST_COUNT = 3

-- Time-based quests (1 is always picked per day)
Economy.DAILY_TIME_QUESTS = {
	{ id = "time_10",      description = "Play for 10 Minutes",   goal = 10, stat = "play_minutes",   reward = { coins = 300 } },
	{ id = "time_20",      description = "Play for 20 Minutes",   goal = 20, stat = "play_minutes",   reward = { coins = 600 } },
	{ id = "time_30",      description = "Play for 30 Minutes",   goal = 30, stat = "play_minutes",   reward = { coins = 1000 } },
}

-- Regular quests (2 are picked per day)
Economy.DAILY_QUESTS = {
	{ id = "play_3",       description = "Play 3 Matches",       goal = 3,  stat = "matches_played", reward = { coins = 300 } },
	{ id = "play_5",       description = "Play 5 Matches",       goal = 5,  stat = "matches_played", reward = { coins = 500 } },
	{ id = "kills_5",      description = "Get 5 Kills",          goal = 5,  stat = "kills",          reward = { coins = 400 } },
	{ id = "kills_10",     description = "Get 10 Kills",         goal = 10, stat = "kills",          reward = { coins = 750 } },
	{ id = "demolish_30",  description = "Break 30 Walls",       goal = 30, stat = "demolitions",    reward = { coins = 250 } },
	{ id = "demolish_50",  description = "Break 50 Walls",       goal = 50, stat = "demolitions",    reward = { coins = 400 } },
	{ id = "powerups_10",  description = "Collect 10 Powerups",  goal = 10, stat = "powerups",       reward = { coins = 300 } },
	{ id = "win_1",        description = "Win 1 Match",          goal = 1,  stat = "wins",           reward = { coins = 500 } },
	{ id = "win_3",        description = "Win 3 Matches",        goal = 3,  stat = "wins",           reward = { coins = 1000 } },
	{ id = "bombs_20",     description = "Place 20 Bombs",       goal = 20, stat = "bombs_placed",   reward = { coins = 250 } },
}

-- Weekly: 3 quests, reset Monday
Economy.WEEKLY_QUEST_COUNT = 3

Economy.WEEKLY_QUESTS = {
	{ id = "w_wins_10",     description = "Win 10 Matches",       goal = 10, stat = "wins",           reward = { coins = 2500 } },
	{ id = "w_kills_50",    description = "Get 50 Kills",         goal = 50, stat = "kills",          reward = { capsule = "Rare" } },
	{ id = "w_play_30",     description = "Play 30 Matches",      goal = 30, stat = "matches_played", reward = { coins = 2000, capsule = "Common" } },
	{ id = "w_demolish_200",description = "Break 200 Walls",      goal = 200,stat = "demolitions",    reward = { coins = 1500 } },
	{ id = "w_streak_5",    description = "Get a 5 Win Streak",   goal = 5,  stat = "win_streak",     reward = { coins = 3000 } },
}

-- =============================================================
-- SPIN WHEEL
-- =============================================================
-- 1 free spin per day, extra spins cost coins
Economy.FREE_SPINS_PER_DAY = 1
Economy.EXTRA_SPIN_COST = 500       -- Coins per additional spin
Economy.MAX_PAID_SPINS_PER_DAY = 3

-- Slot order matches UI slice names: RareSlice, UncommonSlice, RareSlice2, EpicSlice, LegendarySlice, UncommonSlice2, UncommonSlice3
-- rewardType: "coins" | "capsule" | "legendary" (used for landing SFX)
Economy.SPIN_WHEEL_SLOTS = {
	{ sliceName = "RareSlice",       chance = 12, reward = { capsule = "Rare" },      name = "Rare Capsule",      imageId = "rbxassetid://104738757916164", rewardType = "capsule" },
	{ sliceName = "UncommonSlice",   chance = 20, reward = { coins = 250 },           name = "250 Coins",         imageId = "rbxassetid://118687282770235", rewardType = "coins" },
	{ sliceName = "RareSlice2",      chance = 12, reward = { coins = 500 },           name = "500 Coins",         imageId = "rbxassetid://118687282770235", rewardType = "coins" },
	{ sliceName = "EpicSlice",       chance = 8,  reward = { capsule = "Epic" },      name = "Epic Capsule",      imageId = "rbxassetid://104738757916164", rewardType = "capsule" },
	{ sliceName = "LegendarySlice",  chance = 3,  reward = { capsule = "Legendary" }, name = "Legendary Capsule", imageId = "rbxassetid://104738757916164", rewardType = "legendary" },
	{ sliceName = "UncommonSlice2",  chance = 25, reward = { coins = 100 },           name = "100 Coins",         imageId = "rbxassetid://118687282770235", rewardType = "coins" },
	{ sliceName = "UncommonSlice3",  chance = 20, reward = { coins = 1000 },          name = "1K Coins",          imageId = "rbxassetid://118687282770235", rewardType = "coins" },
}

-- =============================================================
-- LEVEL REWARDS
-- =============================================================
-- Every level: 500 + (level * 50) coins
Economy.LEVEL_COIN_BASE = 500
Economy.LEVEL_COIN_SCALE = 50       -- Extra coins per level number

-- Milestone rewards (on top of per-level coins)
Economy.LEVEL_MILESTONES = {
	[5]  = { capsule = "Common",    title = "Spark" },
	[10] = { coins = 2000,          celebration = "exclusive_common" },
	[15] = { capsule = "Rare",      title = "Dynamite" },
	[20] = { coins = 5000,          explosion = "exclusive_rare" },
	[25] = { capsule = "Epic",      title = "Bomb Expert" },
	[30] = { coins = 10000,         celebration = "exclusive_epic" },
	[40] = { capsule = "Legendary", title = "Demolition King" },
	[50] = { coins = 25000,         skin = "exclusive_legendary", title = "Bomb God" },
}

-- =============================================================
-- GROUP / FRIEND BOOSTS
-- =============================================================
Economy.GROUP_MEMBER_BOOST = 1.1     -- 10% more coins if in game group
Economy.FRIEND_BOOST_PER = 0.05     -- 5% per friend in same server
Economy.FRIEND_BOOST_MAX = 1.25     -- Cap at 25% friend boost

-- =============================================================
-- ROTATING SHOP
-- =============================================================
Economy.DAILY_SHOP_SLOTS = 4        -- Number of daily rotating items
Economy.WEEKLY_BUNDLE_SLOTS = 2     -- Number of weekly bundles

-- Weekly bundles are purchasable with coins OR robux
-- Robux price = coin price / COINS_PER_ROBUX (rounded)

-- =============================================================
-- GAMEPASS IDs
-- =============================================================
Economy.GAMEPASS_VIP = 1823484391
Economy.GAMEPASS_2X_COINS = 1826511329
Economy.GAMEPASS_ALL_BLUE = 1826183423

-- VIP perks
Economy.VIP_FREE_SPINS_PER_DAY = 2
Economy.VIP_XP_MULTIPLIER = 1.5

-- Dev product: 2x Luck (temporary boost)
Economy.DEV_PRODUCT_2X_LUCK = 3582271001
Economy.DEV_PRODUCT_2X_LUCK_ROBUX = 75
Economy.LUCK_BOOST_DURATION = 600 -- 10 minutes in seconds

-- =============================================================
-- HELPERS
-- =============================================================

-- Get coins earned for reaching a specific level
function Economy.GetLevelCoins(level: number): number
	return Economy.LEVEL_COIN_BASE + level * Economy.LEVEL_COIN_SCALE
end

-- Get win streak multiplier
function Economy.GetStreakMultiplier(streak: number): number
	local mult = 1.0
	for threshold, value in pairs(Economy.WIN_STREAK_MULTIPLIERS) do
		if streak >= threshold and value > mult then
			mult = value
		end
	end
	return mult
end

-- Calculate total match earnings
function Economy.CalculateMatchEarnings(won: boolean, kills: number, demolitions: number, powerups: number, winStreak: number): number
	local total = Economy.MATCH_BASE_REWARD
	if won then
		total = total + Economy.MATCH_WIN_BONUS
	end
	total = total + kills * Economy.COINS_PER_KILL
	total = total + demolitions * Economy.COINS_PER_DEMOLITION
	total = total + powerups * Economy.COINS_PER_POWERUP

	local mult = Economy.GetStreakMultiplier(winStreak)
	total = math.floor(total * mult)

	return total
end

-- Convert coin price to robux (for shop bundles)
function Economy.CoinsToRobux(coins: number): number
	return math.ceil(coins / Economy.COINS_PER_ROBUX)
end

return Economy
