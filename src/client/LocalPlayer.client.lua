--!strict
-- LocalPlayer.client.lua
-- Handles local player movement input and state

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

-- Wait for remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlaceBomb = Remotes:WaitForChild("PlaceBomb")
local SyncPlayerData = Remotes:WaitForChild("SyncPlayerData")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged")

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

-- Shared modules
local MapData = require(Shared:WaitForChild("MapData"))

-- Initialize grid CFrame from Canvas (client-side)
local function InitializeGridFromCanvas()
	local canvasPart = Workspace:FindFirstChild("Canvas") :: BasePart?
	if canvasPart then
		local canvasCFrame = canvasPart.CFrame
		local canvasSize = canvasPart.Size

		-- Grid origin is at corner of canvas in local space, then transformed to world space
		local localCorner = Vector3.new(-canvasSize.X / 2, canvasSize.Y / 2, -canvasSize.Z / 2)
		local worldCorner = canvasCFrame:PointToWorldSpace(localCorner)

		-- Create the grid CFrame: position at corner, rotation from canvas
		local gridCFrame = CFrame.new(worldCorner) * (canvasCFrame - canvasCFrame.Position)
		MapData.SetGridCFrame(gridCFrame)
		print("[LocalPlayer] Initialized grid CFrame from Canvas")
	else
		warn("[LocalPlayer] Canvas not found, grid rotation may be incorrect")
	end
end

-- Initialize grid on load
InitializeGridFromCanvas()

-- Current game state
local currentGameState = Constants.STATES.LOBBY

-- Local player data (synced from server)
local localPlayerData = {
	bombCount = Constants.MAX_BOMBS_DEFAULT,
	bombRange = Constants.BOMB_DEFAULT_RANGE,
	speed = Constants.MOVE_SPEED,
	lives = Constants.PLAYER_LIVES_DEFAULT,
	coins = 0,
	isAlive = true,
	activeBombs = 0,
}

-- Movement state
local moveDirection = Vector3.zero

-- Bomb placement indicator
local placementIndicator: Part? = nil

local function CreatePlacementIndicator(): Part
	local indicator = Instance.new("Part")
	indicator.Name = "BombPlacementIndicator"
	indicator.Size = Vector3.new(Constants.TILE_SIZE - 0.2, 0.1, Constants.TILE_SIZE - 0.2)
	indicator.Color = Color3.fromRGB(100, 200, 255) -- Light blue
	indicator.Material = Enum.Material.Neon
	indicator.Transparency = 0.5
	indicator.Anchored = true
	indicator.CanCollide = false
	indicator.CastShadow = false
	indicator.Parent = Workspace

	-- Pulsing animation
	task.spawn(function()
		while indicator and indicator.Parent do
			TweenService:Create(indicator, TweenInfo.new(0.4), {Transparency = 0.3}):Play()
			task.wait(0.4)
			if not indicator or not indicator.Parent then break end
			TweenService:Create(indicator, TweenInfo.new(0.4), {Transparency = 0.7}):Play()
			task.wait(0.4)
		end
	end)

	return indicator
end

local function UpdatePlacementIndicator()
	-- Only show during gameplay when player can place bombs
	local shouldShow = (currentGameState == Constants.STATES.PLAYING)
		and localPlayerData.isAlive
		and (localPlayerData.activeBombs < localPlayerData.bombCount)

	if not shouldShow then
		if placementIndicator then
			placementIndicator.Parent = nil
		end
		return
	end

	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Get grid position
	local gridX, gridY = MapData.WorldToGrid(hrp.Position)
	local tileCFrame = MapData.GridToCFrame(gridX, gridY)

	-- Create indicator if needed
	if not placementIndicator then
		placementIndicator = CreatePlacementIndicator()
	end

	-- Update position with rotation to match grid
	placementIndicator.CFrame = tileCFrame * CFrame.new(0, 0.15, 0)
	placementIndicator.Parent = Workspace
end

-- Input handling
local inputKeys = {
	forward = {Enum.KeyCode.W, Enum.KeyCode.Up},
	backward = {Enum.KeyCode.S, Enum.KeyCode.Down},
	left = {Enum.KeyCode.A, Enum.KeyCode.Left},
	right = {Enum.KeyCode.D, Enum.KeyCode.Right},
	bomb = {Enum.KeyCode.Space},
}

local activeInputs = {
	forward = false,
	backward = false,
	left = false,
	right = false,
}

-- Check if a key matches input type
local function IsKeyForInput(keyCode: Enum.KeyCode, inputType: string): boolean
	local keys = inputKeys[inputType]
	if not keys then return false end

	for _, key in ipairs(keys) do
		if key == keyCode then
			return true
		end
	end
	return false
end

-- Handle input began
local function OnInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end

	local keyCode = input.KeyCode

	-- Movement
	if IsKeyForInput(keyCode, "forward") then
		activeInputs.forward = true
	elseif IsKeyForInput(keyCode, "backward") then
		activeInputs.backward = true
	elseif IsKeyForInput(keyCode, "left") then
		activeInputs.left = true
	elseif IsKeyForInput(keyCode, "right") then
		activeInputs.right = true
	end

	-- Bomb placement - only during gameplay
	if IsKeyForInput(keyCode, "bomb") then
		if currentGameState == Constants.STATES.PLAYING then
			PlaceBomb:FireServer()
		end
	end

	-- Gamepad
	if input.KeyCode == Enum.KeyCode.ButtonB then
		if currentGameState == Constants.STATES.PLAYING then
			PlaceBomb:FireServer()
		end
	end
end

-- Handle input ended
local function OnInputEnded(input: InputObject, gameProcessed: boolean)
	local keyCode = input.KeyCode

	if IsKeyForInput(keyCode, "forward") then
		activeInputs.forward = false
	elseif IsKeyForInput(keyCode, "backward") then
		activeInputs.backward = false
	elseif IsKeyForInput(keyCode, "left") then
		activeInputs.left = false
	elseif IsKeyForInput(keyCode, "right") then
		activeInputs.right = false
	end
end

-- Calculate movement direction based on inputs
local function CalculateMoveDirection(): Vector3
	local dir = Vector3.zero

	-- Always use camera-relative movement so WASD matches what you see on screen
	local camera = workspace.CurrentCamera
	if camera then
		local camCFrame = camera.CFrame
		local forward = Vector3.new(camCFrame.LookVector.X, 0, camCFrame.LookVector.Z)
		local right = Vector3.new(camCFrame.RightVector.X, 0, camCFrame.RightVector.Z)

		if forward.Magnitude > 0 then forward = forward.Unit end
		if right.Magnitude > 0 then right = right.Unit end

		if activeInputs.forward then
			dir = dir + forward
		end
		if activeInputs.backward then
			dir = dir - forward
		end
		if activeInputs.left then
			dir = dir - right
		end
		if activeInputs.right then
			dir = dir + right
		end
	end

	-- Normalize if moving diagonally
	if dir.Magnitude > 0 then
		dir = dir.Unit
	end

	return dir
end

-- Check if using custom character (has AnimSaves)
local function IsCustomCharacter(): boolean
	local character = player.Character
	if not character then return false end
	return character:FindFirstChild("AnimSaves") ~= nil
end

-- Update loop
local function OnUpdate(deltaTime: number)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart

	if not humanoid or not hrp then return end
	if not localPlayerData.isAlive then return end

	-- Calculate movement
	moveDirection = CalculateMoveDirection()

	-- Apply movement speed
	humanoid.WalkSpeed = localPlayerData.speed

	-- Check if custom character needs rotation offset
	local isCustom = IsCustomCharacter()

	if isCustom then
		-- Custom character: disable auto-rotate and manually set rotation with offset
		humanoid.AutoRotate = false

		if moveDirection.Magnitude > 0 then
			-- Calculate target rotation (negate X and subtract 90 degrees for model orientation)
			local targetAngle = math.atan2(-moveDirection.X, -moveDirection.Z) - math.rad(90)
			local currentCFrame = hrp.CFrame
			local targetCFrame = CFrame.new(currentCFrame.Position) * CFrame.Angles(0, targetAngle, 0)

			-- Instant rotation for responsive feel
			hrp.CFrame = targetCFrame
		end
	else
		-- Default character: let Roblox handle rotation
		humanoid.AutoRotate = true
	end

	-- Smooth velocity-based movement (only affects horizontal, preserves gravity)
	local speed = localPlayerData.speed
	local currentVel = hrp.AssemblyLinearVelocity
	local currentHorizontal = Vector3.new(currentVel.X, 0, currentVel.Z)

	if moveDirection.Magnitude > 0 then
		local targetVelocity = moveDirection * speed
		-- Instant start, keep vertical velocity for gravity
		hrp.AssemblyLinearVelocity = Vector3.new(targetVelocity.X, currentVel.Y, targetVelocity.Z)
	else
		-- Smooth deceleration when stopping
		local smoothedVelocity = currentHorizontal:Lerp(Vector3.zero, 0.15)
		hrp.AssemblyLinearVelocity = Vector3.new(smoothedVelocity.X, currentVel.Y, smoothedVelocity.Z)
	end

	-- Update bomb placement indicator
	UpdatePlacementIndicator()
end

-- Handle server data sync
SyncPlayerData.OnClientEvent:Connect(function(data)
	if data then
		localPlayerData.bombCount = data.bombCount or Constants.MAX_BOMBS_DEFAULT
		localPlayerData.bombRange = data.bombRange or Constants.BOMB_DEFAULT_RANGE
		localPlayerData.speed = data.speed or Constants.MOVE_SPEED
		localPlayerData.lives = data.lives or Constants.PLAYER_LIVES_DEFAULT
		localPlayerData.coins = data.coins or 0
		localPlayerData.isAlive = data.isAlive ~= false
		localPlayerData.activeBombs = data.activeBombs or 0
	end
end)

-- Create shared data folder for other scripts to read player data
local PlayerDataFolder = Instance.new("Folder")
PlayerDataFolder.Name = "LocalPlayerDataStore"
PlayerDataFolder.Parent = player

local function StoreValue(name: string, value: any)
	local existing = PlayerDataFolder:FindFirstChild(name)
	if existing then
		existing.Value = value
	else
		local valueObj
		if type(value) == "number" then
			valueObj = Instance.new("NumberValue")
		elseif type(value) == "boolean" then
			valueObj = Instance.new("BoolValue")
		else
			return
		end
		valueObj.Name = name
		valueObj.Value = value
		valueObj.Parent = PlayerDataFolder
	end
end

-- Update stored values on sync
SyncPlayerData.OnClientEvent:Connect(function(data)
	if data then
		StoreValue("BombCount", data.bombCount or 1)
		StoreValue("BombRange", data.bombRange or 2)
		StoreValue("Speed", data.speed or 12)
		StoreValue("Lives", data.lives or 1)
		StoreValue("Coins", data.coins or 0)
		StoreValue("IsAlive", data.isAlive ~= false)
		StoreValue("ActiveBombs", data.activeBombs or 0)
	end
end)

-- Initial values
StoreValue("BombCount", localPlayerData.bombCount)
StoreValue("BombRange", localPlayerData.bombRange)
StoreValue("Speed", localPlayerData.speed)
StoreValue("Lives", localPlayerData.lives)
StoreValue("Coins", localPlayerData.coins)
StoreValue("IsAlive", localPlayerData.isAlive)
StoreValue("ActiveBombs", localPlayerData.activeBombs)

-- Disable/enable jumping based on game state
local function SetJumpEnabled(enabled: boolean)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
	if humanoid then
		if enabled then
			humanoid.JumpPower = 50 -- Default jump power
			humanoid.JumpHeight = 7.2 -- Default jump height
		else
			humanoid.JumpPower = 0
			humanoid.JumpHeight = 0
		end
	end
end

-- Listen for game state changes
RoundStateChanged.OnClientEvent:Connect(function(state: string, data: any?)
	if type(state) == "string" and Constants.STATES[state:upper()] then
		currentGameState = state
	elseif state == Constants.STATES.LOBBY or state == Constants.STATES.CHARACTER_SELECT
		or state == Constants.STATES.COUNTDOWN or state == Constants.STATES.PLAYING
		or state == Constants.STATES.ROUND_END or state == Constants.STATES.INTERMISSION then
		currentGameState = state
	end

	-- Disable jumping during gameplay states
	if currentGameState == Constants.STATES.PLAYING or currentGameState == Constants.STATES.COUNTDOWN then
		SetJumpEnabled(false)
	else
		SetJumpEnabled(true)
	end

	-- Hide placement indicator when not playing
	if currentGameState ~= Constants.STATES.PLAYING and placementIndicator then
		placementIndicator.Parent = nil
	end
end)

-- Also disable jump when character spawns during gameplay
player.CharacterAdded:Connect(function(character)
	task.wait(0.1) -- Wait for humanoid
	if currentGameState == Constants.STATES.PLAYING or currentGameState == Constants.STATES.COUNTDOWN then
		SetJumpEnabled(false)
	end
end)

-- Connect events
UserInputService.InputBegan:Connect(OnInputBegan)
UserInputService.InputEnded:Connect(OnInputEnded)
RunService.Heartbeat:Connect(OnUpdate)

-- Danger tiles visibility management
-- Hide danger tiles for players not in the game (dead/spectating)
local function UpdateDangerTilesVisibility()
	local arena = Workspace:FindFirstChild("Arena")
	if not arena then return end

	local dangerFolder = arena:FindFirstChild("DangerTiles")
	if not dangerFolder then return end

	-- Show danger tiles only if player is alive and game is playing
	local shouldShow = localPlayerData.isAlive and
		(currentGameState == Constants.STATES.PLAYING or currentGameState == Constants.STATES.COUNTDOWN)

	for _, tile in ipairs(dangerFolder:GetChildren()) do
		if tile:IsA("BasePart") then
			-- Use LocalTransparencyModifier to hide without affecting server state
			tile.LocalTransparencyModifier = shouldShow and 0 or 1
		end
	end
end

-- Update danger tile visibility when player state changes
SyncPlayerData.OnClientEvent:Connect(function(data)
	if data then
		-- Update visibility after isAlive status change
		task.defer(UpdateDangerTilesVisibility)
	end
end)

-- Update when game state changes
RoundStateChanged.OnClientEvent:Connect(function(state: string, data: any?)
	task.defer(UpdateDangerTilesVisibility)
end)

-- Continuously check for new danger tiles (they're created dynamically)
task.spawn(function()
	while true do
		UpdateDangerTilesVisibility()
		task.wait(0.2)
	end
end)

-- Mobile controls will be handled by GameUI
print("[LocalPlayer] Input handling initialized")
