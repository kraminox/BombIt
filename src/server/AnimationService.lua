--!strict
-- AnimationService.lua
-- Server-side: hold bomb animation + visibility (replicates to all clients)
-- Movement animations (run/idle) are handled client-side for instant input response

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local GameState = require(Shared:WaitForChild("GameState"))

local AnimationService = {}

local HOLDBOMB_ANIM_ID = "rbxassetid://75397675845790"

-- Per-character state
type CharacterState = {
	animator: Animator,
	holdBombTrack: AnimationTrack?,
	isHoldingBomb: boolean,
	character: Model,
}

local characterStates: {[Model]: CharacterState} = {}

-- Set up hold bomb animation for a character (call after character is parented to Workspace)
function AnimationService.SetupCharacter(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local animSaves = character:FindFirstChild("AnimSaves")
	if not animSaves then return end

	-- Get or create Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- Load hold bomb animation
	local animation = Instance.new("Animation")
	animation.AnimationId = HOLDBOMB_ANIM_ID

	local holdBombTrack: AnimationTrack? = nil
	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if success and track then
		holdBombTrack = track
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Action2
	else
		warn("[AnimationService] Failed to load holdbomb for", character.Name)
	end

	characterStates[character] = {
		animator = animator,
		holdBombTrack = holdBombTrack,
		isHoldingBomb = false,
		character = character,
	}

	print("[AnimationService] Set up hold bomb for", character.Name)
end

-- Remove tracking when character is removed
function AnimationService.CleanupCharacter(character: Model)
	local state = characterStates[character]
	if state then
		if state.holdBombTrack and state.holdBombTrack.IsPlaying then
			state.holdBombTrack:Stop(0)
		end
		characterStates[character] = nil
	end
end

-- Update held bomb visibility and animation for a character
function AnimationService.UpdateHoldBomb(character: Model, hasBombsAvailable: boolean)
	local state = characterStates[character]
	if not state then return end

	local heldBomb = character:FindFirstChild("HeldBomb")

	if hasBombsAvailable and not state.isHoldingBomb then
		state.isHoldingBomb = true
		if heldBomb then
			for _, part in ipairs(heldBomb:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Transparency = 0
				elseif part:IsA("ParticleEmitter") then
					part.Enabled = true
				elseif part:IsA("PointLight") then
					part.Enabled = true
				end
			end
		end
		if state.holdBombTrack and not state.holdBombTrack.IsPlaying then
			state.holdBombTrack:Play(0.2)
		end
	elseif not hasBombsAvailable and state.isHoldingBomb then
		state.isHoldingBomb = false
		if heldBomb then
			for _, part in ipairs(heldBomb:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Transparency = 1
				elseif part:IsA("ParticleEmitter") then
					part.Enabled = false
				elseif part:IsA("PointLight") then
					part.Enabled = false
				end
			end
		end
		if state.holdBombTrack and state.holdBombTrack.IsPlaying then
			state.holdBombTrack:Stop(0.2)
		end
	end
end

-- Heartbeat: poll GameState to update hold bomb state for all characters
function AnimationService.Initialize()
	RunService.Heartbeat:Connect(function()
		for character, state in pairs(characterStates) do
			if not character.Parent then
				characterStates[character] = nil
				continue
			end

			local ownerPlayer = Players:GetPlayerFromCharacter(character)
			if ownerPlayer then
				local playerData = GameState.players[ownerPlayer.UserId]
				if playerData then
					local hasBombs = (playerData.bombCount - playerData.activeBombs) > 0
					AnimationService.UpdateHoldBomb(character, hasBombs)
				end
			end
		end
	end)

	print("[AnimationService] Initialized")
end

return AnimationService
