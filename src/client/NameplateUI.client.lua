--!strict
-- NameplateUI.client.lua
-- Displays player name and power-up stats above character heads

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local BombSkins = require(Shared:WaitForChild("BombSkins"))
local Titles = require(Shared:WaitForChild("Titles"))

-- Wait for remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged")

-- Track current game state
local currentGameState = Constants.STATES.LOBBY

-- Track nameplates (gameplay + lobby)
local nameplates = {} :: {[Player]: BillboardGui}
local lobbyNameplates = {} :: {[Player]: BillboardGui}

-- UI icon assets
local Assets = ReplicatedStorage:WaitForChild("Assets")
local UIAssets = Assets:WaitForChild("UI")
local BombIconAsset = UIAssets:WaitForChild("BombIcon")
local LightningIconAsset = UIAssets:WaitForChild("LightningIcon")
local FireIconAsset = UIAssets:WaitForChild("FireIcon")

-- Colors
local SELF_NAME_COLOR = Color3.fromRGB(255, 220, 50)
local SELF_STROKE_COLOR = Color3.fromRGB(80, 50, 0)
local ENEMY_NAME_COLOR = Color3.fromRGB(255, 60, 60)
local ENEMY_STROKE_COLOR = Color3.fromRGB(100, 10, 10)
local FRIENDLY_NAME_COLOR = Color3.fromRGB(100, 230, 120)
local FRIENDLY_STROKE_COLOR = Color3.fromRGB(20, 90, 35)
local STAT_VALUE_COLOR = Color3.fromRGB(255, 255, 255)

-- Create nameplate for a character
local function CreateNameplate(targetPlayer: Player, character: Model): BillboardGui?
	local head = character:FindFirstChild("Head")
	if not head then
		head = character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")
	end
	if not head then return nil end

	-- Check if Color Battle mode by reading ColorIndex from character's PlayerStats
	local colorIndex = 0
	local teamIndex = 0
	local statsFolder = character:FindFirstChild("PlayerStats")
	if statsFolder then
		local colorVal = statsFolder:FindFirstChild("ColorIndex")
		if colorVal then
			colorIndex = colorVal.Value
		end
		local teamVal = statsFolder:FindFirstChild("TeamIndex")
		if teamVal then
			teamIndex = teamVal.Value
		end
	end
	local colorData = if colorIndex > 0 then Constants.PLAYER_COLORS[colorIndex] else nil

	-- Determine teammate status from TeamIndex
	local myTeamIndex = 0
	local myChar = player.Character
	if myChar then
		local myStats = myChar:FindFirstChild("PlayerStats")
		if myStats then
			local myTeamVal = myStats:FindFirstChild("TeamIndex")
			if myTeamVal then
				myTeamIndex = myTeamVal.Value
			end
		end
	end
	local isTeammate = (teamIndex > 0 and myTeamIndex > 0 and teamIndex == myTeamIndex and targetPlayer ~= player)

	-- Create BillboardGui (no background, clean floating look)
	local isMobile = UserInputService.TouchEnabled
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Size = if isMobile then UDim2.new(0, 160, 0, 50) else UDim2.new(0, 260, 0, 80)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 50
	billboard.Adornee = head
	billboard.Parent = player.PlayerGui

	-- Container (no background)
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.Parent = billboard

	-- Player name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PlayerName"
	nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = targetPlayer.DisplayName
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.Parent = container

	-- Determine nameplate colors based on mode:
	-- Color Battle (colorIndex > 0): use assigned PLAYER_COLORS for all players
	-- Team mode non-Color-Battle (teamIndex > 0, colorIndex == 0): friendly = green, enemy = red
	-- FFA standard: self = gold, others = red
	local isSelf = targetPlayer == player
	local isColorBattle = (colorIndex > 0 and colorData ~= nil)
	local isTeamMode = (teamIndex > 0 or myTeamIndex > 0)
	local isFriendly = isSelf or isTeammate

	local nameColor: Color3
	local strokeColor: Color3

	if isColorBattle then
		-- Color Battle: use assigned player colors for everyone
		nameColor = colorData.fill
		strokeColor = colorData.stroke
	elseif isTeamMode then
		-- Team mode (non-Color-Battle): green for friendly, red for enemy
		if isFriendly then
			nameColor = FRIENDLY_NAME_COLOR
			strokeColor = FRIENDLY_STROKE_COLOR
		else
			nameColor = ENEMY_NAME_COLOR
			strokeColor = ENEMY_STROKE_COLOR
		end
	elseif isSelf then
		-- FFA: self = gold
		nameColor = SELF_NAME_COLOR
		strokeColor = SELF_STROKE_COLOR
	else
		-- FFA: others = red
		nameColor = ENEMY_NAME_COLOR
		strokeColor = ENEMY_STROKE_COLOR
	end

	nameLabel.TextColor3 = nameColor

	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = strokeColor
	nameStroke.Thickness = if isMobile then 1 else 1.5
	nameStroke.Parent = nameLabel

	-- Stats container (bottom row)
	local statsFrame = Instance.new("Frame")
	statsFrame.Name = "Stats"
	statsFrame.Size = UDim2.new(1, 0, 0.45, 0)
	statsFrame.Position = UDim2.new(0, 0, 0.55, 0)
	statsFrame.BackgroundTransparency = 1
	statsFrame.Parent = container

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.Padding = UDim.new(0, if isMobile then 3 else 6)
	listLayout.Parent = statsFrame

	-- Sizing based on platform
	local statWidth = if isMobile then 46 else 76
	local iconSize = if isMobile then 20 else 35
	local valueLabelWidth = if isMobile then 24 else 40
	local valueOffset = if isMobile then 22 else 36

	-- Helper to create stat display with image icon
	local function CreateStatDisplay(name: string, iconAsset: Instance, initialValue: number): Frame
		local statFrame = Instance.new("Frame")
		statFrame.Name = name
		statFrame.Size = UDim2.new(0, statWidth, 1, 0)
		statFrame.BackgroundTransparency = 1
		statFrame.Parent = statsFrame

		local iconImage = Instance.new("ImageLabel")
		iconImage.Name = "Icon"
		iconImage.Size = UDim2.new(0, iconSize, 0, iconSize)
		iconImage.Position = UDim2.new(0, 0, 0.5, 0)
		iconImage.AnchorPoint = Vector2.new(0, 0.5)
		iconImage.BackgroundTransparency = 1
		iconImage.ScaleType = Enum.ScaleType.Fit
		if iconAsset:IsA("ImageLabel") then
			iconImage.Image = iconAsset.Image
		elseif iconAsset:IsA("Decal") then
			iconImage.Image = iconAsset.Texture
		end
		iconImage.Parent = statFrame

		local valueLabel = Instance.new("TextLabel")
		valueLabel.Name = "Value"
		valueLabel.Size = UDim2.new(0, valueLabelWidth, 1, 0)
		valueLabel.Position = UDim2.new(0, valueOffset, 0, 0)
		valueLabel.BackgroundTransparency = 1
		valueLabel.Text = tostring(initialValue)
		valueLabel.TextColor3 = STAT_VALUE_COLOR
		valueLabel.TextScaled = true
		valueLabel.Font = Enum.Font.FredokaOne
		valueLabel.Parent = statFrame

		local valueStroke = Instance.new("UIStroke")
		valueStroke.Color = Color3.fromRGB(0, 0, 0)
		valueStroke.Thickness = if isMobile then 0.75 else 1
		valueStroke.Parent = valueLabel

		return statFrame
	end

	-- Create stat displays: Bombs, Speed (lightning), Range (fire)
	CreateStatDisplay("BombCount", BombIconAsset, Constants.MAX_BOMBS_DEFAULT)
	CreateStatDisplay("Speed", LightningIconAsset, Constants.MOVE_SPEED)
	CreateStatDisplay("BombRange", FireIconAsset, Constants.BOMB_DEFAULT_RANGE)

	return billboard
end

-- Lobby nameplate colors
local LOBBY_NAME_COLOR = Color3.fromRGB(255, 255, 255)
local LOBBY_TITLE_COLOR = Color3.fromRGB(255, 200, 60)

-- Helper: darken a color for stroke
local function DarkerColor(color: Color3): Color3
	return Color3.new(color.R * 0.35, color.G * 0.35, color.B * 0.35)
end

-- Montserrat Black font
local MONTSERRAT_BLACK = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold)

-- Create lobby nameplate for a character (name + title)
local function CreateLobbyNameplate(targetPlayer: Player, character: Model): BillboardGui?
	local head = character:FindFirstChild("Head")
	if not head then
		head = character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")
	end
	if not head then return nil end

	-- Get player level from PersistentStats
	local level = 1
	local pStats = targetPlayer:FindFirstChild("PersistentStats")
	if pStats then
		local lvlVal = pStats:FindFirstChild("Level")
		if lvlVal then level = lvlVal.Value end
	end

	-- Check for equipped title (overrides level title)
	local title = Constants.GetTitle(level)
	local titleRarityColor: Color3? = nil
	if pStats then
		local equippedTitleVal = pStats:FindFirstChild("EquippedTitle")
		if equippedTitleVal and equippedTitleVal:IsA("StringValue") and equippedTitleVal.Value ~= "" then
			local titleData = Titles.GetById(equippedTitleVal.Value)
			if titleData then
				title = titleData.name
				titleRarityColor = BombSkins.RarityColors[titleData.rarity]
			end
		end
	end

	local isMobileLobby = UserInputService.TouchEnabled
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "LobbyNameplate"
	billboard.Size = if isMobileLobby then UDim2.new(0, 140, 0, 35) else UDim2.new(0, 220, 0, 55)
	billboard.StudsOffset = Vector3.new(0, 1.8, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 60
	billboard.Adornee = head
	billboard.Parent = player.PlayerGui

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.Parent = billboard

	-- Player name (top)
	local nameColor = LOBBY_NAME_COLOR
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PlayerName"
	nameLabel.Size = UDim2.new(1, 0, 0.55, 0)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = targetPlayer.DisplayName
	nameLabel.TextColor3 = nameColor
	nameLabel.TextScaled = true
	nameLabel.FontFace = MONTSERRAT_BLACK
	nameLabel.Parent = container

	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = DarkerColor(nameColor)
	nameStroke.Thickness = 1
	nameStroke.Parent = nameLabel

	-- Title (bottom, smaller)
	local titleColor = titleRarityColor or LOBBY_TITLE_COLOR
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0.4, 0)
	titleLabel.Position = UDim2.new(0, 0, 0.58, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = title
	titleLabel.TextColor3 = titleColor
	titleLabel.TextScaled = true
	titleLabel.FontFace = MONTSERRAT_BLACK
	titleLabel.Parent = container

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = DarkerColor(titleColor)
	titleStroke.Thickness = 0.8
	titleStroke.Parent = titleLabel

	return billboard
end

-- Setup lobby nameplate for a player
local function SetupLobbyNameplate(targetPlayer: Player)
	-- Remove existing
	if lobbyNameplates[targetPlayer] then
		lobbyNameplates[targetPlayer]:Destroy()
		lobbyNameplates[targetPlayer] = nil
	end

	local character = targetPlayer.Character
	if not character then return end

	-- Only show in lobby/intermission
	if currentGameState ~= Constants.STATES.LOBBY
		and currentGameState ~= Constants.STATES.INTERMISSION
		and currentGameState ~= Constants.STATES.CHARACTER_SELECT then
		return
	end

	local nameplate = CreateLobbyNameplate(targetPlayer, character)
	if nameplate then
		lobbyNameplates[targetPlayer] = nameplate
	end
end

-- Remove lobby nameplate for a player
local function RemoveLobbyNameplate(targetPlayer: Player)
	if lobbyNameplates[targetPlayer] then
		lobbyNameplates[targetPlayer]:Destroy()
		lobbyNameplates[targetPlayer] = nil
	end
end

-- Remove all lobby nameplates
local function RemoveAllLobbyNameplates()
	for _, nameplate in pairs(lobbyNameplates) do
		nameplate:Destroy()
	end
	lobbyNameplates = {}
end

-- Setup lobby nameplates for all players
local function SetupAllLobbyNameplates()
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		SetupLobbyNameplate(targetPlayer)
	end
end

-- Update nameplate stats from character values
local function UpdateNameplateStats(nameplate: BillboardGui, character: Model)
	local statsFolder = character:FindFirstChild("PlayerStats")
	if not statsFolder then return end

	local container = nameplate:FindFirstChild("Container")
	if not container then return end

	local stats = container:FindFirstChild("Stats")
	if not stats then return end

	-- Helper to update a stat value
	local function UpdateStat(statName: string, folderName: string)
		local statFrame = stats:FindFirstChild(statName)
		if statFrame then
			local valueLabel = statFrame:FindFirstChild("Value")
			local statVal = statsFolder:FindFirstChild(folderName)
			if valueLabel and statVal then
				valueLabel.Text = tostring(statVal.Value)
			end
		end
	end

	UpdateStat("BombCount", "BombCount")
	UpdateStat("BombRange", "BombRange")
	UpdateStat("Speed", "Speed")
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
	if currentGameState == Constants.STATES.PLAYING or currentGameState == Constants.STATES.COUNTDOWN then
		SetupPlayerNameplate(targetPlayer)
	elseif currentGameState == Constants.STATES.LOBBY
		or currentGameState == Constants.STATES.INTERMISSION
		or currentGameState == Constants.STATES.CHARACTER_SELECT then
		SetupLobbyNameplate(targetPlayer)
	end
end

-- Track EquippedTitle changes to refresh lobby nameplate instantly
local titleConnections = {} :: {[Player]: RBXScriptConnection}

local function ListenForTitleChanges(targetPlayer: Player)
	-- Disconnect old listener
	if titleConnections[targetPlayer] then
		titleConnections[targetPlayer]:Disconnect()
		titleConnections[targetPlayer] = nil
	end

	local pStats = targetPlayer:FindFirstChild("PersistentStats")
	if not pStats then return end
	local equippedTitleVal = pStats:FindFirstChild("EquippedTitle")
	if not equippedTitleVal or not equippedTitleVal:IsA("StringValue") then return end

	titleConnections[targetPlayer] = equippedTitleVal.Changed:Connect(function()
		-- Only refresh if lobby nameplate exists
		if lobbyNameplates[targetPlayer] then
			SetupLobbyNameplate(targetPlayer)
		end
	end)
end

-- Handle player added
local function OnPlayerAdded(targetPlayer: Player)
	targetPlayer.CharacterAdded:Connect(function(character)
		OnCharacterAdded(targetPlayer, character)
	end)

	-- Listen for title changes (PersistentStats may arrive late)
	ListenForTitleChanges(targetPlayer)
	if not titleConnections[targetPlayer] then
		task.spawn(function()
			local pStats = targetPlayer:WaitForChild("PersistentStats", 10)
			if pStats then
				pStats:WaitForChild("EquippedTitle", 5)
				ListenForTitleChanges(targetPlayer)
			end
		end)
	end

	if targetPlayer.Character then
		OnCharacterAdded(targetPlayer, targetPlayer.Character)
	end
end

-- Handle player removed
local function OnPlayerRemoved(targetPlayer: Player)
	RemovePlayerNameplate(targetPlayer)
	RemoveLobbyNameplate(targetPlayer)
	if titleConnections[targetPlayer] then
		titleConnections[targetPlayer]:Disconnect()
		titleConnections[targetPlayer] = nil
	end
end

-- Handle game state changes
RoundStateChanged.OnClientEvent:Connect(function(state: string, data: any?)
	if type(state) == "string" then
		if state == Constants.STATES.LOBBY or state == Constants.STATES.CHARACTER_SELECT
			or state == Constants.STATES.COUNTDOWN or state == Constants.STATES.PLAYING
			or state == Constants.STATES.ROUND_END or state == Constants.STATES.INTERMISSION then
			currentGameState = state
		elseif state == "Preparing" then
			-- Preparing is a transition state before gameplay; treat as non-lobby, non-gameplay
			currentGameState = "Preparing"
		end
	end

	-- Show gameplay nameplates during gameplay, lobby nameplates otherwise
	if currentGameState == Constants.STATES.PLAYING or currentGameState == Constants.STATES.COUNTDOWN then
		RemoveAllLobbyNameplates()
		SetupAllNameplates()
	elseif currentGameState == Constants.STATES.LOBBY
		or currentGameState == Constants.STATES.INTERMISSION
		or currentGameState == Constants.STATES.CHARACTER_SELECT then
		RemoveAllNameplates()
		-- Delay slightly so characters have time to load after respawn
		task.delay(0.5, function()
			if currentGameState == Constants.STATES.LOBBY
				or currentGameState == Constants.STATES.INTERMISSION
				or currentGameState == Constants.STATES.CHARACTER_SELECT then
				SetupAllLobbyNameplates()
			end
		end)
	else
		-- ROUND_END, Preparing, FadeToLobby, etc. — hide everything
		RemoveAllNameplates()
		RemoveAllLobbyNameplates()
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

-- Show lobby nameplates on initial load (we start in LOBBY state)
task.delay(1, function()
	if currentGameState == Constants.STATES.LOBBY
		or currentGameState == Constants.STATES.INTERMISSION then
		SetupAllLobbyNameplates()
	end
end)

print("[NameplateUI] Initialized")
