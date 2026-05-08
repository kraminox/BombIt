--!strict
-- BombService.lua
-- Handles bomb placement, explosions, and chain reactions

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapData = require(Shared:WaitForChild("MapData"))
local BombSkins = require(Shared:WaitForChild("BombSkins"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlaceBomb = Remotes:WaitForChild("PlaceBomb")
local SyncPlayerData = Remotes:WaitForChild("SyncPlayerData")

local BombService = {}

-- Module references
local RoundSystem
local PowerUpService
local MapGenerator
local InventoryService

-- VFX folder (explosion templates stored here)
local AssetsFolder = ReplicatedStorage:FindFirstChild("Assets")
local VFXFolder = AssetsFolder and AssetsFolder:FindFirstChild("VFX") or ReplicatedStorage:FindFirstChild("VFX")

-- Fallback: old ParticleTemplate for safety
local ParticleTemplate = VFXFolder and VFXFolder:FindFirstChild("ParticleTemplate")
-- Default explosion model
local DefaultExplosion = VFXFolder and VFXFolder:FindFirstChild("Default Red Explosion")

if not VFXFolder then
	warn("[BombService] VFX folder not found in ReplicatedStorage!")
end

-- Warning indicator template
local AssetsFolder = ReplicatedStorage:FindFirstChild("Assets")
local MiscFolder = AssetsFolder and AssetsFolder:FindFirstChild("Misc")
local WarningTemplate = MiscFolder and MiscFolder:FindFirstChild("Warning")

if not WarningTemplate then
	warn("[BombService] Warning template not found at ReplicatedStorage.Assets.Misc.Warning!")
end

-- Sound effects
local SoundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
local SoundVFXFolder = SoundsFolder and SoundsFolder:FindFirstChild("VFX")
local ExplosionSound = SoundVFXFolder and SoundVFXFolder:FindFirstChild("Explosion")

-- Colors
local DANGER_COLOR = Color3.fromRGB(255, 140, 50) -- Orange danger floor
local NORMAL_FLOOR_COLOR = Color3.fromRGB(76, 175, 80) -- Normal green floor (from Canvas)

-- Per-player bomb placement cooldown (prevents spam)
local lastBombTime = {} :: {[number]: number}

-- Active bombs tracking
local activeBombs = {} :: {[string]: {model: Model, gridX: number, gridY: number, ownerId: number, range: number, dangerTiles: {Part}}}
local bombPool = {} :: {Model}
local dangerTilePool = {} :: {Part}

-- Bomb model template (loaded from Assets/Bombs/Default Bomb)
local BombTemplate: Model? = nil

-- Load bomb template from Assets
local function LoadBombTemplate()
	local Assets = ReplicatedStorage:WaitForChild("Assets")
	local Bombs = Assets:WaitForChild("Bombs")
	local defaultBomb = Bombs:WaitForChild("Default Bomb", 10)

	if defaultBomb and defaultBomb:IsA("Model") then
		BombTemplate = defaultBomb
		print("[BombService] Loaded bomb template: Default Bomb")
	else
		warn("[BombService] Default Bomb model not found in Assets/Bombs!")
	end
end

-- Get the bomb model template for a specific player's equipped skin.
-- Always returns the correct template Model (not a clone) for the player's equipped skin.
local function GetBombTemplateForPlayer(player: Player): Model?
	if not InventoryService then return BombTemplate end
	local skinId = InventoryService.GetEquippedBombSkinId(player)
	if not skinId or skinId == "" or skinId == "default_bomb" then return BombTemplate end

	local skinData = BombSkins.GetSkinById(skinId)
	if not skinData then return BombTemplate end

	local skinModel = BombSkins.GetSkinModel(skinData)
	if skinModel then return skinModel end

	return BombTemplate
end

-- Create bomb model by cloning the template
local function CreateBombModel(): Model
	if BombTemplate then
		local bomb = BombTemplate:Clone()
		bomb.Name = "Bomb"

		-- Ensure all parts are anchored and non-collidable for placed bombs
		for _, part in ipairs(bomb:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
			end
		end

		-- Add FuseLight to each Fuse part if not already present
		for _, child in ipairs(bomb:GetChildren()) do
			if child.Name == "Fuse" and child:IsA("BasePart") then
				if not child:FindFirstChild("FuseLight") then
					local light = Instance.new("PointLight")
					light.Name = "FuseLight"
					light.Color = Color3.fromRGB(255, 165, 0)
					light.Brightness = 2
					light.Range = 4
					light.Parent = child
				end
			end
		end

		CollectionService:AddTag(bomb, "Bomb")
		return bomb
	end

	-- Fallback: create a basic bomb programmatically
	local bomb = Instance.new("Model")
	bomb.Name = "Bomb"

	local bombPart = Instance.new("Part")
	bombPart.Name = "Bomb"
	bombPart.Shape = Enum.PartType.Ball
	bombPart.Size = Vector3.new(Constants.BOMB_SIZE, Constants.BOMB_SIZE, Constants.BOMB_SIZE)
	bombPart.Color = Constants.COLORS.BOMB
	bombPart.Material = Enum.Material.SmoothPlastic
	bombPart.Anchored = true
	bombPart.CanCollide = false
	bombPart.Parent = bomb

	local fuse = Instance.new("Part")
	fuse.Name = "Fuse"
	fuse.Shape = Enum.PartType.Cylinder
	fuse.Size = Vector3.new(0.3, 0.5, 0.3)
	fuse.Color = Color3.fromRGB(80, 80, 80)
	fuse.Material = Enum.Material.SmoothPlastic
	fuse.Anchored = true
	fuse.CanCollide = false
	fuse.CFrame = bombPart.CFrame * CFrame.new(0, Constants.BOMB_SIZE / 2 + 0.15, 0) * CFrame.Angles(0, 0, math.rad(90))
	fuse.Parent = bomb

	local light = Instance.new("PointLight")
	light.Name = "FuseLight"
	light.Color = Color3.fromRGB(255, 165, 0)
	light.Brightness = 2
	light.Range = 4
	light.Parent = fuse

	bomb.PrimaryPart = bombPart
	CollectionService:AddTag(bomb, "Bomb")

	return bomb
end

-- Create danger tile indicator using Warning template
local function CreateDangerTile(): Part
	if WarningTemplate then
		local warning = WarningTemplate:Clone()
		warning.Name = "DangerTile"
		warning.Anchored = true
		warning.CanCollide = false
		warning.CastShadow = false
		-- Set decal transparency to 1 (invisible) initially
		local decal = warning:FindFirstChild("Decal")
		if decal and decal:IsA("Decal") then
			decal.Transparency = 1
		end
		return warning
	end

	-- Fallback to basic part
	local part = Instance.new("Part")
	part.Name = "DangerTile"
	part.Size = Vector3.new(Constants.TILE_SIZE - 0.1, 0.15, Constants.TILE_SIZE - 0.1)
	part.Color = DANGER_COLOR
	part.Material = Enum.Material.Neon
	part.Transparency = 0.5
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	return part
end

-- Danger tiles folder (for client-side visibility control)
local dangerTilesFolder: Folder? = nil

-- Get or create the danger tiles folder
local function GetDangerTilesFolder(): Folder
	if dangerTilesFolder and dangerTilesFolder.Parent then
		return dangerTilesFolder
	end

	local arenaFolder = Workspace:FindFirstChild("Arena")
	if arenaFolder then
		dangerTilesFolder = arenaFolder:FindFirstChild("DangerTiles") :: Folder?
		if not dangerTilesFolder then
			dangerTilesFolder = Instance.new("Folder")
			dangerTilesFolder.Name = "DangerTiles"
			dangerTilesFolder.Parent = arenaFolder
		end
	else
		-- Fallback to Workspace
		dangerTilesFolder = Workspace:FindFirstChild("DangerTiles") :: Folder?
		if not dangerTilesFolder then
			dangerTilesFolder = Instance.new("Folder")
			dangerTilesFolder.Name = "DangerTiles"
			dangerTilesFolder.Parent = Workspace
		end
	end

	return dangerTilesFolder :: Folder
end

-- Initialize bomb and explosion pools
function BombService.Initialize()
	local ServerFolder = script.Parent
	RoundSystem = require(ServerFolder:WaitForChild("RoundSystem"))
	PowerUpService = require(ServerFolder:WaitForChild("PowerUpService"))
	MapGenerator = require(ServerFolder:WaitForChild("MapGenerator"))
	InventoryService = require(ServerFolder:WaitForChild("InventoryService"))

	-- Load bomb template from Assets
	LoadBombTemplate()

	-- Create bomb pool
	for _ = 1, Constants.MAX_BOMB_POOL do
		local bomb = CreateBombModel()
		bomb.Parent = ReplicatedStorage
		table.insert(bombPool, bomb)
	end

	-- Create danger tile pool
	for _ = 1, Constants.MAX_EXPLOSION_POOL do
		local dangerTile = CreateDangerTile()
		dangerTile.Parent = ReplicatedStorage
		table.insert(dangerTilePool, dangerTile)
	end

	-- Handle bomb placement requests
	PlaceBomb.OnServerEvent:Connect(function(player: Player)
		BombService.TryPlaceBomb(player)
	end)

	-- Clean up per-player cooldown data when player leaves
	Players.PlayerRemoving:Connect(function(player: Player)
		lastBombTime[player.UserId] = nil
	end)

	print("[BombService] Initialized with " .. #bombPool .. " bombs and " .. #dangerTilePool .. " danger tiles")
end

-- Create a bomb model from a specific template (for player skins)
local function CreateBombFromTemplate(template: Model): Model
	local bomb = template:Clone()
	bomb.Name = "Bomb"

	for _, part in ipairs(bomb:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end

	for _, child in ipairs(bomb:GetChildren()) do
		if child.Name == "Fuse" and child:IsA("BasePart") then
			if not child:FindFirstChild("FuseLight") then
				local light = Instance.new("PointLight")
				light.Name = "FuseLight"
				light.Color = Color3.fromRGB(255, 165, 0)
				light.Brightness = 2
				light.Range = 4
				light.Parent = child
			end
		end
	end

	CollectionService:AddTag(bomb, "Bomb")
	return bomb
end

-- Get a default bomb from pool or create new (pool only contains default bombs)
local function GetBombFromPool(): Model
	if #bombPool > 0 then
		return table.remove(bombPool) :: Model
	end
	return CreateBombModel()
end

-- Return bomb to pool. Skinned bombs are destroyed and replaced with a fresh
-- default so the pool never becomes polluted with non-default models.
local function ReturnBombToPool(bomb: Model)
	-- Check if this bomb was a custom skin (tagged during placement)
	if CollectionService:HasTag(bomb, "SkinnedBomb") then
		-- Destroy the skinned bomb; don't put it back in the pool
		bomb:Destroy()
		-- Replenish the pool with a fresh default bomb so pool size stays stable
		local fresh = CreateBombModel()
		fresh.Parent = ReplicatedStorage
		table.insert(bombPool, fresh)
	else
		bomb.Parent = ReplicatedStorage
		table.insert(bombPool, bomb)
	end
end

-- Get danger tile from pool
local function GetDangerTileFromPool(): Part
	if #dangerTilePool > 0 then
		return table.remove(dangerTilePool) :: Part
	end
	return CreateDangerTile()
end

-- Return danger tile to pool
local function ReturnDangerTileToPool(part: Part)
	-- Reset decal transparency if using Warning template
	local decal = part:FindFirstChild("Decal")
	if decal and decal:IsA("Decal") then
		decal.Transparency = 1
	else
		-- Fallback for basic parts
		part.Transparency = 0.5
		part.Color = DANGER_COLOR
	end
	part.Parent = ReplicatedStorage
	table.insert(dangerTilePool, part)
end

-- Generate unique bomb key
local function GetBombKey(gridX: number, gridY: number): string
	return gridX .. "_" .. gridY
end

function BombService.TryPlaceBomb(player: Player)
	-- Per-player cooldown to prevent bomb spam
	if lastBombTime[player.UserId] and (tick() - lastBombTime[player.UserId]) < 0.3 then return end

	-- Check game state
	if GameState.currentState ~= Constants.STATES.PLAYING then return end

	-- Get player data
	local playerData = GameState.players[player.UserId]
	if not playerData or not playerData.isAlive then return end

	-- Check bomb count
	if playerData.activeBombs >= playerData.bombCount then return end

	-- Get player position
	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Get grid position
	local gridX, gridY = MapData.WorldToGrid(hrp.Position)

	-- Check if tile already has a bomb
	if MapData.HasBomb(gridX, gridY) then return end

	-- Check if tile is walkable (not a wall)
	if not MapData.IsWalkable(gridX, gridY) then return end

	-- Place the bomb
	BombService.PlaceBomb(player, gridX, gridY, playerData.bombRange)
end

function BombService.PlaceBomb(player: Player, gridX: number, gridY: number, range: number)
	local playerData = GameState.players[player.UserId]
	if not playerData then return end

	-- Atomically increment active bombs BEFORE any yields to prevent race conditions
	playerData.activeBombs = playerData.activeBombs + 1

	-- Record cooldown timestamp
	lastBombTime[player.UserId] = tick()

	local arenaFolder = Workspace:FindFirstChild("Arena")
	if not arenaFolder then
		playerData.activeBombs = playerData.activeBombs - 1
		return
	end

	local worldPos = MapData.GridToWorld(gridX, gridY)

	-- Drop sound is played client-side for instant feedback (see LocalPlayer.client.lua)

	-- Get bomb model: always clone fresh from the player's equipped skin template.
	-- This ensures every bomb placed visually matches the player's current skin,
	-- regardless of what the pool contains.
	local playerTemplate = GetBombTemplateForPlayer(player)
	local bomb: Model
	if playerTemplate and playerTemplate ~= BombTemplate then
		-- Player has a non-default skin equipped: clone fresh from skin template
		bomb = CreateBombFromTemplate(playerTemplate)
		-- Tag so ReturnBombToPool knows to destroy instead of pooling
		CollectionService:AddTag(bomb, "SkinnedBomb")
	else
		-- Default skin: pull from pool (pool only contains default bombs)
		bomb = GetBombFromPool()
	end

	-- Position bomb using PrimaryPart
	local bombPart = bomb.PrimaryPart :: BasePart?
	if not bombPart then
		bombPart = bomb:FindFirstChild("Bomb") :: BasePart?
	end
	if bombPart then
		local targetPos = worldPos + Vector3.new(0, Constants.BOMB_SIZE / 2 + 0.1, 0)
		bomb:PivotTo(CFrame.new(targetPos))
	end

	bomb.Parent = arenaFolder

	-- Add collision wall so the bomb blocks player movement (like original Bomberman)
	-- Positioned at TILE_SIZE/2 above grid (same as crate collision boxes)
	-- Non-collidable until the placing player steps off the tile, then solid for everyone
	local collisionWall = Instance.new("Part")
	collisionWall.Name = "BombCollision"
	collisionWall.Size = Vector3.new(Constants.TILE_SIZE, Constants.TILE_SIZE * 2, Constants.TILE_SIZE)
	collisionWall.CFrame = CFrame.new(worldPos + Vector3.new(0, Constants.TILE_SIZE, 0))
	collisionWall.Transparency = 1
	collisionWall.Anchored = true
	collisionWall.CanCollide = false
	collisionWall.CastShadow = false
	collisionWall.Parent = arenaFolder

	task.spawn(function()
		-- Wait until the placing player leaves this tile
		while collisionWall and collisionWall.Parent do
			local character = player.Character
			if not character then break end
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if not hrp then break end
			local pX, pY = MapData.WorldToGrid(hrp.Position)
			if pX ~= gridX or pY ~= gridY then
				break
			end
			task.wait()
		end
		if collisionWall and collisionWall.Parent then
			collisionWall.CanCollide = true
		end
	end)

	-- Update grid
	MapData.SetBomb(gridX, gridY, true)

	-- Get affected tiles and show danger indicators
	local affectedTiles = MapData.GetExplosionTiles(gridX, gridY, range)
	local dangerTiles = {}
	local dangerFolder = GetDangerTilesFolder()

	for _, tile in ipairs(affectedTiles) do
		local tileCFrame = MapData.GridToCFrame(tile.x, tile.y)
		local dangerTile = GetDangerTileFromPool()
		dangerTile.CFrame = tileCFrame * CFrame.new(0, 0.1, 0)
		dangerTile.Parent = dangerFolder

		-- Get decal for animation
		local decal = dangerTile:FindFirstChild("Decal")

		-- Blinking animation (fade decal in and out)
		task.spawn(function()
			while dangerTile and dangerTile.Parent == dangerFolder do
				if decal and decal:IsA("Decal") then
					-- Fade in
					TweenService:Create(decal, TweenInfo.new(0.2), {Transparency = 0.2}):Play()
					task.wait(0.25)
					if not dangerTile or dangerTile.Parent ~= dangerFolder then break end
					-- Fade out
					TweenService:Create(decal, TweenInfo.new(0.2), {Transparency = 0.7}):Play()
					task.wait(0.25)
				else
					-- Fallback for basic parts
					TweenService:Create(dangerTile, TweenInfo.new(0.2), {Transparency = 0.2}):Play()
					task.wait(0.25)
					if not dangerTile or dangerTile.Parent ~= dangerFolder then break end
					TweenService:Create(dangerTile, TweenInfo.new(0.2), {Transparency = 0.6}):Play()
					task.wait(0.25)
				end
			end
		end)

		table.insert(dangerTiles, dangerTile)
	end

	-- Track bomb
	local bombKey = GetBombKey(gridX, gridY)
	activeBombs[bombKey] = {
		model = bomb,
		gridX = gridX,
		gridY = gridY,
		ownerId = player.UserId,
		range = range,
		dangerTiles = dangerTiles,
		collisionWall = collisionWall,
	}

	-- Update player stats (activeBombs already incremented atomically at top of PlaceBomb)
	playerData.bombs_placed = (playerData.bombs_placed or 0) + 1
	SyncPlayerData:FireClient(player, playerData)

	-- Bobbing animation — move entire model with PivotTo so all parts stay in sync
	local baseCFrame = bomb:GetPivot()
	local bobStart = tick()
	task.spawn(function()
		while bomb and bomb.Parent == arenaFolder do
			local elapsed = tick() - bobStart
			local offset = math.sin(elapsed * math.pi / 0.4) * 0.15
			bomb:PivotTo(baseCFrame + Vector3.new(0, offset, 0))
			task.wait()
		end
	end)

	-- Fuse flicker on all fuse parts
	for _, child in ipairs(bomb:GetChildren()) do
		if child.Name == "Fuse" and child:IsA("BasePart") then
			local fuseLight = child:FindFirstChild("FuseLight")
			if fuseLight then
				task.spawn(function()
					while bomb.Parent == arenaFolder do
						fuseLight.Brightness = math.random(1, 3)
						task.wait(0.1)
					end
				end)
			end
		end
	end

	-- Schedule explosion
	task.delay(Constants.BOMB_FUSE_TIME, function()
		if activeBombs[bombKey] then
			BombService.ExplodeBomb(bombKey)
		end
	end)
end

function BombService.ExplodeBomb(bombKey: string)
	local bombData = activeBombs[bombKey]
	if not bombData then return end

	local gridX = bombData.gridX
	local gridY = bombData.gridY
	local range = bombData.range
	local ownerId = bombData.ownerId
	local dangerTiles = bombData.dangerTiles or {}

	-- Remove from tracking
	activeBombs[bombKey] = nil
	MapData.SetBomb(gridX, gridY, false)

	-- Destroy collision wall
	if bombData.collisionWall then
		bombData.collisionWall:Destroy()
	end

	-- Return bomb to pool
	ReturnBombToPool(bombData.model)

	-- Update player bomb count
	local ownerData = GameState.players[ownerId]
	if ownerData then
		ownerData.activeBombs = math.max(0, ownerData.activeBombs - 1)
		for _, player in ipairs(Players:GetPlayers()) do
			if player.UserId == ownerId then
				SyncPlayerData:FireClient(player, ownerData)
				break
			end
		end
	end

	-- Get affected tiles
	local affectedTiles = MapData.GetExplosionTiles(gridX, gridY, range)
	local arenaFolder = Workspace:FindFirstChild("Arena")

	-- Play explosion sound at bomb position
	if ExplosionSound and arenaFolder then
		local sound = ExplosionSound:Clone()
		local soundPart = Instance.new("Part")
		soundPart.Anchored = true
		soundPart.CanCollide = false
		soundPart.Transparency = 1
		soundPart.Size = Vector3.new(1, 1, 1)
		soundPart.Position = MapData.GridToWorld(gridX, gridY) + Vector3.new(0, 1, 0)
		soundPart.Parent = arenaFolder
		sound.Parent = soundPart
		sound:Play()
		Debris:AddItem(soundPart, sound.TimeLength + 0.5)
	end

	-- Get the player's equipped explosion VFX template
	local explosionTemplate = nil
	if InventoryService and VFXFolder then
		local ownerPlayer = Players:GetPlayerByUserId(ownerId)
		if ownerPlayer then
			local modelName = InventoryService.GetEquippedExplosionModel(ownerPlayer)
			explosionTemplate = VFXFolder:FindFirstChild(modelName)
		end
	end
	-- Fallback chain: equipped -> default red -> old ParticleTemplate
	if not explosionTemplate then
		explosionTemplate = DefaultExplosion or ParticleTemplate
	end

	-- Spawn VFX on ALL tiles simultaneously
	if explosionTemplate and arenaFolder then
		for _, tile in ipairs(affectedTiles) do
			local worldPos = MapData.GridToWorld(tile.x, tile.y)

			local vfx = explosionTemplate:Clone()

			-- Handle both Part-based and Model-based templates
			if vfx:IsA("BasePart") then
				vfx.Position = worldPos + Vector3.new(0, 1, 0)
				vfx.Anchored = true
				vfx.CanCollide = false
				vfx.Transparency = 1
			elseif vfx:IsA("Model") then
				-- Model: move via PrimaryPart or PivotTo
				if vfx.PrimaryPart then
					vfx.PrimaryPart.Anchored = true
					vfx.PrimaryPart.CanCollide = false
					vfx:PivotTo(CFrame.new(worldPos + Vector3.new(0, 1, 0)))
				else
					vfx:PivotTo(CFrame.new(worldPos + Vector3.new(0, 1, 0)))
				end
			end

			vfx.Parent = arenaFolder

			-- Tag for client-side particle emission (server :Emit() doesn't replicate)
			CollectionService:AddTag(vfx, "ExplosionVFX")

			Debris:AddItem(vfx, 1.5)
		end
	end

	-- Fade out danger tiles and return to pool
	for _, dangerTile in ipairs(dangerTiles) do
		if dangerTile and dangerTile.Parent then
			local decal = dangerTile:FindFirstChild("Decal")
			if decal and decal:IsA("Decal") then
				-- Fade out decal
				local tween = TweenService:Create(decal, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
					Transparency = 1
				})
				tween:Play()
				tween.Completed:Connect(function()
					ReturnDangerTileToPool(dangerTile)
				end)
			else
				-- Fallback for basic parts
				local tween = TweenService:Create(dangerTile, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
					Transparency = 1
				})
				tween:Play()
				tween.Completed:Connect(function()
					ReturnDangerTileToPool(dangerTile)
				end)
			end
		end
	end

	-- Check for hits on all affected tiles
	for _, tile in ipairs(affectedTiles) do
		BombService.ProcessExplosionTile(tile.x, tile.y, ownerId)
	end
end

-- Paint a floor tile to a player's color (Color Battle mode)
function BombService.PaintTile(gridX: number, gridY: number, ownerId: number)
	local arenaFolder = Workspace:FindFirstChild("Arena")
	if not arenaFolder then return end

	-- Get the player's color
	local colorIndex = GameState.colorAssignments[ownerId]
	if not colorIndex then return end
	local colorData = Constants.PLAYER_COLORS[colorIndex]
	if not colorData then return end

	-- Track previous owner for tile count updates
	local previousOwner = MapData.GetTileOwner(gridX, gridY)

	-- Update grid ownership
	MapData.SetTileOwner(gridX, gridY, ownerId)

	-- Update tile counts and character stat values
	local ownerData = GameState.players[ownerId]
	if ownerData then
		ownerData.tilesOwned = MapData.CountTilesOwnedBy(ownerId)
		-- Update character IntValue for nameplate
		for _, p in ipairs(Players:GetPlayers()) do
			if p.UserId == ownerId and p.Character then
				local stats = p.Character:FindFirstChild("PlayerStats")
				if stats then
					local tv = stats:FindFirstChild("TilesOwned")
					if tv then tv.Value = ownerData.tilesOwned end
				end
				break
			end
		end
	end
	if previousOwner ~= 0 and previousOwner ~= ownerId then
		local prevData = GameState.players[previousOwner]
		if prevData then
			prevData.tilesOwned = MapData.CountTilesOwnedBy(previousOwner)
			for _, p in ipairs(Players:GetPlayers()) do
				if p.UserId == previousOwner and p.Character then
					local stats = p.Character:FindFirstChild("PlayerStats")
					if stats then
						local tv = stats:FindFirstChild("TilesOwned")
						if tv then tv.Value = prevData.tilesOwned end
					end
					break
				end
			end
		end
	end

	-- Find and recolor the floor tile
	local tileName = "FloorTile_" .. gridX .. "_" .. gridY
	local tile = arenaFolder:FindFirstChild(tileName)
	if tile then
		local tileColor = colorData.tile
		if tile:IsA("BasePart") then
			tile.Color = tileColor
		elseif tile:IsA("Model") then
			for _, part in ipairs(tile:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Color = tileColor
				end
			end
		end
	end
end

-- Process explosion tile (damage, destruction, chain reactions - NO VFX here)
function BombService.ProcessExplosionTile(gridX: number, gridY: number, ownerId: number)
	local arenaFolder = Workspace:FindFirstChild("Arena")

	-- Check for chain reaction (other bombs)
	local bombKey = GetBombKey(gridX, gridY)
	if activeBombs[bombKey] then
		task.spawn(function()
			task.wait(0.05) -- Small delay for visual effect
			BombService.ExplodeBomb(bombKey)
		end)
	end

	-- Check for soft wall destruction
	if arenaFolder then
		for _, obj in ipairs(CollectionService:GetTagged("SoftWall")) do
			if obj:IsDescendantOf(arenaFolder) then
				-- Get position from Model or BasePart
				local pos: Vector3?
				if obj:IsA("Model") then
					local part = obj:FindFirstChildWhichIsA("BasePart")
					if part then pos = part.Position end
				elseif obj:IsA("BasePart") then
					pos = obj.Position
				end

				if pos then
					local wallX, wallY = MapData.WorldToGrid(pos)
					if wallX == gridX and wallY == gridY then
						MapGenerator.DestroySoftWall(obj, gridX, gridY)
						-- Track demolition for the bomb owner
						local ownerData = GameState.players[ownerId]
						if ownerData then
							ownerData.demolitions = (ownerData.demolitions or 0) + 1
						end
						break
					end
				end
			end
		end
	end

	-- Paint tile in Color Battle mode (only walkable tiles, not walls)
	if GameState.currentMode.paintTiles and MapData.IsWalkable(gridX, gridY) then
		BombService.PaintTile(gridX, gridY, ownerId)
	end

	-- Check for player hits
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if not character then continue end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then continue end

		local playerX, playerY = MapData.WorldToGrid(hrp.Position)
		if playerX == gridX and playerY == gridY then
			-- Player is in explosion
			local playerData = GameState.players[player.UserId]
			if playerData and playerData.isAlive then
				-- Kill credit is handled in RoundSystem.DamagePlayer
				RoundSystem.DamagePlayer(player, ownerId)
			end
		end
	end

	-- Check for powerup destruction (handles both BasePart and Model powerups)
	for _, obj in ipairs(CollectionService:GetTagged("PowerUp")) do
		if obj:IsDescendantOf(arenaFolder) then
			local pos: Vector3?
			if obj:IsA("BasePart") then
				pos = obj.Position
			elseif obj:IsA("Model") then
				local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
				if part then
					pos = part.Position
				end
			end

			if pos then
				local powerX, powerY = MapData.WorldToGrid(pos)
				if powerX == gridX and powerY == gridY then
					obj:Destroy()
				end
			end
		end
	end

	-- Check for coin destruction
	for _, obj in ipairs(CollectionService:GetTagged("Coin")) do
		if obj:IsDescendantOf(arenaFolder) then
			local pos: Vector3?
			if obj:IsA("BasePart") then
				pos = obj.Position
			elseif obj:IsA("Model") then
				local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
				if part then
					pos = part.Position
				end
			end

			if pos then
				local coinX, coinY = MapData.WorldToGrid(pos)
				if coinX == gridX and coinY == gridY then
					obj:Destroy()
				end
			end
		end
	end
end

function BombService.ClearAllBombs()
	for bombKey, bombData in pairs(activeBombs) do
		MapData.SetBomb(bombData.gridX, bombData.gridY, false)
		ReturnBombToPool(bombData.model)

		-- Destroy collision wall
		if bombData.collisionWall then
			bombData.collisionWall:Destroy()
		end

		-- Clean up danger tiles
		if bombData.dangerTiles then
			for _, dangerTile in ipairs(bombData.dangerTiles) do
				if dangerTile and dangerTile.Parent then
					ReturnDangerTileToPool(dangerTile)
				end
			end
		end
	end
	activeBombs = {}

	-- Reset player bomb counts
	for _, playerData in pairs(GameState.players) do
		playerData.activeBombs = 0
	end
end

-- Force explode all bombs (for admin events)
function BombService.ExplodeAllBombs()
	local keysToExplode = {}
	for key, _ in pairs(activeBombs) do
		table.insert(keysToExplode, key)
	end

	for _, key in ipairs(keysToExplode) do
		if activeBombs[key] then
			BombService.ExplodeBomb(key)
		end
	end
end

return BombService
