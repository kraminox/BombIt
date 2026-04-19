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

-- Player data structure
export type PlayerData = {
	userId: number,
	characterId: number,
	equippedCosmetics: {string}, -- list of accessory names from Outfit1
	lives: number,
	bombCount: number,
	bombRange: number,
	speed: number,
	hasShield: boolean,
	coins: number,
	kills: number,
	isAlive: boolean,
	activeBombs: number,
	curseEndTime: number?,
}

function GameState.CreatePlayerData(userId: number): PlayerData
	return {
		userId = userId,
		characterId = 1,
		equippedCosmetics = {},
		lives = Constants.PLAYER_LIVES_DEFAULT,
		bombCount = Constants.MAX_BOMBS_DEFAULT,
		bombRange = Constants.BOMB_DEFAULT_RANGE,
		speed = Constants.MOVE_SPEED,
		hasShield = false,
		coins = 0,
		kills = 0,
		isAlive = true,
		activeBombs = 0,
		curseEndTime = nil,
	}
end

function GameState.ResetPlayerForRound(playerData: PlayerData)
	playerData.lives = GameState.currentMode.lives or Constants.PLAYER_LIVES_DEFAULT
	playerData.bombCount = Constants.MAX_BOMBS_DEFAULT
	playerData.bombRange = Constants.BOMB_DEFAULT_RANGE
	playerData.speed = Constants.MOVE_SPEED
	playerData.hasShield = false
	playerData.coins = 0
	playerData.isAlive = true
	playerData.activeBombs = 0
	playerData.curseEndTime = nil
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

return GameState
