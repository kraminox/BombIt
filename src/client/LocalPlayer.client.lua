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

	-- Check if we should use fixed grid movement (during gameplay with overhead camera)
	local useFixedMovement = (currentGameState == Constants.STATES.PLAYING or currentGameState == Constants.STATES.COUNTDOWN)

	if useFixedMovement then
		-- Fixed directions for overhead camera (camera looking from +Z toward -Z)
		-- W = up on screen (-Z), S = down (+Z), A = left (-X), D = right (+X)
		if activeInputs.forward then
			dir = dir + Vector3.new(0, 0, -1)
		end
		if activeInputs.backward then
			dir = dir + Vector3.new(0, 0, 1)
		end
		if activeInputs.left then
			dir = dir + Vector3.new(-1, 0, 0)
		end
		if activeInputs.right then
			dir = dir + Vector3.new(1, 0, 0)
		end
	else
		-- Camera-relative movement (free movement in lobby)
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

	-- Smooth velocity-based movement
	local speed = localPlayerData.speed
	local currentVel = hrp.AssemblyLinearVelocity
	local currentHorizontal = Vector3.new(currentVel.X, 0, currentVel.Z)

	if moveDirection.Magnitude > 0 then
		local targetVelocity = moveDirection * speed

		-- Smooth interpolation for fluid movement (0.25 = responsive but smooth)
		local smoothedVelocity = currentHorizontal:Lerp(targetVelocity, 0.25)
		hrp.AssemblyLinearVelocity = Vector3.new(smoothedVelocity.X, currentVel.Y, smoothedVelocity.Z)
	else
		-- Smooth deceleration when stopping (0.2 = quick but not instant)
		local smoothedVelocity = currentHorizontal:Lerp(Vector3.zero, 0.2)
		hrp.AssemblyLinearVelocity = Vector3.new(smoothedVelocity.X, currentVel.Y, smoothedVelocity.Z)
	end
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

-- Mobile controls will be handled by GameUI
print("[LocalPlayer] Input handling initialized")
