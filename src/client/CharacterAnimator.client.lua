--!strict
-- CharacterAnimator.client.lua
-- Handles custom character animations during gameplay

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

-- Wait for remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged")
local SyncPlayerData = Remotes:WaitForChild("SyncPlayerData")

-- Animation IDs
local ANIMATION_IDS = {
	walk = "rbxassetid://78369850475829",
	run = "rbxassetid://103654213982556",
	point = "rbxassetid://96368497783501",
	wave = "rbxassetid://92902913680678",
	laugh = "rbxassetid://121612398032869",
	jump = "rbxassetid://117983273406091",
	holdbomb = "rbxassetid://132661114390349",
}

-- Animation state
local animator: Animator? = nil
local tracks: {[string]: AnimationTrack} = {}
local currentMovementTrack: AnimationTrack? = nil
local currentEmoteTrack: AnimationTrack? = nil
local isCustomCharacter = false

-- Bomb holding state
local heldBombModel: Model? = nil
local isHoldingBomb = false
local bombCount = 1
local activeBombs = 0

-- Find the server-created held bomb on character
local function FindHeldBomb(character: Model): Model?
	return character:FindFirstChild("HeldBomb")
end

-- Show/hide the held bomb
local function SetBombVisible(visible: boolean)
	if heldBombModel then
		for _, part in ipairs(heldBombModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Transparency = visible and 0 or 1
			elseif part:IsA("ParticleEmitter") then
				part.Enabled = visible
			elseif part:IsA("PointLight") then
				part.Enabled = visible
			end
		end
	end
end

-- Update hold bomb state based on available bombs
local function UpdateHoldBombState()
	if not isCustomCharacter then return end

	local hasBombsAvailable = (bombCount - activeBombs) > 0

	if hasBombsAvailable and not isHoldingBomb then
		-- Start holding bomb
		isHoldingBomb = true
		SetBombVisible(true)

		local track = tracks["holdbomb"]
		if track and not track.IsPlaying then
			track:Play(0.2)
		end
	elseif not hasBombsAvailable and isHoldingBomb then
		-- Stop holding bomb
		isHoldingBomb = false
		SetBombVisible(false)

		local track = tracks["holdbomb"]
		if track and track.IsPlaying then
			track:Stop(0.2)
		end
	end
end

-- Load animations for character
local function LoadAnimations(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Check if this is a custom character (has AnimSaves folder)
	local animSaves = character:FindFirstChild("AnimSaves")
	if not animSaves then
		isCustomCharacter = false
		print("[CharacterAnimator] No AnimSaves found, using default animations")
		return
	end

	isCustomCharacter = true
	isHoldingBomb = false
	print("[CharacterAnimator] Custom character detected, loading animations...")

	-- Get or create Animator
	animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- Clear old tracks
	tracks = {}
	currentMovementTrack = nil
	currentEmoteTrack = nil

	-- Create and load animations
	for name, animId in pairs(ANIMATION_IDS) do
		local animation = Instance.new("Animation")
		animation.AnimationId = animId

		local success, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)

		if success and track then
			tracks[name] = track

			-- Configure animation properties
			if name == "walk" or name == "run" then
				track.Looped = true
				track.Priority = Enum.AnimationPriority.Movement
			elseif name == "holdbomb" then
				track.Looped = true
				track.Priority = Enum.AnimationPriority.Action
			else
				-- Emotes
				track.Looped = false
				track.Priority = Enum.AnimationPriority.Action4
			end

			print("[CharacterAnimator] Loaded animation:", name)
		else
			warn("[CharacterAnimator] Failed to load animation:", name)
		end
	end

	-- Find server-created held bomb model
	heldBombModel = FindHeldBomb(character)

	-- Bomb visibility is handled by server, just track reference
	-- Check initial bomb state
	UpdateHoldBombState()
end

-- Play movement animation
local function PlayMovementAnimation(name: string)
	if not isCustomCharacter then return end

	local track = tracks[name]
	if not track then
		print("[CharacterAnimator] No track found for:", name)
		return
	end

	-- Don't restart if already playing
	if currentMovementTrack == track and track.IsPlaying then return end

	-- Stop current movement animation
	if currentMovementTrack and currentMovementTrack ~= track then
		currentMovementTrack:Stop(0.2)
	end

	print("[CharacterAnimator] Playing animation:", name)
	track:Play(0.2)
	currentMovementTrack = track
end

-- Play emote animation
local function PlayEmote(name: string)
	if not isCustomCharacter then return end

	local track = tracks[name]
	if not track then return end

	-- Stop current emote if playing
	if currentEmoteTrack and currentEmoteTrack.IsPlaying then
		currentEmoteTrack:Stop(0.1)
	end

	track:Play(0.1)
	currentEmoteTrack = track
end

-- Update animation based on movement
local function UpdateAnimations()
	if not isCustomCharacter then return end

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Check movement speed
	local velocity = hrp.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	if horizontalSpeed > 1.5 then
		-- Moving - higher threshold to stop animation sooner
		if horizontalSpeed > 14 and tracks["run"] then
			PlayMovementAnimation("run")
		else
			PlayMovementAnimation("walk")
		end
	else
		-- Stopped - stop movement animations immediately
		if currentMovementTrack and currentMovementTrack.IsPlaying then
			currentMovementTrack:Stop(0.05) -- Very fast fade out
			currentMovementTrack = nil
		end
	end
end

-- Handle player data sync from server
SyncPlayerData.OnClientEvent:Connect(function(data)
	if data then
		bombCount = data.bombCount or 1
		activeBombs = data.activeBombs or 0
		UpdateHoldBombState()
	end
end)

-- Character added
local function OnCharacterAdded(character: Model)
	-- Wait for character to load
	task.wait(0.2)
	print("[CharacterAnimator] Character added:", character.Name)
	print("[CharacterAnimator] Character children:")
	for _, child in ipairs(character:GetChildren()) do
		print("  -", child.Name, child.ClassName)
	end
	LoadAnimations(character)
end

-- Connect events
player.CharacterAdded:Connect(OnCharacterAdded)

-- Check existing character
if player.Character then
	OnCharacterAdded(player.Character)
end

-- Emote input handling (number keys 1-4 for emotes)
local UserInputService = game:GetService("UserInputService")

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if not isCustomCharacter then return end

	-- Emote keys
	if input.KeyCode == Enum.KeyCode.One then
		PlayEmote("wave")
	elseif input.KeyCode == Enum.KeyCode.Two then
		PlayEmote("point")
	elseif input.KeyCode == Enum.KeyCode.Three then
		PlayEmote("laugh")
	elseif input.KeyCode == Enum.KeyCode.Four then
		PlayEmote("jump")
	end
end)

-- Update loop
RunService.Heartbeat:Connect(UpdateAnimations)

-- Fix Highlight visibility through walls
local function FixHighlightDepthMode()
	local function setOccluded(highlight: Highlight)
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	end

	-- Fix highlights in ReplicatedStorage/Assets
	local Assets = ReplicatedStorage:FindFirstChild("Assets")
	if Assets then
		for _, desc in ipairs(Assets:GetDescendants()) do
			if desc:IsA("Highlight") then
				setOccluded(desc)
			end
		end
	end

	-- Fix highlights in Workspace
	for _, desc in ipairs(game.Workspace:GetDescendants()) do
		if desc:IsA("Highlight") then
			setOccluded(desc)
		end
	end

	-- Listen for new highlights
	game.Workspace.DescendantAdded:Connect(function(desc)
		if desc:IsA("Highlight") then
			setOccluded(desc)
		end
	end)
end

FixHighlightDepthMode()

print("[CharacterAnimator] Initialized with custom animations")
