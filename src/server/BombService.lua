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

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlaceBomb = Remotes:WaitForChild("PlaceBomb")
local SyncPlayerData = Remotes:WaitForChild("SyncPlayerData")

local BombService = {}

-- Module references
local RoundSystem
local PowerUpService
local MapGenerator

-- VFX template
local VFXFolder = ReplicatedStorage:FindFirstChild("VFX")
local ParticleTemplate = VFXFolder and VFXFolder:FindFirstChild("ParticleTemplate")

if not ParticleTemplate then
	warn("[BombService] ParticleTemplate not found at ReplicatedStorage.VFX.ParticleTemplate!")
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
local DropSound = SoundVFXFolder and SoundVFXFolder:FindFirstChild("Drop")

-- Colors
local DANGER_COLOR = Color3.fromRGB(255, 140, 50) -- Orange danger floor
local NORMAL_FLOOR_COLOR = Color3.fromRGB(76, 175, 80) -- Normal green floor (from Canvas)

-- Active bombs tracking
local activeBombs = {} :: {[string]: {model: Model, gridX: number, gridY: number, ownerId: number, range: number, dangerTiles: {Part}}}
local bombPool = {} :: {Model}
local dangerTilePool = {} :: {Part}

-- Create bomb model template
local function CreateBombModel(): Model
	local bomb = Instance.new("Model")
	bomb.Name = "Bomb"

	-- Main sphere
	local sphere = Instance.new("Part")
	sphere.Name = "Sphere"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(Constants.BOMB_SIZE, Constants.BOMB_SIZE, Constants.BOMB_SIZE)
	sphere.Color = Constants.COLORS.BOMB
	sphere.Material = Enum.Material.SmoothPlastic
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.Parent = bomb

	-- Fuse
	local fuse = Instance.new("Part")
	fuse.Name = "Fuse"
	fuse.Shape = Enum.PartType.Cylinder
	fuse.Size = Vector3.new(0.3, 0.5, 0.3)
	fuse.Color = Color3.fromRGB(80, 80, 80)
	fuse.Material = Enum.Material.SmoothPlastic
	fuse.Anchored = true
	fuse.CanCollide = false
	fuse.CFrame = sphere.CFrame * CFrame.new(0, Constants.BOMB_SIZE / 2 + 0.15, 0) * CFrame.Angles(0, 0, math.rad(90))
	fuse.Parent = bomb

	-- Point light for fuse glow
	local light = Instance.new("PointLight")
	light.Name = "FuseLight"
	light.Color = Color3.fromRGB(255, 165, 0)
	light.Brightness = 2
	light.Range = 4
	light.Parent = fuse

	bomb.PrimaryPart = sphere
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

	print("[BombService] Initialized with " .. #bombPool .. " bombs and " .. #dangerTilePool .. " danger tiles")
end

-- Get a bomb from pool or create new
local function GetBombFromPool(): Model
	if #bombPool > 0 then
		return table.remove(bombPool) :: Model
	end
	return CreateBombModel()
end

-- Return bomb to pool
local function ReturnBombToPool(bomb: Model)
	bomb.Parent = ReplicatedStorage
	table.insert(bombPool, bomb)
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

	local arenaFolder = Workspace:FindFirstChild("Arena")
	if not arenaFolder then return end

	local worldPos = MapData.GridToWorld(gridX, gridY)

	-- Play drop sound immediately
	if DropSound then
		local soundPart = Instance.new("Part")
		soundPart.Anchored = true
		soundPart.CanCollide = false
		soundPart.Transparency = 1
		soundPart.Size = Vector3.new(1, 1, 1)
		soundPart.Position = worldPos + Vector3.new(0, 1, 0)
		soundPart.Parent = arenaFolder

		local sound = DropSound:Clone()
		sound.Parent = soundPart
		sound:Play()
		Debris:AddItem(soundPart, sound.TimeLength + 0.5)
	end

	-- Get bomb from pool
	local bomb = GetBombFromPool()

	-- Position bomb
	local sphere = bomb:FindFirstChild("Sphere") :: Part
	if sphere then
		sphere.Position = worldPos + Vector3.new(0, Constants.BOMB_SIZE / 2 + 0.1, 0)

		-- Update fuse position
		local fuse = bomb:FindFirstChild("Fuse") :: Part
		if fuse then
			fuse.CFrame = sphere.CFrame * CFrame.new(0, Constants.BOMB_SIZE / 2 + 0.15, 0) * CFrame.Angles(0, 0, math.rad(90))
		end
	end

	bomb.Parent = arenaFolder

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
	}

	-- Update player bomb count
	playerData.activeBombs = playerData.activeBombs + 1
	SyncPlayerData:FireClient(player, playerData)

	-- Bobbing animation
	if sphere then
		local bobTween = TweenService:Create(sphere, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Position = sphere.Position + Vector3.new(0, 0.15, 0)
		})
		bobTween:Play()
	end

	-- Fuse flicker
	local light = bomb:FindFirstChild("Fuse") and bomb.Fuse:FindFirstChild("FuseLight")
	if light then
		task.spawn(function()
			while bomb.Parent == arenaFolder do
				light.Brightness = math.random(1, 3)
				task.wait(0.1)
			end
		end)
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

	-- Spawn VFX on ALL tiles simultaneously
	if ParticleTemplate then
		for _, tile in ipairs(affectedTiles) do
			local worldPos = MapData.GridToWorld(tile.x, tile.y)

			local vfx = ParticleTemplate:Clone()
			vfx.Position = worldPos + Vector3.new(0, 1, 0)
			vfx.Anchored = true
			vfx.CanCollide = false
			vfx.Transparency = 1
			vfx.Parent = arenaFolder

			-- Enable all particle emitters
			for _, emitter in ipairs(vfx:GetDescendants()) do
				if emitter:IsA("ParticleEmitter") then
					emitter.Enabled = true
				end
			end

			-- Disable after 0.3s, destroy after 1.5s
			task.delay(0.3, function()
				if vfx and vfx.Parent then
					for _, emitter in ipairs(vfx:GetDescendants()) do
						if emitter:IsA("ParticleEmitter") then
							emitter.Enabled = false
						end
					end
				end
			end)

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
						break
					end
				end
			end
		end
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
				-- Award kill to bomb owner
				if ownerId ~= player.UserId then
					local ownerData = GameState.players[ownerId]
					if ownerData then
						ownerData.kills = ownerData.kills + 1
					end
				end

				RoundSystem.DamagePlayer(player)
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
