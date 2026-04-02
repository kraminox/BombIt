--!strict
-- GameUI.client.lua
-- Main game UI: HUD, countdown, round end, mobile controls
-- Cartoony bubbly style!

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

-- Wait for remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged")
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")
local PowerUpCollected = Remotes:WaitForChild("PowerUpCollected")
local SyncPlayerData = Remotes:WaitForChild("SyncPlayerData")
local PlaceBomb = Remotes:WaitForChild("PlaceBomb")

-- Vibrant color palette (matching modern Roblox UI style)
local COLORS = {
	PRIMARY = Color3.fromRGB(255, 85, 165),       -- Hot pink
	SECONDARY = Color3.fromRGB(85, 205, 252),     -- Bright cyan
	ACCENT = Color3.fromRGB(255, 215, 0),         -- Golden yellow
	DARK = Color3.fromRGB(40, 20, 60),            -- Deep purple-black
	LIGHT = Color3.fromRGB(255, 255, 255),        -- White
	SUCCESS = Color3.fromRGB(80, 220, 100),       -- Bright green
	WARNING = Color3.fromRGB(255, 170, 50),       -- Orange
	DANGER = Color3.fromRGB(255, 70, 100),        -- Red-pink
	SHADOW = Color3.fromRGB(20, 10, 40),          -- Dark shadow
	PURPLE = Color3.fromRGB(180, 100, 255),       -- Bright purple
	GRADIENT_DARK = Color3.fromRGB(60, 30, 80),   -- Gradient inner
}

-- UI elements
local screenGui: ScreenGui
local hudFrame: Frame
local timerLabel: TextLabel
local statsFrame: Frame
local playerListFrame: Frame
local countdownLabel: TextLabel
local roundEndFrame: Frame
local mobileControls: Frame
local lobbyInfoFrame: Frame
local lobbyTimerLabel: TextLabel
local lobbyStatusLabel: TextLabel

-- Current stats
local currentStats = {
	bombCount = 1,
	bombRange = 2,
	speed = 12,
	lives = 1,
	coins = 0,
}

-- Check if mobile
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Helper: Create vibrant frame with colored stroke (modern Roblox style)
local function CreateBubbleFrame(name: string, size: UDim2, position: UDim2, strokeColor: Color3?): Frame
	local container = Instance.new("Frame")
	container.Name = name .. "Container"
	container.Size = size
	container.Position = position
	container.BackgroundTransparency = 1

	-- Main frame with dark inner
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = COLORS.GRADIENT_DARK
	frame.BackgroundTransparency = 0.15
	frame.ZIndex = 2
	frame.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame

	-- Bold colored stroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = strokeColor or COLORS.PRIMARY
	stroke.Thickness = 4
	stroke.Transparency = 0
	stroke.Parent = frame

	-- Inner glow/highlight at top
	local highlight = Instance.new("Frame")
	highlight.Name = "Highlight"
	highlight.Size = UDim2.new(1, -8, 0, 3)
	highlight.Position = UDim2.new(0, 4, 0, 4)
	highlight.BackgroundColor3 = Color3.new(1, 1, 1)
	highlight.BackgroundTransparency = 0.7
	highlight.ZIndex = 3
	highlight.Parent = frame

	local highlightCorner = Instance.new("UICorner")
	highlightCorner.CornerRadius = UDim.new(0, 2)
	highlightCorner.Parent = highlight

	return container
end

-- Helper: Create bouncy tween
local function BounceIn(element: GuiObject, property: string, target: any, duration: number?)
	local tween = TweenService:Create(
		element,
		TweenInfo.new(duration or 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{[property] = target}
	)
	tween:Play()
	return tween
end

-- Helper: Create pulse animation
local function PulseElement(element: GuiObject)
	local originalSize = element.Size
	local tween1 = TweenService:Create(element, TweenInfo.new(0.15), {
		Size = UDim2.new(originalSize.X.Scale * 1.1, originalSize.X.Offset, originalSize.Y.Scale * 1.1, originalSize.Y.Offset)
	})
	tween1:Play()
	tween1.Completed:Connect(function()
		TweenService:Create(element, TweenInfo.new(0.15, Enum.EasingStyle.Bounce), {Size = originalSize}):Play()
	end)
end

-- Create all UI elements
local function CreateUI()
	-- Screen GUI
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "GameUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	-- HUD Frame (top of screen)
	hudFrame = Instance.new("Frame")
	hudFrame.Name = "HUD"
	hudFrame.Size = UDim2.new(1, 0, 0, 80)
	hudFrame.Position = UDim2.new(0, 0, 0, 0)
	hudFrame.BackgroundTransparency = 1
	hudFrame.Visible = false
	hudFrame.Parent = screenGui

	-- Timer (top center) - Bubbly style
	local timerContainer = CreateBubbleFrame("Timer", UDim2.new(0, 140, 0, 60), UDim2.new(0.5, -70, 0, 10), COLORS.PRIMARY)
	timerContainer.Parent = hudFrame

	timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerText"
	timerLabel.Size = UDim2.new(1, 0, 1, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = "2:00"
	timerLabel.TextColor3 = COLORS.LIGHT
	timerLabel.TextSize = 32
	timerLabel.Font = Enum.Font.FredokaOne
	timerLabel.ZIndex = 3
	timerLabel.Parent = timerContainer:FindFirstChild("Timer")

	local timerStroke = Instance.new("UIStroke")
	timerStroke.Color = COLORS.DARK
	timerStroke.Thickness = 2
	timerStroke.Transparency = 0.3
	timerStroke.Parent = timerLabel

	-- Stats Frame (top left) - Bubbly pills
	statsFrame = Instance.new("Frame")
	statsFrame.Name = "Stats"
	statsFrame.Size = UDim2.new(0, 220, 0, 55)
	statsFrame.Position = UDim2.new(0, 15, 0, 12)
	statsFrame.BackgroundTransparency = 1
	statsFrame.Parent = hudFrame

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.FillDirection = Enum.FillDirection.Horizontal
	statsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	statsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	statsLayout.Padding = UDim.new(0, 8)
	statsLayout.Parent = statsFrame

	-- Create stat pills (vibrant style with colored strokes)
	local function CreateStatPill(icon: string, name: string, color: Color3): Frame
		local pill = Instance.new("Frame")
		pill.Name = name
		pill.Size = UDim2.new(0, 70, 0, 50)
		pill.BackgroundColor3 = COLORS.GRADIENT_DARK
		pill.BackgroundTransparency = 0.1

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = pill

		-- Bold colored stroke
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = 3
		stroke.Transparency = 0
		stroke.Parent = pill

		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "Icon"
		iconLabel.Size = UDim2.new(0.45, 0, 1, 0)
		iconLabel.Position = UDim2.new(0, 0, 0, 0)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Text = icon
		iconLabel.TextSize = 22
		iconLabel.Font = Enum.Font.GothamBold
		iconLabel.Parent = pill

		local valueLabel = Instance.new("TextLabel")
		valueLabel.Name = "Value"
		valueLabel.Size = UDim2.new(0.55, 0, 1, 0)
		valueLabel.Position = UDim2.new(0.45, 0, 0, 0)
		valueLabel.BackgroundTransparency = 1
		valueLabel.Text = "1"
		valueLabel.TextColor3 = COLORS.LIGHT
		valueLabel.TextSize = 22
		valueLabel.Font = Enum.Font.FredokaOne
		valueLabel.Parent = pill

		local valueStroke = Instance.new("UIStroke")
		valueStroke.Color = COLORS.DARK
		valueStroke.Thickness = 1.5
		valueStroke.Transparency = 0.3
		valueStroke.Parent = valueLabel

		pill.Parent = statsFrame
		return pill
	end

	CreateStatPill("💣", "BombStat", COLORS.DANGER)
	CreateStatPill("🔥", "RangeStat", COLORS.WARNING)
	CreateStatPill("⚡", "SpeedStat", COLORS.SECONDARY)

	-- Player list (top right) - Bubbly card
	local playerListContainer = CreateBubbleFrame("PlayerList", UDim2.new(0, 180, 0, 140), UDim2.new(1, -195, 0, 10), COLORS.DARK)
	playerListContainer.Parent = hudFrame
	playerListFrame = playerListContainer:FindFirstChild("PlayerList") :: Frame

	local playerListTitle = Instance.new("TextLabel")
	playerListTitle.Name = "Title"
	playerListTitle.Size = UDim2.new(1, 0, 0, 28)
	playerListTitle.Position = UDim2.new(0, 0, 0, 0)
	playerListTitle.BackgroundColor3 = COLORS.SECONDARY
	playerListTitle.BackgroundTransparency = 0.3
	playerListTitle.Text = "PLAYERS"
	playerListTitle.TextColor3 = COLORS.LIGHT
	playerListTitle.TextSize = 14
	playerListTitle.Font = Enum.Font.FredokaOne
	playerListTitle.ZIndex = 3
	playerListTitle.Parent = playerListFrame

	local titleCorner = Instance.new("UICorner")
	titleCorner.CornerRadius = UDim.new(0, 12)
	titleCorner.Parent = playerListTitle

	local playerListContent = Instance.new("Frame")
	playerListContent.Name = "Content"
	playerListContent.Size = UDim2.new(1, -10, 1, -35)
	playerListContent.Position = UDim2.new(0, 5, 0, 30)
	playerListContent.BackgroundTransparency = 1
	playerListContent.ZIndex = 3
	playerListContent.Parent = playerListFrame

	local playerListLayout = Instance.new("UIListLayout")
	playerListLayout.FillDirection = Enum.FillDirection.Vertical
	playerListLayout.Padding = UDim.new(0, 3)
	playerListLayout.Parent = playerListContent

	-- Countdown Label (center, hidden by default) - Big and bouncy
	countdownLabel = Instance.new("TextLabel")
	countdownLabel.Name = "Countdown"
	countdownLabel.Size = UDim2.new(0, 400, 0, 300)
	countdownLabel.Position = UDim2.new(0.5, -200, 0.25, 0)
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.Text = "3"
	countdownLabel.TextColor3 = COLORS.ACCENT
	countdownLabel.TextSize = 200
	countdownLabel.Font = Enum.Font.FredokaOne
	countdownLabel.TextStrokeTransparency = 0
	countdownLabel.TextStrokeColor3 = COLORS.DARK
	countdownLabel.Visible = false
	countdownLabel.Parent = screenGui

	-- Round End Frame - Not used anymore (WinnersUI handles this)
	roundEndFrame = Instance.new("Frame")
	roundEndFrame.Name = "RoundEnd"
	roundEndFrame.Visible = false
	roundEndFrame.Parent = screenGui

	-- Lobby Info Frame - Bubbly welcome banner
	local lobbyContainer = CreateBubbleFrame("LobbyInfo", UDim2.new(0, 420, 0, 130), UDim2.new(0.5, -210, 0.08, 0), COLORS.PRIMARY)
	lobbyContainer.Parent = screenGui
	lobbyInfoFrame = lobbyContainer

	local lobbyFrame = lobbyContainer:FindFirstChild("LobbyInfo") :: Frame

	-- Decorative bombs
	local bombLeft = Instance.new("TextLabel")
	bombLeft.Size = UDim2.new(0, 50, 0, 50)
	bombLeft.Position = UDim2.new(0, 10, 0.5, -25)
	bombLeft.BackgroundTransparency = 1
	bombLeft.Text = "💣"
	bombLeft.TextSize = 40
	bombLeft.ZIndex = 3
	bombLeft.Rotation = -15
	bombLeft.Parent = lobbyFrame

	local bombRight = Instance.new("TextLabel")
	bombRight.Size = UDim2.new(0, 50, 0, 50)
	bombRight.Position = UDim2.new(1, -60, 0.5, -25)
	bombRight.BackgroundTransparency = 1
	bombRight.Text = "💣"
	bombRight.TextSize = 40
	bombRight.ZIndex = 3
	bombRight.Rotation = 15
	bombRight.Parent = lobbyFrame

	lobbyStatusLabel = Instance.new("TextLabel")
	lobbyStatusLabel.Name = "StatusLabel"
	lobbyStatusLabel.Size = UDim2.new(1, -100, 0.55, 0)
	lobbyStatusLabel.Position = UDim2.new(0.5, 0, 0.05, 0)
	lobbyStatusLabel.AnchorPoint = Vector2.new(0.5, 0)
	lobbyStatusLabel.BackgroundTransparency = 1
	lobbyStatusLabel.Text = "BOMB IT!"
	lobbyStatusLabel.TextColor3 = COLORS.LIGHT
	lobbyStatusLabel.TextSize = 38
	lobbyStatusLabel.Font = Enum.Font.FredokaOne
	lobbyStatusLabel.ZIndex = 3
	lobbyStatusLabel.Parent = lobbyFrame

	lobbyTimerLabel = Instance.new("TextLabel")
	lobbyTimerLabel.Name = "TimerLabel"
	lobbyTimerLabel.Size = UDim2.new(1, -100, 0.4, 0)
	lobbyTimerLabel.Position = UDim2.new(0.5, 0, 0.55, 0)
	lobbyTimerLabel.AnchorPoint = Vector2.new(0.5, 0)
	lobbyTimerLabel.BackgroundTransparency = 1
	lobbyTimerLabel.Text = "Waiting for players..."
	lobbyTimerLabel.TextColor3 = COLORS.ACCENT
	lobbyTimerLabel.TextSize = 24
	lobbyTimerLabel.Font = Enum.Font.FredokaOne
	lobbyTimerLabel.ZIndex = 3
	lobbyTimerLabel.Parent = lobbyFrame

	-- Mobile Controls
	if isMobile then
		CreateMobileControls()
	end
end

local function CreateMobileControls()
	mobileControls = Instance.new("Frame")
	mobileControls.Name = "MobileControls"
	mobileControls.Size = UDim2.new(1, 0, 0.4, 0)
	mobileControls.Position = UDim2.new(0, 0, 0.6, 0)
	mobileControls.BackgroundTransparency = 1
	mobileControls.Visible = false
	mobileControls.Parent = screenGui

	-- Joystick background (left side) - Bubbly
	local joystickBg = Instance.new("Frame")
	joystickBg.Name = "JoystickBg"
	joystickBg.Size = UDim2.new(0, 130, 0, 130)
	joystickBg.Position = UDim2.new(0, 25, 0.5, -65)
	joystickBg.BackgroundColor3 = COLORS.DARK
	joystickBg.BackgroundTransparency = 0.3
	joystickBg.Parent = mobileControls

	local joystickCorner = Instance.new("UICorner")
	joystickCorner.CornerRadius = UDim.new(1, 0)
	joystickCorner.Parent = joystickBg

	local joystickStroke = Instance.new("UIStroke")
	joystickStroke.Color = COLORS.SECONDARY
	joystickStroke.Thickness = 4
	joystickStroke.Parent = joystickBg

	-- Joystick thumb
	local joystickThumb = Instance.new("Frame")
	joystickThumb.Name = "JoystickThumb"
	joystickThumb.Size = UDim2.new(0, 55, 0, 55)
	joystickThumb.Position = UDim2.new(0.5, -27.5, 0.5, -27.5)
	joystickThumb.BackgroundColor3 = COLORS.SECONDARY
	joystickThumb.Parent = joystickBg

	local thumbCorner = Instance.new("UICorner")
	thumbCorner.CornerRadius = UDim.new(1, 0)
	thumbCorner.Parent = joystickThumb

	-- Bomb button (right side) - Big and bubbly
	local bombButton = Instance.new("TextButton")
	bombButton.Name = "BombButton"
	bombButton.Size = UDim2.new(0, 110, 0, 110)
	bombButton.Position = UDim2.new(1, -135, 0.5, -55)
	bombButton.BackgroundColor3 = COLORS.DANGER
	bombButton.Text = "💣"
	bombButton.TextSize = 55
	bombButton.Font = Enum.Font.GothamBold
	bombButton.Parent = mobileControls

	local bombCorner = Instance.new("UICorner")
	bombCorner.CornerRadius = UDim.new(1, 0)
	bombCorner.Parent = bombButton

	local bombStroke = Instance.new("UIStroke")
	bombStroke.Color = COLORS.ACCENT
	bombStroke.Thickness = 4
	bombStroke.Transparency = 0
	bombStroke.Parent = bombButton

	-- Bomb button functionality with bounce
	bombButton.MouseButton1Click:Connect(function()
		PulseElement(bombButton)
		PlaceBomb:FireServer()
	end)

	-- Simple joystick implementation
	local joystickActive = false
	local joystickCenter = Vector2.new(0, 0)

	joystickBg.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			joystickActive = true
			joystickCenter = joystickBg.AbsolutePosition + joystickBg.AbsoluteSize / 2
		end
	end)

	joystickBg.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			joystickActive = false
			TweenService:Create(joystickThumb, TweenInfo.new(0.15, Enum.EasingStyle.Back), {
				Position = UDim2.new(0.5, -27.5, 0.5, -27.5)
			}):Play()
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if joystickActive and input.UserInputType == Enum.UserInputType.Touch then
			local touchPos = Vector2.new(input.Position.X, input.Position.Y)
			local offset = touchPos - joystickCenter
			local maxRadius = 40

			if offset.Magnitude > maxRadius then
				offset = offset.Unit * maxRadius
			end

			joystickThumb.Position = UDim2.new(0.5, offset.X - 27.5, 0.5, offset.Y - 27.5)
		end
	end)
end

-- Update stats display with bounce
local function UpdateStats()
	local bombStat = statsFrame:FindFirstChild("BombStat") :: Frame?
	local rangeStat = statsFrame:FindFirstChild("RangeStat") :: Frame?
	local speedStat = statsFrame:FindFirstChild("SpeedStat") :: Frame?

	if bombStat then
		local value = bombStat:FindFirstChild("Value") :: TextLabel?
		if value then
			local oldValue = tonumber(value.Text)
			value.Text = tostring(currentStats.bombCount)
			if oldValue and currentStats.bombCount > oldValue then
				PulseElement(bombStat)
			end
		end
	end
	if rangeStat then
		local value = rangeStat:FindFirstChild("Value") :: TextLabel?
		if value then
			local oldValue = tonumber(value.Text)
			value.Text = tostring(currentStats.bombRange)
			if oldValue and currentStats.bombRange > oldValue then
				PulseElement(rangeStat)
			end
		end
	end
	if speedStat then
		local value = speedStat:FindFirstChild("Value") :: TextLabel?
		if value then
			local speedLevel = math.floor((currentStats.speed - Constants.MOVE_SPEED) / 3)
			local oldValue = tonumber(value.Text)
			value.Text = tostring(speedLevel)
			if oldValue and speedLevel > oldValue then
				PulseElement(speedStat)
			end
		end
	end
end

-- Update timer display
local function UpdateTimer(seconds: number)
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	timerLabel.Text = string.format("%d:%02d", minutes, secs)

	-- Change color when low with pulse
	if seconds <= 10 then
		timerLabel.TextColor3 = COLORS.DANGER
		if seconds <= 5 then
			PulseElement(timerLabel.Parent.Parent :: GuiObject)
		end
	elseif seconds <= 30 then
		timerLabel.TextColor3 = COLORS.WARNING
	else
		timerLabel.TextColor3 = COLORS.LIGHT
	end
end

-- Update player list
local function UpdatePlayerList()
	local content = playerListFrame:FindFirstChild("Content") :: Frame?
	if not content then return end

	-- Clear existing entries
	for _, child in ipairs(content:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	-- Add player entries
	for i, otherPlayer in ipairs(Players:GetPlayers()) do
		local entry = Instance.new("TextLabel")
		entry.Name = otherPlayer.Name
		entry.Size = UDim2.new(1, 0, 0, 22)
		entry.BackgroundColor3 = i % 2 == 0 and COLORS.SECONDARY or COLORS.PRIMARY
		entry.BackgroundTransparency = 0.7
		entry.TextColor3 = COLORS.LIGHT
		entry.TextSize = 13
		entry.Font = Enum.Font.FredokaOne
		entry.TextXAlignment = Enum.TextXAlignment.Left
		entry.Text = "  " .. otherPlayer.Name
		entry.ZIndex = 3

		local entryCorner = Instance.new("UICorner")
		entryCorner.CornerRadius = UDim.new(0, 8)
		entryCorner.Parent = entry

		entry.Parent = content
	end
end

-- Show countdown with big bouncy animation
local function ShowCountdown(number: number, text: string?)
	countdownLabel.Visible = true

	if text then
		countdownLabel.Text = text
		countdownLabel.TextColor3 = COLORS.SUCCESS
	else
		countdownLabel.Text = tostring(number)
		-- Cycle through colors
		local colors = {COLORS.PRIMARY, COLORS.SECONDARY, COLORS.ACCENT}
		countdownLabel.TextColor3 = colors[(number % 3) + 1]
	end

	-- Big bouncy scale animation
	countdownLabel.TextSize = 80
	countdownLabel.Rotation = -10

	local tween1 = TweenService:Create(countdownLabel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextSize = 200,
		Rotation = 0
	})
	tween1:Play()

	if text then
		task.delay(0.8, function()
			TweenService:Create(countdownLabel, TweenInfo.new(0.2), {
				TextTransparency = 1,
				TextStrokeTransparency = 1
			}):Play()
			task.delay(0.2, function()
				countdownLabel.Visible = false
				countdownLabel.TextTransparency = 0
				countdownLabel.TextStrokeTransparency = 0
			end)
		end)
	end
end

-- Show power-up collection effect - Vibrant popup with colored stroke
local function ShowPowerUpEffect(powerUpType: string)
	local powerUpData = Constants.POWERUP_TYPES[powerUpType]
	if not powerUpData then
		-- Handle coin
		if powerUpType == "COIN" then
			powerUpData = {icon = "🪙", name = "Coin", color = COLORS.ACCENT}
		else
			return
		end
	end

	local effectContainer = Instance.new("Frame")
	effectContainer.Size = UDim2.new(0, 240, 0, 65)
	effectContainer.Position = UDim2.new(0.5, -120, 0.75, 0)
	effectContainer.BackgroundColor3 = COLORS.GRADIENT_DARK
	effectContainer.BackgroundTransparency = 0.1
	effectContainer.ZIndex = 100
	effectContainer.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = effectContainer

	-- Bold colored stroke matching powerup color
	local stroke = Instance.new("UIStroke")
	stroke.Color = powerUpData.color
	stroke.Thickness = 4
	stroke.Transparency = 0
	stroke.Parent = effectContainer

	-- Icon on the left with colored background
	local iconFrame = Instance.new("Frame")
	iconFrame.Size = UDim2.new(0, 50, 0, 50)
	iconFrame.Position = UDim2.new(0, 8, 0.5, -25)
	iconFrame.BackgroundColor3 = powerUpData.color
	iconFrame.BackgroundTransparency = 0.2
	iconFrame.ZIndex = 101
	iconFrame.Parent = effectContainer

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 10)
	iconCorner.Parent = iconFrame

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(1, 0, 1, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = powerUpData.icon
	iconLabel.TextColor3 = COLORS.LIGHT
	iconLabel.TextSize = 28
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.ZIndex = 102
	iconLabel.Parent = iconFrame

	-- Name label
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -70, 1, 0)
	label.Position = UDim2.new(0, 65, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = powerUpData.name .. "!"
	label.TextColor3 = COLORS.LIGHT
	label.TextSize = 24
	label.Font = Enum.Font.FredokaOne
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 101
	label.Parent = effectContainer

	-- Text stroke for readability
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = COLORS.DARK
	textStroke.Thickness = 2
	textStroke.Transparency = 0.5
	textStroke.Parent = label

	-- Bounce in
	effectContainer.Position = UDim2.new(0.5, -120, 0.9, 0)
	effectContainer.Size = UDim2.new(0, 120, 0, 35)
	BounceIn(effectContainer, "Position", UDim2.new(0.5, -120, 0.7, 0), 0.3)
	BounceIn(effectContainer, "Size", UDim2.new(0, 240, 0, 65), 0.3)

	-- Fade out and move up
	task.delay(1.5, function()
		TweenService:Create(effectContainer, TweenInfo.new(0.4), {
			Position = UDim2.new(0.5, -120, 0.55, 0),
			BackgroundTransparency = 1
		}):Play()
		TweenService:Create(label, TweenInfo.new(0.4), {TextTransparency = 1}):Play()
		TweenService:Create(textStroke, TweenInfo.new(0.4), {Transparency = 1}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.4), {Transparency = 1}):Play()
		TweenService:Create(iconFrame, TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play()
		TweenService:Create(iconLabel, TweenInfo.new(0.4), {TextTransparency = 1}):Play()
		task.delay(0.4, function()
			effectContainer:Destroy()
		end)
	end)
end

-- Update lobby info display
local function UpdateLobbyInfo(state: string, timer: number?)
	local lobbyFrame = lobbyInfoFrame:FindFirstChild("LobbyInfo") :: Frame?
	if not lobbyFrame then return end

	if state == Constants.STATES.LOBBY then
		lobbyInfoFrame.Visible = true
		lobbyStatusLabel.Text = "BOMB IT!"
		if timer and timer > 0 then
			lobbyTimerLabel.Text = "Starting in " .. timer .. "s"
		else
			lobbyTimerLabel.Text = "Waiting for players..."
		end
	elseif state == Constants.STATES.CHARACTER_SELECT then
		lobbyInfoFrame.Visible = true
		lobbyStatusLabel.Text = "PICK YOUR BOMBER!"
		if timer and timer > 0 then
			lobbyTimerLabel.Text = timer .. " seconds"
		else
			lobbyTimerLabel.Text = ""
		end
	elseif state == Constants.STATES.INTERMISSION then
		lobbyInfoFrame.Visible = true
		lobbyStatusLabel.Text = "GET READY!"
		if timer and timer > 0 then
			lobbyTimerLabel.Text = "Next round in " .. timer .. "s"
		else
			lobbyTimerLabel.Text = ""
		end
	else
		lobbyInfoFrame.Visible = false
	end
end

-- Handle game state changes
RoundStateChanged.OnClientEvent:Connect(function(state: string, data: any?)
	if state == Constants.STATES.PLAYING then
		hudFrame.Visible = true
		countdownLabel.Visible = false
		lobbyInfoFrame.Visible = false
		if mobileControls then
			mobileControls.Visible = true
		end
		UpdatePlayerList()
	elseif state == Constants.STATES.COUNTDOWN then
		hudFrame.Visible = false
		lobbyInfoFrame.Visible = false
		if mobileControls then
			mobileControls.Visible = false
		end
	elseif state == "Countdown" and data then
		lobbyInfoFrame.Visible = false
		if data.number >= 0 then
			ShowCountdown(data.number, nil)
		elseif data.text then
			ShowCountdown(-1, data.text)
		end
	elseif state == Constants.STATES.ROUND_END or state == "RoundResults" then
		hudFrame.Visible = false
		lobbyInfoFrame.Visible = false
		if mobileControls then
			mobileControls.Visible = false
		end
	elseif state == Constants.STATES.INTERMISSION then
		hudFrame.Visible = false
		countdownLabel.Visible = false
		UpdateLobbyInfo(state, nil)
		if mobileControls then
			mobileControls.Visible = false
		end
	elseif state == Constants.STATES.LOBBY then
		hudFrame.Visible = false
		countdownLabel.Visible = false
		UpdateLobbyInfo(state, nil)
		if mobileControls then
			mobileControls.Visible = false
		end
	elseif state == Constants.STATES.CHARACTER_SELECT then
		UpdateLobbyInfo(state, nil)
	elseif state == "Timer" and data and data.timer then
		if lobbyInfoFrame.Visible then
			local currentStatus = lobbyStatusLabel.Text
			if currentStatus == "BOMB IT!" then
				UpdateLobbyInfo(Constants.STATES.LOBBY, data.timer)
			elseif currentStatus == "PICK YOUR BOMBER!" then
				UpdateLobbyInfo(Constants.STATES.CHARACTER_SELECT, data.timer)
			elseif currentStatus == "GET READY!" then
				UpdateLobbyInfo(Constants.STATES.INTERMISSION, data.timer)
			end
		end
	end
end)

-- Handle HUD updates
UpdateHUD.OnClientEvent:Connect(function(updateType: string, value: any)
	if updateType == "Timer" then
		UpdateTimer(value)
	end
end)

-- Handle player data sync
SyncPlayerData.OnClientEvent:Connect(function(data)
	if data then
		currentStats.bombCount = data.bombCount or 1
		currentStats.bombRange = data.bombRange or 2
		currentStats.speed = data.speed or Constants.MOVE_SPEED
		currentStats.lives = data.lives or 1
		currentStats.coins = data.coins or 0
		UpdateStats()
	end
end)

-- Handle power-up collection
PowerUpCollected.OnClientEvent:Connect(function(powerUpType: string)
	ShowPowerUpEffect(powerUpType)
end)

-- Update player list periodically
task.spawn(function()
	while true do
		task.wait(2)
		if hudFrame.Visible then
			UpdatePlayerList()
		end
	end
end)

-- Initialize
CreateUI()
UpdateStats()
UpdateLobbyInfo(Constants.STATES.LOBBY, nil)
print("[GameUI] Initialized")
