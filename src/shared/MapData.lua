--!strict
-- MapData.lua
-- Grid system helpers and map data utilities

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local MapData = {}

-- Grid walkability data (updated by server, read by both)
-- true = walkable, false = blocked
MapData.walkabilityGrid = {} :: {{boolean}}
MapData.bombGrid = {} :: {{boolean}} -- true = bomb present

-- Dynamic grid origin and rotation (set by MapGenerator based on Canvas CFrame)
MapData.gridOrigin = Vector3.new(-50, 1, -50)
MapData.gridCFrame = CFrame.new(-50, 1, -50) -- Full CFrame with rotation
MapData.gridRotation = CFrame.new() -- Just the rotation component

function MapData.SetGridOrigin(origin: Vector3)
	MapData.gridOrigin = origin
end

function MapData.SetGridCFrame(cframe: CFrame)
	MapData.gridCFrame = cframe
	MapData.gridOrigin = cframe.Position
	-- Extract just the rotation component (no position)
	MapData.gridRotation = cframe - cframe.Position
end

-- Initialize empty grids
function MapData.InitializeGrids()
	MapData.walkabilityGrid = {}
	MapData.bombGrid = {}
	MapData.hardWallGrid = {}

	for x = 1, Constants.GRID_WIDTH do
		MapData.walkabilityGrid[x] = {}
		MapData.bombGrid[x] = {}
		MapData.hardWallGrid[x] = {}
		for y = 1, Constants.GRID_HEIGHT do
			MapData.walkabilityGrid[x][y] = true
			MapData.bombGrid[x][y] = false
			MapData.hardWallGrid[x][y] = false
		end
	end
end

-- Convert world position to grid coordinates (1-indexed)
-- Handles rotated canvas by transforming to local space first
function MapData.WorldToGrid(worldPos: Vector3): (number, number)
	-- Transform world position to local grid space (inverse of grid CFrame)
	local localPos = MapData.gridCFrame:PointToObjectSpace(worldPos)

	-- In local space, X is grid X direction, Z is grid Y direction
	local relativeX = localPos.X
	local relativeZ = localPos.Z

	local gridX = math.floor(relativeX / Constants.TILE_SIZE) + 1
	local gridY = math.floor(relativeZ / Constants.TILE_SIZE) + 1

	-- Clamp to valid grid range
	gridX = math.clamp(gridX, 1, Constants.GRID_WIDTH)
	gridY = math.clamp(gridY, 1, Constants.GRID_HEIGHT)

	return gridX, gridY
end

-- Convert grid coordinates to world position (center of tile)
-- Applies canvas rotation to position tiles correctly
function MapData.GridToWorld(gridX: number, gridY: number): Vector3
	-- Calculate local position (relative to grid origin, before rotation)
	local localX = (gridX - 0.5) * Constants.TILE_SIZE
	local localY = 0
	local localZ = (gridY - 0.5) * Constants.TILE_SIZE
	local localPos = Vector3.new(localX, localY, localZ)

	-- Transform to world space using grid CFrame (applies rotation)
	local worldPos = MapData.gridCFrame:PointToWorldSpace(localPos)

	return worldPos
end

-- Get the rotation CFrame to apply to placed objects
function MapData.GetGridRotation(): CFrame
	return MapData.gridRotation
end

-- Get full CFrame for a grid position (position + rotation)
function MapData.GridToCFrame(gridX: number, gridY: number): CFrame
	local localX = (gridX - 0.5) * Constants.TILE_SIZE
	local localY = 0
	local localZ = (gridY - 0.5) * Constants.TILE_SIZE

	-- Create local CFrame and transform to world space
	local localCFrame = CFrame.new(localX, localY, localZ)
	return MapData.gridCFrame * localCFrame
end

-- Check if a grid position is walkable (no walls)
function MapData.IsWalkable(gridX: number, gridY: number): boolean
	if gridX < 1 or gridX > Constants.GRID_WIDTH then return false end
	if gridY < 1 or gridY > Constants.GRID_HEIGHT then return false end

	return MapData.walkabilityGrid[gridX] and MapData.walkabilityGrid[gridX][gridY] == true
end

-- Check if a grid position has a bomb
function MapData.HasBomb(gridX: number, gridY: number): boolean
	if gridX < 1 or gridX > Constants.GRID_WIDTH then return false end
	if gridY < 1 or gridY > Constants.GRID_HEIGHT then return false end

	return MapData.bombGrid[gridX] and MapData.bombGrid[gridX][gridY] == true
end

-- Set walkability for a tile
function MapData.SetWalkable(gridX: number, gridY: number, walkable: boolean)
	if gridX < 1 or gridX > Constants.GRID_WIDTH then return end
	if gridY < 1 or gridY > Constants.GRID_HEIGHT then return end

	if MapData.walkabilityGrid[gridX] then
		MapData.walkabilityGrid[gridX][gridY] = walkable
	end
end

-- Set bomb presence for a tile
function MapData.SetBomb(gridX: number, gridY: number, hasBomb: boolean)
	if gridX < 1 or gridX > Constants.GRID_WIDTH then return end
	if gridY < 1 or gridY > Constants.GRID_HEIGHT then return end

	if MapData.bombGrid[gridX] then
		MapData.bombGrid[gridX][gridY] = hasBomb
	end
end

-- Check if a grid position is within playable area (simple rectangle)
function MapData.IsInPlayableArea(gridX: number, gridY: number): boolean
	return gridX >= 1 and gridX <= Constants.GRID_WIDTH and gridY >= 1 and gridY <= Constants.GRID_HEIGHT
end

-- Check if position is in spawn zone (should be kept clear)
function MapData.IsSpawnCorner(gridX: number, gridY: number): boolean
	-- 3x3 clear zones for 6 player spawns
	local w, h = Constants.GRID_WIDTH, Constants.GRID_HEIGHT
	local midY = math.ceil(h / 2)

	local spawnZones = {
		-- 4 corners
		{1, 1},           -- Top-left
		{w - 2, 1},       -- Top-right
		{1, h - 2},       -- Bottom-left
		{w - 2, h - 2},   -- Bottom-right
		-- 2 mid-sides
		{1, midY - 1},    -- Mid-left
		{w - 2, midY - 1}, -- Mid-right
	}

	for _, zone in ipairs(spawnZones) do
		local zx, zy = zone[1], zone[2]
		if gridX >= zx and gridX <= zx + 2 and gridY >= zy and gridY <= zy + 2 then
			return true
		end
	end

	return false
end

-- Check if position should have a hard wall (fixed grid pattern)
function MapData.IsHardWallPosition(gridX: number, gridY: number): boolean
	-- Hard walls at every even x AND even y (1-indexed, so checking for divisibility)
	return gridX % 2 == 0 and gridY % 2 == 0
end

-- Get spawn positions for players (6 positions for rectangle)
function MapData.GetSpawnPositions(): {Vector3}
	local w, h = Constants.GRID_WIDTH, Constants.GRID_HEIGHT
	local midY = math.ceil(h / 2)

	local spawns = {
		-- 4 corners
		MapData.GridToWorld(2, 2),       -- Top-left
		MapData.GridToWorld(w - 1, 2),   -- Top-right
		MapData.GridToWorld(2, h - 1),   -- Bottom-left
		MapData.GridToWorld(w - 1, h - 1), -- Bottom-right
		-- 2 mid-sides
		MapData.GridToWorld(2, midY),     -- Mid-left
		MapData.GridToWorld(w - 1, midY), -- Mid-right
	}
	return spawns
end

-- Track hard wall positions (set by MapGenerator)
MapData.hardWallGrid = {} :: {{boolean}}

function MapData.InitializeHardWallGrid()
	MapData.hardWallGrid = {}
	for x = 1, Constants.GRID_WIDTH do
		MapData.hardWallGrid[x] = {}
		for y = 1, Constants.GRID_HEIGHT do
			MapData.hardWallGrid[x][y] = false
		end
	end
end

function MapData.SetHardWall(gridX: number, gridY: number, isHard: boolean)
	if gridX < 1 or gridX > Constants.GRID_WIDTH then return end
	if gridY < 1 or gridY > Constants.GRID_HEIGHT then return end
	if MapData.hardWallGrid[gridX] then
		MapData.hardWallGrid[gridX][gridY] = isHard
	end
end

function MapData.IsHardWall(gridX: number, gridY: number): boolean
	if gridX < 1 or gridX > Constants.GRID_WIDTH then return true end
	if gridY < 1 or gridY > Constants.GRID_HEIGHT then return true end
	return MapData.hardWallGrid[gridX] and MapData.hardWallGrid[gridX][gridY] == true
end

-- Get all tiles affected by an explosion from a position with given range
function MapData.GetExplosionTiles(gridX: number, gridY: number, range: number): {{x: number, y: number}}
	local tiles = {{x = gridX, y = gridY}} -- Center tile

	-- Directions: up, down, left, right (cross pattern +)
	local directions = {
		{dx = 0, dy = -1}, -- Up (negative Z)
		{dx = 0, dy = 1},  -- Down (positive Z)
		{dx = -1, dy = 0}, -- Left (negative X)
		{dx = 1, dy = 0},  -- Right (positive X)
	}

	for _, dir in ipairs(directions) do
		for i = 1, range do
			local tx = gridX + dir.dx * i
			local ty = gridY + dir.dy * i

			-- Check bounds
			if tx < 1 or tx > Constants.GRID_WIDTH or ty < 1 or ty > Constants.GRID_HEIGHT then
				break
			end

			-- Check for hard wall (explosion stops, doesn't affect hard wall)
			if MapData.IsHardWall(tx, ty) then
				break
			end

			-- Add tile to explosion (including soft walls - they all get destroyed)
			table.insert(tiles, {x = tx, y = ty})

			-- Soft walls don't stop the explosion anymore - continue through them
		end
	end

	return tiles
end

-- Flood fill to check connectivity from a position
function MapData.FloodFillReachable(startX: number, startY: number): {{x: number, y: number}}
	local visited = {}
	local reachable = {}
	local queue = {{x = startX, y = startY}}

	local function key(x: number, y: number): string
		return x .. "," .. y
	end

	while #queue > 0 do
		local current = table.remove(queue, 1)
		local k = key(current.x, current.y)

		if visited[k] then continue end
		visited[k] = true

		if not MapData.IsWalkable(current.x, current.y) then continue end

		table.insert(reachable, current)

		-- Add neighbors
		local neighbors = {
			{x = current.x + 1, y = current.y},
			{x = current.x - 1, y = current.y},
			{x = current.x, y = current.y + 1},
			{x = current.x, y = current.y - 1},
		}

		for _, neighbor in ipairs(neighbors) do
			if neighbor.x >= 1 and neighbor.x <= Constants.GRID_WIDTH and
			   neighbor.y >= 1 and neighbor.y <= Constants.GRID_HEIGHT then
				if not visited[key(neighbor.x, neighbor.y)] then
					table.insert(queue, neighbor)
				end
			end
		end
	end

	return reachable
end

return MapData
