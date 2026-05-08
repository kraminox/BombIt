--!strict
-- Constants.lua
-- Single source of truth for all tunable game values

local Constants = {}

-- Grid System (based on 80x80 canvas with 4-stud tiles)
Constants.TILE_SIZE = 4
Constants.GRID_WIDTH = 20
Constants.GRID_HEIGHT = 20
Constants.CANVAS_SIZE = Vector3.new(80, 7, 80) -- Size of Canvas part

-- Movement
Constants.MOVE_SPEED = 12 -- Base studs/second
Constants.MOVE_SPEED_MAX = 24 -- Max speed with powerups

-- Camera (overhead following view)
Constants.CAMERA_ANGLE = 60 -- Degrees pitch looking down
Constants.CAMERA_HEIGHT = 25 -- Studs above player
Constants.CAMERA_DISTANCE = 18 -- Studs behind player
Constants.CAMERA_FOV = 55
Constants.CAMERA_SMOOTHING = 0.15 -- Lerp factor per frame

-- Bombs
Constants.BOMB_FUSE_TIME = 2.5 -- Seconds before explosion
Constants.BOMB_DEFAULT_RANGE = 1 -- Tiles in each direction
Constants.MAX_BOMBS_DEFAULT = 1 -- Simultaneous bombs per player
Constants.BOMB_SIZE = 1.8 -- Diameter in studs

-- Health
Constants.PLAYER_LIVES_DEFAULT = 1
Constants.INVINCIBILITY_FRAMES = 1.5 -- Seconds of invincibility after hit

-- Map Generation
Constants.SOFT_WALL_DENSITY = 0.55
Constants.POWERUP_SPAWN_CHANCE = 0.30
Constants.COIN_SPAWN_CHANCE = 0.50 -- For Coin Grab mode

-- Round Timing
Constants.LOBBY_WAIT_TIME = 20
Constants.CHARACTER_SELECT_TIME = 8
Constants.COUNTDOWN_TIME = 3
Constants.ROUND_LENGTH = 120 -- 2 minutes
Constants.ROUND_END_TIME = 3
Constants.INTERMISSION_TIME = 30
Constants.MIN_PLAYERS = 2
Constants.MAX_PLAYERS = 6

-- XP Rewards
Constants.XP_PER_KILL = 100
Constants.XP_PER_DEMOLITION = 10
Constants.XP_PER_POWERUP = 25
Constants.XP_WIN_BONUS = 200

-- XP Leveling
Constants.XP_PER_LEVEL_BASE = 300
Constants.XP_PER_LEVEL_GROWTH = 100
-- XP needed for level L = BASE + (L-1) * GROWTH
-- Level 1: 300, Level 2: 400, Level 5: 700, Level 10: 1200, Level 20: 2200

function Constants.GetLevelInfo(totalXp: number): (number, number, number)
	-- Returns: level, xpProgressInLevel, xpNeededForLevel
	local level = 1
	local remaining = totalXp
	while true do
		local needed = Constants.XP_PER_LEVEL_BASE + (level - 1) * Constants.XP_PER_LEVEL_GROWTH
		if remaining < needed then
			return level, remaining, needed
		end
		remaining = remaining - needed
		level = level + 1
	end
end

-- Level titles (sorted by min level, highest first for lookup)
Constants.LEVEL_TITLES = {
	{minLevel = 50, title = "Bomb God"},
	{minLevel = 40, title = "Demolition King"},
	{minLevel = 30, title = "Blast Master"},
	{minLevel = 25, title = "Bomb Expert"},
	{minLevel = 20, title = "Detonator"},
	{minLevel = 15, title = "Dynamite"},
	{minLevel = 10, title = "Firecracker"},
	{minLevel = 7,  title = "Fuse Lighter"},
	{minLevel = 4,  title = "Spark"},
	{minLevel = 1,  title = "Rookie"},
}

function Constants.GetTitle(level: number): string
	for _, entry in ipairs(Constants.LEVEL_TITLES) do
		if level >= entry.minLevel then
			return entry.title
		end
	end
	return "Rookie"
end

-- VFX
Constants.EXPLOSION_DURATION = 0.4
Constants.WALL_DESTROY_DURATION = 0.2

-- Pooling
Constants.MAX_BOMB_POOL = 20
Constants.MAX_EXPLOSION_POOL = 50

-- Colors (pastel anime style)
Constants.COLORS = {
	FLOOR_LIGHT = Color3.fromRGB(255, 222, 173), -- Warm sand/peach
	FLOOR_DARK = Color3.fromRGB(238, 203, 153),  -- Darker sand
	HARD_WALL = Color3.fromRGB(169, 169, 169),   -- Silver gray stone
	SOFT_WALL = Color3.fromRGB(180, 210, 140),   -- Soft green (bushes/crates)
	BOMB = Color3.fromRGB(50, 50, 60),           -- Dark blue-gray
	EXPLOSION = Color3.fromRGB(255, 180, 80),    -- Warm orange
	LOBBY_FLOOR = Color3.fromRGB(200, 200, 210), -- Light gray-blue
	BORDER = Color3.fromRGB(120, 160, 120),      -- Hedge green
}

-- Power-Up Types
Constants.POWERUP_TYPES = {
	BOMB_UP = {
		id = "BOMB_UP",
		name = "+1 Bomb",
		mesh = "Bomb", -- ReplicatedStorage/Assets/Powerups/Bomb
		icon = "💣",
		color = Color3.fromRGB(255, 100, 100), -- Red
	},
	FIRE_UP = {
		id = "FIRE_UP",
		name = "+1 Range",
		mesh = "Fire", -- ReplicatedStorage/Assets/Powerups/Fire
		icon = "🔥",
		color = Color3.fromRGB(255, 165, 0), -- Orange
	},
	SPEED_UP = {
		id = "SPEED_UP",
		name = "Speed Boost",
		mesh = "Lightning", -- ReplicatedStorage/Assets/Powerups/Lightning
		icon = "⚡",
		color = Color3.fromRGB(255, 255, 0), -- Yellow
	},
}

-- Player scale when in-game (slightly smaller for arena feel)
Constants.IN_GAME_SCALE = 0.85

-- Game States
Constants.STATES = {
	LOBBY = "Lobby",
	CHARACTER_SELECT = "CharacterSelect",
	PREPARING = "Preparing",
	COUNTDOWN = "Countdown",
	PLAYING = "Playing",
	ROUND_END = "RoundEnd",
	ROUND_RESULTS = "RoundResults",
	FADE_TO_LOBBY = "FadeToLobby",
	INTERMISSION = "Intermission",
}

-- Game Modes
Constants.MODES = {
	FFA = {
		id = "FFA",
		name = "Free For All",
		maxPlayers = 6,
		lives = 1,
		teamSize = 1,
		collectCoins = false,
	},
	TEAM = {
		id = "TEAM",
		name = "3v3",
		maxPlayers = 6,
		lives = 1,
		teamSize = 3,
		collectCoins = false,
	},
	COIN_GRAB = {
		id = "COIN_GRAB",
		name = "Coin Grab",
		maxPlayers = 6,
		lives = 3,
		teamSize = 1,
		collectCoins = true,
		coinTarget = 10,
	},
	COLOR_BATTLE = {
		id = "COLOR_BATTLE",
		name = "Color Battle",
		maxPlayers = 6,
		lives = 1,
		teamSize = 1,
		collectCoins = false,
		paintTiles = true,
	},
	FALLING_TILES = {
		id = "FALLING_TILES",
		name = "Falling Tiles",
		maxPlayers = 6,
		lives = 1,
		teamSize = 1,
		collectCoins = false,
		fallingTiles = true,
	},
	RESPAWN = {
		id = "RESPAWN",
		name = "Respawn",
		maxPlayers = 6,
		lives = 1,
		teamSize = 1,
		collectCoins = false,
		respawn = true,
	},
}

-- Player colors for Color Battle mode (up to 6 players)
Constants.PLAYER_COLORS = {
	{ name = "Red",    fill = Color3.fromRGB(255, 50, 50),   stroke = Color3.fromRGB(140, 15, 15),  tile = Color3.fromRGB(255, 70, 70) },
	{ name = "Blue",   fill = Color3.fromRGB(50, 100, 255),  stroke = Color3.fromRGB(15, 35, 140),  tile = Color3.fromRGB(70, 120, 255) },
	{ name = "Yellow", fill = Color3.fromRGB(255, 220, 40),  stroke = Color3.fromRGB(140, 110, 10), tile = Color3.fromRGB(255, 230, 70) },
	{ name = "White",  fill = Color3.fromRGB(240, 240, 240), stroke = Color3.fromRGB(120, 120, 120), tile = Color3.fromRGB(245, 245, 245) },
	{ name = "Pink",   fill = Color3.fromRGB(255, 100, 180), stroke = Color3.fromRGB(140, 40, 90),  tile = Color3.fromRGB(255, 120, 190) },
	{ name = "Black",  fill = Color3.fromRGB(40, 40, 40),    stroke = Color3.fromRGB(10, 10, 10),   tile = Color3.fromRGB(55, 55, 55) },
}

-- Admin Events
Constants.ADMIN_EVENTS = {
	MAP_BREAK = "mapbreak",
	COIN_RAIN = "coinrain",
	SIZE_CHAOS = "sizechaos",
	SPEED_GOD = "speedgod",
	BOMB_PARTY = "bombparty",
}

-- Admin User IDs (add your own)
Constants.ADMIN_IDS = {
	-- Add admin UserIds here
}

-- Emotes (animation IDs)
Constants.EMOTES = {
	{id = "wave", name = "Wave", icon = "👋", animId = "rbxassetid://507770239"},
	{id = "cheer", name = "Cheer", icon = "🎉", animId = "rbxassetid://507771019"},
	{id = "dance", name = "Dance", icon = "💃", animId = "rbxassetid://507771955"},
	{id = "laugh", name = "Laugh", icon = "😂", animId = "rbxassetid://507770818"},
	{id = "point", name = "Point", icon = "👉", animId = "rbxassetid://507770453"},
	{id = "salute", name = "Salute", icon = "🫡", animId = "rbxassetid://507771176"},
}

-- Stickers (displayed above head)
Constants.STICKERS = {
	{id = "gg", text = "GG!", color = Color3.fromRGB(100, 255, 100)},
	{id = "wow", text = "WOW!", color = Color3.fromRGB(255, 200, 50)},
	{id = "lol", text = "LOL", color = Color3.fromRGB(255, 100, 255)},
	{id = "ez", text = "EZ", color = Color3.fromRGB(255, 50, 50)},
	{id = "nice", text = "NICE!", color = Color3.fromRGB(50, 200, 255)},
	{id = "oof", text = "OOF", color = Color3.fromRGB(255, 150, 50)},
}

-- Game Mode Selection (slot machine UI)
Constants.PLAYER_FORMATS = {
	{ id = "FFA", name = "FFA", teamSize = 1 },
	{ id = "2V2", name = "2v2", teamSize = 2 },
	{ id = "3V3", name = "3v3", teamSize = 3 },
}

Constants.GAME_TYPES = {
	{ id = "STANDARD", name = "Standard" },
	{ id = "COLOR_BATTLE", name = "Color Battle" },
	{ id = "FLOOR_IS_LAVA", name = "Floor is Lava" },
	{ id = "RESPAWN", name = "Respawn" },
}

Constants.MODE_SELECTION_DURATION = 5

-- Maps (formatId .. "_" .. typeId) → MODES key
Constants.MODE_MAP = {
	FFA_STANDARD = "FFA",
	FFA_COLOR_BATTLE = "COLOR_BATTLE",
	FFA_FLOOR_IS_LAVA = "FALLING_TILES",
	["2V2_STANDARD"] = "FFA",
	["2V2_COLOR_BATTLE"] = "COLOR_BATTLE",
	["2V2_FLOOR_IS_LAVA"] = "FALLING_TILES",
	["3V3_STANDARD"] = "TEAM",
	["3V3_COLOR_BATTLE"] = "COLOR_BATTLE",
	["3V3_FLOOR_IS_LAVA"] = "FALLING_TILES",
	FFA_RESPAWN = "RESPAWN",
	["2V2_RESPAWN"] = "RESPAWN",
	["3V3_RESPAWN"] = "RESPAWN",
}

-- Look up MODE_MAP, shallow-copy the base mode table, override teamSize from format
function Constants.GetModeFromCombo(formatId: string, typeId: string)
	local key = formatId .. "_" .. typeId
	local modeKey = Constants.MODE_MAP[key]
	if not modeKey then
		modeKey = "FFA"
	end

	local baseMode = Constants.MODES[modeKey]
	if not baseMode then
		baseMode = Constants.MODES.FFA
	end

	-- Shallow copy
	local mode = {}
	for k, v in pairs(baseMode) do
		mode[k] = v
	end

	-- Override teamSize from the format entry
	for _, fmt in ipairs(Constants.PLAYER_FORMATS) do
		if fmt.id == formatId then
			mode.teamSize = fmt.teamSize
			break
		end
	end

	return mode
end

-- Respawn Mode
Constants.RESPAWN_INVULN_DURATION = 3    -- seconds of invulnerability after respawn
Constants.RESPAWN_BLINK_INTERVAL = 0.15  -- seconds per blink cycle
Constants.RESPAWN_DELAY = 1.5            -- seconds of ragdoll before teleporting

-- Sound IDs (Roblox asset IDs) - using verified working sounds
Constants.SOUNDS = {
	EXPLOSION = "rbxassetid://5801257793",
	POWERUP = "rbxassetid://5801257793",
	COUNTDOWN = "rbxassetid://5801257793",
	WIN = "rbxassetid://5801257793",
	PLACE_BOMB = "rbxassetid://5801257793",
}

return Constants
