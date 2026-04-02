--!strict
-- NameplateUI.client.lua
-- Displays player name and power-up stats above character heads

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

-- Track current game state
local currentGameState = Constants.STATES.LOBBY

-- Track nameplates
local nameplates = {} :: {[Player]: BillboardGui}

-- Colors
local NAMEPLATE_BG_COLOR = Color3.fromRGB(30, 30, 40)
local STAT_ICON_COLOR = Color3.fromRGB(255, 255, 255)
local NAME_COLOR = Color3.fromRGB(255, 255, 255)

-- Create nameplate for a character
local function CreateNameplate(targetPlayer: Player, character: Model): BillboardGui?
	local head = character:FindFirstChild("Head")
	if not head then
		-- Try to find any part to attach to
		head = character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")
	end
	if not head then return nil end

	-- Create BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Size = UDim2.new(0, 120, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 3.5, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 50
	billboard.Adornee = head
	billboard.Parent = player.PlayerGui

	-- Background frame
	local bgFrame = Instance.new("Frame")
	bgFrame.Name = "Background"
	bgFrame.Size = UDim2.new(1, 0, 1, 0)
	bgFrame.BackgroundColor3 = NAMEPLATE_BG_COLOR
	bgFrame.BackgroundTransparency = 0.3
	bgFrame.BorderSizePixel = 0
	bgFrame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = bgFrame

	-- Player name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PlayerName"
	nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = targetPlayer.DisplayName
	nameLabel.TextColor3 = NAME_COLOR
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = bgFrame

	-- Stats container
	local statsFrame = Instance.new("Frame")
	statsFrame.Name = "Stats"
	statsFrame.Size = UDim2.new(1, -8, 0.45, 0)
	statsFrame.Position = UDim2.new(0, 4, 0.5, 2)
	statsFrame.BackgroundTransparency = 1
	statsFrame.Parent = bgFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = statsFrame

	-- Helper to create stat display
	local function CreateStatDisplay(name: string, icon: string, initialValue: number): Frame
		local statFrame = Instance.new("Frame")
		statFrame.Name = name
		statFrame.Size = UDim2.new(0, 30, 1, 0)
		statFrame.BackgroundTransparency = 1
		statFrame.Parent = statsFrame

		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "Icon"
		iconLabel.Size = UDim2.new(0.5, 0, 1, 0)
		iconLabel.Position = UDim2.new(0, 0, 0, 0)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Text = icon
		iconLabel.TextColor3 = STAT_ICON_COLOR
		iconLabel.TextScaled = true
		iconLabel.Font = Enum.Font.GothamBold
		iconLabel.Parent = statFrame

		local valueLabel = Instance.new("TextLabel")
		valueLabel.Name = "Value"
		valueLabel.Size = UDim2.new(0.5, 0, 1, 0)
		valueLabel.Position = UDim2.new(0.5, 0, 0, 0)
		valueLabel.BackgroundTransparency = 1
		valueLabel.Text = tostring(initialValue)
		valueLabel.TextColor3 = STAT_ICON_COLOR
		valueLabel.TextScaled = true
		valueLabel.Font = Enum.Font.GothamBold
		valueLabel.Parent = statFrame

		return statFrame
	end

	-- Create stat displays with emoji icons
	-- Bomb icon, Lightning/fire for range, Running shoe for speed
	CreateStatDisplay("BombCount", "💣", Constants.MAX_BOMBS_DEFAULT)
	CreateStatDisplay("BombRange", "⚡", Constants.BOMB_DEFAULT_RANGE)
	CreateStatDisplay("Speed", "👟", Constants.MOVE_SPEED)

	return billboard
end

-- Update nameplate stats from character values
local function UpdateNameplateStats(nameplate: BillboardGui, character: Model)
	local statsFolder = character:FindFirstChild("PlayerStats")
	if not statsFolder then return end

	local bgFrame = nameplate:FindFirstChild("Background")
	if not bgFrame then return end

	local stats = bgFrame:FindFirstChild("Stats")
	if not stats then return end

	-- Update each stat
	local bombCountFrame = stats:FindFirstChild("BombCount")
	if bombCountFrame then
		local valueLabel = bombCountFrame:FindFirstChild("Value")
		local bombCountVal = statsFolder:FindFirstChild("BombCount")
		if valueLabel and bombCountVal then
			valueLabel.Text = tostring(bombCountVal.Value)
		end
	end

	local bombRangeFrame = stats:FindFirstChild("BombRange")
	if bombRangeFrame then
		local valueLabel = bombRangeFrame:FindFirstChild("Value")
		local bombRangeVal = statsFolder:FindFirstChild("BombRange")
		if valueLabel and bombRangeVal then
			valueLabel.Text = tostring(bombRangeVal.Value)
		end
	end

	local speedFrame = stats:FindFirstChild("Speed")
	if speedFrame then
		local valueLabel = speedFrame:FindFirstChild("Value")
		local speedVal = statsFolder:FindFirstChild("Speed")
		if valueLabel and speedVal then
			valueLabel.Text = tostring(speedVal.Value)
		end
	end
end

-- Setup nameplate for a player
local function SetupPlayerNameplate(targetPlayer: Player)
	-- Remove existing nameplate
	if nameplates[targetPlayer] then
		nameplates[targetPlayer]:Destroy()
		nameplates[targetPlayer] = nil
	end

	local character = targetPlayer.Character
	if not character then return end

	-- Only show nameplates during gameplay
	if currentGameState ~= Constants.STATES.PLAYING and currentGameState ~= Constants.STATES.COUNTDOWN then
		return
	end

	local nameplate = CreateNameplate(targetPlayer, character)
	if nameplate then
		nameplates[targetPlayer] = nameplate
	end
end

-- Remove nameplate for a player
local function RemovePlayerNameplate(targetPlayer: Player)
	if nameplates[targetPlayer] then
		nameplates[targetPlayer]:Destroy()
		nameplates[targetPlayer] = nil
	end
end

-- Remove all nameplates
local function RemoveAllNameplates()
	for targetPlayer, nameplate in pairs(nameplates) do
		nameplate:Destroy()
	end
	nameplates = {}
end

-- Setup nameplates for all current players
local function SetupAllNameplates()
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		SetupPlayerNameplate(targetPlayer)
	end
end

-- Handle character added
local function OnCharacterAdded(targetPlayer: Player, character: Model)
	-- Wait for character to fully load
	task.wait(0.5)
	SetupPlayerNameplate(targetPlayer)
end

-- Handle player added
local function OnPlayerAdded(targetPlayer: Player)
	targetPlayer.CharacterAdded:Connect(function(character)
		OnCharacterAdded(targetPlayer, character)
	end)

	if targetPlayer.Character then
		OnCharacterAdded(targetPlayer, targetPlayer.Character)
	end
end

-- Handle player removed
local function OnPlayerRemoved(targetPlayer: Player)
	RemovePlayerNameplate(targetPlayer)
end

-- Handle game state changes
RoundStateChanged.OnClientEvent:Connect(function(state: string, data: any?)
	if type(state) == "string" then
		if state == Constants.STATES.LOBBY or state == Constants.STATES.CHARACTER_SELECT
			or state == Constants.STATES.COUNTDOWN or state == Constants.STATES.PLAYING
			or state == Constants.STATES.ROUND_END or state == Constants.STATES.INTERMISSION then
			currentGameState = state
		end
	end

	-- Show nameplates during gameplay, hide otherwise
	if currentGameState == Constants.STATES.PLAYING or currentGameState == Constants.STATES.COUNTDOWN then
		SetupAllNameplates()
	else
		RemoveAllNameplates()
	end
end)

-- Handle player death - remove their nameplate
local PlayerDied = Remotes:WaitForChild("PlayerDied")
PlayerDied.OnClientEvent:Connect(function(userId: number)
	-- Find the player and remove their nameplate
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer.UserId == userId then
			RemovePlayerNameplate(targetPlayer)
			break
		end
	end
end)

-- Update loop for stat changes
RunService.Heartbeat:Connect(function()
	-- Only update during gameplay
	if currentGameState ~= Constants.STATES.PLAYING and currentGameState ~= Constants.STATES.COUNTDOWN then
		return
	end

	for targetPlayer, nameplate in pairs(nameplates) do
		if targetPlayer.Character then
			UpdateNameplateStats(nameplate, targetPlayer.Character)
		end
	end
end)

-- Connect player events
Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(OnPlayerRemoved)

-- Setup existing players
for _, targetPlayer in ipairs(Players:GetPlayers()) do
	OnPlayerAdded(targetPlayer)
end

print("[NameplateUI] Initialized")
