--!strict
-- Constants.lua
-- Single source of truth for all tunable game values

local Constants = {}

-- Grid System (based on 90x90 canvas with 4-stud tiles)
Constants.TILE_SIZE = 4
Constants.GRID_WIDTH = 22
Constants.GRID_HEIGHT = 22
Constants.CANVAS_SIZE = Vector3.new(90, 21, 90) -- Size of Canvas part

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
Constants.BOMB_DEFAULT_RANGE = 2 -- Tiles in each direction
Constants.MAX_BOMBS_DEFAULT = 1 -- Simultaneous bombs per player
Constants.BOMB_SIZE = 1.8 -- Diameter in studs

-- Health
Constants.PLAYER_LIVES_DEFAULT = 1
Constants.INVINCIBILITY_FRAMES = 1.5 -- Seconds of invincibility after hit

-- Map Generation
Constants.SOFT_WALL_DENSITY = 0.55
Constants.POWERUP_SPAWN_CHANCE = 0.25
Constants.COIN_SPAWN_CHANCE = 0.50 -- For Coin Grab mode

-- Round Timing
Constants.LOBBY_WAIT_TIME = 10
Constants.CHARACTER_SELECT_TIME = 8
Constants.COUNTDOWN_TIME = 3
Constants.ROUND_LENGTH = 120 -- 2 minutes
Constants.ROUND_END_TIME = 3
Constants.INTERMISSION_TIME = 4
Constants.MIN_PLAYERS = 1 -- Set to 1 for testing
Constants.MAX_PLAYERS = 6

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
		color = Color3.fromRGB(255, 165, 0), -- Orange
		icon = "💣",
	},
	FIRE_UP = {
		id = "FIRE_UP",
		name = "+1 Range",
		color = Color3.fromRGB(255, 50, 50), -- Red
		icon = "🔥",
	},
	SPEED_UP = {
		id = "SPEED_UP",
		name = "Speed Boost",
		color = Color3.fromRGB(255, 255, 0), -- Yellow
		icon = "⚡",
	},
	SHIELD = {
		id = "SHIELD",
		name = "Shield",
		color = Color3.fromRGB(0, 255, 255), -- Cyan
		icon = "🛡️",
	},
	SKULL = {
		id = "SKULL",
		name = "Curse",
		color = Color3.fromRGB(148, 0, 211), -- Purple
		icon = "💀",
	},
}

-- Character Data
Constants.CHARACTERS = {
	{
		id = 1,
		name = "Sparky",
		bodyColor = Color3.fromRGB(255, 255, 0), -- Bright Yellow
		accentColor = Color3.fromRGB(255, 165, 0), -- Orange
		accessory = "lightning",
	},
	{
		id = 2,
		name = "Bubbles",
		bodyColor = Color3.fromRGB(135, 206, 235), -- Sky Blue
		accentColor = Color3.fromRGB(255, 255, 255), -- White
		accessory = "bow",
	},
	{
		id = 3,
		name = "Ember",
		bodyColor = Color3.fromRGB(255, 50, 50), -- Bright Red
		accentColor = Color3.fromRGB(139, 0, 0), -- Dark Red
		accessory = "flame",
	},
	{
		id = 4,
		name = "Clover",
		bodyColor = Color3.fromRGB(50, 205, 50), -- Lime Green
		accentColor = Color3.fromRGB(0, 100, 0), -- Dark Green
		accessory = "leaf",
	},
	{
		id = 5,
		name = "Midnight",
		bodyColor = Color3.fromRGB(75, 0, 130), -- Dark Purple
		accentColor = Color3.fromRGB(0, 255, 255), -- Cyan
		accessory = "star",
	},
	{
		id = 6,
		name = "Snowball",
		bodyColor = Color3.fromRGB(255, 255, 255), -- White
		accentColor = Color3.fromRGB(173, 216, 230), -- Light Blue
		accessory = "snowflake",
	},
}

-- Game States
Constants.STATES = {
	LOBBY = "Lobby",
	CHARACTER_SELECT = "CharacterSelect",
	COUNTDOWN = "Countdown",
	PLAYING = "Playing",
	ROUND_END = "RoundEnd",
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

-- Winners podium positions (relative to podium center)
Constants.PODIUM_POSITIONS = {
	{place = 1, offset = Vector3.new(0, 6, 0), height = 6},      -- 1st place (center, tallest)
	{place = 2, offset = Vector3.new(-6, 4, 0), height = 4},    -- 2nd place (left)
	{place = 3, offset = Vector3.new(6, 2, 0), height = 2},     -- 3rd place (right)
}

-- Sound IDs (Roblox asset IDs) - using verified working sounds
Constants.SOUNDS = {
	EXPLOSION = "rbxassetid://5801257793",
	POWERUP = "rbxassetid://5801257793",
	COUNTDOWN = "rbxassetid://5801257793",
	WIN = "rbxassetid://5801257793",
	PLACE_BOMB = "rbxassetid://5801257793",
}

return Constants
