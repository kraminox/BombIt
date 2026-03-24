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

-- Active bombs tracking
local activeBombs = {} :: {[string]: {model: Model, gridX: number, gridY: number, ownerId: number, range: number}}
local bombPool = {} :: {Model}
local explosionPool = {} :: {Part}

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

-- Create explosion effect part
local function CreateExplosionPart(): Part
	local part = Instance.new("Part")
	part.Name = "Explosion"
	part.Size = Vector3.new(Constants.TILE_SIZE, 0.5, Constants.TILE_SIZE)
	part.Color = Constants.COLORS.EXPLOSION
	part.Material = Enum.Material.Neon
	part.Transparency = 0
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	return part
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

	-- Create explosion pool
	for _ = 1, Constants.MAX_EXPLOSION_POOL do
		local explosion = CreateExplosionPart()
		explosion.Parent = ReplicatedStorage
		table.insert(explosionPool, explosion)
	end

	-- Handle bomb placement requests
	PlaceBomb.OnServerEvent:Connect(function(player: Player)
		BombService.TryPlaceBomb(player)
	end)

	print("[BombService] Initialized with " .. #bombPool .. " bombs and " .. #explosionPool .. " explosion effects")
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

-- Get explosion part from pool
local function GetExplosionFromPool(): Part
	if #explosionPool > 0 then
		return table.remove(explosionPool) :: Part
	end
	return CreateExplosionPart()
end

-- Return explosion part to pool
local function ReturnExplosionToPool(part: Part)
	part.Transparency = 0
	part.Parent = ReplicatedStorage
	table.insert(explosionPool, part)
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

	-- Get bomb from pool
	local bomb = GetBombFromPool()
	local worldPos = MapData.GridToWorld(gridX, gridY)

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

	bomb.Parent = Workspace:FindFirstChild("Arena")

	-- Update grid
	MapData.SetBomb(gridX, gridY, true)

	-- Track bomb
	local bombKey = GetBombKey(gridX, gridY)
	activeBombs[bombKey] = {
		model = bomb,
		gridX = gridX,
		gridY = gridY,
		ownerId = player.UserId,
		range = range,
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
			while bomb.Parent == Workspace:FindFirstChild("Arena") do
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

	-- Create explosion effects and check for hits
	for _, tile in ipairs(affectedTiles) do
		BombService.CreateExplosionAt(tile.x, tile.y, ownerId)
	end

	-- Play explosion sound (clients handle this via CollectionService)
end

function BombService.CreateExplosionAt(gridX: number, gridY: number, ownerId: number)
	local worldPos = MapData.GridToWorld(gridX, gridY)

	-- Create visual effect
	local explosionPart = GetExplosionFromPool()
	explosionPart.Position = worldPos + Vector3.new(0, 0.5, 0)
	explosionPart.Parent = Workspace:FindFirstChild("Arena")

	-- Fade out animation
	local tween = TweenService:Create(explosionPart, TweenInfo.new(Constants.EXPLOSION_DURATION, Enum.EasingStyle.Linear), {
		Transparency = 1
	})
	tween:Play()
	tween.Completed:Connect(function()
		ReturnExplosionToPool(explosionPart)
	end)

	-- Check for chain reaction (other bombs)
	local bombKey = GetBombKey(gridX, gridY)
	if activeBombs[bombKey] then
		task.spawn(function()
			task.wait(0.05) -- Small delay for visual effect
			BombService.ExplodeBomb(bombKey)
		end)
	end

	-- Check for soft wall destruction
	local arenaFolder = Workspace:FindFirstChild("Arena")
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

	-- Check for powerup destruction
	for _, obj in ipairs(CollectionService:GetTagged("PowerUp")) do
		if obj:IsA("BasePart") and obj:IsDescendantOf(arenaFolder) then
			local powerX, powerY = MapData.WorldToGrid(obj.Position)
			if powerX == gridX and powerY == gridY then
				obj:Destroy()
			end
		end
	end
end

function BombService.ClearAllBombs()
	for bombKey, bombData in pairs(activeBombs) do
		MapData.SetBomb(bombData.gridX, bombData.gridY, false)
		ReturnBombToPool(bombData.model)
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
