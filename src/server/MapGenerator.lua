--!strict
-- MapGenerator.lua
-- Generates arena maps, lobby, and character models

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local MapData = require(Shared:WaitForChild("MapData"))

local MapGenerator = {}

-- Module references
local PowerUpService

-- Stored references
local arenaFolder: Folder
local lobbyFolder: Folder
local charactersFolder: Folder
local canvasPart: BasePart?
local gridOrigin: Vector3 = Vector3.zero

-- Model templates (crates, props, floor tiles)
local modelTemplates = {
	SoftCrate = nil :: Model?,
	HardCrate = nil :: Model?,
	LightShade = nil :: Instance?,
	DarkShade = nil :: Instance?,
}

-- Create a smooth low-poly part
local function CreatePart(size: Vector3, position: Vector3, color: Color3, name: string, canCollide: boolean?, meshType: string?): BasePart
	local part: BasePart

	if canCollide == nil then canCollide = true end

	-- Create clean low-poly part
	part = Instance.new("Part")
	part.Size = size
	part.CFrame = CFrame.new(position)
	part.Color = color
	part.Name = name
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = canCollide
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	return part
end

-- Create a crate model (soft or hard)
local function CreateCrate(position: Vector3, name: string, crateType: string): Model?
	local template = crateType == "soft" and modelTemplates.SoftCrate or modelTemplates.HardCrate
	if not template then return nil end

	local crate = template:Clone()
	crate.Name = name

	-- Position the crate
	local primaryPart = crate.PrimaryPart or crate:FindFirstChildWhichIsA("BasePart")
	if primaryPart then
		crate:SetPrimaryPartCFrame(CFrame.new(position))
	else
		-- Move all parts manually
		for _, part in ipairs(crate:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
		-- Set position of first part
		local firstPart = crate:FindFirstChildWhichIsA("BasePart")
		if firstPart then
			local offset = firstPart.Position
			for _, part in ipairs(crate:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Position = position + (part.Position - offset)
				end
			end
		end
	end

	-- Ensure all parts are anchored and have collision
	for _, part in ipairs(crate:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = true
		end
	end

	return crate
end

function MapGenerator.Initialize()
	local ServerFolder = script.Parent
	PowerUpService = require(ServerFolder:WaitForChild("PowerUpService"))

	arenaFolder = Workspace:FindFirstChild("Arena") :: Folder
	lobbyFolder = Workspace:FindFirstChild("Lobby") :: Folder
	charactersFolder = ReplicatedStorage:FindFirstChild("Characters") :: Folder
	canvasPart = Workspace:FindFirstChild("Canvas") :: BasePart?

	if not arenaFolder then
		arenaFolder = Instance.new("Folder")
		arenaFolder.Name = "Arena"
		arenaFolder.Parent = Workspace
	end

	if not lobbyFolder then
		lobbyFolder = Instance.new("Folder")
		lobbyFolder.Name = "Lobby"
		lobbyFolder.Parent = Workspace
	end

	if not charactersFolder then
		charactersFolder = Instance.new("Folder")
		charactersFolder.Name = "Characters"
		charactersFolder.Parent = ReplicatedStorage
	end

	-- Load models from ReplicatedStorage
	modelTemplates.SoftCrate = ReplicatedStorage:FindFirstChild("SoftCrate") :: Model?
	modelTemplates.HardCrate = ReplicatedStorage:FindFirstChild("HardCrate") :: Model?
	modelTemplates.LightShade = ReplicatedStorage:FindFirstChild("LightShade") -- Case sensitive!
	modelTemplates.DarkShade = ReplicatedStorage:FindFirstChild("DarkShade")

	if modelTemplates.SoftCrate then print("[MapGenerator] Found SoftCrate") end
	if modelTemplates.HardCrate then print("[MapGenerator] Found HardCrate") end
	if modelTemplates.LightShade then print("[MapGenerator] Found LightShade") end
	if modelTemplates.DarkShade then print("[MapGenerator] Found DarkShade") end

	-- Calculate grid origin from Canvas part
	if canvasPart then
		local canvasPos = canvasPart.Position
		local canvasSize = canvasPart.Size
		-- Grid origin is bottom-left corner of canvas (on top surface)
		gridOrigin = Vector3.new(
			canvasPos.X - canvasSize.X / 2,
			canvasPos.Y + canvasSize.Y / 2,
			canvasPos.Z - canvasSize.Z / 2
		)
		print("[MapGenerator] Found Canvas at", canvasPos, "Grid origin:", gridOrigin)
	else
		warn("[MapGenerator] Canvas not found in Workspace, using default origin")
		gridOrigin = Vector3.new(-50, 1, -50)
	end

	print("[MapGenerator] Initialized")
end

-- Get grid origin (calculated from Canvas)
function MapGenerator.GetGridOrigin(): Vector3
	return gridOrigin
end

function MapGenerator.BuildLobby()
	-- User has custom lobby in Workspace, no need to build
	print("[MapGenerator] Using existing lobby")
end

function MapGenerator.BuildCharacters()
	-- Clear existing placeholder characters, but preserve custom characters (with AnimSaves)
	for _, child in ipairs(charactersFolder:GetChildren()) do
		if child:IsA("Model") and not child:FindFirstChild("AnimSaves") then
			child:Destroy()
		end
	end

	for _, charData in ipairs(Constants.CHARACTERS) do
		-- Only create if not already exists
		if not charactersFolder:FindFirstChild(charData.name) then
			local character = MapGenerator.CreateCharacterModel(charData)
			character.Name = charData.name
			character.Parent = charactersFolder
		end
	end

	print("[MapGenerator] Built " .. #Constants.CHARACTERS .. " character models")
end

function MapGenerator.CreateCharacterModel(charData: {id: number, name: string, bodyColor: Color3, accentColor: Color3, accessory: string}): Model
	local model = Instance.new("Model")
	model.Name = charData.name

	-- Body (chunky cube - combined torso and head)
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, 2.5, 2)
	body.Position = Vector3.new(0, 2.25, 0)
	body.Color = charData.bodyColor
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.Parent = model

	-- Eyes
	local eyeLeft = Instance.new("Part")
	eyeLeft.Name = "EyeLeft"
	eyeLeft.Shape = Enum.PartType.Ball
	eyeLeft.Size = Vector3.new(0.5, 0.5, 0.5)
	eyeLeft.Position = Vector3.new(-0.4, 2.7, -0.9)
	eyeLeft.Color = Color3.new(1, 1, 1)
	eyeLeft.Material = Enum.Material.SmoothPlastic
	eyeLeft.Anchored = true
	eyeLeft.Parent = model

	local eyeRight = Instance.new("Part")
	eyeRight.Name = "EyeRight"
	eyeRight.Shape = Enum.PartType.Ball
	eyeRight.Size = Vector3.new(0.5, 0.5, 0.5)
	eyeRight.Position = Vector3.new(0.4, 2.7, -0.9)
	eyeRight.Color = Color3.new(1, 1, 1)
	eyeRight.Material = Enum.Material.SmoothPlastic
	eyeRight.Anchored = true
	eyeRight.Parent = model

	-- Pupils
	local pupilLeft = Instance.new("Part")
	pupilLeft.Name = "PupilLeft"
	pupilLeft.Shape = Enum.PartType.Ball
	pupilLeft.Size = Vector3.new(0.2, 0.2, 0.2)
	pupilLeft.Position = Vector3.new(-0.4, 2.7, -1.1)
	pupilLeft.Color = Color3.new(0, 0, 0)
	pupilLeft.Material = Enum.Material.SmoothPlastic
	pupilLeft.Anchored = true
	pupilLeft.Parent = model

	local pupilRight = Instance.new("Part")
	pupilRight.Name = "PupilRight"
	pupilRight.Shape = Enum.PartType.Ball
	pupilRight.Size = Vector3.new(0.2, 0.2, 0.2)
	pupilRight.Position = Vector3.new(0.4, 2.7, -1.1)
	pupilRight.Color = Color3.new(0, 0, 0)
	pupilRight.Material = Enum.Material.SmoothPlastic
	pupilRight.Anchored = true
	pupilRight.Parent = model

	-- Feet
	local footLeft = Instance.new("Part")
	footLeft.Name = "FootLeft"
	footLeft.Size = Vector3.new(0.8, 0.5, 1)
	footLeft.Position = Vector3.new(-0.5, 0.25, 0)
	footLeft.Color = charData.accentColor
	footLeft.Material = Enum.Material.SmoothPlastic
	footLeft.Anchored = true
	footLeft.Parent = model

	local footRight = Instance.new("Part")
	footRight.Name = "FootRight"
	footRight.Size = Vector3.new(0.8, 0.5, 1)
	footRight.Position = Vector3.new(0.5, 0.25, 0)
	footRight.Color = charData.accentColor
	footRight.Material = Enum.Material.SmoothPlastic
	footRight.Anchored = true
	footRight.Parent = model

	-- Accessory based on type
	if charData.accessory == "lightning" then
		local bolt = Instance.new("Part")
		bolt.Name = "Accessory"
		bolt.Size = Vector3.new(0.3, 0.8, 0.1)
		bolt.Position = Vector3.new(0, 4, 0)
		bolt.Color = Color3.fromRGB(255, 255, 0)
		bolt.Material = Enum.Material.Neon
		bolt.Anchored = true
		bolt.Parent = model
	elseif charData.accessory == "bow" then
		local bow = Instance.new("Part")
		bow.Name = "Accessory"
		bow.Size = Vector3.new(0.6, 0.4, 0.2)
		bow.Position = Vector3.new(0, 3.7, 0)
		bow.Color = Color3.fromRGB(255, 105, 180)
		bow.Material = Enum.Material.SmoothPlastic
		bow.Anchored = true
		bow.Parent = model
	elseif charData.accessory == "flame" then
		local flame = Instance.new("Part")
		flame.Name = "Accessory"
		flame.Shape = Enum.PartType.Ball
		flame.Size = Vector3.new(0.5, 0.5, 0.5)
		flame.Position = Vector3.new(0, 4, 0)
		flame.Color = Color3.fromRGB(255, 100, 0)
		flame.Material = Enum.Material.Neon
		flame.Anchored = true
		flame.Parent = model

		local fire = Instance.new("Fire")
		fire.Heat = 5
		fire.Size = 3
		fire.Parent = flame
	elseif charData.accessory == "leaf" then
		local leaf = Instance.new("Part")
		leaf.Name = "Accessory"
		leaf.Size = Vector3.new(0.4, 0.6, 0.1)
		leaf.Position = Vector3.new(0, 3.8, 0)
		leaf.Color = Color3.fromRGB(34, 139, 34)
		leaf.Material = Enum.Material.Grass
		leaf.Anchored = true
		leaf.Parent = model
	elseif charData.accessory == "star" then
		local star = Instance.new("Part")
		star.Name = "Accessory"
		star.Shape = Enum.PartType.Ball
		star.Size = Vector3.new(0.4, 0.4, 0.4)
		star.Position = Vector3.new(0, 3.8, 0)
		star.Color = Color3.fromRGB(255, 255, 100)
		star.Material = Enum.Material.Neon
		star.Anchored = true
		star.Parent = model
	elseif charData.accessory == "snowflake" then
		local decal = Instance.new("Decal")
		decal.Name = "SnowflakeDecal"
		decal.Face = Enum.NormalId.Front
		decal.Color3 = Color3.fromRGB(173, 216, 230)
		decal.Parent = body
	end

	model.PrimaryPart = body
	return model
end

-- Map patterns for rectangle arena with 6 spawns (more hard walls)
local MAP_PATTERNS = {
	-- Pattern 1: Classic grid pattern (every other tile)
	function(grid, w, h)
		for x = 2, w - 1 do
			for y = 2, h - 1 do
				if x % 2 == 0 and y % 2 == 0 then
					if MapData.IsInPlayableArea(x, y) and not MapData.IsSpawnCorner(x, y) then
						grid[x][y] = "hard"
					end
				end
			end
		end
	end,

	-- Pattern 2: Dense grid with scattered pillars
	function(grid, w, h)
		local cx, cy = math.ceil(w/2), math.ceil(h/2)

		-- Every other tile pattern
		for x = 2, w - 1 do
			for y = 2, h - 1 do
				if x % 2 == 0 and y % 2 == 0 then
					if MapData.IsInPlayableArea(x, y) and not MapData.IsSpawnCorner(x, y) then
						grid[x][y] = "hard"
					end
				end
			end
		end

		-- Extra pillars
		local pillars = {
			{cx-3, cy-3}, {cx+3, cy-3}, {cx-3, cy+3}, {cx+3, cy+3},
			{cx, cy-5}, {cx, cy+5}, {cx-5, cy}, {cx+5, cy},
		}
		for _, p in ipairs(pillars) do
			if MapData.IsInPlayableArea(p[1], p[2]) and not MapData.IsSpawnCorner(p[1], p[2]) then
				grid[p[1]][p[2]] = "hard"
			end
		end
	end,

	-- Pattern 3: Diamond + grid hybrid
	function(grid, w, h)
		local cx, cy = math.ceil(w/2), math.ceil(h/2)

		-- Base grid pattern
		for x = 2, w - 1 do
			for y = 2, h - 1 do
				if x % 2 == 0 and y % 2 == 0 then
					if MapData.IsInPlayableArea(x, y) and not MapData.IsSpawnCorner(x, y) then
						grid[x][y] = "hard"
					end
				end
			end
		end

		-- Diamond additions
		for x = 1, w do
			for y = 1, h do
				local dist = math.abs(x - cx) + math.abs(y - cy)
				if dist == 5 then
					if MapData.IsInPlayableArea(x, y) and not MapData.IsSpawnCorner(x, y) then
						grid[x][y] = "hard"
					end
				end
			end
		end
	end,

	-- Pattern 4: Cross corridors with pillars
	function(grid, w, h)
		local cx, cy = math.ceil(w/2), math.ceil(h/2)

		-- Grid pattern
		for x = 2, w - 1 do
			for y = 2, h - 1 do
				if x % 2 == 0 and y % 2 == 0 then
					if MapData.IsInPlayableArea(x, y) and not MapData.IsSpawnCorner(x, y) then
						-- Skip center cross
						if x ~= cx and y ~= cy then
							grid[x][y] = "hard"
						end
					end
				end
			end
		end

		-- Ring around center
		for x = cx-3, cx+3 do
			for y = cy-3, cy+3 do
				if (x == cx-3 or x == cx+3 or y == cy-3 or y == cy+3) then
					if MapData.IsInPlayableArea(x, y) and not MapData.IsSpawnCorner(x, y) then
						grid[x][y] = "hard"
					end
				end
			end
		end
	end,

	-- Pattern 5: Maze-like walls
	function(grid, w, h)
		-- Base grid
		for x = 2, w - 1 do
			for y = 2, h - 1 do
				if x % 2 == 0 and y % 2 == 0 then
					if MapData.IsInPlayableArea(x, y) and not MapData.IsSpawnCorner(x, y) then
						grid[x][y] = "hard"
					end
				end
			end
		end

		-- Add some extra walls for maze feel
		for x = 3, w - 2, 4 do
			for y = 3, h - 2, 4 do
				if MapData.IsInPlayableArea(x, y) and not MapData.IsSpawnCorner(x, y) then
					grid[x][y] = "hard"
				end
			end
		end
	end,

	-- Pattern 6: Symmetric blocks
	function(grid, w, h)
		local cx, cy = math.ceil(w/2), math.ceil(h/2)

		-- Standard grid
		for x = 2, w - 1 do
			for y = 2, h - 1 do
				if x % 2 == 0 and y % 2 == 0 then
					if MapData.IsInPlayableArea(x, y) and not MapData.IsSpawnCorner(x, y) then
						grid[x][y] = "hard"
					end
				end
			end
		end

		-- Symmetric corner blocks
		local blocks = {
			{3, 3}, {w-2, 3}, {3, h-2}, {w-2, h-2},
			{cx, 3}, {cx, h-2}, {3, cy}, {w-2, cy},
		}
		for _, p in ipairs(blocks) do
			if MapData.IsInPlayableArea(p[1], p[2]) and not MapData.IsSpawnCorner(p[1], p[2]) then
				grid[p[1]][p[2]] = "hard"
			end
		end
	end,
}

function MapGenerator.GenerateMap()
	-- Clear existing arena
	arenaFolder:ClearAllChildren()

	-- Set grid origin from Canvas
	if canvasPart then
		local canvasPos = canvasPart.Position
		local canvasSize = canvasPart.Size
		gridOrigin = Vector3.new(
			canvasPos.X - canvasSize.X / 2,
			canvasPos.Y + canvasSize.Y / 2,
			canvasPos.Z - canvasSize.Z / 2
		)
		MapData.SetGridOrigin(gridOrigin)
	end

	-- Reset grid data
	MapData.InitializeGrids()

	local w, h = Constants.GRID_WIDTH, Constants.GRID_HEIGHT

	-- Create a layout grid
	local layoutGrid = {}
	for x = 1, w do
		layoutGrid[x] = {}
		for y = 1, h do
			layoutGrid[x][y] = "empty"
		end
	end

	-- Pick a random pattern
	local patternFunc = MAP_PATTERNS[math.random(1, #MAP_PATTERNS)]
	patternFunc(layoutGrid, w, h)

	-- Create floor tiles (checkerboard using LightShade mesh with color tinting)
	local TILE_GAP = 0.15 -- Small gap between tiles
	local TILE_SCALE = 1 - (TILE_GAP / Constants.TILE_SIZE) -- Scale down to create gap

	-- Colors for checkerboard
	local LIGHT_COLOR = Color3.fromRGB(255, 245, 230) -- Warm cream white
	local DARK_COLOR = Color3.fromRGB(180, 160, 140)  -- Tan/brown for contrast

	-- Use LightShade as the base template for all tiles
	local tileTemplate = modelTemplates.LightShade

	for x = 1, w do
		for y = 1, h do
			local worldPos = MapData.GridToWorld(x, y)
			local isLightTile = (x + y) % 2 == 0
			local tileColor = isLightTile and LIGHT_COLOR or DARK_COLOR

			if tileTemplate then
				local tile = tileTemplate:Clone()
				tile.Name = "FloorTile_" .. x .. "_" .. y

				-- Position tile (size is 4, 2.2, 4 so offset Y by half height)
				local tilePos = worldPos - Vector3.new(0, 1.1, 0)

				if tile:IsA("BasePart") then
					-- It's a MeshPart directly
					tile.Position = tilePos
					tile.Anchored = true
					tile.CanCollide = true
					tile.Size = tile.Size * Vector3.new(TILE_SCALE, 1, TILE_SCALE)
					tile.Color = tileColor
					tile.Parent = arenaFolder
				elseif tile:IsA("Model") then
					local primary = tile.PrimaryPart or tile:FindFirstChildWhichIsA("BasePart")
					if primary then
						tile:SetPrimaryPartCFrame(CFrame.new(tilePos))
					end
					-- Apply color and scale to all parts
					for _, part in ipairs(tile:GetDescendants()) do
						if part:IsA("BasePart") then
							part.Size = part.Size * Vector3.new(TILE_SCALE, 1, TILE_SCALE)
							part.Color = tileColor
							part.Anchored = true
						end
					end
					tile.Parent = arenaFolder
				end
			else
				-- Fallback to basic part (with gap)
				local gapSize = Constants.TILE_SIZE - TILE_GAP
				local tile = CreatePart(
					Vector3.new(gapSize, 1, gapSize),
					worldPos - Vector3.new(0, 0.5, 0),
					tileColor,
					"FloorTile_" .. x .. "_" .. y,
					true,
					"FloorTile"
				)
				tile.Parent = arenaFolder
			end
		end
	end

	-- Create MapSpawn parts for 6 player spawns
	MapGenerator.CreateMapSpawns()

	-- Place hard walls based on layout grid (only in playable area)
	for x = 1, w do
		for y = 1, h do
			if not MapData.IsInPlayableArea(x, y) then continue end

			if layoutGrid[x][y] == "hard" then
				local worldPos = MapData.GridToWorld(x, y)
				local wallPos = worldPos + Vector3.new(0, Constants.TILE_SIZE / 2, 0)

				-- Try to use HardCrate model
				local crate = CreateCrate(wallPos, "HardWall_" .. x .. "_" .. y, "hard")
				if crate then
					crate.Parent = arenaFolder
					CollectionService:AddTag(crate, "HardWall")
				else
					-- Fallback to basic part
					local wall = CreatePart(
						Vector3.new(Constants.TILE_SIZE, Constants.TILE_SIZE, Constants.TILE_SIZE),
						wallPos,
						Constants.COLORS.HARD_WALL,
						"HardWall_" .. x .. "_" .. y,
						true,
						"HardWall"
					)
					wall.Parent = arenaFolder
					CollectionService:AddTag(wall, "HardWall")
				end

				MapData.SetWalkable(x, y, false)
				MapData.SetHardWall(x, y, true)
			end
		end
	end

	-- Place soft walls with clustered placement (only in playable area)
	local softWallChance = Constants.SOFT_WALL_DENSITY
	for x = 1, w do
		for y = 1, h do
			-- Skip if not in playable area
			if not MapData.IsInPlayableArea(x, y) then continue end
			-- Skip if already occupied
			if not MapData.IsWalkable(x, y) then continue end
			-- Skip spawn corners
			if MapData.IsSpawnCorner(x, y) then continue end

			-- Cluster-based placement
			local neighborBonus = 0
			for dx = -1, 1 do
				for dy = -1, 1 do
					local nx, ny = x + dx, y + dy
					if nx >= 1 and nx <= w and ny >= 1 and ny <= h then
						if layoutGrid[nx] and layoutGrid[nx][ny] == "soft" then
							neighborBonus = neighborBonus + 0.1
						end
					end
				end
			end

			local chance = math.min(softWallChance + neighborBonus, 0.75)

			if math.random() < chance then
				local worldPos = MapData.GridToWorld(x, y)
				local wallPos = worldPos + Vector3.new(0, Constants.TILE_SIZE / 2, 0)

				-- Try to use SoftCrate model
				local crate = CreateCrate(wallPos, "SoftWall_" .. x .. "_" .. y, "soft")
				if crate then
					crate.Parent = arenaFolder
					CollectionService:AddTag(crate, "SoftWall")
				else
					-- Fallback to basic part
					local colorVariation = math.random(-20, 20)
					local r = math.clamp(Constants.COLORS.SOFT_WALL.R * 255 + colorVariation, 180, 255)
					local g = math.clamp(Constants.COLORS.SOFT_WALL.G * 255 + colorVariation/2, 140, 200)
					local b = math.clamp(Constants.COLORS.SOFT_WALL.B * 255 + colorVariation, 180, 255)
					local softColor = Color3.fromRGB(r, g, b)

					local wall = CreatePart(
						Vector3.new(Constants.TILE_SIZE, Constants.TILE_SIZE, Constants.TILE_SIZE),
						wallPos,
						softColor,
						"SoftWall_" .. x .. "_" .. y,
						true,
						"SoftWall"
					)
					wall.Parent = arenaFolder
					CollectionService:AddTag(wall, "SoftWall")
				end

				MapData.SetWalkable(x, y, false)
				layoutGrid[x][y] = "soft"
			end
		end
	end

	-- Ensure connectivity from spawn positions to center
	MapGenerator.EnsureConnectivity()

	-- Border removed - arena is open

	-- Spawn a few test coins on the map
	task.defer(function()
		print("[MapGenerator] Attempting to spawn test coins, PowerUpService:", PowerUpService)
		local spawned = 0
		for i = 1, 5 do
			local x = math.random(3, w - 2)
			local y = math.random(3, h - 2)
			if MapData.IsWalkable(x, y) then
				print("[MapGenerator] Spawning coin at", x, y)
				PowerUpService.SpawnCoin(x, y)
				spawned = spawned + 1
			end
		end
		print("[MapGenerator] Spawned", spawned, "test coins")
	end)

	print("[MapGenerator] Rectangle map generated on Canvas")
end

-- Create 6 MapSpawn parts at spawn positions
function MapGenerator.CreateMapSpawns()
	local spawns = MapData.GetSpawnPositions()

	for i, pos in ipairs(spawns) do
		local spawnPart = Instance.new("Part")
		spawnPart.Name = "MapSpawn_" .. i
		spawnPart.Size = Vector3.new(3, 1, 3)
		spawnPart.Position = pos + Vector3.new(0, 0.5, 0)
		spawnPart.Anchored = true
		spawnPart.CanCollide = false
		spawnPart.Transparency = 1
		spawnPart.Parent = arenaFolder

		CollectionService:AddTag(spawnPart, "MapSpawn")
	end

	print("[MapGenerator] Created 6 MapSpawn parts")
end

function MapGenerator.EnsureConnectivity()
	local centerX = math.ceil(Constants.GRID_WIDTH / 2)
	local centerY = math.ceil(Constants.GRID_HEIGHT / 2)
	local w, h = Constants.GRID_WIDTH, Constants.GRID_HEIGHT
	local midY = math.ceil(h / 2)

	-- Make center accessible
	MapGenerator.ClearPathTo(centerX, centerY)

	-- Check each spawn zone (6 positions for rectangle)
	local spawnZones = {
		{2, 2},           -- Top-left
		{w - 1, 2},       -- Top-right
		{2, h - 1},       -- Bottom-left
		{w - 1, h - 1},   -- Bottom-right
		{2, midY},        -- Mid-left
		{w - 1, midY},    -- Mid-right
	}

	for _, zone in ipairs(spawnZones) do
		local reachable = MapData.FloodFillReachable(zone[1], zone[2])

		local centerReachable = false
		for _, tile in ipairs(reachable) do
			if tile.x == centerX and tile.y == centerY then
				centerReachable = true
				break
			end
		end

		if not centerReachable then
			MapGenerator.ClearPathBetween(zone[1], zone[2], centerX, centerY)
		end
	end
end

function MapGenerator.ClearPathTo(gridX: number, gridY: number)
	-- Clear the target tile if it has a soft wall
	local arenaFolder = Workspace:FindFirstChild("Arena")
	if not arenaFolder then return end

	for _, obj in ipairs(CollectionService:GetTagged("SoftWall")) do
		if obj:IsDescendantOf(arenaFolder) then
			local pos: Vector3?
			if obj:IsA("Model") then
				local part = obj:FindFirstChildWhichIsA("BasePart")
				if part then pos = part.Position end
			elseif obj:IsA("BasePart") then
				pos = obj.Position
			end

			if pos then
				local wx, wy = MapData.WorldToGrid(pos)
				if wx == gridX and wy == gridY then
					obj:Destroy()
					MapData.SetWalkable(gridX, gridY, true)
					break
				end
			end
		end
	end
end

function MapGenerator.ClearPathBetween(x1: number, y1: number, x2: number, y2: number)
	-- Simple straight line path clearing (Manhattan path)
	local currentX = x1
	local currentY = y1

	while currentX ~= x2 do
		if currentX < x2 then
			currentX = currentX + 1
		else
			currentX = currentX - 1
		end

		-- Skip hard walls
		if not MapData.IsHardWallPosition(currentX, currentY) then
			MapGenerator.ClearPathTo(currentX, currentY)
		else
			-- Go around hard wall
			if currentY < y2 then
				currentY = currentY + 1
			elseif currentY > y2 then
				currentY = currentY - 1
			end
		end
	end

	while currentY ~= y2 do
		if currentY < y2 then
			currentY = currentY + 1
		else
			currentY = currentY - 1
		end

		if not MapData.IsHardWallPosition(currentX, currentY) then
			MapGenerator.ClearPathTo(currentX, currentY)
		end
	end
end

function MapGenerator.CreateBorder()
	MapGenerator.CreateRectBorder()
end

function MapGenerator.CreateRectBorder()
	local arenaFolder = Workspace:FindFirstChild("Arena")
	if not arenaFolder then return end

	local tileSize = Constants.TILE_SIZE
	local wallHeight = 8
	local wallThickness = 4
	local borderColor = Constants.COLORS.BORDER or Color3.fromRGB(120, 160, 120)
	local w, h = Constants.GRID_WIDTH, Constants.GRID_HEIGHT

	-- Calculate grid bounds from dynamic origin
	local gridLeft = gridOrigin.X
	local gridRight = gridOrigin.X + w * tileSize
	local gridTop = gridOrigin.Z
	local gridBottom = gridOrigin.Z + h * tileSize
	local gridY = gridOrigin.Y + wallHeight / 2

	-- Simple 4-wall rectangle border
	local borders = {
		-- Top wall
		{pos = Vector3.new((gridLeft + gridRight) / 2, gridY, gridTop - wallThickness / 2),
		 size = Vector3.new(gridRight - gridLeft + wallThickness * 2, wallHeight, wallThickness)},
		-- Bottom wall
		{pos = Vector3.new((gridLeft + gridRight) / 2, gridY, gridBottom + wallThickness / 2),
		 size = Vector3.new(gridRight - gridLeft + wallThickness * 2, wallHeight, wallThickness)},
		-- Left wall
		{pos = Vector3.new(gridLeft - wallThickness / 2, gridY, (gridTop + gridBottom) / 2),
		 size = Vector3.new(wallThickness, wallHeight, gridBottom - gridTop)},
		-- Right wall
		{pos = Vector3.new(gridRight + wallThickness / 2, gridY, (gridTop + gridBottom) / 2),
		 size = Vector3.new(wallThickness, wallHeight, gridBottom - gridTop)},
	}

	for i, border in ipairs(borders) do
		local wall = CreatePart(border.size, border.pos, borderColor, "Border_" .. i, true, "BorderWall")
		CollectionService:AddTag(wall, "BorderWall")
		wall.Parent = arenaFolder
	end
end

function MapGenerator.DestroySoftWall(wall: Instance, gridX: number, gridY: number)
	-- Update grid
	MapData.SetWalkable(gridX, gridY, true)

	-- Get position for powerup spawn
	local spawnPos: Vector3
	local parts: {BasePart} = {}

	if wall:IsA("Model") then
		-- It's a crate model - get all mesh parts
		for _, part in ipairs(wall:GetDescendants()) do
			if part:IsA("BasePart") then
				table.insert(parts, part)
				if not spawnPos then
					spawnPos = part.Position
				end
			end
		end
	elseif wall:IsA("BasePart") then
		-- It's a single part
		table.insert(parts, wall)
		spawnPos = wall.Position
	end

	if #parts == 0 then
		wall:Destroy()
		return
	end

	-- Animate each part flying apart
	for i, part in ipairs(parts) do
		-- Disable collision immediately
		part.CanCollide = false

		-- Random direction for pieces to fly
		local randomDir = Vector3.new(
			(math.random() - 0.5) * 2,
			math.random() * 1.5 + 0.5,
			(math.random() - 0.5) * 2
		).Unit

		local randomSpin = Vector3.new(
			math.random() * 360,
			math.random() * 360,
			math.random() * 360
		)

		-- Unanchor for physics
		part.Anchored = false

		-- Apply impulse to fly apart
		local impulse = randomDir * 15
		if part:IsA("BasePart") then
			part:ApplyImpulse(impulse)
			part:ApplyAngularImpulse(randomSpin * 0.1)
		end

		-- Tween to shrink and fade
		local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local tween = TweenService:Create(part, tweenInfo, {
			Size = part.Size * 0.1,
			Transparency = 1
		})
		tween:Play()
	end

	-- Spawn particles at center
	local particlePart = Instance.new("Part")
	particlePart.Size = Vector3.new(1, 1, 1)
	particlePart.Position = spawnPos or Vector3.zero
	particlePart.Anchored = true
	particlePart.CanCollide = false
	particlePart.Transparency = 1
	particlePart.Parent = Workspace

	-- Wood splinter particles
	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(Color3.fromRGB(194, 155, 97)) -- Wood color
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0)
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1)
	})
	particles.Lifetime = NumberRange.new(0.3, 0.6)
	particles.Rate = 0
	particles.Speed = NumberRange.new(8, 15)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Rotation = NumberRange.new(0, 360)
	particles.RotSpeed = NumberRange.new(-200, 200)
	particles.Parent = particlePart

	-- Burst particles
	particles:Emit(20)

	-- Cleanup after animation
	task.delay(0.5, function()
		-- Check for powerup spawn
		if math.random() < Constants.POWERUP_SPAWN_CHANCE then
			PowerUpService.SpawnRandomPowerUp(gridX, gridY)
		end

		particlePart:Destroy()
		if wall and wall.Parent then
			wall:Destroy()
		end
	end)
end

function MapGenerator.DestroyAllSoftWalls()
	local arenaFolder = Workspace:FindFirstChild("Arena")
	if not arenaFolder then return end

	for _, obj in ipairs(CollectionService:GetTagged("SoftWall")) do
		if obj:IsDescendantOf(arenaFolder) then
			local pos: Vector3
			if obj:IsA("Model") then
				local part = obj:FindFirstChildWhichIsA("BasePart")
				if part then pos = part.Position end
			elseif obj:IsA("BasePart") then
				pos = obj.Position
			end

			if pos then
				local gridX, gridY = MapData.WorldToGrid(pos)
				MapGenerator.DestroySoftWall(obj, gridX, gridY)
			end
		end
	end
end

-- Build winners podium stage
function MapGenerator.BuildWinnersPodium()
	local podiumFolder = Workspace:FindFirstChild("WinnersPodium")
	if not podiumFolder then
		podiumFolder = Instance.new("Folder")
		podiumFolder.Name = "WinnersPodium"
		podiumFolder.Parent = Workspace
	else
		podiumFolder:ClearAllChildren()
	end

	local podiumCenter = Vector3.new(0, 0, 50) -- In front of arena

	-- Create base platform
	local basePlatform = CreatePart(
		Vector3.new(30, 2, 20),
		podiumCenter + Vector3.new(0, -1, 0),
		Color3.fromRGB(60, 60, 80),
		"PodiumBase",
		true
	)
	basePlatform.Parent = podiumFolder

	-- Create the 3 podium stands
	local podiumColors = {
		Color3.fromRGB(255, 215, 0),  -- Gold for 1st
		Color3.fromRGB(192, 192, 192), -- Silver for 2nd
		Color3.fromRGB(205, 127, 50),  -- Bronze for 3rd
	}

	for i, podData in ipairs(Constants.PODIUM_POSITIONS) do
		local podiumPart = CreatePart(
			Vector3.new(5, podData.height, 5),
			podiumCenter + podData.offset + Vector3.new(0, podData.height / 2, 0),
			podiumColors[i],
			"Podium_" .. podData.place,
			true
		)
		podiumPart.Parent = podiumFolder

		-- Add place number label
		local placeLabel = Instance.new("BillboardGui")
		placeLabel.Name = "PlaceLabel"
		placeLabel.Size = UDim2.new(0, 80, 0, 80)
		placeLabel.StudsOffset = Vector3.new(0, -podData.height / 2 + 1, 2.6)
		placeLabel.AlwaysOnTop = false
		placeLabel.Parent = podiumPart

		local placeText = Instance.new("TextLabel")
		placeText.Size = UDim2.new(1, 0, 1, 0)
		placeText.BackgroundTransparency = 1
		placeText.Text = tostring(podData.place)
		placeText.TextColor3 = Color3.new(1, 1, 1)
		placeText.TextStrokeTransparency = 0
		placeText.TextScaled = true
		placeText.Font = Enum.Font.GothamBold
		placeText.Parent = placeLabel

		-- Add spotlight
		local spotlight = Instance.new("SpotLight")
		spotlight.Face = Enum.NormalId.Top
		spotlight.Brightness = 5
		spotlight.Range = 15
		spotlight.Angle = 60
		spotlight.Color = podiumColors[i]
		spotlight.Parent = podiumPart
	end

	-- Add confetti emitters (particles)
	for i = 1, 3 do
		local confettiPart = Instance.new("Part")
		confettiPart.Name = "ConfettiEmitter_" .. i
		confettiPart.Size = Vector3.new(1, 1, 1)
		confettiPart.Position = podiumCenter + Vector3.new((i - 2) * 10, 15, 0)
		confettiPart.Anchored = true
		confettiPart.CanCollide = false
		confettiPart.Transparency = 1
		confettiPart.Parent = podiumFolder

		local confetti = Instance.new("ParticleEmitter")
		confetti.Name = "Confetti"
		confetti.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 100, 100)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(100, 255, 100)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(100, 100, 255)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(255, 255, 100)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 255)),
		})
		confetti.Size = NumberSequence.new(0.3, 0.1)
		confetti.Lifetime = NumberRange.new(3, 5)
		confetti.Rate = 20
		confetti.Speed = NumberRange.new(5, 10)
		confetti.SpreadAngle = Vector2.new(180, 180)
		confetti.RotSpeed = NumberRange.new(-180, 180)
		confetti.Enabled = false -- Enabled during winners stage
		confetti.Parent = confettiPart
	end

	-- Background decoration
	local backdrop = CreatePart(
		Vector3.new(40, 20, 2),
		podiumCenter + Vector3.new(0, 9, -12),
		Color3.fromRGB(40, 40, 60),
		"Backdrop",
		true
	)
	backdrop.Parent = podiumFolder

	-- "WINNERS" text on backdrop
	local winnersLabel = Instance.new("BillboardGui")
	winnersLabel.Name = "WinnersLabel"
	winnersLabel.Size = UDim2.new(0, 300, 0, 80)
	winnersLabel.StudsOffset = Vector3.new(0, 5, 1.1)
	winnersLabel.AlwaysOnTop = false
	winnersLabel.Parent = backdrop

	local winnersText = Instance.new("TextLabel")
	winnersText.Size = UDim2.new(1, 0, 1, 0)
	winnersText.BackgroundTransparency = 1
	winnersText.Text = "🏆 WINNERS 🏆"
	winnersText.TextColor3 = Color3.fromRGB(255, 215, 0)
	winnersText.TextStrokeTransparency = 0
	winnersText.TextScaled = true
	winnersText.Font = Enum.Font.GothamBold
	winnersText.Parent = winnersLabel

	return podiumFolder
end

-- Enable/disable confetti
function MapGenerator.SetConfettiEnabled(enabled: boolean)
	local podiumFolder = Workspace:FindFirstChild("WinnersPodium")
	if not podiumFolder then return end

	for _, child in ipairs(podiumFolder:GetChildren()) do
		if child.Name:match("ConfettiEmitter") then
			local confetti = child:FindFirstChild("Confetti")
			if confetti then
				confetti.Enabled = enabled
			end
		end
	end
end

-- Get podium spawn position for a place (1, 2, or 3)
function MapGenerator.GetPodiumPosition(place: number): Vector3
	local podiumCenter = Vector3.new(0, 0, 50)
	for _, podData in ipairs(Constants.PODIUM_POSITIONS) do
		if podData.place == place then
			return podiumCenter + podData.offset + Vector3.new(0, podData.height + 3, 0)
		end
	end
	return podiumCenter + Vector3.new(0, 10, 0)
end

return MapGenerator
