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

-- Sound effects
local SoundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
local UISounds = SoundsFolder and SoundsFolder:FindFirstChild("UI")
local clickSound: Sound? = UISounds and UISounds:FindFirstChild("Click") :: Sound? or nil
local countdownSound: Sound? = UISounds and UISounds:FindFirstChild("Countdown") :: Sound? or nil

-- Wait for remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged")
local UpdateHUD = Remotes:WaitForChild("UpdateHUD")
local PowerUpCollected = Remotes:WaitForChild("PowerUpCollected")
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
local colorBattleDisplayUI: Frame? = nil
local countdownLabel: TextLabel
local roundEndFrame: Frame
local mobileControls: Frame
local bannerUI: ScreenGui
local bannerBG: Frame
local bannerTextLabel: TextLabel
local bannerTextShadow: TextLabel
local currentBannerState: string? = nil
local navHUD: ScreenGui? = nil
local moneyLabel: TextLabel? = nil

-- Respawn leaderboard state
local leaderboardHolder: Frame? = nil
local lbTemplates: {Frame} = {} -- [1]=1stTemplate, [2]=2ndTemplate, [3]=3rdTemplate (cloned originals)
local lbActiveEntries: {Frame} = {} -- currently visible leaderboard entries
local lbKillCounts: {[number]: number} = {} -- userId -> kills this round
local isRespawnMode = false
local PlayerDied: RemoteEvent? = nil

-- Track coins earned from last round for NavHUD typewriter
local pendingCoinsEarned = 0
local pendingTotalCoins = 0

-- AFK state: read from BoolValue created by AFKToggle
local isAFK = false
local lastRoundState: string? = nil
local lastRoundData: any? = nil

-- Check if mobile (TouchEnabled alone is enough — Studio device emulator also sets KeyboardEnabled)
local isMobile = UserInputService.TouchEnabled

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

	-- Timer uses the existing BannerUI (initialized below)

	-- Stats are shown on overhead UI nameplates, no HUD stats needed

	-- Get reference to the pre-built ColorBattleDisplayUI (lives in a ScreenGui from StarterGui)
	task.spawn(function()
		-- Search all ScreenGuis in PlayerGui for the ColorBattleDisplayUI frame
		local maxWait = 10
		local elapsed = 0
		while not colorBattleDisplayUI and elapsed < maxWait do
			for _, gui in ipairs(playerGui:GetChildren()) do
				if gui:IsA("ScreenGui") then
					local found = gui:FindFirstChild("ColorBattleDisplayUI")
					if found then
						colorBattleDisplayUI = found
						colorBattleDisplayUI.Visible = false -- Hidden until Color Battle starts
						break
					end
				end
			end
			if not colorBattleDisplayUI then
				task.wait(0.5)
				elapsed = elapsed + 0.5
			end
		end
	end)

	-- Countdown ScreenGui (above cinematic bars at DisplayOrder 10)
	local countdownGui = Instance.new("ScreenGui")
	countdownGui.Name = "CountdownUI"
	countdownGui.ResetOnSpawn = false
	countdownGui.DisplayOrder = 20
	countdownGui.IgnoreGuiInset = true
	countdownGui.Parent = playerGui

	-- Countdown Label (center, hidden by default)
	countdownLabel = Instance.new("TextLabel")
	countdownLabel.Name = "Countdown"
	countdownLabel.Size = UDim2.new(1, 0, 0.3, 0)
	countdownLabel.Position = UDim2.new(0, 0, 0.35, 0)
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.Text = ""
	countdownLabel.TextColor3 = Color3.new(1, 1, 1)
	countdownLabel.TextSize = 52
	countdownLabel.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.ExtraBold)
	countdownLabel.TextStrokeTransparency = 0
	countdownLabel.TextStrokeColor3 = Color3.fromRGB(140, 20, 20)
	countdownLabel.Visible = false
	countdownLabel.Parent = countdownGui

	-- Round End Frame - Not used anymore (WinnersUI handles this)
	roundEndFrame = Instance.new("Frame")
	roundEndFrame.Name = "RoundEnd"
	roundEndFrame.Visible = false
	roundEndFrame.Parent = screenGui

	-- Banner UI - reference existing BannerUI in PlayerGui
	bannerUI = playerGui:WaitForChild("BannerUI")
	bannerBG = bannerUI:WaitForChild("IntermissionFrame")
	bannerTextLabel = bannerBG:WaitForChild("TextLabel")
	bannerTextShadow = bannerBG:WaitForChild("TextShadow")
	bannerUI.Enabled = false

	-- NavHUD reference (pre-built ScreenGui) — spawned async, use background wait
	task.spawn(function()
		navHUD = playerGui:WaitForChild("NavHUD", 15) :: ScreenGui?
		if navHUD then
			local parentFrame = navHUD:FindFirstChild("ParentFrame")
			if parentFrame then
				local moneyFrame = parentFrame:FindFirstChild("MoneyFrame")
				if moneyFrame then
					moneyLabel = moneyFrame:FindFirstChild("MoneyLabel") :: TextLabel?
				end
			end
		end

		-- Set initial coin display from PersistentStats and listen for changes
		if moneyLabel then
			local pStats = player:WaitForChild("PersistentStats", 10)
			if pStats then
				local coinsVal = pStats:FindFirstChild("TotalCoins")
				if coinsVal and coinsVal:IsA("IntValue") then
					moneyLabel.Text = "$" .. tostring(coinsVal.Value)

					-- Listen for real-time coin changes (codes, group rewards, purchases, etc.)
					coinsVal.Changed:Connect(function(newValue: number)
						if moneyLabel then
							moneyLabel.Text = "$" .. tostring(newValue)
						end
					end)
				end
			end
		end
	end)

	-- Mobile Controls created after this function (see below)
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

	-- Bomb button (right side, next to jump button)
	local bombButton = Instance.new("ImageButton")
	bombButton.Name = "BombButton"
	bombButton.Size = UDim2.new(0, 90, 0, 90)
	bombButton.Position = UDim2.new(1, -200, 0.5, -45)
	bombButton.AnchorPoint = Vector2.new(0, 0)
	bombButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	bombButton.BackgroundTransparency = 0.4
	bombButton.Image = "rbxassetid://79587040789244"
	bombButton.ImageTransparency = 0.3
	bombButton.ScaleType = Enum.ScaleType.Fit
	bombButton.Parent = mobileControls

	local bombCorner = Instance.new("UICorner")
	bombCorner.CornerRadius = UDim.new(1, 0)
	bombCorner.Parent = bombButton

	local bombStroke = Instance.new("UIStroke")
	bombStroke.Color = Color3.fromRGB(255, 255, 255)
	bombStroke.Thickness = 2.5
	bombStroke.Transparency = 0.5
	bombStroke.Parent = bombButton

	-- Bomb button functionality with bounce
	bombButton.MouseButton1Click:Connect(function()
		if clickSound then clickSound:Play() end
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

-- Stats are displayed via overhead nameplates, no HUD update needed

-- Helper to set banner text (updates both label and shadow)
local function SetBannerText(text: string)
	if not bannerTextLabel or not bannerTextShadow then return end
	bannerTextLabel.Text = text
	bannerTextShadow.Text = text
end

-- Update timer display using BannerUI
local function UpdateTimer(seconds: number)
	if not bannerUI then return end
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	local timeText = string.format("%d:%02d", minutes, secs)
	SetBannerText(timeText)
	bannerUI.Enabled = true
	if bannerBG then bannerBG.Visible = true end
end

-- Total paintable tiles on the grid (GRID_WIDTH * GRID_HEIGHT minus hard walls)
-- Hard walls are at every even x AND even y (1-indexed), so count those
local TOTAL_TILES: number = 0
do
	local count = 0
	for x = 1, Constants.GRID_WIDTH do
		for y = 1, Constants.GRID_HEIGHT do
			-- Hard walls at even x AND even y
			if not (x % 2 == 0 and y % 2 == 0) then
				count = count + 1
			end
		end
	end
	TOTAL_TILES = count
end

-- Persistent bar instances keyed by colorIndex, and their last known values
local activeBars = {} :: {[number]: Frame}
local barCurrentTiles = {} :: {[number]: number} -- last displayed tile count per colorIndex
local knownPlayerColors = {} :: {[number]: number} -- {userId = colorIndex} — cached so dead players' bars persist
local barTweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local barPositionTweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Digit count-up helper: smoothly counts from old to new value on a TextLabel
local function AnimateDigit(label: TextLabel, oldVal: number, newVal: number)
	if oldVal == newVal then return end
	local diff = math.abs(newVal - oldVal)
	local steps = math.min(diff, 20)
	if steps == 0 then steps = 1 end
	local stepTime = 0.35 / steps
	for i = 1, steps do
		local v = math.floor(oldVal + (i / steps) * (newVal - oldVal))
		label.Text = tostring(v)
		task.wait(stepTime)
	end
	label.Text = tostring(newVal)
end

-- Update the Color Battle display with animations
local function UpdateColorBattleDisplay()
	if not colorBattleDisplayUI then return end

	-- Gather per-color tile counts from all players
	-- Cache colorIndex so dead players (no character) keep their bar
	local colorTiles = {} :: {[number]: number}
	for _, p in ipairs(Players:GetPlayers()) do
		local character = p.Character
		local stats = character and character:FindFirstChild("PlayerStats")
		if stats then
			local colorVal = stats:FindFirstChild("ColorIndex")
			local tilesVal = stats:FindFirstChild("TilesOwned")
			if colorVal and colorVal.Value > 0 then
				knownPlayerColors[p.UserId] = colorVal.Value
				local tiles = tilesVal and tilesVal.Value or 0
				colorTiles[colorVal.Value] = (colorTiles[colorVal.Value] or 0) + tiles
			end
		else
			-- Player is dead / no character — use cached color with last known tile count
			local cachedColor = knownPlayerColors[p.UserId]
			if cachedColor and cachedColor > 0 then
				local lastTiles = barCurrentTiles[cachedColor] or 0
				if not colorTiles[cachedColor] then
					colorTiles[cachedColor] = lastTiles
				end
			end
		end
	end

	-- Sort by tile count ascending (smallest on left, tallest on right)
	local sorted = {}
	for ci, tiles in pairs(colorTiles) do
		table.insert(sorted, {colorIndex = ci, tiles = tiles})
	end
	table.sort(sorted, function(a, b)
		if a.tiles == b.tiles then return a.colorIndex < b.colorIndex end
		return a.tiles < b.tiles
	end)

	-- Get the BarTemplate
	local barTemplate = colorBattleDisplayUI:FindFirstChild("BarTemplate")
	if not barTemplate then return end
	barTemplate.Visible = false

	local maxTiles = TOTAL_TILES
	if maxTiles <= 0 then maxTiles = 1 end

	-- Track which colors are still active this frame
	local activeThisFrame = {} :: {[number]: boolean}

	for i, entry in ipairs(sorted) do
		activeThisFrame[entry.colorIndex] = true
		local colorData = Constants.PLAYER_COLORS[entry.colorIndex]
		if not colorData then continue end

		local bar = activeBars[entry.colorIndex]

		-- Create bar if it doesn't exist yet
		if not bar or not bar.Parent then
			bar = barTemplate:Clone()
			bar.Name = "Bar_" .. entry.colorIndex
			bar.Visible = true
			bar.BackgroundColor3 = colorData.fill

			local stroke = bar:FindFirstChildOfClass("UIStroke")
			if stroke then stroke.Color = colorData.stroke end

			local digit = bar:FindFirstChild("Digit")
			if digit and digit:IsA("TextLabel") then
				digit.TextColor3 = colorData.fill
				digit.Text = "0"
				local digitStroke = digit:FindFirstChildOfClass("UIStroke")
				if digitStroke then digitStroke.Color = colorData.stroke end
			end

			-- Start at zero height for intro animation
			bar.Size = UDim2.new(bar.Size.X.Scale, bar.Size.X.Offset, 0.02, 0)
			bar.Parent = colorBattleDisplayUI

			activeBars[entry.colorIndex] = bar
			barCurrentTiles[entry.colorIndex] = 0
		end

		-- Tween LayoutOrder for position swapping (UIListLayout uses this)
		if bar.LayoutOrder ~= i then
			bar.LayoutOrder = i
		end

		-- Tween bar height
		local fraction = math.clamp(entry.tiles / maxTiles, 0, 1)
		local minHeight = 0.05
		local targetHeight = minHeight + (1 - minHeight) * fraction
		local targetSize = UDim2.new(bar.Size.X.Scale, bar.Size.X.Offset, targetHeight, 0)

		if math.abs(bar.Size.Y.Scale - targetHeight) > 0.005 then
			TweenService:Create(bar, barTweenInfo, {Size = targetSize}):Play()
		end

		-- Animate digit count-up if tile count changed
		local oldTiles = barCurrentTiles[entry.colorIndex] or 0
		if entry.tiles ~= oldTiles then
			local digit = bar:FindFirstChild("Digit")
			if digit and digit:IsA("TextLabel") then
				local capturedOld = oldTiles
				local capturedNew = entry.tiles
				task.spawn(AnimateDigit, digit, capturedOld, capturedNew)
			end
			barCurrentTiles[entry.colorIndex] = entry.tiles
		end
	end

	-- Remove bars for colors no longer in play (player left, etc.)
	for ci, bar in pairs(activeBars) do
		if not activeThisFrame[ci] then
			-- Shrink out then destroy
			local shrinkTween = TweenService:Create(bar, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
				Size = UDim2.new(bar.Size.X.Scale, bar.Size.X.Offset, 0, 0),
			})
			shrinkTween:Play()
			shrinkTween.Completed:Connect(function()
				bar:Destroy()
			end)
			activeBars[ci] = nil
			barCurrentTiles[ci] = nil
		end
	end
end

-- Clear all active bars (called when leaving Color Battle)
local function ClearColorBattleBars()
	for ci, bar in pairs(activeBars) do
		if bar and bar.Parent then
			bar:Destroy()
		end
	end
	activeBars = {}
	barCurrentTiles = {}
	knownPlayerColors = {}
end

-- ============================================================
-- RESPAWN LEADERBOARD (top 3 kills)
-- ============================================================

-- Find and cache leaderboard templates from the pre-built UI
local function InitLeaderboard()
	-- Re-initialize if the cached holder was destroyed (e.g. ResetOnSpawn re-cloned the ScreenGui)
	if leaderboardHolder and leaderboardHolder.Parent then return end -- still valid

	-- Reset stale references
	leaderboardHolder = nil
	lbTemplates = {}

	-- Search for RespawnEliminations > LeaderboardHolder inside any ScreenGui
	for _, gui in ipairs(playerGui:GetChildren()) do
		if not gui:IsA("ScreenGui") then continue end
		local respawnElim = gui:FindFirstChild("RespawnEliminations", true)
		if respawnElim then
			local holder = respawnElim:FindFirstChild("LeaderboardHolder") :: Frame?
			if holder then
				leaderboardHolder = holder

				-- Clone templates and remove originals from layout
				local names = { "1stTemplate", "2ndTemplate", "3rdTemplate" }
				for i, tplName in ipairs(names) do
					local tpl = holder:FindFirstChild(tplName) :: Frame?
					if tpl then
						lbTemplates[i] = tpl:Clone()
						tpl:Destroy()
					end
				end
				break
			end
		end
	end
end

-- Clear all active leaderboard entries
local function ClearLeaderboard()
	for _, entry in ipairs(lbActiveEntries) do
		if entry and entry.Parent then
			entry:Destroy()
		end
	end
	lbActiveEntries = {}
	lbKillCounts = {}
end

-- Show/hide the leaderboard holder (and its parent RespawnEliminations frame)
local function SetLeaderboardVisible(vis: boolean)
	if leaderboardHolder then
		leaderboardHolder.Visible = vis
		-- Also toggle the parent RespawnEliminations frame
		local respawnElim = leaderboardHolder.Parent
		if respawnElim then
			respawnElim.Visible = vis
		end
	end
end

-- Get sorted top players by kills (max 3)
local function GetTopPlayers(): {{userId: number, kills: number}}
	local entries: {{userId: number, kills: number}} = {}
	for userId, kills in pairs(lbKillCounts) do
		-- Only include players still in the game
		local p = Players:GetPlayerByUserId(userId)
		if p then
			table.insert(entries, { userId = userId, kills = kills })
		end
	end

	-- Sort descending by kills, then by userId for stability
	table.sort(entries, function(a, b)
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		return a.userId < b.userId
	end)

	-- Cap at 3
	if #entries > 3 then
		local trimmed = {}
		for i = 1, 3 do
			trimmed[i] = entries[i]
		end
		return trimmed
	end
	return entries
end

-- Update a single leaderboard entry frame with player data
local function SetupLBEntry(entry: Frame, data: {userId: number, kills: number})
	-- PlayerName
	local playerName = entry:FindFirstChild("PlayerName") :: TextLabel?
	if playerName and playerName:IsA("TextLabel") then
		local p = Players:GetPlayerByUserId(data.userId)
		playerName.Text = if p then p.DisplayName else "???"
	end

	-- Eliminations count
	local elimLabel = entry:FindFirstChild("Eliminations") :: TextLabel?
	if elimLabel and elimLabel:IsA("TextLabel") then
		elimLabel.Text = tostring(data.kills)
	end

	-- Player icon (headshot thumbnail)
	local playerIcon = entry:FindFirstChild("PlayerIcon") :: ImageLabel?
	if playerIcon and playerIcon:IsA("ImageLabel") then
		local ok, thumb = pcall(function()
			return Players:GetUserThumbnailAsync(
				data.userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size48x48
			)
		end)
		if ok and thumb then
			playerIcon.Image = thumb
		end
	end
end

-- Rebuild the leaderboard display with animation
local function UpdateLeaderboard()
	if not isRespawnMode then return end

	-- Re-initialize if holder was destroyed (ResetOnSpawn re-cloned ScreenGui)
	if not leaderboardHolder or not leaderboardHolder.Parent then
		InitLeaderboard()
	end
	if not leaderboardHolder then return end

	local topPlayers = GetTopPlayers()

	-- Only show players with at least 1 kill
	local showPlayers: {{userId: number, kills: number}} = {}
	for _, entry in ipairs(topPlayers) do
		if entry.kills > 0 then
			table.insert(showPlayers, entry)
		end
	end

	-- Build a map of old entry positions: userId -> layoutOrder
	local oldOrder: {[number]: number} = {}
	for _, entry in ipairs(lbActiveEntries) do
		local uid = entry:GetAttribute("UserId")
		local lo = entry.LayoutOrder
		if uid then
			oldOrder[uid] = lo
		end
	end

	-- Destroy old entries
	for _, entry in ipairs(lbActiveEntries) do
		if entry and entry.Parent then
			entry:Destroy()
		end
	end
	lbActiveEntries = {}

	-- Create new entries from templates
	for rank, data in ipairs(showPlayers) do
		local template = lbTemplates[rank]
		if not template then continue end

		local entry = template:Clone()
		entry.Name = "LB_" .. rank
		entry.LayoutOrder = rank
		entry.Visible = true
		entry:SetAttribute("UserId", data.userId)

		SetupLBEntry(entry, data)

		entry.Parent = leaderboardHolder
		table.insert(lbActiveEntries, entry)

		-- Animate if player changed position
		local prevOrder = oldOrder[data.userId]
		if prevOrder and prevOrder ~= rank then
			-- Position changed — scale bounce animation
			local uiScale = entry:FindFirstChildOfClass("UIScale")
			if not uiScale then
				uiScale = Instance.new("UIScale")
				uiScale.Parent = entry
			end
			uiScale.Scale = 1.25
			TweenService:Create(uiScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		elseif not prevOrder and #oldOrder > 0 then
			-- New entry appearing — slide in from left
			local origPos = entry.Position
			entry.Position = UDim2.new(origPos.X.Scale - 0.5, origPos.X.Offset, origPos.Y.Scale, origPos.Y.Offset)
			TweenService:Create(entry, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Position = origPos,
			}):Play()
		end
	end

	-- Show or hide the holder based on whether there are entries
	SetLeaderboardVisible(#showPlayers > 0)
end

-- Handle a kill event for the respawn leaderboard
local function OnRespawnKill(victimId: number, killerId: number)
	if not isRespawnMode then return end
	if killerId <= 0 then return end -- environmental kill
	if killerId == victimId then return end -- self-kill

	lbKillCounts[killerId] = (lbKillCounts[killerId] or 0) + 1
	UpdateLeaderboard()
end

-- Show countdown with bounce animation
local function ShowCountdown(number: number, text: string?)
	countdownLabel.Visible = true
	countdownLabel.TextTransparency = 0
	countdownLabel.TextStrokeTransparency = 0
	countdownLabel.Rotation = 0

	if text then
		-- Final text: "Bomb Them Up!" — red with dark red stroke
		countdownLabel.Text = text
		countdownLabel.TextColor3 = Color3.fromRGB(255, 30, 30)
		countdownLabel.TextStrokeColor3 = Color3.fromRGB(140, 20, 20)
		countdownLabel.TextSize = 28
		countdownLabel.Rotation = -3

		local tween1 = TweenService:Create(countdownLabel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			TextSize = 52,
			Rotation = 0
		})
		tween1:Play()

		task.delay(0.6, function()
			TweenService:Create(countdownLabel, TweenInfo.new(0.2), {
				TextTransparency = 1,
				TextStrokeTransparency = 1
			}):Play()
			task.delay(0.2, function()
				countdownLabel.Visible = false
			end)
		end)
	else
		-- Numbers: "3!" "2!" "1!" — white with dark red stroke
		if countdownSound and number == 3 then countdownSound:Play() end
		countdownLabel.Text = tostring(number) .. "!"
		countdownLabel.TextColor3 = Color3.new(1, 1, 1)
		countdownLabel.TextStrokeColor3 = Color3.fromRGB(140, 20, 20)
		countdownLabel.TextSize = 30
		countdownLabel.Rotation = -5

		local tween1 = TweenService:Create(countdownLabel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			TextSize = 56,
			Rotation = 0
		})
		tween1:Play()

		-- Fade out at end of second
		task.delay(0.7, function()
			TweenService:Create(countdownLabel, TweenInfo.new(0.25), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
		end)
	end
end

-- Show power-up collection effect - Vibrant popup with colored stroke
-- Map power-up types to icon asset names
local POWERUP_ICON_MAP = {
	BOMB_UP = "BombIcon",
	FIRE_UP = "FireIcon",
	SPEED_UP = "LightningIcon",
}

local function ShowPowerUpEffect(powerUpType: string)
	local powerUpData = Constants.POWERUP_TYPES[powerUpType]
	if not powerUpData then
		if powerUpType == "COIN" then
			powerUpData = {icon = "🪙", name = "Coin", color = COLORS.ACCENT}
		else
			return
		end
	end

	-- Container for icon + "+1" text, starts at center of screen
	local container = Instance.new("Frame")
	container.Name = "PowerUpPopup"
	container.Size = UDim2.new(0, 120, 0, 60)
	container.Position = UDim2.new(0.5, -60, 0.45, 0)
	container.BackgroundTransparency = 1
	container.ZIndex = 100
	container.Parent = screenGui

	-- Icon image from Assets/UI
	local iconAssetName = POWERUP_ICON_MAP[powerUpType]
	local UIAssets = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("UI")

	if iconAssetName and UIAssets then
		local iconAsset = UIAssets:FindFirstChild(iconAssetName)
		if iconAsset and iconAsset:IsA("ImageLabel") then
			local iconImage = Instance.new("ImageLabel")
			iconImage.Name = "Icon"
			iconImage.Image = iconAsset.Image
			iconImage.Size = UDim2.new(0, 50, 0, 50)
			iconImage.Position = UDim2.new(0, 0, 0.5, -25)
			iconImage.BackgroundTransparency = 1
			iconImage.ScaleType = Enum.ScaleType.Fit
			iconImage.ZIndex = 101
			iconImage.Parent = container
		end
	end

	-- "+1" text label
	local plusLabel = Instance.new("TextLabel")
	plusLabel.Name = "PlusOne"
	plusLabel.Size = UDim2.new(0, 60, 0, 50)
	plusLabel.Position = UDim2.new(0, 55, 0.5, -25)
	plusLabel.BackgroundTransparency = 1
	plusLabel.Text = if powerUpType == "COIN" then "+10" else "+1"
	plusLabel.TextColor3 = COLORS.LIGHT
	plusLabel.TextSize = 36
	plusLabel.Font = Enum.Font.FredokaOne
	plusLabel.ZIndex = 101
	plusLabel.Parent = container

	local plusStroke = Instance.new("UIStroke")
	plusStroke.Color = COLORS.DARK
	plusStroke.Thickness = 2
	plusStroke.Parent = plusLabel

	-- Animate: float upward while fading out
	local startPos = container.Position
	local endPos = UDim2.new(startPos.X.Scale, startPos.X.Offset, startPos.Y.Scale - 0.15, startPos.Y.Offset)

	TweenService:Create(container, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = endPos,
	}):Play()

	-- Fade out after a brief hold
	task.delay(0.5, function()
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("ImageLabel") then
				TweenService:Create(child, TweenInfo.new(0.6), { ImageTransparency = 1 }):Play()
			elseif child:IsA("TextLabel") then
				TweenService:Create(child, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
				local childStroke = child:FindFirstChildOfClass("UIStroke")
				if childStroke then
					TweenService:Create(childStroke, TweenInfo.new(0.6), { Transparency = 1 }):Play()
				end
			end
		end

		task.delay(0.7, function()
			container:Destroy()
		end)
	end)
end

-- Animate the NavHUD MoneyLabel with a typewriter count-up
local function AnimateMoneyLabel(coinsEarned: number, totalCoins: number)
	if not moneyLabel or coinsEarned <= 0 then return end

	local startVal = totalCoins - coinsEarned
	if startVal < 0 then startVal = 0 end

	-- Set starting value
	moneyLabel.Text = "$" .. tostring(startVal)

	local duration = 0.8
	local steps = math.min(coinsEarned, 30)
	if steps == 0 then steps = 1 end
	local stepTime = duration / steps

	for i = 1, steps do
		local value = math.floor(startVal + (i / steps) * coinsEarned)
		moneyLabel.Text = "$" .. tostring(value)
		task.wait(stepTime)
	end

	moneyLabel.Text = "$" .. tostring(totalCoins)

	-- Quick pulse on the money label
	local origSize = moneyLabel.Size
	local pulseSize = UDim2.new(
		origSize.X.Scale * 1.15, origSize.X.Offset * 1.15,
		origSize.Y.Scale * 1.15, origSize.Y.Offset * 1.15
	)
	local grow = TweenService:Create(moneyLabel, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = pulseSize,
	})
	grow:Play()
	grow.Completed:Wait()
	TweenService:Create(moneyLabel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = origSize,
	}):Play()
end

-- Update lobby info display
local function UpdateLobbyInfo(state: string, timer: number?)
	if not bannerUI then return end
	currentBannerState = state
	if state == Constants.STATES.LOBBY then
		bannerUI.Enabled = true
		if bannerBG then bannerBG.Visible = true end
		if timer and timer > 0 then
			SetBannerText("Starting in " .. timer .. "s")
		else
			SetBannerText("Waiting for players...")
		end
	elseif state == Constants.STATES.CHARACTER_SELECT then
		bannerUI.Enabled = true
		if bannerBG then bannerBG.Visible = true end
		if timer and timer > 0 then
			SetBannerText("Pick Your Bomber! " .. timer .. "s")
		else
			SetBannerText("Pick Your Bomber!")
		end
	elseif state == Constants.STATES.INTERMISSION then
		bannerUI.Enabled = true
		if bannerBG then bannerBG.Visible = true end
		if timer and timer > 0 then
			SetBannerText("Next round in " .. timer .. "s")
		else
			SetBannerText("Get Ready!")
		end
	else
		if bannerBG then bannerBG.Visible = false end
		currentBannerState = nil
	end
end

-- Handle game state changes
RoundStateChanged.OnClientEvent:Connect(function(state: string, data: any?)
	lastRoundState = state
	lastRoundData = data

	-- Track current mode for Color Battle / Respawn display
	if data and type(data) == "table" and data.mode then
		-- Show/hide ColorBattleDisplayUI based on mode
		if colorBattleDisplayUI then
			colorBattleDisplayUI.Visible = data.mode.paintTiles == true
		end
		-- Track respawn mode for leaderboard
		isRespawnMode = data.mode.respawn == true
	end

	-- AFK players keep lobby UI during game states (no HUD, keep NavHUD visible)
	if isAFK and (state == "Preparing" or state == Constants.STATES.PLAYING or state == Constants.STATES.COUNTDOWN or state == "Countdown") then
		hudFrame.Visible = false
		countdownLabel.Visible = false
		if navHUD then navHUD.Enabled = true end
		if mobileControls then mobileControls.Visible = false end
		if colorBattleDisplayUI then colorBattleDisplayUI.Visible = false end
		if bannerUI then bannerUI.Enabled = true end
		if bannerBG then bannerBG.Visible = true end
		SetBannerText("You are AFK")
		return
	end

	if state == "Preparing" then
		-- Show preparation text
		hudFrame.Visible = false
		if bannerUI then
			bannerUI.Enabled = true
			if bannerBG then bannerBG.Visible = true end
			SetBannerText("Teleporting Players...")
		end
		if navHUD then navHUD.Enabled = false end
		if mobileControls then mobileControls.Visible = false end

		-- Respawn leaderboard: reset and init for new round
		ClearLeaderboard()
		if isRespawnMode then
			InitLeaderboard()
			SetLeaderboardVisible(false) -- hidden until first kill
		end
	elseif state == Constants.STATES.PLAYING then
		hudFrame.Visible = true
		countdownLabel.Visible = false
		-- Re-enable bannerUI for the round timer display
		if bannerUI then bannerUI.Enabled = true end
		if bannerBG then bannerBG.Visible = true end
		if navHUD then navHUD.Enabled = false end
		if mobileControls then
			mobileControls.Visible = true
		end

		-- Respawn leaderboard: ensure initialized (fallback if Preparing was missed or ScreenGui was re-cloned)
		if isRespawnMode and (not leaderboardHolder or not leaderboardHolder.Parent) then
			InitLeaderboard()
			SetLeaderboardVisible(false)
		end
	elseif state == Constants.STATES.COUNTDOWN or state == "Countdown" then
		hudFrame.Visible = false
		if bannerUI then bannerUI.Enabled = true end
		if bannerBG then bannerBG.Visible = false end
		if navHUD then navHUD.Enabled = false end
		if mobileControls then
			mobileControls.Visible = false
		end
		-- Show countdown numbers/text if data is provided (per-second tick events)
		if data and type(data) == "table" then
			if data.number and data.number >= 0 then
				ShowCountdown(data.number, nil)
			elseif data.text then
				ShowCountdown(-1, data.text)
			end
		end
	elseif state == Constants.STATES.ROUND_END or state == "RoundResults" then
		hudFrame.Visible = false
		if bannerUI then bannerUI.Enabled = true end
		if bannerBG then bannerBG.Visible = false end
		if navHUD then navHUD.Enabled = false end
		if colorBattleDisplayUI then colorBattleDisplayUI.Visible = false end
		ClearColorBattleBars()
		ClearLeaderboard()
		SetLeaderboardVisible(false)
		isRespawnMode = false
		if mobileControls then
			mobileControls.Visible = false
		end
		-- Capture coins earned for NavHUD typewriter later
		if state == "RoundResults" and data and data.results then
			local userId = player.UserId
			for _, result in ipairs(data.results) do
				if result.userId == userId then
					pendingCoinsEarned = result.coins or 0
					pendingTotalCoins = result.totalCoins or 0
					break
				end
			end
		end
	elseif state == Constants.STATES.INTERMISSION then
		hudFrame.Visible = false
		countdownLabel.Visible = false
		if colorBattleDisplayUI then colorBattleDisplayUI.Visible = false end
		ClearColorBattleBars()
		ClearLeaderboard()
		SetLeaderboardVisible(false)
		UpdateLobbyInfo(state, nil)
		if navHUD then navHUD.Enabled = true end
		if mobileControls then
			mobileControls.Visible = false
		end
		-- Animate money label with earned coins
		if pendingCoinsEarned > 0 then
			local coins = pendingCoinsEarned
			local total = pendingTotalCoins
			pendingCoinsEarned = 0
			pendingTotalCoins = 0
			task.spawn(function()
				task.wait(0.3) -- Brief delay for NavHUD to become visible
				AnimateMoneyLabel(coins, total)
			end)
		end
	elseif state == Constants.STATES.LOBBY then
		hudFrame.Visible = false
		countdownLabel.Visible = false
		if colorBattleDisplayUI then colorBattleDisplayUI.Visible = false end
		ClearColorBattleBars()
		ClearLeaderboard()
		SetLeaderboardVisible(false)
		UpdateLobbyInfo(state, nil)
		if navHUD then navHUD.Enabled = true end
		if mobileControls then
			mobileControls.Visible = false
		end
		-- Animate money label with earned coins (if returning from FadeToLobby)
		if pendingCoinsEarned > 0 then
			local coins = pendingCoinsEarned
			local total = pendingTotalCoins
			pendingCoinsEarned = 0
			pendingTotalCoins = 0
			task.spawn(function()
				task.wait(0.3)
				AnimateMoneyLabel(coins, total)
			end)
		end
	elseif state == "FadeToLobby" then
		-- Player died and returned to lobby mid-round, or round ended
		hudFrame.Visible = false
		countdownLabel.Visible = false
		if colorBattleDisplayUI then colorBattleDisplayUI.Visible = false end
		ClearColorBattleBars()
		ClearLeaderboard()
		SetLeaderboardVisible(false)
		if navHUD then navHUD.Enabled = true end
		if mobileControls then
			mobileControls.Visible = false
		end
	elseif state == Constants.STATES.CHARACTER_SELECT then
		UpdateLobbyInfo(state, nil)
	elseif state == "Timer" and data and data.timer then
		if bannerUI and bannerUI.Enabled and currentBannerState then
			UpdateLobbyInfo(currentBannerState, data.timer)
		end
	end
end)

-- Handle HUD updates
UpdateHUD.OnClientEvent:Connect(function(updateType: string, value: any)
	if updateType == "Timer" then
		UpdateTimer(value)
	end
end)

-- Handle power-up collection
PowerUpCollected.OnClientEvent:Connect(function(powerUpType: string)
	ShowPowerUpEffect(powerUpType)
end)

-- Update Color Battle display periodically during gameplay
task.spawn(function()
	while true do
		task.wait(0.5)
		if hudFrame.Visible and colorBattleDisplayUI and colorBattleDisplayUI.Visible then
			UpdateColorBattleDisplay()
		end
	end
end)

-- Connect PlayerDied for respawn leaderboard kill tracking
task.spawn(function()
	PlayerDied = Remotes:WaitForChild("PlayerDied", 15) :: RemoteEvent?
	if PlayerDied then
		PlayerDied.OnClientEvent:Connect(function(victimId: number, killerId: number?)
			OnRespawnKill(victimId, killerId or 0)
		end)
	end
end)

-- AFK state listener: when toggled AFK mid-game, restore lobby UI
task.spawn(function()
	local afkVal = player:FindFirstChild("IsAFK") :: BoolValue?
	if not afkVal then
		afkVal = player:WaitForChild("IsAFK", 10) :: BoolValue?
	end
	if afkVal then
		isAFK = afkVal.Value
		afkVal.Changed:Connect(function(value: boolean)
			isAFK = value
			if isAFK then
				-- Immediately restore lobby UI state
				hudFrame.Visible = false
				countdownLabel.Visible = false
				if navHUD then navHUD.Enabled = true end
				if mobileControls then mobileControls.Visible = false end
				if colorBattleDisplayUI then colorBattleDisplayUI.Visible = false end
				if bannerUI then bannerUI.Enabled = true end
				if bannerBG then bannerBG.Visible = true end
				SetBannerText("You are AFK")
			else
				-- Un-AFK: restore correct UI for current state
				-- During gameplay states, AFK players sit in lobby, so show lobby banner
				-- During lobby/intermission states, just restore the normal banner
				local state = lastRoundState
				if state == Constants.STATES.LOBBY or state == Constants.STATES.INTERMISSION or state == Constants.STATES.CHARACTER_SELECT then
					UpdateLobbyInfo(state, nil)
				elseif state == Constants.STATES.PLAYING or state == "Preparing" or state == Constants.STATES.COUNTDOWN or state == "Countdown" then
					-- Player is in lobby while game is running
					if bannerUI then bannerUI.Enabled = true end
					if bannerBG then bannerBG.Visible = true end
					SetBannerText("Waiting for round to end...")
				else
					-- Fallback: show generic lobby text
					if bannerUI then bannerUI.Enabled = true end
					if bannerBG then bannerBG.Visible = true end
					SetBannerText("Waiting for players...")
				end
			end
		end)
	end
end)

-- Initialize
CreateUI()
if isMobile then
	CreateMobileControls()
end
UpdateLobbyInfo(Constants.STATES.LOBBY, nil)
print("[GameUI] Initialized")
