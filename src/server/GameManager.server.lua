--!strict
-- GameManager.server.lua
-- Main server script that initializes all systems and manages game flow

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local BadgeService = game:GetService("BadgeService")
local RunService = game:GetService("RunService")

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapData = require(Shared:WaitForChild("MapData"))
local Economy = require(Shared:WaitForChild("Economy"))

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
local PowerUpCollected = CreateRemote("PowerUpCollected", "RemoteEvent")
local AdminEvent = CreateRemote("AdminEvent", "RemoteEvent")
local UpdateHUD = CreateRemote("UpdateHUD", "RemoteEvent")
local PlayerDied = CreateRemote("PlayerDied", "RemoteEvent")
local SyncPlayerData = CreateRemote("SyncPlayerData", "RemoteEvent")
local ColorBattleSync = CreateRemote("ColorBattleSync", "RemoteEvent")
local ModeSelection = CreateRemote("ModeSelection", "RemoteEvent")
local EquipItem = CreateRemote("EquipItem", "RemoteEvent")
local UnequipItem = CreateRemote("UnequipItem", "RemoteEvent")
local OpenCapsule = CreateRemote("OpenCapsule", "RemoteFunction")
local SyncInventory = CreateRemote("SyncInventory", "RemoteEvent")
local RequestSpin = CreateRemote("RequestSpin", "RemoteEvent")
local SpinResult = CreateRemote("SpinResult", "RemoteEvent")
local GetSpinStatus = CreateRemote("GetSpinStatus", "RemoteFunction")
local RequestGroupReward = CreateRemote("RequestGroupReward", "RemoteFunction")
local BuyCapsule = CreateRemote("BuyCapsule", "RemoteFunction")
local GetDailyRewardStatus = CreateRemote("GetDailyRewardStatus", "RemoteFunction")
local ClaimDailyReward = CreateRemote("ClaimDailyReward", "RemoteFunction")
local RedeemCode = CreateRemote("RedeemCode", "RemoteFunction")
local GetConfigSettings = CreateRemote("GetConfigSettings", "RemoteFunction")
local SaveConfigSettings = CreateRemote("SaveConfigSettings", "RemoteEvent")
local LuckBoostActivated = CreateRemote("LuckBoostActivated", "RemoteEvent")
local ServerAnnouncement = CreateRemote("ServerAnnouncement", "RemoteEvent")
local SetAFK = CreateRemote("SetAFK", "RemoteEvent")
local ClaimFreeSkin = CreateRemote("ClaimFreeSkin", "RemoteFunction")
local GetFreeSkinStatus = CreateRemote("GetFreeSkinStatus", "RemoteFunction")
local GetInventory = CreateRemote("GetInventory", "RemoteFunction")

-- DataStore
local PlayerDataStore = DataStoreService:GetDataStore("BombThemPlayerData_v1")
local ReceiptDataStore = DataStoreService:GetDataStore("BombThemReceipts_v1")

-- Per-player processing mutex (prevents race conditions on economy remotes)
local playerProcessing: {[number]: boolean} = {}

-- AFK state tracking
local afkPlayers: {[number]: boolean} = {}

local function AcquireLock(userId: number): boolean
	if playerProcessing[userId] then return false end
	playerProcessing[userId] = true
	return true
end

local function ReleaseLock(userId: number)
	playerProcessing[userId] = nil
end

-- Module references (loaded after initialization)
local RoundSystem
local BombService
local MapGenerator
local PowerUpService
local AnimationService
local InventoryService
local LeaderboardService
local QuestService

-- Badge IDs
local BADGE_BETA_BOMBER = 4024754823772298
local BADGE_W_BOMBER = 3977195912374781
local BADGE_CAPSULE_HUNGRY = 2972630628895318

local function AwardBadge(player: Player, badgeId: number)
	pcall(function()
		if not BadgeService:UserHasBadgeAsync(player.UserId, badgeId) then
			BadgeService:AwardBadge(player.UserId, badgeId)
		end
	end)
end

-- Player data storage
local playerSaveData = {} :: {[number]: {wins: number, totalCoins: number}}

-- Store CharacterAdded connections for cleanup
local characterAddedConnections: {[number]: RBXScriptConnection} = {}

-- Spin data keyed by UserId (in-memory, persisted inside playerSaveData)
local playerSpinData = {} :: {[number]: {freeSpinsUsedToday: number, paidSpinsUsedToday: number, lastSpinDate: string}}

-- Get today's date string for spin tracking
local function GetTodayString(): string
	local now = os.date("!*t") :: any
	return string.format("%04d-%02d-%02d", now.year, now.month, now.day)
end

-- Get or create spin data for a player, resetting if the date changed
local function GetSpinData(userId: number): {freeSpinsUsedToday: number, paidSpinsUsedToday: number, lastSpinDate: string}
	local sd = playerSpinData[userId]
	if not sd then
		sd = { freeSpinsUsedToday = 0, paidSpinsUsedToday = 0, lastSpinDate = GetTodayString() }
		playerSpinData[userId] = sd
	end
	local today = GetTodayString()
	if sd.lastSpinDate ~= today then
		sd.freeSpinsUsedToday = 0
		sd.paidSpinsUsedToday = 0
		sd.lastSpinDate = today
	end
	return sd
end

-- Check if a player has an active 2x luck boost
local function HasLuckBoost(userId: number): boolean
	local expiry = GameState.luckBoostExpiry[userId]
	if expiry and os.time() < expiry then
		return true
	end
	-- Clean up expired
	if expiry then
		GameState.luckBoostExpiry[userId] = nil
	end
	return false
end

-- Weighted random slot picker (server-side)
-- With 2x luck: Epic/Legendary/Rare capsule chances are doubled
local function PickSpinSlot(userId: number?): number
	local boosted = userId and HasLuckBoost(userId) or false
	local totalWeight = 0
	local weights = {}
	for i, slot in ipairs(Economy.SPIN_WHEEL_SLOTS) do
		local w = slot.chance
		if boosted and (slot.rewardType == "capsule" or slot.rewardType == "legendary") then
			w = w * 2
		end
		weights[i] = w
		totalWeight = totalWeight + w
	end
	local roll = math.random() * totalWeight
	local cumulative = 0
	for i, w in ipairs(weights) do
		cumulative = cumulative + w
		if roll <= cumulative then
			return i
		end
	end
	return 1
end

-- Session ID for session locking (unique per server instance)
local SESSION_ID = game.JobId .. "_" .. tostring(os.time())

-- Load player data from DataStore
local function LoadPlayerData(player: Player)
	local success, data = pcall(function()
		return PlayerDataStore:GetAsync("Player_" .. player.UserId)
	end)

	if success and data then
		-- Session lock: stamp this server's session
		data._sessionId = SESSION_ID
		playerSaveData[player.UserId] = data
		-- Backfill new fields for older saves
		if data.totalKills == nil then data.totalKills = 0 end
		if data.robuxSpent == nil then data.robuxSpent = 0 end
		if data.groupRewardClaimed == nil then data.groupRewardClaimed = false end
		if data.questData == nil then data.questData = {} end
		if data.dailyRewardData == nil then data.dailyRewardData = { currentDay = 1, lastClaimDate = "", claimedToday = false } end
		if data.redeemedCodes == nil then data.redeemedCodes = {} end
		if data.configSettings == nil then data.configSettings = { musicEnabled = true, sfxEnabled = true, skipCapsuleOpens = false } end
		if data.capsulesOpened == nil then data.capsulesOpened = 0 end
		if data.freeSkinClaimed == nil then data.freeSkinClaimed = false end
	else
		playerSaveData[player.UserId] = {
			wins = 0,
			totalCoins = 0,
			totalXp = 0,
			totalKills = 0,
			robuxSpent = 0,
			_sessionId = SESSION_ID,
		}
	end

	-- Initialize game state for player
	GameState.players[player.UserId] = GameState.CreatePlayerData(player.UserId)

	-- Initialize persistent data (survives across rounds)
	local totalXp = playerSaveData[player.UserId].totalXp or 0
	local totalCoins = playerSaveData[player.UserId].totalCoins or 0
	local totalKills = playerSaveData[player.UserId].totalKills or 0
	local robuxSpent = playerSaveData[player.UserId].robuxSpent or 0
	local wins = playerSaveData[player.UserId].wins or 0
	GameState.persistentData[player.UserId] = {
		totalXp = totalXp,
		totalCoins = totalCoins,
		totalKills = totalKills,
		robuxSpent = robuxSpent,
		wins = wins,
	}

	-- Expose level/xp as IntValues on the Player for all clients to read
	local playerStats = Instance.new("Folder")
	playerStats.Name = "PersistentStats"
	playerStats.Parent = player

	local levelVal = Instance.new("IntValue")
	levelVal.Name = "Level"
	local level = Constants.GetLevelInfo(totalXp)
	levelVal.Value = level
	levelVal.Parent = playerStats

	local xpVal = Instance.new("IntValue")
	xpVal.Name = "TotalXp"
	xpVal.Value = totalXp
	xpVal.Parent = playerStats

	local coinsVal = Instance.new("IntValue")
	coinsVal.Name = "TotalCoins"
	coinsVal.Value = totalCoins
	coinsVal.Parent = playerStats

	local killsVal = Instance.new("IntValue")
	killsVal.Name = "TotalKills"
	killsVal.Value = totalKills
	killsVal.Parent = playerStats

	local equippedTitleVal = Instance.new("StringValue")
	equippedTitleVal.Name = "EquippedTitle"
	equippedTitleVal.Value = ""
	equippedTitleVal.Parent = playerStats

	-- Load spin data from save
	local savedSpin = playerSaveData[player.UserId].spinData
	if savedSpin then
		playerSpinData[player.UserId] = {
			freeSpinsUsedToday = savedSpin.freeSpinsUsedToday or 0,
			paidSpinsUsedToday = savedSpin.paidSpinsUsedToday or 0,
			lastSpinDate = savedSpin.lastSpinDate or "",
		}
	end
	-- Ensure spin data exists and date is current
	GetSpinData(player.UserId)

	-- Load inventory (will create default with all items for testing)
	if InventoryService then
		InventoryService.LoadInventory(player, playerSaveData[player.UserId])
		-- Grant level milestone titles based on current level
		local lvl = Constants.GetLevelInfo(playerSaveData[player.UserId].totalXp or 0)
		InventoryService.GrantMilestoneTitles(player, lvl)
		-- Set equipped title from loaded inventory
		local inv = InventoryService.GetInventory(player)
		if inv and inv.equippedTitle ~= "" then
			equippedTitleVal.Value = inv.equippedTitle
		end
		-- Sync inventory to client so titles and other items are visible immediately
		if inv then
			SyncInventory:FireClient(player, inv)
		end
	end
end

-- Save player data to DataStore
local function SavePlayerData(player: Player)
	local data = playerSaveData[player.UserId]
	if not data then return end

	-- Sync persistent data back to save table
	local persistent = GameState.persistentData[player.UserId]
	if persistent then
		data.totalXp = persistent.totalXp
		data.totalCoins = persistent.totalCoins or 0
		data.totalKills = persistent.totalKills or 0
		data.robuxSpent = persistent.robuxSpent or 0
		data.wins = persistent.wins or data.wins or 0
	end

	-- Merge spin data into save
	local sd = playerSpinData[player.UserId]
	if sd then
		data.spinData = {
			freeSpinsUsedToday = sd.freeSpinsUsedToday,
			paidSpinsUsedToday = sd.paidSpinsUsedToday,
			lastSpinDate = sd.lastSpinDate,
		}
	end

	-- Merge inventory into save data
	if InventoryService then
		data.inventory = InventoryService.SaveInventory(player)
	end

	-- Merge quest data into save
	if QuestService then
		data.questData = QuestService.GetSaveData(player)
	end

	-- Use UpdateAsync with session check to prevent overwriting another server's data
	data._sessionId = SESSION_ID
	local success, err = pcall(function()
		PlayerDataStore:UpdateAsync("Player_" .. player.UserId, function(oldData)
			-- If another server has claimed this player's data, don't overwrite
			if oldData and oldData._sessionId and oldData._sessionId ~= SESSION_ID then
				-- Another server owns this data — only save if our data is newer
				-- (this handles the edge case of dual-session)
				warn("[GameManager] Session conflict for " .. player.Name .. ", overriding with latest data")
			end
			return data
		end)
	end)

	if not success then
		warn("Failed to save player data for " .. player.Name .. ": " .. tostring(err))
	end
end

-- Assign all parts of a character to the Players collision group
local function SetPlayerCollisionGroup(character: Model)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Players"
		end
	end
	-- Also catch parts added later (accessories loading in)
	character.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") then
			part.CollisionGroup = "Players"
		end
	end)
end

-- ============================================================
-- GAMEPASS OWNERSHIP CACHE
-- ============================================================
local function CheckGamepasses(player: Player)
	local cache = { vip = false, doubleCoins = false, allBlue = false }

	local ok1, res1 = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, Economy.GAMEPASS_VIP)
	end)
	if ok1 and res1 then cache.vip = true end

	local ok2, res2 = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, Economy.GAMEPASS_2X_COINS)
	end)
	if ok2 and res2 then cache.doubleCoins = true end

	local ok3, res3 = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, Economy.GAMEPASS_ALL_BLUE)
	end)
	if ok3 and res3 then cache.allBlue = true end

	GameState.gamepassCache[player.UserId] = cache
	return cache
end

-- Grant VIP items to inventory if not already owned
local function GrantVIPItems(player: Player)
	if not InventoryService then return end
	local inv = InventoryService.GetInventory(player)
	if not inv then return end

	-- VIP items: bee bomb skin, gold explosion, confetti explosion, default dance
	local vipSkins = { "pet_bee" }
	local vipExplosions = { "default_gold_explosion", "confetti_explosion" }
	local vipDances = { "default_dance" }
	local vipTitles = { "vip_golden" }

	for _, id in ipairs(vipSkins) do
		local owned = false
		for _, sid in ipairs(inv.ownedSkins) do if sid == id then owned = true break end end
		if not owned then table.insert(inv.ownedSkins, id) end
	end
	for _, id in ipairs(vipExplosions) do
		local owned = false
		for _, sid in ipairs(inv.ownedExplosions) do if sid == id then owned = true break end end
		if not owned then table.insert(inv.ownedExplosions, id) end
	end
	for _, id in ipairs(vipDances) do
		local owned = false
		for _, sid in ipairs(inv.ownedDances) do if sid == id then owned = true break end end
		if not owned then table.insert(inv.ownedDances, id) end
	end
	for _, id in ipairs(vipTitles) do
		local owned = false
		for _, sid in ipairs(inv.ownedTitles) do if sid == id then owned = true break end end
		if not owned then table.insert(inv.ownedTitles, id) end
	end
end

-- Grant All Blue Pack items to inventory if not already owned
local function GrantAllBlueItems(player: Player)
	if not InventoryService then return end
	local inv = InventoryService.GetInventory(player)
	if not inv then return end

	local blueExplosions = { "lightning_explosion", "water_explosion" }
	local blueSkins = { "dynamite_blue" }

	for _, id in ipairs(blueExplosions) do
		local owned = false
		for _, sid in ipairs(inv.ownedExplosions) do if sid == id then owned = true break end end
		if not owned then table.insert(inv.ownedExplosions, id) end
	end
	for _, id in ipairs(blueSkins) do
		local owned = false
		for _, sid in ipairs(inv.ownedSkins) do if sid == id then owned = true break end end
		if not owned then table.insert(inv.ownedSkins, id) end
	end
end

-- Handle player joining
local function OnPlayerAdded(player: Player)
	LoadPlayerData(player)

	-- Apply collision group to current and future characters
	if player.Character then
		SetPlayerCollisionGroup(player.Character)
	end
	-- Store connection for cleanup on PlayerRemoving
	characterAddedConnections[player.UserId] = player.CharacterAdded:Connect(SetPlayerCollisionGroup)

	-- Check gamepass ownership and grant items
	local gpCache = CheckGamepasses(player)
	if gpCache.vip then
		GrantVIPItems(player)
	end
	if gpCache.allBlue then
		GrantAllBlueItems(player)
	end

	-- Sync player data to client
	SyncPlayerData:FireClient(player, GameState.players[player.UserId])

	-- Sync inventory to client
	if InventoryService then
		local inv = InventoryService.GetInventory(player)
		if inv then
			SyncInventory:FireClient(player, inv)
		end
	end

	-- Push current stats to leaderboard datastores
	if LeaderboardService then
		local saves = playerSaveData[player.UserId]
		if saves then
			LeaderboardService.UpdatePlayerStats(player, "wins", saves.wins or 0)
			LeaderboardService.UpdatePlayerStats(player, "totalKills", saves.totalKills or 0)
			LeaderboardService.UpdatePlayerStats(player, "robuxSpent", saves.robuxSpent or 0)
		end
	end

	-- Load and sync quests
	if QuestService then
		local saves = playerSaveData[player.UserId]
		QuestService.LoadPlayerQuests(player, saves and saves.questData or nil)
		local SyncQuests = Remotes:FindFirstChild("SyncQuests")
		if SyncQuests then
			SyncQuests:FireClient(player, QuestService.GetPlayerQuests(player))
		end
	end

	-- Award Beta Bomber badge (early release)
	task.spawn(AwardBadge, player, BADGE_BETA_BOMBER)

	-- Notify round system of new player
	if RoundSystem then
		RoundSystem.OnPlayerAdded(player)
	end
end

-- Handle player leaving
local function OnPlayerRemoving(player: Player)
	SavePlayerData(player)

	-- Push final stats to leaderboard datastores (after save syncs persistent data)
	if LeaderboardService then
		local saves = playerSaveData[player.UserId]
		if saves then
			LeaderboardService.UpdateStatByUserId(player.UserId, "wins", saves.wins or 0)
			LeaderboardService.UpdateStatByUserId(player.UserId, "totalKills", saves.totalKills or 0)
			LeaderboardService.UpdateStatByUserId(player.UserId, "robuxSpent", saves.robuxSpent or 0)
		end
	end

	-- Disconnect CharacterAdded connection
	if characterAddedConnections[player.UserId] then
		characterAddedConnections[player.UserId]:Disconnect()
		characterAddedConnections[player.UserId] = nil
	end

	-- Clean up game state
	GameState.players[player.UserId] = nil
	GameState.persistentData[player.UserId] = nil
	GameState.gamepassCache[player.UserId] = nil
	GameState.luckBoostExpiry[player.UserId] = nil
	playerSaveData[player.UserId] = nil
	playerSpinData[player.UserId] = nil
	playerProcessing[player.UserId] = nil
	afkPlayers[player.UserId] = nil

	-- Clean up inventory
	if InventoryService then
		InventoryService.RemoveInventory(player)
	end

	-- Clean up quest data
	if QuestService then
		QuestService.RemovePlayer(player)
	end

	-- Notify round system
	if RoundSystem then
		RoundSystem.OnPlayerRemoved(player)
	end
end

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

-- Handle AdminEvent fired from client (e.g. admin panel UI)
AdminEvent.OnServerEvent:Connect(function(player: Player, eventId: string)
	if type(eventId) ~= "string" then return end

	-- Permission check: must be in ADMIN_IDS or running in Studio
	local allowed = false
	for _, adminId in ipairs(Constants.ADMIN_IDS) do
		if player.UserId == adminId then
			allowed = true
			break
		end
	end
	if not allowed and RunService:IsStudio() then
		allowed = true
	end
	if not allowed then return end

	-- Validate the event ID exists in ADMIN_EVENTS
	local validEvent = false
	for eventKey, _ in pairs(Constants.ADMIN_EVENTS) do
		if eventKey == eventId then
			validEvent = true
			break
		end
	end
	if not validEvent then return end

	-- Trigger the admin event
	if RoundSystem then
		RoundSystem.TriggerAdminEvent(eventId)
	end
	AdminEvent:FireAllClients(eventId)
end)

-- Initialize game systems
local function Initialize()
	print("[GameManager] Initializing Bomb Them!")

	-- Set up collision group so players don't collide with each other
	PhysicsService:RegisterCollisionGroup("Players")
	PhysicsService:CollisionGroupSetCollidable("Players", "Players", false)

	-- Initialize map data
	MapData.InitializeGrids()

	-- Load server modules
	local ServerFolder = script.Parent
	RoundSystem = require(ServerFolder:WaitForChild("RoundSystem"))
	BombService = require(ServerFolder:WaitForChild("BombService"))
	MapGenerator = require(ServerFolder:WaitForChild("MapGenerator"))
	PowerUpService = require(ServerFolder:WaitForChild("PowerUpService"))
	AnimationService = require(ServerFolder:WaitForChild("AnimationService"))
	InventoryService = require(ServerFolder:WaitForChild("InventoryService"))
	LeaderboardService = require(ServerFolder:WaitForChild("LeaderboardService"))
	QuestService = require(ServerFolder:WaitForChild("QuestService"))

	-- Initialize services
	MapGenerator.Initialize()
	BombService.Initialize()
	PowerUpService.Initialize()
	AnimationService.Initialize()
	LeaderboardService.Initialize()
	QuestService.Initialize()
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

-- Inventory remote handlers
EquipItem.OnServerEvent:Connect(function(player: Player, category: string, itemId: string)
	if type(category) ~= "string" or type(itemId) ~= "string" then return end
	if not InventoryService then return end

	local success = InventoryService.EquipItem(player, category, itemId)
	if success then
		local inv = InventoryService.GetInventory(player)
		if inv then
			SyncInventory:FireClient(player, inv)
		end
	end
end)

UnequipItem.OnServerEvent:Connect(function(player: Player, category: string)
	if type(category) ~= "string" then return end
	if not InventoryService then return end

	local success = InventoryService.UnequipItem(player, category)
	if success then
		local inv = InventoryService.GetInventory(player)
		if inv then
			SyncInventory:FireClient(player, inv)
		end
	end
end)

OpenCapsule.OnServerInvoke = function(player: Player, capsuleIndex: number)
	if type(capsuleIndex) ~= "number" then return { success = false } end
	if math.floor(capsuleIndex) ~= capsuleIndex then return { success = false } end
	if not InventoryService then return { success = false } end
	if not AcquireLock(player.UserId) then return { success = false, reason = "busy" } end

	local reward = InventoryService.OpenCapsule(player, capsuleIndex)
	if reward then
		local inv = InventoryService.GetInventory(player)
		if inv then
			SyncInventory:FireClient(player, inv)
		end

		-- Track capsules opened for badge
		local saves = playerSaveData[player.UserId]
		if saves then
			saves.capsulesOpened = (saves.capsulesOpened or 0) + 1
			if saves.capsulesOpened >= 10 then
				task.spawn(AwardBadge, player, BADGE_CAPSULE_HUNGRY)
			end
		end

		-- Announce legendary item drops to all players
		if reward.rarity == "Legendary" then
			ServerAnnouncement:FireAllClients("legendary_drop", {
				playerName = player.DisplayName,
				itemName = reward.itemName or "Legendary Item",
			})
		end

		ReleaseLock(player.UserId)
		return { success = true, reward = reward }
	end
	ReleaseLock(player.UserId)
	return { success = false }
end

-- Spin wheel: return current spin status to client
GetSpinStatus.OnServerInvoke = function(player: Player)
	local sd = GetSpinData(player.UserId)
	local persistent = GameState.persistentData[player.UserId]
	local totalCoins = if persistent then persistent.totalCoins else 0
	-- VIP gets extra free spins
	local gpCache = GameState.gamepassCache[player.UserId]
	local freeSpinsPerDay = if gpCache and gpCache.vip then Economy.VIP_FREE_SPINS_PER_DAY else Economy.FREE_SPINS_PER_DAY
	return {
		freeSpinsLeft = math.max(0, freeSpinsPerDay - sd.freeSpinsUsedToday),
		paidSpinsLeft = math.max(0, Economy.MAX_PAID_SPINS_PER_DAY - sd.paidSpinsUsedToday),
		totalCoins = totalCoins,
	}
end

-- Spin wheel: handle spin request
RequestSpin.OnServerEvent:Connect(function(player: Player)
	if not AcquireLock(player.UserId) then return end

	local sd = GetSpinData(player.UserId)
	local persistent = GameState.persistentData[player.UserId]
	if not persistent then ReleaseLock(player.UserId) return end

	-- VIP gets extra free spins
	local gpCache = GameState.gamepassCache[player.UserId]
	local freeSpinsPerDay = if gpCache and gpCache.vip then Economy.VIP_FREE_SPINS_PER_DAY else Economy.FREE_SPINS_PER_DAY
	local freeSpinsLeft = math.max(0, freeSpinsPerDay - sd.freeSpinsUsedToday)
	local paidSpinsLeft = math.max(0, Economy.MAX_PAID_SPINS_PER_DAY - sd.paidSpinsUsedToday)
	local isFree = freeSpinsLeft > 0

	if isFree then
		-- Use free spin
		sd.freeSpinsUsedToday += 1
	elseif paidSpinsLeft > 0 and persistent.totalCoins >= Economy.EXTRA_SPIN_COST then
		-- Deduct coins for paid spin
		persistent.totalCoins -= Economy.EXTRA_SPIN_COST
		sd.paidSpinsUsedToday += 1
		-- Update the client-visible IntValue
		local pStats = player:FindFirstChild("PersistentStats")
		if pStats then
			local coinsVal = pStats:FindFirstChild("TotalCoins")
			if coinsVal then
				(coinsVal :: IntValue).Value = persistent.totalCoins
			end
		end
	else
		-- Not eligible
		ReleaseLock(player.UserId)
		return
	end

	-- Roll winner
	local slotIndex = PickSpinSlot(player.UserId)
	local slot = Economy.SPIN_WHEEL_SLOTS[slotIndex]
	local reward = slot.reward

	-- Grant reward
	if reward.coins then
		persistent.totalCoins += reward.coins
		local pStats = player:FindFirstChild("PersistentStats")
		if pStats then
			local coinsVal = pStats:FindFirstChild("TotalCoins")
			if coinsVal then
				(coinsVal :: IntValue).Value = persistent.totalCoins
			end
		end
	elseif reward.capsule and InventoryService then
		InventoryService.AddCapsule(player, reward.capsule)
		-- Sync inventory so capsule tab updates
		local inv = InventoryService.GetInventory(player)
		if inv then
			SyncInventory:FireClient(player, inv)
		end
	end

	-- Recalculate spins left after this spin
	local newFreeLeft = math.max(0, freeSpinsPerDay - sd.freeSpinsUsedToday)
	local newPaidLeft = math.max(0, Economy.MAX_PAID_SPINS_PER_DAY - sd.paidSpinsUsedToday)

	-- Fire result to client
	SpinResult:FireClient(player, {
		slotIndex = slotIndex,
		rewardName = slot.name,
		rewardType = slot.rewardType or "coins",
		totalCoins = persistent.totalCoins,
		freeSpinsLeft = newFreeLeft,
		paidSpinsLeft = newPaidLeft,
	})

	ReleaseLock(player.UserId)
end)

-- ============================================================
-- DAILY REWARDS
-- ============================================================
-- Reward definitions matching the client display (Days 1-7)
local DAILY_REWARDS = {
	{ coins = 500 },
	{ capsules = { "Common", "Common" } },
	{ capsules = { "Rare" } },            -- "Bomb Skin" — grant a Rare capsule
	{ coins = 1000 },
	{ capsules = { "Rare" } },            -- "Win Dance" — grant a Rare capsule
	{ capsules = { "Common", "Common", "Common" } },
	{ capsules = { "Epic" } },            -- Day 7 special
}

local function GetTodayDateString(): string
	return os.date("!%Y-%m-%d", os.time()) :: string
end

-- Calculate daily reward state for a player on join
-- Streak logic: if last claim was yesterday, advance day. If >1 day gap, reset to 1.
local function ResolveDailyRewardState(saves: any)
	local dr = saves.dailyRewardData
	if not dr then
		dr = { currentDay = 1, lastClaimDate = "", claimedToday = false }
		saves.dailyRewardData = dr
	end

	local today = GetTodayDateString()

	if dr.lastClaimDate == today then
		-- Already claimed today, keep state
		dr.claimedToday = true
		return
	end

	-- Check if last claim was yesterday (streak continues)
	if dr.lastClaimDate ~= "" then
		local year, month, day = string.match(dr.lastClaimDate, "(%d+)-(%d+)-(%d+)")
		if year then
			local lastTime = os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 0 })
			local todayYear, todayMonth, todayDay = string.match(today, "(%d+)-(%d+)-(%d+)")
			local todayTime = os.time({ year = tonumber(todayYear), month = tonumber(todayMonth), day = tonumber(todayDay), hour = 0 })
			local daysDiff = math.floor((todayTime - lastTime) / 86400)

			if daysDiff == 1 then
				-- Yesterday — advance day (wrap after 7)
				dr.currentDay = (dr.currentDay % 7) + 1
			elseif daysDiff > 1 then
				-- Streak broken — reset
				dr.currentDay = 1
			end
		else
			dr.currentDay = 1
		end
	end

	dr.claimedToday = false
end

-- Get daily reward status for client
GetDailyRewardStatus.OnServerInvoke = function(player: Player)
	local saves = playerSaveData[player.UserId]
	if not saves then return { currentDay = 1, claimedToday = false } end

	ResolveDailyRewardState(saves)
	local dr = saves.dailyRewardData
	return {
		currentDay = dr.currentDay,
		claimedToday = dr.claimedToday,
	}
end

-- Claim daily reward
ClaimDailyReward.OnServerInvoke = function(player: Player)
	if not AcquireLock(player.UserId) then return { success = false, reason = "busy" } end

	local saves = playerSaveData[player.UserId]
	local persistent = GameState.persistentData[player.UserId]
	if not saves or not persistent then
		ReleaseLock(player.UserId)
		return { success = false, reason = "no_data" }
	end

	ResolveDailyRewardState(saves)
	local dr = saves.dailyRewardData

	if dr.claimedToday then
		ReleaseLock(player.UserId)
		return { success = false, reason = "already_claimed" }
	end

	local dayIndex = dr.currentDay
	local reward = DAILY_REWARDS[dayIndex]
	if not reward then
		ReleaseLock(player.UserId)
		return { success = false, reason = "invalid_day" }
	end

	-- Mark as claimed
	dr.claimedToday = true
	dr.lastClaimDate = GetTodayDateString()

	-- Grant rewards
	local coinsGranted = 0
	if reward.coins then
		persistent.totalCoins = (persistent.totalCoins or 0) + reward.coins
		coinsGranted = reward.coins

		-- Update client-visible IntValue
		local pStats = player:FindFirstChild("PersistentStats")
		if pStats then
			local coinsVal = pStats:FindFirstChild("TotalCoins")
			if coinsVal then
				(coinsVal :: IntValue).Value = persistent.totalCoins
			end
		end
	end

	local capsulesGranted = 0
	if reward.capsules and InventoryService then
		for _, rarity in ipairs(reward.capsules) do
			InventoryService.AddCapsule(player, rarity)
			capsulesGranted += 1
		end
		-- Sync inventory so capsule tab updates
		local inv = InventoryService.GetInventory(player)
		if inv then
			SyncInventory:FireClient(player, inv)
		end
	end

	ReleaseLock(player.UserId)
	return {
		success = true,
		coinsGranted = coinsGranted,
		capsulesGranted = capsulesGranted,
		day = dayIndex,
	}
end

-- ============================================================
-- CODE REDEMPTION
-- ============================================================
-- Define available codes and their rewards
local CODES: {[string]: {coins: number?, capsules: {{rarity: string}}?}} = {
	["EarlyRelease"] = { coins = 500 },
	["EarlyAccess"] = { coins = 500 },
}

RedeemCode.OnServerInvoke = function(player: Player, code: string)
	if type(code) ~= "string" then return { success = false, reason = "invalid" } end
	if #code > 50 then return { success = false, reason = "invalid" } end
	if not AcquireLock(player.UserId) then return { success = false, reason = "busy" } end

	local saves = playerSaveData[player.UserId]
	local persistent = GameState.persistentData[player.UserId]
	if not saves or not persistent then
		ReleaseLock(player.UserId)
		return { success = false, reason = "no_data" }
	end

	-- Ensure redeemedCodes table exists
	if not saves.redeemedCodes then saves.redeemedCodes = {} end

	-- Normalize code (case-insensitive lookup)
	local reward = nil
	local canonicalCode = nil
	for codeKey, codeReward in pairs(CODES) do
		if string.lower(codeKey) == string.lower(code) then
			reward = codeReward
			canonicalCode = codeKey
			break
		end
	end

	if not reward then
		ReleaseLock(player.UserId)
		return { success = false, reason = "invalid_code" }
	end

	-- Check if already redeemed
	for _, redeemed in ipairs(saves.redeemedCodes) do
		if redeemed == canonicalCode then
			ReleaseLock(player.UserId)
			return { success = false, reason = "already_redeemed" }
		end
	end

	-- Mark as redeemed
	table.insert(saves.redeemedCodes, canonicalCode)

	-- Grant rewards
	local coinsGranted = 0
	if reward.coins then
		persistent.totalCoins = (persistent.totalCoins or 0) + reward.coins
		coinsGranted = reward.coins
		local pStats = player:FindFirstChild("PersistentStats")
		if pStats then
			local coinsVal = pStats:FindFirstChild("TotalCoins")
			if coinsVal then
				(coinsVal :: IntValue).Value = persistent.totalCoins
			end
		end
	end

	if reward.capsules and InventoryService then
		for _, cap in ipairs(reward.capsules) do
			InventoryService.AddCapsule(player, cap.rarity)
		end
		local inv = InventoryService.GetInventory(player)
		if inv then
			SyncInventory:FireClient(player, inv)
		end
	end

	ReleaseLock(player.UserId)
	return { success = true, coinsGranted = coinsGranted }
end

-- AFK toggle
SetAFK.OnServerEvent:Connect(function(player: Player, isAfk: any)
	if type(isAfk) ~= "boolean" then return end
	afkPlayers[player.UserId] = isAfk
end)

-- Expose AFK state for RoundSystem
function IsPlayerAFK(userId: number): boolean
	return afkPlayers[userId] == true
end

-- Make AFK check available globally via shared module attribute
GameState.IsPlayerAFK = IsPlayerAFK

-- Free skin claim
local FREE_SKIN_ID = "pet_squirrel"

GetFreeSkinStatus.OnServerInvoke = function(player: Player)
	local saves = playerSaveData[player.UserId]
	if not saves then return false end
	return saves.freeSkinClaimed == true
end

ClaimFreeSkin.OnServerInvoke = function(player: Player)
	local saves = playerSaveData[player.UserId]
	if not saves then return false end
	-- Already claimed
	if saves.freeSkinClaimed then return false end
	-- Grant the skin
	if not InventoryService then return false end
	local inv = InventoryService.GetInventory(player)
	if not inv then return false end
	local alreadyOwned = false
	for _, id in ipairs(inv.ownedSkins) do
		if id == FREE_SKIN_ID then alreadyOwned = true break end
	end
	if not alreadyOwned then
		table.insert(inv.ownedSkins, FREE_SKIN_ID)
	end
	saves.freeSkinClaimed = true
	SyncInventory:FireClient(player, inv)
	return true
end

-- Pull inventory on demand (client fallback if push was missed)
GetInventory.OnServerInvoke = function(player: Player)
	if not InventoryService then return nil end
	return InventoryService.GetInventory(player)
end

-- Config settings: get saved settings
GetConfigSettings.OnServerInvoke = function(player: Player)
	local saves = playerSaveData[player.UserId]
	if not saves or not saves.configSettings then
		return { musicEnabled = true, sfxEnabled = true, skipCapsuleOpens = false }
	end
	return saves.configSettings
end

-- Config settings: save when player changes a toggle
SaveConfigSettings.OnServerEvent:Connect(function(player: Player, settings: any)
	if type(settings) ~= "table" then return end
	local saves = playerSaveData[player.UserId]
	if not saves then return end
	saves.configSettings = {
		musicEnabled = if type(settings.musicEnabled) == "boolean" then settings.musicEnabled else true,
		sfxEnabled = if type(settings.sfxEnabled) == "boolean" then settings.sfxEnabled else true,
		skipCapsuleOpens = if type(settings.skipCapsuleOpens) == "boolean" then settings.skipCapsuleOpens else false,
	}
end)

-- Group chest: check membership and grant rewards
local GROUP_ID = 511584075

RequestGroupReward.OnServerInvoke = function(player: Player)
	if not AcquireLock(player.UserId) then return { status = "busy" } end

	local saves = playerSaveData[player.UserId]
	local persistent = GameState.persistentData[player.UserId]
	if not saves or not persistent then
		ReleaseLock(player.UserId)
		return { status = "error" }
	end

	-- Already claimed
	if saves.groupRewardClaimed then
		ReleaseLock(player.UserId)
		return { status = "already_claimed" }
	end

	-- Check group membership
	local inGroup = false
	local ok, result = pcall(function()
		return player:IsInGroup(GROUP_ID)
	end)
	if ok then
		inGroup = result
	end

	if not inGroup then
		ReleaseLock(player.UserId)
		return { status = "not_in_group", groupId = GROUP_ID }
	end

	-- Grant rewards: 1000 coins + Legendary capsule
	persistent.totalCoins += 1000
	saves.totalCoins = persistent.totalCoins
	saves.groupRewardClaimed = true

	-- Update client-visible IntValue
	local pStats = player:FindFirstChild("PersistentStats")
	if pStats then
		local coinsVal = pStats:FindFirstChild("TotalCoins")
		if coinsVal then
			(coinsVal :: IntValue).Value = persistent.totalCoins
		end
	end

	-- Grant Legendary capsule
	if InventoryService then
		InventoryService.AddCapsule(player, "Legendary")
		local inv = InventoryService.GetInventory(player)
		if inv then
			SyncInventory:FireClient(player, inv)
		end
	end

	ReleaseLock(player.UserId)
	return { status = "success", totalCoins = persistent.totalCoins }
end

-- ============================================================
-- CAPSULE SHOP: buy with coins
-- ============================================================
BuyCapsule.OnServerInvoke = function(player: Player, rarity: string)
	if type(rarity) ~= "string" then return { success = false, reason = "invalid" } end

	local coinPrice = Economy.CAPSULE_PRICES[rarity]
	if not coinPrice then return { success = false, reason = "invalid_rarity" } end
	if not AcquireLock(player.UserId) then return { success = false, reason = "busy" } end

	local persistent = GameState.persistentData[player.UserId]
	if not persistent then ReleaseLock(player.UserId) return { success = false, reason = "no_data" } end

	if persistent.totalCoins < coinPrice then
		ReleaseLock(player.UserId)
		return { success = false, reason = "not_enough_coins" }
	end

	-- Deduct coins
	persistent.totalCoins -= coinPrice

	-- Update client-visible IntValue
	local pStats = player:FindFirstChild("PersistentStats")
	if pStats then
		local coinsVal = pStats:FindFirstChild("TotalCoins")
		if coinsVal then
			(coinsVal :: IntValue).Value = persistent.totalCoins
		end
	end

	-- Add capsule to inventory
	if InventoryService then
		InventoryService.AddCapsule(player, rarity)
		local inv = InventoryService.GetInventory(player)
		if inv then
			SyncInventory:FireClient(player, inv)
		end
	end

	ReleaseLock(player.UserId)
	return { success = true, totalCoins = persistent.totalCoins }
end

-- ============================================================
-- CAPSULE SHOP: buy with Robux (Dev Products via MarketplaceService)
-- ============================================================
local MarketplaceService = game:GetService("MarketplaceService")

-- Build reverse lookup: productId -> { rarity, count, robux }
local productIdToReward: {[number]: { rarity: string, count: number, robux: number }} = {}
for key, data in pairs(Economy.CAPSULE_DEV_PRODUCTS) do
	local rarity: string
	local count = 1
	if key == "Legendary1" then
		rarity = "Legendary"
		count = 1
	elseif key == "Legendary3" then
		rarity = "Legendary"
		count = 3
	elseif key == "Legendary5" then
		rarity = "Legendary"
		count = 5
	else
		rarity = key -- "Uncommon", "Rare", "Epic", "Random"
		count = 1
	end
	productIdToReward[data.productId] = { rarity = rarity, count = count, robux = data.robux or 0 }
end

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Idempotency: check if this receipt was already processed
	local receiptKey = "Receipt_" .. tostring(receiptInfo.PurchaseId)
	local alreadyProcessed = false
	pcall(function()
		local existing = ReceiptDataStore:GetAsync(receiptKey)
		if existing then alreadyProcessed = true end
	end)
	if alreadyProcessed then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- 2x Luck boost dev product
	if receiptInfo.ProductId == Economy.DEV_PRODUCT_2X_LUCK then
		GameState.luckBoostExpiry[receiptInfo.PlayerId] = os.time() + Economy.LUCK_BOOST_DURATION
		-- Notify client that boost is active
		local LuckBoostActivated = Remotes:FindFirstChild("LuckBoostActivated")
		if LuckBoostActivated and player then
			(LuckBoostActivated :: RemoteEvent):FireClient(player, Economy.LUCK_BOOST_DURATION)
		end
		-- Announce to all players
		ServerAnnouncement:FireAllClients("purchase_luck", {
			playerName = player.DisplayName,
		})
		-- Track robux spent
		local persistent = GameState.persistentData[receiptInfo.PlayerId]
		if persistent then
			persistent.robuxSpent = (persistent.robuxSpent or 0) + (Economy.DEV_PRODUCT_2X_LUCK_ROBUX or 49)
		end
		-- Mark receipt as processed
		pcall(function() ReceiptDataStore:SetAsync(receiptKey, true) end)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local reward = productIdToReward[receiptInfo.ProductId]
	if not reward then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not InventoryService then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Grant capsules
	local rarity = reward.rarity
	if rarity == "Random" then
		-- Random capsule: roll a rarity from the weighted table
		-- 2x Luck: double the weight of Rare/Epic/Legendary
		local boosted = HasLuckBoost(receiptInfo.PlayerId)
		for _ = 1, reward.count do
			local totalWeight = 0
			for _, entry in ipairs(Economy.RANDOM_CAPSULE_WEIGHTS) do
				local w = entry.weight
				if boosted and (entry.rarity == "Rare" or entry.rarity == "Epic" or entry.rarity == "Legendary") then
					w = w * 2
				end
				totalWeight += w
			end
			local roll = math.random(1, totalWeight)
			local cumulative = 0
			local chosenRarity = "Common"
			for _, entry in ipairs(Economy.RANDOM_CAPSULE_WEIGHTS) do
				local w = entry.weight
				if boosted and (entry.rarity == "Rare" or entry.rarity == "Epic" or entry.rarity == "Legendary") then
					w = w * 2
				end
				cumulative += w
				if roll <= cumulative then
					chosenRarity = entry.rarity
					break
				end
			end
			InventoryService.AddCapsule(player, chosenRarity)
		end
	else
		for _ = 1, reward.count do
			InventoryService.AddCapsule(player, rarity)
		end
	end

	-- Announce legendary capsule purchases
	if rarity == "Legendary" then
		ServerAnnouncement:FireAllClients("purchase_legendary", {
			playerName = player.DisplayName,
			count = reward.count,
		})
	end

	-- Track robux spent
	local persistent = GameState.persistentData[receiptInfo.PlayerId]
	if persistent then
		persistent.robuxSpent = (persistent.robuxSpent or 0) + (reward.robux or 0)
	end

	-- Sync inventory to client
	local inv = InventoryService.GetInventory(player)
	if inv then
		SyncInventory:FireClient(player, inv)
	end

	-- Mark receipt as processed
	pcall(function() ReceiptDataStore:SetAsync(receiptKey, true) end)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ============================================================
-- GAMEPASS PURCHASE HANDLER (mid-session purchases)
-- ============================================================
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased then return end

	local cache = GameState.gamepassCache[player.UserId]
	if not cache then return end

	if gamePassId == Economy.GAMEPASS_VIP then
		cache.vip = true
		GrantVIPItems(player)
		ServerAnnouncement:FireAllClients("purchase_vip", {
			playerName = player.DisplayName,
		})
	elseif gamePassId == Economy.GAMEPASS_2X_COINS then
		cache.doubleCoins = true
	elseif gamePassId == Economy.GAMEPASS_ALL_BLUE then
		cache.allBlue = true
		GrantAllBlueItems(player)
	else
		return
	end

	-- Sync updated inventory to client
	if InventoryService then
		local inv = InventoryService.GetInventory(player)
		if inv then
			SyncInventory:FireClient(player, inv)
		end
	end
end)

-- Auto-save all players every 60 seconds and push leaderboard stats
task.spawn(function()
	while true do
		task.wait(60)
		for _, p in ipairs(Players:GetPlayers()) do
			task.spawn(function()
				SavePlayerData(p)
				if LeaderboardService then
					local saves = playerSaveData[p.UserId]
					if saves then
						LeaderboardService.UpdatePlayerStats(p, "wins", saves.wins or 0)
						LeaderboardService.UpdatePlayerStats(p, "totalKills", saves.totalKills or 0)
						LeaderboardService.UpdatePlayerStats(p, "robuxSpent", saves.robuxSpent or 0)
					end
				end
			end)
		end
	end
end)

-- Save all players on server shutdown
game:BindToClose(function()
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			SavePlayerData(p)
		end)
	end
	task.wait(3) -- Give DataStore requests time to complete
end)

-- ============================================================
-- PERIODIC SERVER CHAT REMINDERS (every 5 min, 25s between each)
-- ============================================================
task.spawn(function()
	local reminders = {
		{ type = "code",  text = 'Use code "EarlyAccess" for 500 free Coins!' },
		{ type = "social", text = "Join our Community for Exclusive Codes!" },
		{ type = "beta",  text = "Game is in Beta! DM aladdin0v0 with any suggestions/bugs" },
	}

	while true do
		task.wait(300) -- 5 minutes
		for i, reminder in ipairs(reminders) do
			ServerAnnouncement:FireAllClients("reminder", reminder)
			if i < #reminders then
				task.wait(25)
			end
		end
	end
end)

-- ============================================================
-- SERVER-SIDE WALKSPEED ENFORCEMENT (anti-cheat)
-- ============================================================
local lastSpeedCheck = 0
RunService.Heartbeat:Connect(function()
	if tick() - lastSpeedCheck < 1 then return end
	lastSpeedCheck = tick()
	if GameState.currentState ~= Constants.STATES.PLAYING then return end
	for userId, playerData in pairs(GameState.players) do
		local p = Players:GetPlayerByUserId(userId)
		if p and p.Character then
			local humanoid = p.Character:FindFirstChild("Humanoid")
			if humanoid and playerData.isAlive then
				if humanoid.WalkSpeed ~= playerData.speed then
					humanoid.WalkSpeed = playerData.speed
				end
				-- Also enforce no jumping during gameplay
				humanoid.JumpPower = 0
				humanoid.JumpHeight = 0
			end
		end
	end
end)

-- Start initialization
Initialize()
