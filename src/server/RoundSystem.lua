--!strict
-- RoundSystem.lua
-- Manages game rounds, states, and transitions

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapData = require(Shared:WaitForChild("MapData"))

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

-- State tracking
local roundCoroutine: thread? = nil
local roundTimer = 0
local currentWinner: Player? = nil
local roundResults = {} -- {userId, kills, place}

-- Remotes for emotes/stickers
local PlayEmote
local ShowSticker

-- Character models for spawning
local CharactersFolder = ReplicatedStorage:WaitForChild("Characters")

function RoundSystem.Initialize()
	local ServerFolder = script.Parent
	BombService = require(ServerFolder:WaitForChild("BombService"))
	MapGenerator = require(ServerFolder:WaitForChild("MapGenerator"))
	PowerUpService = require(ServerFolder:WaitForChild("PowerUpService"))

	-- Build lobby, characters, and winners podium
	MapGenerator.BuildLobby()
	MapGenerator.BuildCharacters()
	MapGenerator.BuildWinnersPodium()

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

	-- Handle emote requests
	PlayEmote.OnServerEvent:Connect(function(player: Player, emoteId: string)
		RoundSystem.HandleEmote(player, emoteId)
	end)

	-- Handle sticker requests
	ShowSticker.OnServerEvent:Connect(function(player: Player, stickerId: string)
		RoundSystem.HandleSticker(player, stickerId)
	end)

	-- Start game loop
	task.spawn(RoundSystem.GameLoop)
end

-- Handle emote playing
function RoundSystem.HandleEmote(player: Player, emoteId: string)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end

	-- Find emote data
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
	local character = player.Character
	if not character then return end

	-- Find sticker data
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
function RoundSystem.CalculateResults(): {{userId: number, kills: number, place: number}}
	local results = {}

	for userId, playerData in pairs(GameState.players) do
		table.insert(results, {
			userId = userId,
			kills = playerData.kills or 0,
			isAlive = playerData.isAlive,
		})
	end

	-- Sort by: alive first, then by kills
	table.sort(results, function(a, b)
		if a.isAlive ~= b.isAlive then
			return a.isAlive
		end
		return a.kills > b.kills
	end)

	-- Assign places
	for i, result in ipairs(results) do
		result.place = i
	end

	return results
end

-- Teleport winners to podium
function RoundSystem.TeleportToPodium(results: {{userId: number, kills: number, place: number}})
	for _, result in ipairs(results) do
		if result.place <= 3 then
			local player = Players:GetPlayerByUserId(result.userId)
			if player and player.Character then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local podiumPos = MapGenerator.GetPodiumPosition(result.place)
					hrp.CFrame = CFrame.new(podiumPos) * CFrame.Angles(0, math.rad(180), 0)
				end
			end
		end
	end

	-- Enable confetti
	MapGenerator.SetConfettiEnabled(true)
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
	-- Spawn player in lobby
	RoundSystem.SpawnPlayerInLobby(player)

	-- Sync current game state
	RoundStateChanged:FireClient(player, GameState.currentState, {
		timer = roundTimer,
		mode = GameState.currentMode,
	})
end

function RoundSystem.OnPlayerRemoved(player: Player)
	-- Check if this affects the round
	if GameState.currentState == Constants.STATES.PLAYING then
		RoundSystem.CheckRoundEnd()
	end
end

function RoundSystem.SpawnPlayerInLobby(player: Player)
	-- Create a simple spawn location in lobby
	local lobbyFolder = Workspace:FindFirstChild("Lobby")
	if not lobbyFolder then return end

	local spawnPart = lobbyFolder:FindFirstChild("SpawnLocation")
	if spawnPart then
		local character = player.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local offset = Vector3.new(math.random(-5, 5), 3, math.random(-5, 5))
				hrp.CFrame = spawnPart.CFrame + offset
			end
		end
	end
end

function RoundSystem.SpawnPlayersInArena()
	local spawnPositions = MapData.GetSpawnPositions()
	local playerList = Players:GetPlayers()

	for i, player in ipairs(playerList) do
		local spawnIndex = ((i - 1) % #spawnPositions) + 1
		local spawnPos = spawnPositions[spawnIndex]

		-- Reset player data for round
		local playerData = GameState.players[player.UserId]
		if playerData then
			GameState.ResetPlayerForRound(playerData)
			SyncPlayerData:FireClient(player, playerData)
		end

		-- Create or get character
		local character = RoundSystem.GetOrCreateCharacter(player)
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.CFrame = CFrame.new(spawnPos + Vector3.new(0, 3, 0))
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
end

function RoundSystem.GetOrCreateCharacter(player: Player): Model?
	-- Look for a character template with AnimSaves folder (custom animated character)
	local template = nil
	print("[RoundSystem] Looking for custom character in CharactersFolder...")
	for _, child in ipairs(CharactersFolder:GetChildren()) do
		print("[RoundSystem] Found:", child.Name, "HasAnimSaves:", child:FindFirstChild("AnimSaves") ~= nil)
		if child:IsA("Model") and child:FindFirstChild("AnimSaves") then
			template = child
			print("[RoundSystem] Selected template:", child.Name)
			break
		end
	end

	if not template then
		-- No custom character found, use default Roblox character
		print("[RoundSystem] No custom character with AnimSaves found, using default")
		if not player.Character then
			player:LoadCharacter()
			task.wait(0.5)
		end
		return player.Character
	end

	-- Clone the custom character
	local character = template:Clone()
	character.Name = player.Name
	print("[RoundSystem] Cloned character for", player.Name, "HasAnimSaves:", character:FindFirstChild("AnimSaves") ~= nil)

	-- Set up Humanoid
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- Hide name overhead

		-- Responsive movement settings (no ice physics)
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 0 -- No jumping in game
		humanoid.JumpHeight = 0
		humanoid.HipHeight = 2 -- Adjust based on character model
		humanoid.MaxSlopeAngle = 89 -- Can walk on steep slopes
	end

	-- Ensure HumanoidRootPart exists and is set as PrimaryPart
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.Anchored = false
		character.PrimaryPart = hrp
	end

	-- Unanchor all parts and set physics properties
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanTouch = true -- Enable touch detection for powerups

			-- Set high friction to prevent ice sliding
			local physProperties = PhysicalProperties.new(
				0.7,  -- Density
				2.0,  -- Friction (high = no sliding)
				0.0,  -- Elasticity (no bounce)
				1.0,  -- FrictionWeight
				0.0   -- ElasticityWeight
			)
			part.CustomPhysicalProperties = physProperties

			-- Only HumanoidRootPart and Torso should collide with walls
			if part.Name ~= "HumanoidRootPart" and part.Name ~= "Torso" then
				part.CanCollide = false
			end
		end
	end

	-- Parent to Workspace and assign to player
	character.Parent = Workspace
	player.Character = character

	-- Animations are handled client-side by CharacterAnimator.client.lua

	return character
end

function RoundSystem.OnPlayerDeath(player: Player)
	local playerData = GameState.players[player.UserId]
	if not playerData then return end

	if not playerData.isAlive then return end -- Already dead

	local eliminated = GameState.TakeDamage(playerData)

	if eliminated then
		playerData.isAlive = false
		PlayerDied:FireAllClients(player.UserId)

		-- Check if round should end
		RoundSystem.CheckRoundEnd()
	else
		-- Player took damage but not eliminated
		SyncPlayerData:FireClient(player, playerData)
	end
end

function RoundSystem.DamagePlayer(player: Player)
	local playerData = GameState.players[player.UserId]
	if not playerData or not playerData.isAlive then return end

	-- Check invincibility
	-- (would need to track last hit time, simplified for now)

	local eliminated = GameState.TakeDamage(playerData)
	SyncPlayerData:FireClient(player, playerData)

	if eliminated then
		PlayerDied:FireAllClients(player.UserId)

		-- Kill the character
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChild("Humanoid")
			if humanoid then
				humanoid.Health = 0
			end
		end

		RoundSystem.CheckRoundEnd()
	end
end

function RoundSystem.CheckRoundEnd()
	if GameState.currentState ~= Constants.STATES.PLAYING then return end

	local alivePlayers = GameState.GetAlivePlayers()
	local totalPlayers = #Players:GetPlayers()

	-- In single player testing mode, only end if player dies
	if totalPlayers == 1 then
		if #alivePlayers == 0 then
			currentWinner = nil
			RoundSystem.EndRound()
		end
		return
	end

	if #alivePlayers <= 1 then
		-- Round over
		if #alivePlayers == 1 then
			-- Find the winning player
			local winnerData = alivePlayers[1]
			for _, player in ipairs(Players:GetPlayers()) do
				if player.UserId == winnerData.userId then
					currentWinner = player
					break
				end
			end
		else
			currentWinner = nil -- Draw
		end

		RoundSystem.EndRound()
	end
end

function RoundSystem.EndRound()
	RoundSystem.SetState(Constants.STATES.ROUND_END)

	-- Broadcast winner
	RoundStateChanged:FireAllClients("Winner", {
		winner = currentWinner and currentWinner.Name or "Nobody",
		winnerId = currentWinner and currentWinner.UserId or 0,
	})
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

function RoundSystem.GameLoop()
	while true do
		-- LOBBY STATE
		RoundSystem.SetState(Constants.STATES.LOBBY)
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
		while lobbyTimer > 0 and GameState.GetPlayerCount() < Constants.MAX_PLAYERS do
			roundTimer = lobbyTimer
			RoundStateChanged:FireAllClients("Timer", {timer = lobbyTimer})
			task.wait(1)
			lobbyTimer = lobbyTimer - 1

			-- Start early if enough players
			if GameState.GetPlayerCount() >= Constants.MIN_PLAYERS and lobbyTimer <= 15 then
				break
			end
		end

		-- Generate new map (skip character select)
		MapGenerator.GenerateMap()

		-- COUNTDOWN STATE
		RoundSystem.SetState(Constants.STATES.COUNTDOWN)
		RoundSystem.SpawnPlayersInArena()

		for i = 3, 0, -1 do
			roundTimer = i
			RoundStateChanged:FireAllClients("Countdown", {number = i})
			task.wait(1)
		end
		RoundStateChanged:FireAllClients("Countdown", {number = -1, text = "GO!"})
		task.wait(0.5)

		-- PLAYING STATE
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

			RoundSystem.EndRound()
		end

		-- ROUND END STATE - Winners Podium
		RoundSystem.SetState(Constants.STATES.ROUND_END)

		-- Calculate results
		roundResults = RoundSystem.CalculateResults()

		-- Broadcast results to clients
		RoundStateChanged:FireAllClients("RoundResults", {
			results = roundResults,
			winner = currentWinner and currentWinner.Name or "Nobody",
		})

		-- Clean up arena
		BombService.ClearAllBombs()
		PowerUpService.ClearAllPowerUps()

		-- Respawn all players and teleport top 3 to podium
		for _, player in ipairs(Players:GetPlayers()) do
			player:LoadCharacter()
			task.wait(0.2)
		end
		task.wait(0.5)

		-- Teleport top 3 to podium
		RoundSystem.TeleportToPodium(roundResults)

		-- Winners stage duration (show emotes/stickers)
		for i = 8, 0, -1 do
			roundTimer = i
			RoundStateChanged:FireAllClients("Timer", {timer = i, stage = "winners"})
			task.wait(1)
		end

		-- Disable confetti
		MapGenerator.SetConfettiEnabled(false)

		-- INTERMISSION STATE
		RoundSystem.SetState(Constants.STATES.INTERMISSION)

		-- Respawn players in lobby
		for _, player in ipairs(Players:GetPlayers()) do
			player:LoadCharacter()
			task.wait(0.1)
			RoundSystem.SpawnPlayerInLobby(player)
		end

		for i = Constants.INTERMISSION_TIME, 0, -1 do
			roundTimer = i
			RoundStateChanged:FireAllClients("Timer", {timer = i})
			task.wait(1)
		end
	end
end

return RoundSystem
