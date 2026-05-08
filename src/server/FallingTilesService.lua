--!strict
-- FallingTilesService.lua
-- Shrinks the arena ring-by-ring from the outside in.
-- Floor tiles shake, then collapse into a lava pool below.
-- Objects on those tiles (walls, crates) also fall and dissolve.
-- Players who touch the lava die.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local MapData = require(Shared:WaitForChild("MapData"))
local GameState = require(Shared:WaitForChild("GameState"))

local FallingTilesService = {}

-- Module references (set during Initialize)
local RoundSystem

-- Timing
local SHAKE_DURATION = 2.0 -- seconds of shaking before tile collapses
local FIRST_RING_DELAY = 8 -- seconds before first ring starts shaking
local RING_INTERVAL = 8 -- seconds between each ring drop

-- State
local active = false
local lavaInstance: BasePart? = nil
local lavaConnections: {RBXScriptConnection} = {}
local heartbeatConnection: RBXScriptConnection? = nil
local fallKillY: number = -100 -- set dynamically from canvas position

-- Water/Lava transition
local WATER_SLIDE_DISTANCE = 30 -- studs to slide water down / lava up
local WATER_SLIDE_DURATION = 1.5 -- seconds for the slide animation
local waterOriginalCFrame: CFrame? = nil -- saved on first use

function FallingTilesService.Initialize()
	local ServerFolder = script.Parent
	RoundSystem = require(ServerFolder:WaitForChild("RoundSystem"))
end

-- ============================================================
-- Ring helpers
-- ============================================================

-- Which ring a tile belongs to (0 = outermost edge)
local function GetTileRing(x: number, y: number): number
	return math.min(x - 1, y - 1, Constants.GRID_WIDTH - x, Constants.GRID_HEIGHT - y)
end

-- Max ring index for the grid
local function GetMaxRing(): number
	return math.min(
		math.floor((Constants.GRID_WIDTH - 1) / 2),
		math.floor((Constants.GRID_HEIGHT - 1) / 2)
	)
end

-- All tile positions in a specific ring
local function GetTilesInRing(ring: number): {{x: number, y: number}}
	local tiles = {}
	for x = 1, Constants.GRID_WIDTH do
		for y = 1, Constants.GRID_HEIGHT do
			if GetTileRing(x, y) == ring then
				table.insert(tiles, {x = x, y = y})
			end
		end
	end
	return tiles
end

-- ============================================================
-- Arena queries
-- ============================================================

local function GetFloorTile(gridX: number, gridY: number): Instance?
	local arena = Workspace:FindFirstChild("Arena")
	if not arena then return nil end
	return arena:FindFirstChild("FloorTile_" .. gridX .. "_" .. gridY)
end

-- Find any objects sitting on a grid position (walls, crates, powerups, etc.)
local function GetObjectsAtGridPos(gridX: number, gridY: number): {Instance}
	local objects = {}
	local arena = Workspace:FindFirstChild("Arena")
	if not arena then return objects end

	for _, child in ipairs(arena:GetChildren()) do
		if child.Name:match("^FloorTile_") then continue end
		if child.Name:match("^MapSpawn") then continue end

		local pos: Vector3? = nil
		if child:IsA("BasePart") then
			pos = child.Position
		elseif child:IsA("Model") then
			local primary = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")
			if primary then pos = primary.Position end
		end

		if pos then
			local cx, cy = MapData.WorldToGrid(pos)
			if cx == gridX and cy == gridY then
				table.insert(objects, child)
			end
		end
	end
	return objects
end

-- ============================================================
-- Drop helpers
-- ============================================================

-- Drop a floor tile — CanCollide off so players fall through the hole,
-- tile falls through lava and gets cleaned up out of view
local function DropFloorTile(obj: Instance)
	if obj:IsA("BasePart") then
		obj.Anchored = false
		obj.CanCollide = false
	end
	for _, part in ipairs(obj:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
		end
	end
	Debris:AddItem(obj, 4)
end

-- Drop an object (wall, crate, powerup) — keeps CanCollide so it lands
-- on the lava surface and dissolves there via Touched
local function DropObject(obj: Instance)
	-- Break any running animation coroutines (e.g. powerup bounce)
	-- by briefly parenting to nil, then re-parenting to Workspace
	obj.Parent = nil

	-- Unanchor but KEEP collision so it lands on the lava
	if obj:IsA("BasePart") then
		obj.Anchored = false
		obj.CanCollide = true
	end
	for _, part in ipairs(obj:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = true
		end
	end

	-- Re-parent to Workspace so it visually falls
	obj.Parent = Workspace

	-- Safety cleanup in case it never touches lava
	Debris:AddItem(obj, 8)
end

-- ============================================================
-- Dissolve effect — applied when objects touch lava
-- ============================================================

local function ApplyLavaDissolve(obj: Instance)
	if obj:FindFirstChild("_LavaDissolved") then return end
	local tag = Instance.new("BoolValue")
	tag.Name = "_LavaDissolved"
	tag.Parent = obj

	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(0, 0, 0)
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Parent = obj

	TweenService:Create(highlight, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		FillTransparency = 0,
	}):Play()

	-- Destroy after dissolve completes
	Debris:AddItem(obj, 1.5)
end

-- ============================================================
-- Drop a single tile and everything sitting on it
-- ============================================================

local function DropTile(gridX: number, gridY: number)
	local tile = GetFloorTile(gridX, gridY)
	if not tile then return end

	-- Collect all BaseParts in the floor tile for shaking
	local tileParts: {BasePart} = {}
	local originalCFrames: {CFrame} = {}
	local warningColor = Color3.fromRGB(255, 80, 60)

	if tile:IsA("BasePart") then
		table.insert(tileParts, tile)
		table.insert(originalCFrames, tile.CFrame)
	elseif tile:IsA("Model") then
		for _, part in ipairs(tile:GetDescendants()) do
			if part:IsA("BasePart") then
				table.insert(tileParts, part)
				table.insert(originalCFrames, part.CFrame)
			end
		end
	end

	if #tileParts == 0 then return end

	-- Flash to red warning
	for _, part in ipairs(tileParts) do
		TweenService:Create(part, TweenInfo.new(0.3), {
			Color = warningColor,
		}):Play()
	end

	-- Shake with increasing intensity
	local shakeStart = tick()
	while tick() - shakeStart < SHAKE_DURATION do
		if not active then
			for i, part in ipairs(tileParts) do
				if part.Parent then part.CFrame = originalCFrames[i] end
			end
			return
		end

		local progress = (tick() - shakeStart) / SHAKE_DURATION
		local intensity = 0.15 + 0.2 * progress
		local ox = (math.random() - 0.5) * 2 * intensity
		local oz = (math.random() - 0.5) * 2 * intensity
		local offset = CFrame.new(ox, 0, oz)
		for i, part in ipairs(tileParts) do
			if part.Parent then part.CFrame = originalCFrames[i] * offset end
		end
		task.wait(0.03)
	end

	-- Reset before collapse
	for i, part in ipairs(tileParts) do
		if part.Parent then part.CFrame = originalCFrames[i] end
	end
	if not active then return end

	-- === Collapse: disable collision first so there's a real hole ===
	for _, part in ipairs(tileParts) do
		part.CanCollide = false
	end

	-- Drop the floor tile (no collision — falls through lava, just disappears)
	DropFloorTile(tile)

	-- Drop any objects on this tile (walls, crates, powerups)
	-- These keep collision so they land on the lava and dissolve
	local objects = GetObjectsAtGridPos(gridX, gridY)
	for _, obj in ipairs(objects) do
		DropObject(obj)
	end
end

-- ============================================================
-- Lava touch handler
-- ============================================================

local function OnLavaTouched(hit: BasePart)
	if not active then return end
	-- Only process kills during active gameplay
	if GameState.currentState ~= Constants.STATES.PLAYING then return end

	local parent = hit.Parent
	if not parent then return end

	-- Check if this is a player character
	local player = Players:GetPlayerFromCharacter(parent)
	if player then
		-- Player touched lava — kill them
		if hit:FindFirstChild("Sssh") then return end -- already processed

		local humanoid = parent:FindFirstChild("Humanoid") :: Humanoid?
		if not humanoid or humanoid.Health <= 0 then return end

		local playerData = GameState.players[player.UserId]
		if not playerData or not playerData.isAlive then return end

		-- Play lava hiss sound
		if lavaInstance then
			local ssshTemplate = lavaInstance:FindFirstChild("Sssh")
			if ssshTemplate then
				local snd = ssshTemplate:Clone()
				snd.Parent = hit
				snd.PlaybackSpeed = math.random(80, 150) / 100
				snd:Play()
				Debris:AddItem(snd, 2)
			end
		end

		RoundSystem.DamagePlayer(player, 0)
		return
	end

	-- Non-player object touched lava — apply black dissolve effect
	-- Walk up to find the top-level object, but stop at Folders (like Arena)
	local obj = hit
	while obj.Parent and obj.Parent ~= Workspace and not obj.Parent:IsA("Folder") do
		obj = obj.Parent :: Instance
	end

	-- Skip the lava itself
	if obj == lavaInstance then return end

	ApplyLavaDissolve(obj)
end

-- ============================================================
-- Lava texture animation (replaces the original Animation script)
-- ============================================================

local function AnimateLavaTexture(lava: BasePart)
	local texture = lava:FindFirstChild("Texture")
	if not texture then return end

	while active and lava.Parent do
		local waitX = math.random(10, 30)
		local waitY = math.random(10, 30)
		local offsetX = math.random(-80, 80) / 10
		local offsetY = math.random(-80, 80) / 10
		local waitTime = math.max(waitX, waitY)

		TweenService:Create(texture, TweenInfo.new(waitX, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
			OffsetStudsU = offsetX,
		}):Play()
		TweenService:Create(texture, TweenInfo.new(waitY, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
			OffsetStudsV = offsetY,
		}):Play()

		task.wait(waitTime - 0.1)
	end
end

-- ============================================================
-- Safety heartbeat — kill players who somehow fall past the lava
-- ============================================================

local function OnHeartbeat()
	if not active then return end
	-- Only kill players during active gameplay (not during countdown/preparing)
	if GameState.currentState ~= Constants.STATES.PLAYING then return end

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if not character then continue end

		local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then continue end

		if hrp.Position.Y < fallKillY then
			local playerData = GameState.players[player.UserId]
			if playerData and playerData.isAlive then
					RoundSystem.DamagePlayer(player, 0)
			end
		end
	end
end

-- ============================================================
-- Ring dropping loop
-- ============================================================

local function RingLoop()
	local maxRing = GetMaxRing()

	task.wait(FIRST_RING_DELAY)

	for ring = 0, maxRing do
		if not active then return end

		-- Drop every tile in this ring concurrently
		local tiles = GetTilesInRing(ring)
		for _, pos in ipairs(tiles) do
			task.spawn(DropTile, pos.x, pos.y)
		end

		if ring < maxRing then
			task.wait(RING_INTERVAL)
		end
	end
end

-- ============================================================
-- Start / Stop
-- ============================================================

function FallingTilesService.Start()
	FallingTilesService.Stop()
	FallingTilesService.Cleanup()
	active = true

	-- Disable Canvas collision — floor tiles are the real walkable surface
	local canvas = Workspace:FindFirstChild("Canvas") :: BasePart?
	if canvas then
		canvas.CanCollide = false
		fallKillY = canvas.Position.Y - 40
	end

	-- Clone Lava from ReplicatedStorage > Assets > Misc
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local miscFolder = assetsFolder and assetsFolder:FindFirstChild("Misc")
	local lavaTemplate = miscFolder and miscFolder:FindFirstChild("Lava")

	if lavaTemplate and canvas then
		local lava = lavaTemplate:Clone()

		-- Remove any scripts — we handle all logic here
		for _, child in ipairs(lava:GetChildren()) do
			if child:IsA("Script") or child:IsA("LocalScript") then
				child:Destroy()
			end
		end

		-- Start lava below its final position so it slides up
		if lava:IsA("BasePart") then
			lava.CFrame = lava.CFrame - Vector3.new(0, WATER_SLIDE_DISTANCE, 0)
		elseif lava:IsA("Model") and lava.PrimaryPart then
			lava:PivotTo(lava:GetPivot() - Vector3.new(0, WATER_SLIDE_DISTANCE, 0))
		end

		-- Parent to Workspace
		lava.Parent = Workspace
		lavaInstance = lava

		-- Connect Touched for kills
		if lava:IsA("BasePart") then
			table.insert(lavaConnections, lava.Touched:Connect(OnLavaTouched))
		end
		-- Also connect any child BaseParts (lava mesh pieces)
		for _, desc in ipairs(lava:GetDescendants()) do
			if desc:IsA("BasePart") then
				table.insert(lavaConnections, desc.Touched:Connect(OnLavaTouched))
			end
		end

		-- Start lava texture animation
		if lava:IsA("BasePart") then
			task.spawn(AnimateLavaTexture, lava)
		end

		-- Slide lava UP into position
		if lava:IsA("BasePart") then
			TweenService:Create(lava, TweenInfo.new(WATER_SLIDE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
				CFrame = lava.CFrame + Vector3.new(0, WATER_SLIDE_DISTANCE, 0),
			}):Play()
		end
	end

	-- Slide water DOWN out of view
	local waterModel = Workspace:FindFirstChild("Water") :: Model?
	if waterModel and waterModel.PrimaryPart then
		if not waterOriginalCFrame then
			waterOriginalCFrame = waterModel:GetPivot()
		end
		local targetPivot = waterModel:GetPivot() - Vector3.new(0, WATER_SLIDE_DISTANCE, 0)
		TweenService:Create(waterModel.PrimaryPart, TweenInfo.new(WATER_SLIDE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
			CFrame = waterModel.PrimaryPart.CFrame - Vector3.new(0, WATER_SLIDE_DISTANCE, 0),
		}):Play()
		-- Also move non-primary parts that are welded via PivotTo after tween
		task.delay(WATER_SLIDE_DURATION, function()
			if waterModel and waterModel.Parent then
				waterModel:PivotTo(targetPivot)
			end
		end)
	end

	-- Safety heartbeat
	heartbeatConnection = RunService.Heartbeat:Connect(OnHeartbeat)

	-- Start ring-by-ring collapse
	task.spawn(RingLoop)
end

-- Stop the falling tiles mechanic (ring loop + heartbeat) but keep lava visible
function FallingTilesService.Stop()
	active = false

	-- Disconnect lava kill events
	for _, conn in ipairs(lavaConnections) do
		conn:Disconnect()
	end
	lavaConnections = {}

	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
end

-- Full cleanup — destroy lava, restore water, restore Canvas collision
-- Call this AFTER players have been teleported back to lobby
function FallingTilesService.Cleanup()
	-- Remove lava from workspace
	if lavaInstance and lavaInstance.Parent then
		lavaInstance:Destroy()
	end
	lavaInstance = nil

	-- Slide water back UP to its original position
	local waterModel = Workspace:FindFirstChild("Water") :: Model?
	if waterModel and waterModel.PrimaryPart and waterOriginalCFrame then
		local currentPivot = waterModel:GetPivot()
		local targetPivot = waterOriginalCFrame

		-- Only animate if it's actually displaced
		if (currentPivot.Position - targetPivot.Position).Magnitude > 1 then
			TweenService:Create(waterModel.PrimaryPart, TweenInfo.new(WATER_SLIDE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
				CFrame = waterModel.PrimaryPart.CFrame + Vector3.new(0, targetPivot.Position.Y - currentPivot.Position.Y, 0),
			}):Play()
			task.delay(WATER_SLIDE_DURATION, function()
				if waterModel and waterModel.Parent then
					waterModel:PivotTo(targetPivot)
				end
			end)
		end
	end

	-- Restore Canvas collision
	local canvas = Workspace:FindFirstChild("Canvas") :: BasePart?
	if canvas then
		canvas.CanCollide = true
	end
end

function FallingTilesService.HasTileFallen(gridX: number, gridY: number): boolean
	local arena = Workspace:FindFirstChild("Arena")
	if not arena then return true end
	return arena:FindFirstChild("FloorTile_" .. gridX .. "_" .. gridY) == nil
end

return FallingTilesService
