--!strict
-- GameManager.server.lua
-- Main server script that initializes all systems and manages game flow

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapData = require(Shared:WaitForChild("MapData"))

-- Create RemoteEvents
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local function CreateRemote(name: string, className: string): Instance
	local existing = Remotes:FindFirstChild(name)
	if existing then return existing end

	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = Remotes
	return remote
end

local PlaceBomb = CreateRemote("PlaceBomb", "RemoteEvent")
local PlayerMoved = CreateRemote("PlayerMoved", "RemoteEvent")
local RoundStateChanged = CreateRemote("RoundStateChanged", "RemoteEvent")
local CharacterSelected = CreateRemote("CharacterSelected", "RemoteEvent")
local PowerUpCollected = CreateRemote("PowerUpCollected", "RemoteEvent")
local AdminEvent = CreateRemote("AdminEvent", "RemoteEvent")
local UpdateHUD = CreateRemote("UpdateHUD", "RemoteEvent")
local RequestCharacterSelect = CreateRemote("RequestCharacterSelect", "RemoteEvent")
local PlayerDied = CreateRemote("PlayerDied", "RemoteEvent")
local SyncPlayerData = CreateRemote("SyncPlayerData", "RemoteEvent")

-- DataStore
local PlayerDataStore = DataStoreService:GetDataStore("BombThemPlayerData_v1")

-- Module references (loaded after initialization)
local RoundSystem
local BombService
local MapGenerator
local PowerUpService
local AnimationService

-- Player data storage
local playerSaveData = {} :: {[number]: {wins: number, totalCoins: number, equippedCosmetics: {}, ownedCosmetics: {}}}

-- Load player data from DataStore
local function LoadPlayerData(player: Player)
	local success, data = pcall(function()
		return PlayerDataStore:GetAsync("Player_" .. player.UserId)
	end)

	if success and data then
		playerSaveData[player.UserId] = data
	else
		playerSaveData[player.UserId] = {
			wins = 0,
			totalCoins = 0,
			equippedCosmetics = {},
			ownedCosmetics = {},
		}
	end

	-- Initialize game state for player
	GameState.players[player.UserId] = GameState.CreatePlayerData(player.UserId)
end

-- Save player data to DataStore
local function SavePlayerData(player: Player)
	local data = playerSaveData[player.UserId]
	if not data then return end

	local success, err = pcall(function()
		PlayerDataStore:SetAsync("Player_" .. player.UserId, data)
	end)

	if not success then
		warn("Failed to save player data for " .. player.Name .. ": " .. tostring(err))
	end
end

-- Handle player joining
local function OnPlayerAdded(player: Player)
	LoadPlayerData(player)

	-- Sync player data to client
	SyncPlayerData:FireClient(player, GameState.players[player.UserId])

	-- Notify round system of new player
	if RoundSystem then
		RoundSystem.OnPlayerAdded(player)
	end
end

-- Handle player leaving
local function OnPlayerRemoving(player: Player)
	SavePlayerData(player)

	-- Clean up game state
	GameState.players[player.UserId] = nil
	playerSaveData[player.UserId] = nil

	-- Notify round system
	if RoundSystem then
		RoundSystem.OnPlayerRemoved(player)
	end
end

-- Handle character selection
CharacterSelected.OnServerEvent:Connect(function(player: Player, characterId: number)
	local playerData = GameState.players[player.UserId]
	if not playerData then return end

	-- Validate character ID
	if characterId < 1 or characterId > #Constants.CHARACTERS then
		characterId = 1
	end

	playerData.characterId = characterId

	-- Notify other clients
	RoundStateChanged:FireAllClients("CharacterSelected", {
		userId = player.UserId,
		characterId = characterId,
	})
end)

-- Handle player position updates (anti-cheat validation)
PlayerMoved.OnServerEvent:Connect(function(player: Player, position: Vector3)
	-- Basic validation - could add more sophisticated anti-cheat here
	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end

	-- For now, just acknowledge the update
	-- Could add speed/teleport hack detection here
end)

-- Admin command handling
local function IsAdmin(player: Player): boolean
	for _, adminId in ipairs(Constants.ADMIN_IDS) do
		if player.UserId == adminId then
			return true
		end
	end
	-- Also allow studio testing
	return game:GetService("RunService"):IsStudio()
end

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)
		if not IsAdmin(player) then return end

		local prefix, eventName = string.match(message, "^(/event)%s+(%w+)$")
		if prefix and eventName then
			for eventId, eventCommand in pairs(Constants.ADMIN_EVENTS) do
				if eventCommand == eventName:lower() then
					-- Trigger admin event
					if RoundSystem then
						RoundSystem.TriggerAdminEvent(eventId)
					end
					AdminEvent:FireAllClients(eventId)
					break
				end
			end
		end
	end)
end)

-- Initialize game systems
local function Initialize()
	print("[GameManager] Initializing Bomb Them!")

	-- Initialize map data
	MapData.InitializeGrids()

	-- Load server modules
	local ServerFolder = script.Parent
	RoundSystem = require(ServerFolder:WaitForChild("RoundSystem"))
	BombService = require(ServerFolder:WaitForChild("BombService"))
	MapGenerator = require(ServerFolder:WaitForChild("MapGenerator"))
	PowerUpService = require(ServerFolder:WaitForChild("PowerUpService"))
	AnimationService = require(ServerFolder:WaitForChild("AnimationService"))

	-- Initialize services
	MapGenerator.Initialize()
	BombService.Initialize()
	PowerUpService.Initialize()
	AnimationService.Initialize()
	RoundSystem.Initialize()

	-- Connect player events
	Players.PlayerAdded:Connect(OnPlayerAdded)
	Players.PlayerRemoving:Connect(OnPlayerRemoving)

	-- Handle existing players (in case of script reload)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(OnPlayerAdded, player)
	end

	print("[GameManager] Initialization complete!")
end

-- Start initialization
Initialize()
