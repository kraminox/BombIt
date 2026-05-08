--!strict
-- RoundSystem.lua
-- Manages game rounds, states, and transitions

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local BadgeService = game:GetService("BadgeService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapData = require(Shared:WaitForChild("MapData"))
local WinDancesModule = Shared:WaitForChild("WinDances", 10)
local WinDances = WinDancesModule and require(WinDancesModule) or nil
local BombSkins = require(Shared:WaitForChild("BombSkins"))
local Economy = require(Shared:WaitForChild("Economy"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged")
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")
local PlayerDied = Remotes:WaitForChild("PlayerDied")
local AdminEvent = Remotes:WaitForChild("AdminEvent")
local SyncPlayerData = Remotes:WaitForChild("SyncPlayerData")

local RoundSystem = {}

-- Module references
local BombService
local MapGenerator
local PowerUpService
local AnimationService
local FallingTilesService
local InventoryService
local LeaderboardService
local QuestService

-- State tracking
local roundCoroutine: thread? = nil
local roundTimer = 0

-- Store CharacterAdded connections per player for cleanup
local roundCharConnections: {[number]: RBXScriptConnection} = {}
local currentWinner: Player? = nil
local roundResults = {} -- {userId, kills, place}

-- Recency tracking for mode selection (recent modes get 0.6x weight)
local recentFormats = {} :: {string} -- last 2 format IDs
local recentGameTypes = {} :: {string} -- last 2 game type IDs
local RECENCY_MULTIPLIER = 0.6

-- Rate limiting for emotes/stickers
local lastEmoteTime = {} :: {[number]: number}
local lastStickerTime = {} :: {[number]: number}
local EMOTE_COOLDOWN = 2 -- seconds

-- Remotes for emotes/stickers
local PlayEmote
local ShowSticker
local ColorBattleSync
local ModeSelection

-- Physics properties for in-game characters
local PhysicalProperties = PhysicalProperties

function RoundSystem.Initialize()
	local ServerFolder = script.Parent
	BombService = require(ServerFolder:WaitForChild("BombService"))
	MapGenerator = require(ServerFolder:WaitForChild("MapGenerator"))
	PowerUpService = require(ServerFolder:WaitForChild("PowerUpService"))
	AnimationService = require(ServerFolder:WaitForChild("AnimationService"))
	FallingTilesService = require(ServerFolder:WaitForChild("FallingTilesService"))
	FallingTilesService.Initialize()
	InventoryService = require(ServerFolder:WaitForChild("InventoryService"))
	LeaderboardService = require(ServerFolder:WaitForChild("LeaderboardService"))
	QuestService = require(ServerFolder:WaitForChild("QuestService"))

	-- Build lobby
	MapGenerator.BuildLobby()

	-- Create emote/sticker remotes
	local function CreateRemote(name: string): RemoteEvent
		local existing = Remotes:FindFirstChild(name)
		if existing then return existing end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = Remotes
		return remote
	end

	PlayEmote = CreateRemote("PlayEmote")
	ShowSticker = CreateRemote("ShowSticker")
	ColorBattleSync = CreateRemote("ColorBattleSync")
	ModeSelection = CreateRemote("ModeSelection")

	-- Handle emote requests
	PlayEmote.OnServerEvent:Connect(function(player: Player, emoteId: string)
		RoundSystem.HandleEmote(player, emoteId)
	end)

	-- Handle sticker requests
	ShowSticker.OnServerEvent:Connect(function(player: Player, stickerId: string)
		RoundSystem.HandleSticker(player, stickerId)
	end)

	-- Start game loop (set to false to pause rounds for UI testing)
	local ENABLE_GAME_LOOP = true
	if ENABLE_GAME_LOOP then
		task.spawn(RoundSystem.GameLoop)
	else
		print("[RoundSystem] Game loop PAUSED — set ENABLE_GAME_LOOP to true to resume")
	end
end

-- Handle emote playing
function RoundSystem.HandleEmote(player: Player, emoteId: string)
	-- Rate limit
	local now = tick()
	if lastEmoteTime[player.UserId] and (now - lastEmoteTime[player.UserId]) < EMOTE_COOLDOWN then return end
	lastEmoteTime[player.UserId] = now

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end

	-- Validate emoteId against Constants.EMOTES
	local emoteData
	for _, emote in ipairs(Constants.EMOTES) do
		if emote.id == emoteId then
			emoteData = emote
			break
		end
	end

	if not emoteData then return end

	-- Play animation
	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = emoteData.animId

	local animTrack = animator:LoadAnimation(animation)
	animTrack:Play()

	-- Broadcast to all clients
	PlayEmote:FireAllClients(player.UserId, emoteId)
end

-- Handle sticker display
function RoundSystem.HandleSticker(player: Player, stickerId: string)
	-- Rate limit
	local now = tick()
	if lastStickerTime[player.UserId] and (now - lastStickerTime[player.UserId]) < EMOTE_COOLDOWN then return end
	lastStickerTime[player.UserId] = now

	local character = player.Character
	if not character then return end

	-- Validate stickerId against Constants.STICKERS
	local stickerData
	for _, sticker in ipairs(Constants.STICKERS) do
		if sticker.id == stickerId then
			stickerData = sticker
			break
		end
	end

	if not stickerData then return end

	-- Broadcast to all clients (they handle the visual)
	ShowSticker:FireAllClients(player.UserId, stickerId)
end

-- Calculate round results and rankings
function RoundSystem.CalculateResults(): {{userId: number, kills: number, coins: number, demolitions: number, powerupsCollected: number, xp: number, xpBefore: number, xpAfter: number, place: number}}
	local results = {}

	for userId, playerData in pairs(GameState.players) do
		local kills = playerData.kills or 0
		local demolitions = playerData.demolitions or 0
		local powerups = playerData.powerupsCollected or 0
		local isAlive = playerData.isAlive

		-- Calculate XP earned this round
		local xp = (kills * Constants.XP_PER_KILL)
			+ (demolitions * Constants.XP_PER_DEMOLITION)
			+ (powerups * Constants.XP_PER_POWERUP)

		-- Win bonus for the winner (and all winning teammates in team modes)
		local isWinner = false
		if currentWinner then
			local teamSize = GameState.currentMode.teamSize or 1
			if teamSize > 1 then
				-- Team mode: all players on the winning team get the win bonus
				local winnerTeam = GameState.teamAssignments[currentWinner.UserId]
				local playerTeam = GameState.teamAssignments[userId]
				if winnerTeam and playerTeam and winnerTeam == playerTeam then
					isWinner = true
				end
			else
				if currentWinner.UserId == userId then
					isWinner = true
				end
			end
		end
		if isWinner then
			xp = xp + Constants.XP_WIN_BONUS
		end

		-- Base participation award: 5% of current level XP requirement
		local persistent = GameState.persistentData[userId]
		local xpBefore = persistent and persistent.totalXp or 0
		local _, _, xpNeeded = Constants.GetLevelInfo(xpBefore)
		local baseXp = math.floor(xpNeeded * 0.05)
		xp = xp + baseXp

		-- Apply VIP XP multiplier
		local gpCache = GameState.gamepassCache[userId]
		if gpCache and gpCache.vip then
			xp = math.floor(xp * Economy.VIP_XP_MULTIPLIER)
		end

		-- Update persistent XP and track progression
		local xpAfter = xpBefore + xp
		if persistent then
			persistent.totalXp = xpAfter
		end

		-- Calculate coins using Economy module
		local roundCoins = Economy.CalculateMatchEarnings(
			isWinner,
			playerData.kills or 0,
			playerData.demolitions or 0,
			playerData.powerupsCollected or 0,
			persistent and persistent.winStreak or 0
		)

		-- Apply 2x Coins gamepass multiplier
		if gpCache and gpCache.doubleCoins then
			roundCoins = roundCoins * 2
		end

		local coinsBefore = persistent and persistent.totalCoins or 0
		local coinsAfter = coinsBefore + roundCoins
		if persistent then
			persistent.totalCoins = coinsAfter
		end

		-- Sync PersistentStats IntValues on the Player object
		local p = Players:GetPlayerByUserId(userId)
		if p then
			local pStats = p:FindFirstChild("PersistentStats")
			if pStats then
				local lvlVal = pStats:FindFirstChild("Level")
				if lvlVal then
					local newLevel = Constants.GetLevelInfo(xpAfter)
					lvlVal.Value = newLevel

					-- Grant level milestone titles
					if InventoryService then
						InventoryService.GrantMilestoneTitles(p, newLevel)
					end
				end
				local xpValObj = pStats:FindFirstChild("TotalXp")
				if xpValObj then xpValObj.Value = xpAfter end
				local coinsValObj = pStats:FindFirstChild("TotalCoins")
				if coinsValObj then coinsValObj.Value = coinsAfter end
			end
		end

		table.insert(results, {
			userId = userId,
			kills = kills,
			coins = roundCoins,
			totalCoins = coinsAfter,
			demolitions = demolitions,
			powerupsCollected = powerups,
			xp = xp,
			xpBefore = xpBefore,
			xpAfter = xpAfter,
			isAlive = isAlive,
			tilesOwned = playerData.tilesOwned or 0,
		})
	end

	-- Sort by mode-specific criteria
	if GameState.currentMode.respawn then
		-- Respawn mode: sort by kills (most kills = first place)
		table.sort(results, function(a, b)
			return a.kills > b.kills
		end)
	elseif GameState.currentMode.paintTiles then
		-- Color Battle: sort by tiles owned (most tiles = first place)
		table.sort(results, function(a, b)
			return (a.tilesOwned or 0) > (b.tilesOwned or 0)
		end)
	else
		-- Default: alive first, then by kills
		table.sort(results, function(a, b)
			if a.isAlive ~= b.isAlive then
				return a.isAlive
			end
			return a.kills > b.kills
		end)
	end

	-- Assign places
	for i, result in ipairs(results) do
		result.place = i
	end

	-- Track quest stats for all participants
	if QuestService then
		for _, result in ipairs(results) do
			local p = Players:GetPlayerByUserId(result.userId)
			if p then
				-- Matches played
				QuestService.IncrementStat(p, "matches_played", 1)
				-- Kills
				if result.kills > 0 then
					QuestService.IncrementStat(p, "kills", result.kills)
				end
				-- Demolitions
				if result.demolitions > 0 then
					QuestService.IncrementStat(p, "demolitions", result.demolitions)
				end
				-- Powerups
				if result.powerupsCollected > 0 then
					QuestService.IncrementStat(p, "powerups", result.powerupsCollected)
				end
				-- Bombs placed
				local pd = GameState.players[result.userId]
				if pd and pd.bombs_placed and pd.bombs_placed > 0 then
					QuestService.IncrementStat(p, "bombs_placed", pd.bombs_placed)
				end
				-- Win (check team membership for team modes)
				local didWin = false
				if currentWinner then
					local teamSize2 = GameState.currentMode.teamSize or 1
					if teamSize2 > 1 then
						local winnerTeam = GameState.teamAssignments[currentWinner.UserId]
						local playerTeam = GameState.teamAssignments[result.userId]
						if winnerTeam and playerTeam and winnerTeam == playerTeam then
							didWin = true
						end
					else
						didWin = (currentWinner.UserId == result.userId)
					end
				end

				if didWin then
					QuestService.IncrementStat(p, "wins", 1)
					-- Win streak
					local persistent = GameState.persistentData[result.userId]
					local streak = (persistent and persistent.win_streak or 0) + 1
					if persistent then persistent.win_streak = streak end
					QuestService.SetStat(p, "win_streak", streak)
				else
					-- Reset win streak on loss
					local persistent = GameState.persistentData[result.userId]
					if persistent then persistent.win_streak = 0 end
					QuestService.SetStat(p, "win_streak", 0)
				end
			end
		end
	end

	return results
end

function RoundSystem.SetState(newState: string)
	GameState.currentState = newState
	RoundStateChanged:FireAllClients(newState, {
		timer = roundTimer,
		mode = GameState.currentMode,
	})
	print("[RoundSystem] State changed to: " .. newState)
end

function RoundSystem.OnPlayerAdded(player: Player)
	-- Wait a moment for player to fully load
	task.wait(0.5)

	-- Let player spawn naturally as their avatar on SpawnLocation in lobby
	-- Don't force custom character here

	-- Set lobby walk speed on initial spawn and any future respawns outside of rounds
	local function onCharacterAdded(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if humanoid and GameState.currentState ~= Constants.STATES.PLAYING then
			humanoid.WalkSpeed = 18
		end
	end
	-- Disconnect previous connection if exists (shouldn't happen, but safe)
	if roundCharConnections[player.UserId] then
		roundCharConnections[player.UserId]:Disconnect()
	end
	roundCharConnections[player.UserId] = player.CharacterAdded:Connect(onCharacterAdded)
	-- Apply to current character if already spawned
	if player.Character then
		onCharacterAdded(player.Character)
	end

	-- Sync current game state
	RoundStateChanged:FireClient(player, GameState.currentState, {
		timer = roundTimer,
		mode = GameState.currentMode,
	})
end

function RoundSystem.OnPlayerRemoved(player: Player)
	-- Disconnect CharacterAdded connection
	if roundCharConnections[player.UserId] then
		roundCharConnections[player.UserId]:Disconnect()
		roundCharConnections[player.UserId] = nil
	end

	-- Check if this affects the round
	if GameState.currentState == Constants.STATES.PLAYING then
		RoundSystem.CheckRoundEnd()
	end
end

function RoundSystem.SpawnPlayerInLobby(player: Player)
	-- Load the player's regular Roblox avatar
	-- They will spawn on a SpawnLocation in the lobby automatically
	player:LoadCharacter()

	-- Remove ForceField, restore lobby defaults
	task.defer(function()
		local character = player.Character
		if character then
			local ff = character:FindFirstChildOfClass("ForceField")
			if ff then ff:Destroy() end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = 18
				humanoid.JumpPower = 50
				humanoid.JumpHeight = 7.2
			end

			-- Remove in-game overhead UI (stat labels, nameplates)
			local head = character:FindFirstChild("Head")
			if head then
				for _, child in ipairs(head:GetChildren()) do
					if child:IsA("BillboardGui") then
						child:Destroy()
					end
				end
			end
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				for _, child in ipairs(hrp:GetChildren()) do
					if child:IsA("BillboardGui") then
						child:Destroy()
					end
				end
			end
		end
	end)
end

-- Assign teams to players for team modes (2v2, 3v3)
function RoundSystem.AssignTeams()
	GameState.teamAssignments = {}
	local teamSize = GameState.currentMode.teamSize or 1

	if teamSize <= 1 then return end -- FFA, no teams

	-- Only assign teams to non-AFK players
	local shuffled = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if not GameState.IsPlayerAFK(p.UserId) then
			table.insert(shuffled, p)
		end
	end
	for i = #shuffled, 2, -1 do
		local j = math.random(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end

	-- Assign teams: team 1 gets first teamSize players, team 2 gets next, etc.
	for i, p in ipairs(shuffled) do
		local teamIndex = math.ceil(i / teamSize)
		GameState.teamAssignments[p.UserId] = teamIndex
	end
end

-- Check if two players are on the same team
function RoundSystem.AreTeammates(userId1: number, userId2: number): boolean
	local teamSize = GameState.currentMode.teamSize or 1
	if teamSize <= 1 then return false end -- FFA, no teammates
	local team1 = GameState.teamAssignments[userId1]
	local team2 = GameState.teamAssignments[userId2]
	if not team1 or not team2 then return false end
	return team1 == team2
end

-- Assign colors to players for Color Battle mode (and team modes)
function RoundSystem.AssignPlayerColors()
	GameState.colorAssignments = {}
	local teamSize = GameState.currentMode.teamSize or 1

	-- Only assign colors to non-AFK players
	local activePlayers = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if not GameState.IsPlayerAFK(p.UserId) then
			table.insert(activePlayers, p)
		end
	end

	if teamSize > 1 then
		-- Team mode: assign same color to all players on the same team
		for _, p in ipairs(activePlayers) do
			local teamIndex = GameState.teamAssignments[p.UserId] or 1
			local colorIndex = ((teamIndex - 1) % #Constants.PLAYER_COLORS) + 1
			GameState.colorAssignments[p.UserId] = colorIndex

			local playerData = GameState.players[p.UserId]
			if playerData then
				playerData.colorIndex = colorIndex
			end
		end
	else
		-- FFA: unique color per player
		for i, p in ipairs(activePlayers) do
			local colorIndex = ((i - 1) % #Constants.PLAYER_COLORS) + 1
			GameState.colorAssignments[p.UserId] = colorIndex

			local playerData = GameState.players[p.UserId]
			if playerData then
				playerData.colorIndex = colorIndex
			end
		end
	end

	-- Sync to all clients
	ColorBattleSync:FireAllClients("AssignColors", GameState.colorAssignments)
end

function RoundSystem.SpawnPlayersInArena()
	-- Filter out AFK players and mark them as not alive for this round
	local playerList = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if GameState.IsPlayerAFK(p.UserId) then
			local pd = GameState.players[p.UserId]
			if pd then
				pd.isAlive = false
			end
		else
			table.insert(playerList, p)
		end
	end
	local arena = Workspace:FindFirstChild("Arena")

	-- Assign teams for team modes (2v2, 3v3)
	local teamSize = GameState.currentMode.teamSize or 1
	if teamSize > 1 then
		RoundSystem.AssignTeams()
		-- Sync team assignments to all clients
		ColorBattleSync:FireAllClients("AssignTeams", GameState.teamAssignments)
	end

	-- Assign colors: always in team modes (so teammates match), and in Color Battle
	if GameState.currentMode.paintTiles or teamSize > 1 then
		RoundSystem.AssignPlayerColors()
	end

	-- Load all characters in parallel
	for _, player in ipairs(playerList) do
		-- Reset player data for round
		local playerData = GameState.players[player.UserId]
		if playerData then
			GameState.ResetPlayerForRound(playerData)
			-- Restore color index after reset
			if GameState.currentMode.paintTiles then
				playerData.colorIndex = GameState.colorAssignments[player.UserId] or 0
			end
			SyncPlayerData:FireClient(player, playerData)
		end

		player:LoadCharacter()
	end

	-- Brief wait for characters to load
	task.wait(0.3)

	-- Remove ForceFields from all arena characters
	for _, player in ipairs(playerList) do
		local character = player.Character
		if character then
			local ff = character:FindFirstChildOfClass("ForceField")
			if ff then ff:Destroy() end
		end
	end

	-- Set up all characters
	for i, player in ipairs(playerList) do
		local character = player.Character
		if not character then
			task.wait(0.5)
			character = player.Character
		end
		if not character then continue end

		-- Wait for HumanoidRootPart to exist
		local hrp = character:WaitForChild("HumanoidRootPart", 3) :: BasePart?
		if not hrp then continue end

		-- Find MapSpawn part for this player
		local spawnPart = arena and arena:FindFirstChild("MapSpawn_" .. i)
		if not spawnPart then
			spawnPart = arena and arena:FindFirstChild("MapSpawn_1")
		end

		-- Set up character for arena
		RoundSystem.SetupArenaCharacter(character, player)

		local playerData = GameState.players[player.UserId]

		if spawnPart then
			-- Spawn slightly above the surface to prevent falling through
			local spawnY = spawnPart.Position.Y + (spawnPart.Size.Y / 2) + 2
			local spawnCFrame = CFrame.new(spawnPart.Position.X, spawnY, spawnPart.Position.Z)
			local _, rotY, _ = spawnPart.CFrame:ToEulerAnglesYXZ()
			hrp.CFrame = spawnCFrame * CFrame.Angles(0, rotY, 0)
		end

		-- Update character stats for nameplate UI
		if playerData then
			RoundSystem.UpdateCharacterStats(player, playerData)
		end

		-- Set up death handling
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.Died:Once(function()
				RoundSystem.OnPlayerDeath(player)
			end)
		end
	end
end

function RoundSystem.GetOrCreateCharacter(player: Player): Model?
	-- Use default Roblox character
	player:LoadCharacter()
	task.wait(0.3)

	local character = player.Character
	if not character then return nil end

	-- Remove ForceField
	local ff = character:FindFirstChildOfClass("ForceField")
	if ff then ff:Destroy() end

	RoundSystem.SetupArenaCharacter(character, player)
	return character
end

-- Set up a character for arena gameplay (no loading, just configuration)
function RoundSystem.SetupArenaCharacter(character: Model, player: Player?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Configure humanoid for arena gameplay
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.WalkSpeed = Constants.MOVE_SPEED
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0

	-- Slightly shrink player for in-game
	local scale = Constants.IN_GAME_SCALE
	local bodyDepth = humanoid:FindFirstChild("BodyDepthScale") :: NumberValue?
	local bodyHeight = humanoid:FindFirstChild("BodyHeightScale") :: NumberValue?
	local bodyWidth = humanoid:FindFirstChild("BodyWidthScale") :: NumberValue?
	local headScale = humanoid:FindFirstChild("HeadScale") :: NumberValue?
	if bodyDepth then bodyDepth.Value = scale end
	if bodyHeight then bodyHeight.Value = scale end
	if bodyWidth then bodyWidth.Value = scale end
	if headScale then headScale.Value = scale end

	-- Set physics properties on all body parts
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanTouch = true

			-- Disable collision on all limbs
			if part.Name ~= "HumanoidRootPart" then
				part.CanCollide = false
			end
		end
	end

	-- Force HumanoidRootPart collision every physics step (Humanoid controller resets it)
	-- Store connection on character so it can be cleaned up on respawn
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		-- Disconnect any previous collision connection (from prior respawn)
		local oldConn = character:GetAttribute("_collisionConn")
		if oldConn then
			-- Attribute can't store connections; we use a BindableEvent as cleanup signal
		end

		local collisionConn
		collisionConn = RunService.Stepped:Connect(function()
			if not character or not character.Parent then
				collisionConn:Disconnect()
				return
			end
			if hrp and hrp.Parent then
				hrp.CanCollide = true
			else
				collisionConn:Disconnect()
			end
		end)

		-- Store connection in a cleanup tag so RespawnPlayer can disconnect it
		local tag = Instance.new("BindableEvent")
		tag.Name = "_CollisionCleanup"
		tag.Parent = character
		tag.Event:Connect(function()
			collisionConn:Disconnect()
		end)
	end

	-- Create held bomb model welded to torso
	local heldBomb = RoundSystem.CreateHeldBomb(player)
	if heldBomb then
		-- R15: UpperTorso, R6: Torso, fallback: HumanoidRootPart
		local torso = character:FindFirstChild("UpperTorso")
			or character:FindFirstChild("Torso")
			or character:FindFirstChild("HumanoidRootPart")
		if torso then
			local weld = Instance.new("Weld")
			weld.Name = "BombWeld"
			weld.Part0 = torso
			weld.Part1 = heldBomb.PrimaryPart
			weld.C0 = CFrame.new(0, 0.3, -1.5)
			weld.Parent = heldBomb.PrimaryPart
			heldBomb.Parent = character
		end
	end

	-- Create stats folder for client UI to read
	local statsFolder = Instance.new("Folder")
	statsFolder.Name = "PlayerStats"
	statsFolder.Parent = character

	local bombCountVal = Instance.new("IntValue")
	bombCountVal.Name = "BombCount"
	bombCountVal.Value = Constants.MAX_BOMBS_DEFAULT
	bombCountVal.Parent = statsFolder

	local bombRangeVal = Instance.new("IntValue")
	bombRangeVal.Name = "BombRange"
	bombRangeVal.Value = Constants.BOMB_DEFAULT_RANGE
	bombRangeVal.Parent = statsFolder

	local speedVal = Instance.new("IntValue")
	speedVal.Name = "Speed"
	speedVal.Value = Constants.MOVE_SPEED
	speedVal.Parent = statsFolder

	-- Color index and team index for team/color modes
	local teamSizeForColor = GameState.currentMode.teamSize or 1
	if GameState.currentMode.paintTiles or teamSizeForColor > 1 then
		local colorVal = Instance.new("IntValue")
		colorVal.Name = "ColorIndex"
		colorVal.Value = player and GameState.colorAssignments[player.UserId] or 0
		colorVal.Parent = statsFolder
	end

	if teamSizeForColor > 1 and player then
		local teamVal = Instance.new("IntValue")
		teamVal.Name = "TeamIndex"
		teamVal.Value = GameState.teamAssignments[player.UserId] or 0
		teamVal.Parent = statsFolder
	end

	-- Color Battle: add tiles owned
	if GameState.currentMode.paintTiles then
		local tilesVal = Instance.new("IntValue")
		tilesVal.Name = "TilesOwned"
		tilesVal.Value = 0
		tilesVal.Parent = statsFolder
	end

	-- Set up server-side hold bomb animation
	if AnimationService then
		task.defer(function()
			AnimationService.SetupCharacter(character)
			AnimationService.UpdateHoldBomb(character, true)
		end)
	end
end

-- Update character stat values (for nameplate UI)
function RoundSystem.UpdateCharacterStats(player: Player, playerData: any)
	local character = player.Character
	if not character then return end

	local statsFolder = character:FindFirstChild("PlayerStats")
	if not statsFolder then return end

	local bombCount = statsFolder:FindFirstChild("BombCount")
	if bombCount then bombCount.Value = playerData.bombCount or Constants.MAX_BOMBS_DEFAULT end

	local bombRange = statsFolder:FindFirstChild("BombRange")
	if bombRange then bombRange.Value = playerData.bombRange or Constants.BOMB_DEFAULT_RANGE end

	local speed = statsFolder:FindFirstChild("Speed")
	if speed then speed.Value = playerData.speed or Constants.MOVE_SPEED end

	-- Color Battle stats
	local colorVal = statsFolder:FindFirstChild("ColorIndex")
	if colorVal then colorVal.Value = playerData.colorIndex or 0 end

	local tilesVal = statsFolder:FindFirstChild("TilesOwned")
	if tilesVal then tilesVal.Value = playerData.tilesOwned or 0 end
end

-- Create a bomb model to hold (uses player's equipped skin or Default Bomb)
function RoundSystem.CreateHeldBomb(player: Player?): Model
	local Assets = ReplicatedStorage:WaitForChild("Assets")
	local BombsFolder = Assets:WaitForChild("Bombs")

	-- Try to use the player's equipped skin
	local BombTemplate: Model? = nil
	if player and InventoryService then
		local inv = InventoryService.GetInventory(player)
		if inv and inv.equippedSkin and inv.equippedSkin ~= "" then
			local skinData = BombSkins.GetSkinById(inv.equippedSkin)
			if skinData then
				local skinModel = BombSkins.GetSkinModel(skinData)
				if skinModel then
					BombTemplate = skinModel
				end
			end
		end
	end
	-- Fallback to default
	if not BombTemplate then
		BombTemplate = BombsFolder:FindFirstChild("Default Bomb")
	end

	if BombTemplate and BombTemplate:IsA("Model") then
		local bomb = BombTemplate:Clone()
		bomb.Name = "HeldBomb"

		-- Configure all parts for held bomb (unanchored, massless, no collision)
		for _, part in ipairs(bomb:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.CanCollide = false
				part.Massless = true
			end
		end

		-- Weld ALL child parts to the primary part so complex models stay together
		local bombPart = bomb.PrimaryPart or bomb:FindFirstChild("Bomb")
		if bombPart then
			for _, child in ipairs(bomb:GetDescendants()) do
				if child:IsA("BasePart") and child ~= bombPart then
					local offset = bombPart.CFrame:ToObjectSpace(child.CFrame)
					local weld = Instance.new("Weld")
					weld.Part0 = bombPart
					weld.Part1 = child
					weld.C0 = offset
					weld.Parent = child

					-- Fuse-specific: add spark particles and light
					if child.Name == "Fuse" then
						if not child:FindFirstChild("Spark") then
							local spark = Instance.new("ParticleEmitter")
							spark.Name = "Spark"
							spark.Color = ColorSequence.new(Color3.fromRGB(255, 200, 0))
							spark.Size = NumberSequence.new(0.2, 0)
							spark.Lifetime = NumberRange.new(0.2, 0.4)
							spark.Rate = 20
							spark.Speed = NumberRange.new(1, 2)
							spark.SpreadAngle = Vector2.new(30, 30)
							spark.Parent = child
						end

						if not child:FindFirstChild("FuseLight") then
							local light = Instance.new("PointLight")
							light.Name = "FuseLight"
							light.Color = Color3.fromRGB(255, 150, 0)
							light.Brightness = 1
							light.Range = 4
							light.Parent = child
						end
					end
				end
			end
		end

		return bomb
	end

	-- Fallback: create a basic held bomb programmatically
	local bomb = Instance.new("Model")
	bomb.Name = "HeldBomb"

	local bombPart = Instance.new("Part")
	bombPart.Name = "Bomb"
	bombPart.Shape = Enum.PartType.Ball
	bombPart.Size = Vector3.new(1.8, 1.8, 1.8)
	bombPart.Color = Color3.fromRGB(30, 30, 30)
	bombPart.Material = Enum.Material.SmoothPlastic
	bombPart.CanCollide = false
	bombPart.Massless = true
	bombPart.Parent = bomb

	local fuse = Instance.new("Part")
	fuse.Name = "Fuse"
	fuse.Size = Vector3.new(0.15, 0.4, 0.15)
	fuse.Color = Color3.fromRGB(139, 90, 43)
	fuse.Material = Enum.Material.Fabric
	fuse.CanCollide = false
	fuse.Massless = true
	fuse.Parent = bomb

	local fuseWeld = Instance.new("Weld")
	fuseWeld.Part0 = bombPart
	fuseWeld.Part1 = fuse
	fuseWeld.C0 = CFrame.new(0, 0.9, 0)
	fuseWeld.Parent = fuse

	local spark = Instance.new("ParticleEmitter")
	spark.Name = "Spark"
	spark.Color = ColorSequence.new(Color3.fromRGB(255, 200, 0))
	spark.Size = NumberSequence.new(0.2, 0)
	spark.Lifetime = NumberRange.new(0.2, 0.4)
	spark.Rate = 20
	spark.Speed = NumberRange.new(1, 2)
	spark.SpreadAngle = Vector2.new(30, 30)
	spark.Parent = fuse

	local light = Instance.new("PointLight")
	light.Name = "FuseLight"
	light.Color = Color3.fromRGB(255, 150, 0)
	light.Brightness = 1
	light.Range = 4
	light.Parent = fuse

	bomb.PrimaryPart = bombPart
	return bomb
end

function RoundSystem.OnPlayerDeath(player: Player)
	local playerData = GameState.players[player.UserId]
	if not playerData then return end

	if not playerData.isAlive then return end -- Already dead

	-- In respawn mode, deaths are handled by DamagePlayer — skip Humanoid.Died fallback
	if GameState.currentMode and GameState.currentMode.respawn then return end

	local eliminated = GameState.TakeDamage(playerData)

	if eliminated then
		playerData.isAlive = false
		PlayerDied:FireAllClients(player.UserId, 0)

		-- Check if round should end
		RoundSystem.CheckRoundEnd()
	else
		-- Player took damage but not eliminated
		SyncPlayerData:FireClient(player, playerData)
	end
end

-- Ragdoll a character for death crumble effect (R15)
function RoundSystem.RagdollCharacter(character: Model)
	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if not humanoid then return end

	-- Prevent humanoid from recovering
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	-- Enable collisions on all body parts so they rest on ground
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = true
			part.CanQuery = false
		end
	end

	-- Convert Motor6Ds to BallSocketConstraints for ragdoll physics
	for _, motor in ipairs(character:GetDescendants()) do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			local att0 = Instance.new("Attachment")
			att0.Name = "RagdollAtt0"
			att0.CFrame = motor.C0
			att0.Parent = motor.Part0

			local att1 = Instance.new("Attachment")
			att1.Name = "RagdollAtt1"
			att1.CFrame = motor.C1
			att1.Parent = motor.Part1

			local constraint = Instance.new("BallSocketConstraint")
			constraint.Attachment0 = att0
			constraint.Attachment1 = att1
			constraint.LimitsEnabled = true
			constraint.UpperAngle = 50
			constraint.TwistLimitsEnabled = false
			constraint.Parent = motor.Part0

			motor.Enabled = false
		end
	end

	-- Break accessory welds so they fall off during crumble
	for _, accessory in ipairs(character:GetChildren()) do
		if accessory:IsA("Accessory") then
			local handle = accessory:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				handle.CanCollide = true
				for _, weld in ipairs(handle:GetChildren()) do
					if weld:IsA("Weld") or weld:IsA("WeldConstraint") then
						weld:Destroy()
					end
				end
			end
		end
	end

	-- Break held bomb weld
	local heldBomb = character:FindFirstChild("HeldBomb")
	if heldBomb then
		local bombWeld = heldBomb:FindFirstChild("BombWeld", true)
		if bombWeld then
			bombWeld:Destroy()
		end
		for _, part in ipairs(heldBomb:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = true
			end
		end
	end

	-- Small pop impulse for dramatic ragdoll launch
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.Anchored = false
		hrp:ApplyImpulse(Vector3.new(
			math.random(-20, 20),
			math.random(40, 80),
			math.random(-20, 20)
		))
	end
end

-- Find a random spawn point not occupied by another player
function RoundSystem.GetUnoccupiedSpawn(): BasePart?
	local arena = Workspace:FindFirstChild("Arena")
	if not arena then return nil end

	local spawns = {}
	for _, child in ipairs(arena:GetChildren()) do
		if child:IsA("BasePart") and child.Name:match("^MapSpawn_%d+$") then
			table.insert(spawns, child)
		end
	end

	if #spawns == 0 then return nil end

	-- Gather alive player positions
	local playerPositions = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local character = p.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				table.insert(playerPositions, hrp.Position)
			end
		end
	end

	-- Filter to unoccupied spawns (no player within 6 studs)
	local unoccupied = {}
	for _, spawn in ipairs(spawns) do
		local occupied = false
		for _, pos in ipairs(playerPositions) do
			if (spawn.Position - pos).Magnitude < 6 then
				occupied = true
				break
			end
		end
		if not occupied then
			table.insert(unoccupied, spawn)
		end
	end

	if #unoccupied > 0 then
		return unoccupied[math.random(1, #unoccupied)]
	end
	-- Fallback: any random spawn
	return spawns[math.random(1, #spawns)]
end

-- Respawn a player after death in Respawn mode
function RoundSystem.RespawnPlayer(player: Player)
	if GameState.currentState ~= Constants.STATES.PLAYING then return end
	local playerData = GameState.players[player.UserId]
	if not playerData then return end

	-- Pick spawn before reloading character
	local spawnPart = RoundSystem.GetUnoccupiedSpawn()

	-- Destroy old character and clean up
	local oldChar = player.Character
	if oldChar then
		-- Disconnect collision connection from previous life
		local cleanupTag = oldChar:FindFirstChild("_CollisionCleanup")
		if cleanupTag and cleanupTag:IsA("BindableEvent") then
			cleanupTag:Fire()
		end

		if AnimationService then
			AnimationService.CleanupCharacter(oldChar)
		end
		oldChar:Destroy()
		player.Character = nil
	end

	-- Load fresh character
	player:LoadCharacter()
	task.wait(0.3)

	local character = player.Character
	if not character then return end

	-- Remove ForceField
	local ff = character:FindFirstChildOfClass("ForceField")
	if ff then ff:Destroy() end

	-- Position at spawn
	if spawnPart then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local spawnY = spawnPart.Position.Y + (spawnPart.Size.Y / 2)
			local spawnCFrame = CFrame.new(spawnPart.Position.X, spawnY, spawnPart.Position.Z)
			local _, rotY, _ = spawnPart.CFrame:ToEulerAnglesYXZ()
			hrp.CFrame = spawnCFrame * CFrame.Angles(0, rotY, 0)
		end
	end

	-- Set up character for arena
	RoundSystem.SetupArenaCharacter(character, player)

	-- Restore player stats (keep kills, reset powerups)
	playerData.isAlive = true
	playerData.hasShield = false
	playerData.bombCount = Constants.MAX_BOMBS_DEFAULT
	playerData.bombRange = Constants.BOMB_DEFAULT_RANGE
	playerData.speed = Constants.MOVE_SPEED
	playerData.activeBombs = 0

	-- Apply walk speed
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = playerData.speed

		-- Re-register death handler
		humanoid.Died:Once(function()
			RoundSystem.OnPlayerDeath(player)
		end)
	end

	-- Update nameplate stats
	RoundSystem.UpdateCharacterStats(player, playerData)

	-- Start invulnerability
	playerData.invulnerable = true
	SyncPlayerData:FireClient(player, playerData)

	-- Blink effect coroutine
	task.spawn(function()
		local elapsed = 0
		local visible = true
		local heldBomb = character:FindFirstChild("HeldBomb")

		-- Store original transparency values so we restore them correctly
		local originalTransparency: {[BasePart]: number} = {}
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart"
				and not (heldBomb and part:IsDescendantOf(heldBomb)) then
				originalTransparency[part] = part.Transparency
			end
		end

		while elapsed < Constants.RESPAWN_INVULN_DURATION do
			if not character or not character.Parent then break end
			visible = not visible
			for part, origT in pairs(originalTransparency) do
				if part and part.Parent then
					part.Transparency = if visible then origT else math.max(origT, 0.5)
				end
			end
			task.wait(Constants.RESPAWN_BLINK_INTERVAL)
			elapsed = elapsed + Constants.RESPAWN_BLINK_INTERVAL
		end
		-- Restore original transparency values
		if character and character.Parent then
			for part, origT in pairs(originalTransparency) do
				if part and part.Parent then
					part.Transparency = origT
				end
			end
		end
		playerData.invulnerable = false
	end)
end

function RoundSystem.DamagePlayer(player: Player, killerId: number?)
	local playerData = GameState.players[player.UserId]
	if not playerData or not playerData.isAlive then return end

	-- Check respawn invulnerability
	if playerData.invulnerable then return end

	-- Friendly fire immunity: teammates can't damage each other (but you CAN damage yourself)
	if killerId and killerId ~= 0 and killerId ~= player.UserId then
		if RoundSystem.AreTeammates(player.UserId, killerId) then
			return -- teammate bomb, no damage
		end
	end

	-- Respawn mode: no elimination, just ragdoll and respawn
	if GameState.currentMode.respawn then
		-- Credit the kill (skip self-kills)
		if killerId and killerId ~= 0 and killerId ~= player.UserId then
			local killerData = GameState.players[killerId]
			if killerData then
				killerData.kills = (killerData.kills or 0) + 1
				local killerPlayer = Players:GetPlayerByUserId(killerId)
				if killerPlayer then
					SyncPlayerData:FireClient(killerPlayer, killerData)
				end
			end
		end

		-- Fire kill feed event
		PlayerDied:FireAllClients(player.UserId, killerId or 0)

		-- Ragdoll briefly
		local character = player.Character
		if character then
			RoundSystem.RagdollCharacter(character)
		end

		-- After delay, respawn (no fade-to-black)
		task.delay(Constants.RESPAWN_DELAY, function()
			RoundSystem.RespawnPlayer(player)
		end)
		return
	end

	local eliminated = GameState.TakeDamage(playerData)
	SyncPlayerData:FireClient(player, playerData)

	if eliminated then
		PlayerDied:FireAllClients(player.UserId, killerId or 0)

		-- Ragdoll character for crumble death effect
		local character = player.Character
		if character then
			RoundSystem.RagdollCharacter(character)

			-- Let ragdoll + crumble play out, then fade and clean up
			task.delay(1.2, function()
				-- Tell the dead player to fade to black
				RoundStateChanged:FireClient(player, "FadeToLobby")

				-- Destroy character while screen is black
				task.delay(0.3, function()
					if character and character.Parent then
						if AnimationService then
							AnimationService.CleanupCharacter(character)
						end
						character:Destroy()
						player.Character = nil
					end
					RoundSystem.SpawnPlayerInLobby(player)
				end)
			end)
		end

		-- Delay round end check so death animation plays out
		task.delay(2, function()
			RoundSystem.CheckRoundEnd()
		end)
	end
end

function RoundSystem.CheckRoundEnd()
	if GameState.currentState ~= Constants.STATES.PLAYING then return end

	-- Respawn mode: round never ends from kills, only from timer
	if GameState.currentMode.respawn then return end

	-- In Color Battle mode, end early only if the tile leader is the last one alive
	if GameState.currentMode.paintTiles then
		local alivePlayers = GameState.GetAlivePlayers()
		if #alivePlayers <= 1 and #alivePlayers > 0 then
			local lastAlive = alivePlayers[1]
			-- Check if the last player alive also leads in tiles
			local bestUserId = 0
			local bestTiles = 0
			for userId, playerData in pairs(GameState.players) do
				local tiles = MapData.CountTilesOwnedBy(userId)
				playerData.tilesOwned = tiles
				if tiles > bestTiles then
					bestTiles = tiles
					bestUserId = userId
				end
			end
			if lastAlive.userId == bestUserId then
				-- Tile leader is last alive — no contest, end now
				for _, p in ipairs(Players:GetPlayers()) do
					if p.UserId == bestUserId then
						currentWinner = p
						break
					end
				end
				RoundSystem.EndRound()
			end
			-- Otherwise let the timer run out so tile counts decide
		end
		return
	end

	local alivePlayers = GameState.GetAlivePlayers()
	local totalPlayers = #Players:GetPlayers()
	local teamSize = GameState.currentMode.teamSize or 1

	-- In single player testing mode, only end if player dies
	if totalPlayers == 1 then
		if #alivePlayers == 0 then
			currentWinner = nil
			RoundSystem.EndRound()
		end
		return
	end

	if teamSize > 1 then
		-- Team mode: check if only one team has alive players
		local aliveTeams = {} :: {[number]: boolean}
		for _, pd in ipairs(alivePlayers) do
			local team = GameState.teamAssignments[pd.userId]
			if team then
				aliveTeams[team] = true
			end
		end

		local teamCount = 0
		local lastTeam = 0
		for team in pairs(aliveTeams) do
			teamCount += 1
			lastTeam = team
		end

		if teamCount <= 1 then
			if teamCount == 1 and #alivePlayers > 0 then
				-- Find first alive player on winning team as the "winner"
				-- (the results screen will show all winning teammates)
				for _, pd in ipairs(alivePlayers) do
					if GameState.teamAssignments[pd.userId] == lastTeam then
						for _, p in ipairs(Players:GetPlayers()) do
							if p.UserId == pd.userId then
								currentWinner = p
								break
							end
						end
						break
					end
				end
			elseif #alivePlayers == 0 then
				currentWinner = nil -- Draw, all dead
			end
			RoundSystem.EndRound()
		end
	else
		-- FFA mode
		if #alivePlayers <= 1 then
			if #alivePlayers == 1 then
				local winnerData = alivePlayers[1]
				for _, p in ipairs(Players:GetPlayers()) do
					if p.UserId == winnerData.userId then
						currentWinner = p
						break
					end
				end
			else
				currentWinner = nil -- Draw
			end
			RoundSystem.EndRound()
		end
	end
end

function RoundSystem.EndRound()
	RoundSystem.SetState(Constants.STATES.ROUND_END)
end

function RoundSystem.TriggerAdminEvent(eventId: string)
	print("[RoundSystem] Admin event triggered: " .. eventId)

	if eventId == "MAP_BREAK" then
		-- Destroy all soft walls
		MapGenerator.DestroyAllSoftWalls()
	elseif eventId == "COIN_RAIN" then
		-- Spawn coins randomly
		task.spawn(function()
			for i = 1, 30 do
				local x = math.random(1, Constants.GRID_WIDTH)
				local y = math.random(1, Constants.GRID_HEIGHT)
				if MapData.IsWalkable(x, y) then
					PowerUpService.SpawnCoin(x, y)
				end
				task.wait(0.1)
			end
		end)
	elseif eventId == "SIZE_CHAOS" then
		-- Random size changes
		task.spawn(function()
			for _ = 1, 5 do
				for _, player in ipairs(Players:GetPlayers()) do
					local character = player.Character
					if character then
						local humanoid = character:FindFirstChild("Humanoid")
						if humanoid then
							local scale = humanoid:FindFirstChild("BodyHeightScale")
							if scale then
								scale.Value = math.random(50, 250) / 100
							end
						end
					end
				end
				task.wait(3)
			end
			-- Reset sizes
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				if character then
					local humanoid = character:FindFirstChild("Humanoid")
					if humanoid then
						local scale = humanoid:FindFirstChild("BodyHeightScale")
						if scale then
							scale.Value = 1
						end
					end
				end
			end
		end)
	elseif eventId == "SPEED_GOD" then
		-- Max speed for all
		for _, playerData in pairs(GameState.players) do
			playerData.speed = Constants.MOVE_SPEED_MAX
		end
		task.delay(10, function()
			for _, playerData in pairs(GameState.players) do
				playerData.speed = Constants.MOVE_SPEED
			end
		end)
	elseif eventId == "BOMB_PARTY" then
		-- Unlimited bombs and max range
		for _, playerData in pairs(GameState.players) do
			playerData.bombCount = 99
			playerData.bombRange = 10
		end
		task.delay(10, function()
			for _, playerData in pairs(GameState.players) do
				playerData.bombCount = Constants.MAX_BOMBS_DEFAULT
				playerData.bombRange = Constants.BOMB_DEFAULT_RANGE
			end
		end)
	end
end

-- Weighted random pick: entries get reduced weight if their id is in the recency list
local function WeightedPick(entries: {{id: string, [string]: any}}, recentIds: {string}): {id: string, [string]: any}
	-- Build weight table
	local weights = {}
	local totalWeight = 0
	for i, entry in ipairs(entries) do
		local w = 1.0
		for _, recentId in ipairs(recentIds) do
			if entry.id == recentId then
				w = w * RECENCY_MULTIPLIER
				break
			end
		end
		weights[i] = w
		totalWeight = totalWeight + w
	end

	-- Roll
	local roll = math.random() * totalWeight
	local cumulative = 0
	for i, entry in ipairs(entries) do
		cumulative = cumulative + weights[i]
		if roll <= cumulative then
			return entry
		end
	end
	return entries[#entries] -- fallback
end

-- Track a chosen id in a recency list (keep last 2)
local function TrackRecent(list: {string}, id: string)
	table.insert(list, id)
	if #list > 2 then
		table.remove(list, 1)
	end
end

function RoundSystem.SelectRandomMode(): (string, string)
	-- Exclude AFK players from player count so team modes require enough active players
	local playerCount = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if not GameState.IsPlayerAFK(p.UserId) then
			playerCount = playerCount + 1
		end
	end

	-- Filter formats by player count: 2v2 needs 4+, 3v3 needs 6+
	local eligible = {}
	for _, fmt in ipairs(Constants.PLAYER_FORMATS) do
		local minPlayers = fmt.teamSize * 2 -- need at least 2 full teams
		if minPlayers <= 2 then minPlayers = 1 end -- FFA works with any count
		if playerCount >= minPlayers then
			table.insert(eligible, fmt)
		end
	end
	if #eligible == 0 then
		eligible = { Constants.PLAYER_FORMATS[1] } -- fallback to FFA
	end

	local format = WeightedPick(eligible, recentFormats)
	local gameType = WeightedPick(Constants.GAME_TYPES, recentGameTypes)

	-- Track selections for future weighting
	TrackRecent(recentFormats, format.id)
	TrackRecent(recentGameTypes, gameType.id)

	local mode = Constants.GetModeFromCombo(format.id, gameType.id)
	GameState.currentMode = mode
	return format.id, gameType.id
end

function RoundSystem.GameLoop()
	while true do
		-- LOBBY STATE
		RoundSystem.SetState(Constants.STATES.LOBBY)

		-- Clear team assignments from previous round
		GameState.teamAssignments = {}

		-- Keep Canvas hidden — the generated arena map is visible instead
		local canvas = Workspace:FindFirstChild("Canvas")
		if canvas and canvas:IsA("BasePart") then
			canvas.Transparency = 1
		end

		-- Ensure a preview map exists (first iteration won't have one from end-of-round)
		local arenaCheck = Workspace:FindFirstChild("Arena")
		if not arenaCheck or #arenaCheck:GetChildren() == 0 then
			MapGenerator.GenerateMap()
		end

		local waitStart = tick()

		while GameState.GetPlayerCount() < Constants.MIN_PLAYERS do
			task.wait(1)
			-- Don't wait forever if no players
			if tick() - waitStart > 300 then
				waitStart = tick() -- Reset timer
			end
		end

		-- Wait for more players or timeout
		local lobbyTimer = Constants.LOBBY_WAIT_TIME
		while lobbyTimer > 0 do
			roundTimer = lobbyTimer
			RoundStateChanged:FireAllClients("Timer", {timer = lobbyTimer})
			task.wait(1)
			lobbyTimer = lobbyTimer - 1
		end

		-- Select random game mode and fire to clients for slot animation
		local chosenFormat, chosenType = RoundSystem.SelectRandomMode()
		ModeSelection:FireAllClients(chosenFormat, chosenType)
		task.wait(Constants.MODE_SELECTION_DURATION)

		-- Tell clients to black out the screen before any respawning happens
		RoundStateChanged:FireAllClients("Preparing", {
			mode = GameState.currentMode,
		})
		task.wait(0.4) -- Let the black fade complete on clients

		-- Generate new map (skip character select)
		MapGenerator.GenerateMap()

		-- Hide Canvas part since arena floor is now generated
		local canvas = Workspace:FindFirstChild("Canvas")
		if canvas and canvas:IsA("BasePart") then
			canvas.Transparency = 1
		end

		-- Start falling tiles BEFORE spawning players so lava is already present
		if GameState.currentMode.fallingTiles then
			FallingTilesService.Start()
		end

		-- Spawn players in arena FIRST so they're on the map before camera starts
		RoundSystem.SpawnPlayersInArena()

		-- Lock all players during countdown (WalkSpeed = 0)
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				local hum = p.Character:FindFirstChild("Humanoid")
				if hum then
					hum.WalkSpeed = 0
				end
			end
		end

		-- Brief wait for characters to fully settle on the map
		task.wait(0.3)

		-- COUNTDOWN STATE — now that players are positioned
		RoundSystem.SetState(Constants.STATES.COUNTDOWN)

		-- Send active player list for camera panning (exclude AFK players)
		local activePlayers = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character and not GameState.IsPlayerAFK(p.UserId) then
				table.insert(activePlayers, p.UserId)
			end
		end

		for i = 3, 1, -1 do
			roundTimer = i
			RoundStateChanged:FireAllClients("Countdown", {number = i, activePlayers = activePlayers})
			task.wait(1)
		end
		RoundStateChanged:FireAllClients("Countdown", {number = -1, text = "Bomb Them Up!", activePlayers = activePlayers})
		task.wait(0.8)

		-- PLAYING STATE — unlock movement
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				local hum = p.Character:FindFirstChild("Humanoid")
				if hum then
					local pd = GameState.players[p.UserId]
					hum.WalkSpeed = pd and pd.speed or Constants.MOVE_SPEED
				end
			end
		end

		RoundSystem.SetState(Constants.STATES.PLAYING)
		currentWinner = nil

		local playTimer = Constants.ROUND_LENGTH
		while playTimer > 0 and GameState.currentState == Constants.STATES.PLAYING do
			roundTimer = playTimer
			UpdateHUD:FireAllClients("Timer", playTimer)

			task.wait(1)
			playTimer = playTimer - 1

			-- Update curse effects
			for _, playerData in pairs(GameState.players) do
				if playerData.curseEndTime and tick() >= playerData.curseEndTime then
					playerData.curseEndTime = nil
				end
			end
		end

		-- Time ran out
		if GameState.currentState == Constants.STATES.PLAYING then
			if GameState.currentMode.respawn then
				-- Respawn mode: winner is player with most kills
				local bestKills = -1
				local bestUserId = 0
				for userId, playerData in pairs(GameState.players) do
					if (playerData.kills or 0) > bestKills then
						bestKills = playerData.kills or 0
						bestUserId = userId
					end
				end
				if bestUserId ~= 0 then
					for _, p in ipairs(Players:GetPlayers()) do
						if p.UserId == bestUserId then
							currentWinner = p
							break
						end
					end
				else
					currentWinner = nil
				end
				RoundSystem.EndRound()
			elseif GameState.currentMode.paintTiles then
				-- Color Battle: determine winner by most tiles
				local bestUserId = 0
				local bestTiles = 0
				for userId, playerData in pairs(GameState.players) do
					local tiles = MapData.CountTilesOwnedBy(userId)
					playerData.tilesOwned = tiles
					if tiles > bestTiles then
						bestTiles = tiles
						bestUserId = userId
					end
				end

				if bestUserId ~= 0 then
					for _, p in ipairs(Players:GetPlayers()) do
						if p.UserId == bestUserId then
							currentWinner = p
							break
						end
					end
				else
					currentWinner = nil
				end
			else
				-- Sudden death if tied
				local alive = GameState.GetAlivePlayers()
				if #alive > 1 then
					-- Destroy all remaining soft walls
					MapGenerator.DestroyAllSoftWalls()

					-- Double bomb range
					for _, playerData in pairs(GameState.players) do
						playerData.bombRange = playerData.bombRange * 2
					end

					-- Give extra time
					playTimer = 30
					while playTimer > 0 and GameState.currentState == Constants.STATES.PLAYING do
						UpdateHUD:FireAllClients("Timer", playTimer)
						task.wait(1)
						playTimer = playTimer - 1
					end
				end

				-- After sudden death, determine winner
				if GameState.currentState == Constants.STATES.PLAYING then
					local teamSizeSD = GameState.currentMode.teamSize or 1
					local aliveSD = GameState.GetAlivePlayers()

					if teamSizeSD > 1 then
						-- Team mode tiebreaker: team with most alive players wins
						local teamAliveCounts = {} :: {[number]: number}
						for _, pd in ipairs(aliveSD) do
							local team = GameState.teamAssignments[pd.userId]
							if team then
								teamAliveCounts[team] = (teamAliveCounts[team] or 0) + 1
							end
						end

						local bestTeam = 0
						local bestCount = 0
						local isTied = false
						for team, count in pairs(teamAliveCounts) do
							if count > bestCount then
								bestCount = count
								bestTeam = team
								isTied = false
							elseif count == bestCount then
								isTied = true
							end
						end

						if isTied or bestTeam == 0 then
							currentWinner = nil -- Draw
						else
							-- Find first alive player on winning team
							for _, pd in ipairs(aliveSD) do
								if GameState.teamAssignments[pd.userId] == bestTeam then
									for _, p in ipairs(Players:GetPlayers()) do
										if p.UserId == pd.userId then
											currentWinner = p
											break
										end
									end
									break
								end
							end
						end
					else
						-- FFA: if still multiple alive after sudden death, pick by most kills
						if #aliveSD > 1 then
							local bestKillsSD = -1
							local bestPlayerSD: Player? = nil
							for _, pd in ipairs(aliveSD) do
								local kills = pd.kills or 0
								if kills > bestKillsSD then
									bestKillsSD = kills
									for _, p in ipairs(Players:GetPlayers()) do
										if p.UserId == pd.userId then
											bestPlayerSD = p
											break
										end
									end
								end
							end
							currentWinner = bestPlayerSD
						elseif #aliveSD == 1 then
							for _, p in ipairs(Players:GetPlayers()) do
								if p.UserId == aliveSD[1].userId then
									currentWinner = p
									break
								end
							end
						else
							currentWinner = nil
						end
					end
				end
			end

			RoundSystem.EndRound()
		end

		-- ROUND END STATE - Announce winner on map
		-- (State already set to ROUND_END by EndRound())

		-- Calculate results
		roundResults = RoundSystem.CalculateResults()

		-- Accumulate lifetime kills and wins into persistent data
		for _, result in ipairs(roundResults) do
			local persistent = GameState.persistentData[result.userId]
			if persistent then
				-- Add this round's kills to lifetime total
				persistent.totalKills = (persistent.totalKills or 0) + (result.kills or 0)

				-- Update TotalKills IntValue
				local p = Players:GetPlayerByUserId(result.userId)
				if p then
					local pStats = p:FindFirstChild("PersistentStats")
					if pStats then
						local killsValObj = pStats:FindFirstChild("TotalKills")
						if killsValObj then killsValObj.Value = persistent.totalKills end
					end

					-- Push updated kills to leaderboard
					if LeaderboardService then
						LeaderboardService.UpdatePlayerStats(p, "totalKills", persistent.totalKills)
					end
				end
			end
		end

		-- Increment wins for the winner(s) — all teammates in team modes
		if currentWinner then
			local winningPlayers = { currentWinner }
			local tSize = GameState.currentMode.teamSize or 1
			if tSize > 1 then
				local winnerTeam = GameState.teamAssignments[currentWinner.UserId]
				if winnerTeam then
					winningPlayers = {}
					for _, p in ipairs(Players:GetPlayers()) do
						if GameState.teamAssignments[p.UserId] == winnerTeam then
							table.insert(winningPlayers, p)
						end
					end
				end
			end

			for _, wp in ipairs(winningPlayers) do
				local persistent = GameState.persistentData[wp.UserId]
				if persistent then
					persistent.wins = (persistent.wins or 0) + 1

					if LeaderboardService then
						LeaderboardService.UpdatePlayerStats(wp, "wins", persistent.wins)
					end
				end

				-- Award W Bomber badge on first win
				task.spawn(function()
					pcall(function()
						local BADGE_W_BOMBER = 3977195912374781
						if not BadgeService:UserHasBadgeAsync(wp.UserId, BADGE_W_BOMBER) then
							BadgeService:AwardBadge(wp.UserId, BADGE_W_BOMBER)
						end
					end)
				end)
			end
		end

		-- Stop bombs and falling tiles immediately so winner can't die during celebration
		BombService.ClearAllBombs()
		FallingTilesService.Stop()

		-- Make all players invulnerable and freeze them
		for _, p in ipairs(Players:GetPlayers()) do
			local pd = GameState.players[p.UserId]
			if pd then
				pd.invulnerable = true
			end
			if p.Character then
				local hum = p.Character:FindFirstChild("Humanoid")
				if hum then
					hum.WalkSpeed = 0
				end
				local hrp = p.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					hrp.Anchored = true
				end
				-- Hide held bomb
				local heldBomb = p.Character:FindFirstChild("HeldBomb")
				if heldBomb then
					for _, part in ipairs(heldBomb:GetDescendants()) do
						if part:IsA("BasePart") then
							part.Transparency = 1
						elseif part:IsA("ParticleEmitter") then
							part.Enabled = false
						elseif part:IsA("Light") then
							part.Enabled = false
						end
					end
				end
			end
		end

		-- Play a random win dance on the winner's character
		if currentWinner and currentWinner.Character and WinDances then
			local humanoid = currentWinner.Character:FindFirstChild("Humanoid")
			if humanoid then
				local animator = humanoid:FindFirstChild("Animator")
				if not animator then
					animator = Instance.new("Animator")
					animator.Parent = humanoid
				end

				-- Unanchor winner so animation plays properly
				local winnerHrp = currentWinner.Character:FindFirstChild("HumanoidRootPart")
				if winnerHrp then
					winnerHrp.Anchored = false
				end

				-- Use equipped dance if available, otherwise random
				local chosenDance = nil
				if InventoryService then
					local inv = InventoryService.GetInventory(currentWinner)
					if inv and inv.equippedDance and inv.equippedDance ~= "" then
						chosenDance = WinDances.GetById(inv.equippedDance)
					end
				end
				if not chosenDance then
					local dances = WinDances.Dances
					chosenDance = dances[math.random(1, #dances)]
				end
				local animation = Instance.new("Animation")
				animation.AnimationId = chosenDance.animId

				local animTrack = animator:LoadAnimation(animation)
				animTrack.Priority = Enum.AnimationPriority.Action4
				animTrack.Looped = true
				animTrack:Play()
			end
		end

		-- Build winning team info for team modes
		local winnerNames = {}
		local winnerIds = {}
		local teamSize = GameState.currentMode.teamSize or 1

		if currentWinner and teamSize > 1 then
			local winnerTeam = GameState.teamAssignments[currentWinner.UserId]
			if winnerTeam then
				for _, p in ipairs(Players:GetPlayers()) do
					if GameState.teamAssignments[p.UserId] == winnerTeam then
						table.insert(winnerNames, p.Name)
						table.insert(winnerIds, p.UserId)
					end
				end
			end
		end

		if #winnerNames == 0 and currentWinner then
			winnerNames = { currentWinner.Name }
			winnerIds = { currentWinner.UserId }
		end

		-- Announce winner to all clients (stays on map)
		RoundStateChanged:FireAllClients("RoundResults", {
			results = roundResults,
			winner = #winnerNames > 0 and table.concat(winnerNames, " & ") or "Nobody",
			winnerId = currentWinner and currentWinner.UserId or 0,
			winnerIds = winnerIds,
			teamAssignments = teamSize > 1 and GameState.teamAssignments or nil,
		})

		-- Show winner cinematic for longer to allow dance + stats + XP progress display
		task.wait(8)

		-- Clean up remaining arena objects (bombs and falling tiles already stopped at round end)
		PowerUpService.ClearAllPowerUps()

		-- Black fade transition, then return all players to lobby
		RoundStateChanged:FireAllClients("FadeToLobby")
		task.wait(0.5)

		-- Clear the map and immediately generate a fresh one so players see it from lobby
		local arenaFolder = Workspace:FindFirstChild("Arena")
		if arenaFolder then
			arenaFolder:ClearAllChildren()
		end
		MapData.InitializeGrids()
		MapGenerator.GenerateMap()

		-- Hide Canvas since arena floor is visible
		local canvasRef = Workspace:FindFirstChild("Canvas")
		if canvasRef and canvasRef:IsA("BasePart") then
			canvasRef.Transparency = 1
		end

		-- INTERMISSION STATE
		RoundSystem.SetState(Constants.STATES.INTERMISSION)

		for _, p in ipairs(Players:GetPlayers()) do
			RoundSystem.SpawnPlayerInLobby(p)
			task.wait(0.1)
		end

		-- Now that players are back in lobby, destroy lava and restore Canvas
		FallingTilesService.Cleanup()

		-- Brief pause for cleanup before looping back to lobby countdown
		task.wait(1)
	end
end

return RoundSystem
