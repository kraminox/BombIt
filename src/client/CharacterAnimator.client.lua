--!strict
-- CharacterAnimator.client.lua
-- Handles movement animations (input-driven, instant response) and emote input
-- Hold bomb animations are handled server-side by AnimationService

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlayEmote = Remotes:WaitForChild("PlayEmote")

-- Animation IDs
local ANIMATION_IDS = {
	run = "rbxassetid://132677938126739",
	idle = "rbxassetid://93531440131609",
}

local WALK_SPEED_SCALE = 0.75
local IDLE_SPEED_SCALE = 0.5

-- Animation state
local animator: Animator? = nil
local tracks: {[string]: AnimationTrack} = {}
local currentMovementTrack: AnimationTrack? = nil
local isCustomCharacter = false
local isMoving = false

-- Movement key tracking (mirrors LocalPlayer.client.lua)
local movementKeys = {
	[Enum.KeyCode.W] = true, [Enum.KeyCode.Up] = true,
	[Enum.KeyCode.S] = true, [Enum.KeyCode.Down] = true,
	[Enum.KeyCode.A] = true, [Enum.KeyCode.Left] = true,
	[Enum.KeyCode.D] = true, [Enum.KeyCode.Right] = true,
}
local heldMoveKeys = 0

-- Track movement key presses
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if movementKeys[input.KeyCode] then
		heldMoveKeys = heldMoveKeys + 1
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if movementKeys[input.KeyCode] then
		heldMoveKeys = math.max(0, heldMoveKeys - 1)
	end
end)

-- Load animations for character
local function LoadAnimations(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 3) :: Humanoid?
	end
	if not humanoid then return end

	local animSaves = character:FindFirstChild("AnimSaves")
	if not animSaves then
		isCustomCharacter = false
		return
	end

	isCustomCharacter = true
	heldMoveKeys = 0

	-- Get Animator (server creates it via AnimationService)
	animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		-- Wait briefly for server to create it
		task.wait(0.3)
		animator = humanoid:FindFirstChildOfClass("Animator")
	end
	if not animator then return end

	-- Clear old tracks
	tracks = {}
	currentMovementTrack = nil

	-- Load movement animations
	for name, animId in pairs(ANIMATION_IDS) do
		local animation = Instance.new("Animation")
		animation.AnimationId = animId

		local success, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)

		if success and track then
			tracks[name] = track
			track.Looped = true
			track.Priority = Enum.AnimationPriority.Movement
		end
	end

	-- Start idle
	local idleTrack = tracks["idle"]
	if idleTrack then
		idleTrack:Play(0)
		idleTrack:AdjustSpeed(IDLE_SPEED_SCALE)
	end
end

-- Update loop - driven by input, not velocity
RunService:BindToRenderStep("CharacterAnimations", Enum.RenderPriority.Input.Value + 1, function()
	if not isCustomCharacter then return end

	local character = player.Character
	if not character then return end

	local nowMoving = heldMoveKeys > 0

	if nowMoving and not isMoving then
		-- Started moving
		isMoving = true
		local idleTrack = tracks["idle"]
		if idleTrack and idleTrack.IsPlaying then
			idleTrack:Stop(0.1)
		end
		local runTrack = tracks["run"]
		if runTrack then
			runTrack:Play(0.1)
			currentMovementTrack = runTrack
		end
	elseif not nowMoving and isMoving then
		-- Stopped moving
		isMoving = false
		if currentMovementTrack and currentMovementTrack.IsPlaying then
			currentMovementTrack:Stop(0.1)
			currentMovementTrack = nil
		end
		local idleTrack = tracks["idle"]
		if idleTrack and not idleTrack.IsPlaying then
			idleTrack:Play(0)
			idleTrack:AdjustSpeed(IDLE_SPEED_SCALE)
		end
	end

	-- Adjust run speed based on actual velocity
	if isMoving and currentMovementTrack then
		local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			local vel = hrp.AssemblyLinearVelocity
			local hSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
			if hSpeed > 14 then
				currentMovementTrack:AdjustSpeed(1)
			else
				currentMovementTrack:AdjustSpeed(WALK_SPEED_SCALE)
			end
		end
	end
end)

-- Character added
local function OnCharacterAdded(character: Model)
	task.wait(0.3)
	LoadAnimations(character)
end

player.CharacterAdded:Connect(OnCharacterAdded)
if player.Character then
	OnCharacterAdded(player.Character)
end

-- Emote input (number keys 1-4)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.One then
		PlayEmote:FireServer("wave")
	elseif input.KeyCode == Enum.KeyCode.Two then
		PlayEmote:FireServer("point")
	elseif input.KeyCode == Enum.KeyCode.Three then
		PlayEmote:FireServer("laugh")
	elseif input.KeyCode == Enum.KeyCode.Four then
		PlayEmote:FireServer("happyjumps")
	end
end)

-- Fix Highlight visibility through walls
local function FixHighlightDepthMode()
	local function setOccluded(highlight: Highlight)
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	end

	local Assets = ReplicatedStorage:FindFirstChild("Assets")
	if Assets then
		for _, desc in ipairs(Assets:GetDescendants()) do
			if desc:IsA("Highlight") then
				setOccluded(desc)
			end
		end
	end

	for _, desc in ipairs(game.Workspace:GetDescendants()) do
		if desc:IsA("Highlight") then
			setOccluded(desc)
		end
	end

	game.Workspace.DescendantAdded:Connect(function(desc)
		if desc:IsA("Highlight") then
			setOccluded(desc)
		end
	end)
end

FixHighlightDepthMode()

print("[CharacterAnimator] Initialized (movement: client, hold bomb: server)")
