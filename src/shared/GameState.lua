--!strict
-- GameState.lua
-- Shared game state management

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local GameState = {}
GameState.__index = GameState

-- Current state data
GameState.currentState = Constants.STATES.LOBBY
GameState.currentMode = Constants.MODES.FFA
GameState.roundTimer = 0
GameState.players = {} -- {[userId] = playerData}
GameState.persistentData = {} -- {[userId] = {totalXp: number}}
GameState.colorAssignments = {} :: {[number]: number} -- {[userId] = colorIndex} for Color Battle
GameState.teamAssignments = {} :: {[number]: number} -- {[userId] = teamIndex} for team modes
GameState.gamepassCache = {} :: {[number]: {vip: boolean, doubleCoins: boolean, allBlue: boolean}} -- {[userId] = passes}
GameState.luckBoostExpiry = {} :: {[number]: number} -- {[userId] = os.time() expiry timestamp}

-- Player data structure
export type PlayerData = {
	userId: number,
	lives: number,
	bombCount: number,
	bombRange: number,
	speed: number,
	hasShield: boolean,
	coins: number,
	kills: number,
	demolitions: number,
	powerupsCollected: number,
	isAlive: boolean,
	activeBombs: number,
	curseEndTime: number?,
	colorIndex: number,
	tilesOwned: number,
	invulnerable: boolean,
}

function GameState.CreatePlayerData(userId: number): PlayerData
	return {
		userId = userId,
		lives = Constants.PLAYER_LIVES_DEFAULT,
		bombCount = Constants.MAX_BOMBS_DEFAULT,
		bombRange = Constants.BOMB_DEFAULT_RANGE,
		speed = Constants.MOVE_SPEED,
		hasShield = false,
		coins = 0,
		kills = 0,
		demolitions = 0,
		powerupsCollected = 0,
		isAlive = true,
		activeBombs = 0,
		curseEndTime = nil,
		colorIndex = 0,
		tilesOwned = 0,
		invulnerable = false,
	}
end

function GameState.ResetPlayerForRound(playerData: PlayerData)
	playerData.lives = GameState.currentMode.lives or Constants.PLAYER_LIVES_DEFAULT
	playerData.bombCount = Constants.MAX_BOMBS_DEFAULT
	playerData.bombRange = Constants.BOMB_DEFAULT_RANGE
	playerData.speed = Constants.MOVE_SPEED
	playerData.hasShield = false
	playerData.coins = 0
	playerData.kills = 0
	playerData.demolitions = 0
	playerData.powerupsCollected = 0
	playerData.isAlive = true
	playerData.activeBombs = 0
	playerData.curseEndTime = nil
	playerData.colorIndex = 0
	playerData.tilesOwned = 0
	playerData.invulnerable = false
end

function GameState.ApplyPowerUp(playerData: PlayerData, powerUpType: string)
	local powerUp = Constants.POWERUP_TYPES[powerUpType]
	if not powerUp then return end

	if powerUpType == "BOMB_UP" then
		playerData.bombCount = playerData.bombCount + 1
	elseif powerUpType == "FIRE_UP" then
		playerData.bombRange = playerData.bombRange + 1
	elseif powerUpType == "SPEED_UP" then
		playerData.speed = math.min(playerData.speed + 3, Constants.MOVE_SPEED_MAX)
	end
end

function GameState.TakeDamage(playerData: PlayerData): boolean
	-- Returns true if player was eliminated
	if playerData.hasShield then
		playerData.hasShield = false
		return false
	end

	playerData.lives = playerData.lives - 1
	if playerData.lives <= 0 then
		playerData.isAlive = false
		return true
	end
	return false
end

function GameState.GetAlivePlayers(): {PlayerData}
	local alive = {}
	for _, data in pairs(GameState.players) do
		if data.isAlive then
			table.insert(alive, data)
		end
	end
	return alive
end

function GameState.GetPlayerCount(): number
	local count = 0
	for _ in pairs(GameState.players) do
		count = count + 1
	end
	return count
end

-- AFK check — set by GameManager, called by RoundSystem
-- Default implementation (overridden by GameManager at runtime)
GameState.IsPlayerAFK = function(_userId: number): boolean
	return false
end

return GameState
