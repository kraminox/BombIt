--!strict
-- WinnersUI.client.lua
-- Results screen using pre-built ResultsUI ScreenGui + XPProgress bar + cinematic bars

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

-- Sound effects
local SoundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
local UISounds = SoundsFolder and SoundsFolder:FindFirstChild("UI")
local xpDingSound: Sound? = UISounds and UISounds:FindFirstChild("XPDing") :: Sound? or nil
local achieveSound: Sound? = UISounds and UISounds:FindFirstChild("Achieve") :: Sound? or nil

-- Wait for remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged")

-- Sticker remote (created by server)
local ShowSticker

task.spawn(function()
	ShowSticker = Remotes:WaitForChild("ShowSticker", 10)
end)

-- ResultsUI references (pre-built ScreenGui)
local resultsUI = playerGui:WaitForChild("ResultsUI")
local parentFrame = resultsUI:WaitForChild("ParentFrame")
local topDivider = parentFrame:WaitForChild("TopDivider")
local resultLabel = parentFrame:WaitForChild("ResultLabel") :: TextLabel
local killsLabel = parentFrame:WaitForChild("KillsLabel") :: TextLabel
local demosLabel = parentFrame:WaitForChild("DemosLabel") :: TextLabel
local powersLabel = parentFrame:WaitForChild("PowersLabel") :: TextLabel
local rewardFrame = parentFrame:WaitForChild("RewardFrame")
local coinsImage = rewardFrame:WaitForChild("CoinsImage")
local coinsValue = rewardFrame:WaitForChild("CoinsValue") :: TextLabel
local xpImage = rewardFrame:WaitForChild("XpImage")
local xpValue = rewardFrame:WaitForChild("XpValue") :: TextLabel
local capsuleImage = rewardFrame:WaitForChild("CapsuleImage")
local capsuleValue = rewardFrame:WaitForChild("CapsuleValue") :: TextLabel

-- XPProgress references (pre-built ScreenGui)
local xpProgressUI = playerGui:WaitForChild("XPProgress")
local xpProgressFrame = xpProgressUI:WaitForChild("ParentFrame")
local xpFill = xpProgressFrame:WaitForChild("ProgressFill") :: Frame
local xpStarImage = xpProgressFrame:WaitForChild("StarImage") :: ImageLabel
local xpStudBg = xpProgressFrame:WaitForChild("StudBg") :: ImageLabel
local xpProgressText = xpProgressFrame:WaitForChild("ProgressValue") :: TextLabel
local xpLevelText = xpProgressFrame:WaitForChild("LevelValue") :: TextLabel

-- Store original sizes/positions for animations
local killsOriginalSize: UDim2
local demosOriginalSize: UDim2
local powersOriginalSize: UDim2
local parentFrameOriginalPosition: UDim2
local rewardFrameOriginalSize: UDim2
local xpProgressFrameOrigPos: UDim2
local xpFillOrigSize: UDim2
local xpStarOrigSize: UDim2

-- Cinematic bars (code-created)
local topBar: Frame
local bottomBar: Frame
local BAR_HEIGHT = 0.10

-- Full-screen black fade for round transitions
local fadeOverlay: Frame? = nil

-- Track active stickers
local activeStickers = {}

-- Track animation state
local isShowing = false

-- Track current game mode (updated from state changes)
local currentMode: any = nil

-- Helper: play a tween and return it
local function PlayTween(instance: Instance, info: TweenInfo, props: {[string]: any}): Tween
	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

-- Initialize: grab original sizes and hide everything
local function InitializeUI()
	killsOriginalSize = killsLabel.Size
	demosOriginalSize = demosLabel.Size
	powersOriginalSize = powersLabel.Size
	parentFrameOriginalPosition = parentFrame.Position
	rewardFrameOriginalSize = rewardFrame.Size

	xpProgressFrameOrigPos = xpProgressFrame.Position
	xpFillOrigSize = xpFill.Size
	xpStarOrigSize = xpStarImage.Size

	-- Hide ResultsUI
	resultsUI.Enabled = false
	parentFrame.Visible = false
	resultLabel.Visible = false
	killsLabel.Visible = false
	demosLabel.Visible = false
	powersLabel.Visible = false
	rewardFrame.Visible = false
	capsuleImage.Visible = false
	capsuleValue.Visible = false
	xpImage.Visible = false
	xpValue.Visible = false

	-- Hide XPProgress
	xpProgressUI.Enabled = false
end

-- Create cinematic bars and emote frame
local function CreateCinematicUI()
	-- Cinematic ScreenGui (separate so it layers correctly)
	local cinematicGui = Instance.new("ScreenGui")
	cinematicGui.Name = "CinematicUI"
	cinematicGui.ResetOnSpawn = false
	cinematicGui.DisplayOrder = 10
	cinematicGui.IgnoreGuiInset = true
	cinematicGui.Enabled = false
	cinematicGui.Parent = playerGui

	-- Top bar
	topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, BAR_HEIGHT, 0)
	topBar.Position = UDim2.new(0, 0, -BAR_HEIGHT, 0)
	topBar.BackgroundColor3 = Color3.new(0, 0, 0)
	topBar.BorderSizePixel = 0
	topBar.ZIndex = 5
	topBar.Parent = cinematicGui

	-- Bottom bar
	bottomBar = Instance.new("Frame")
	bottomBar.Name = "BottomBar"
	bottomBar.Size = UDim2.new(1, 0, BAR_HEIGHT, 0)
	bottomBar.Position = UDim2.new(0, 0, 1, 0)
	bottomBar.BackgroundColor3 = Color3.new(0, 0, 0)
	bottomBar.BorderSizePixel = 0
	bottomBar.ZIndex = 5
	bottomBar.Parent = cinematicGui

	-- Full-screen black fade overlay (hidden by default, used during round prep)
	fadeOverlay = Instance.new("Frame")
	fadeOverlay.Name = "FadeOverlay"
	fadeOverlay.Size = UDim2.new(1, 0, 1, 0)
	fadeOverlay.Position = UDim2.new(0, 0, 0, 0)
	fadeOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
	fadeOverlay.BackgroundTransparency = 1
	fadeOverlay.BorderSizePixel = 0
	fadeOverlay.ZIndex = 10
	fadeOverlay.Parent = cinematicGui

	return cinematicGui
end

-- Show sticker above player's head
local function DisplaySticker(userId: number, stickerId: string)
	local targetPlayer = Players:GetPlayerByUserId(userId)
	if not targetPlayer or not targetPlayer.Character then return end

	local head = targetPlayer.Character:FindFirstChild("Head")
	if not head then return end

	local stickerData
	for _, sticker in ipairs(Constants.STICKERS) do
		if sticker.id == stickerId then
			stickerData = sticker
			break
		end
	end
	if not stickerData then return end

	if activeStickers[userId] then
		activeStickers[userId]:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Sticker_" .. stickerId
	billboard.Size = UDim2.new(0, 100, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = head

	local stickerLabel = Instance.new("TextLabel")
	stickerLabel.Size = UDim2.new(1, 0, 1, 0)
	stickerLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	stickerLabel.BackgroundTransparency = 0.3
	stickerLabel.Text = stickerData.text
	stickerLabel.TextColor3 = stickerData.color
	stickerLabel.TextScaled = true
	stickerLabel.Font = Enum.Font.GothamBold
	stickerLabel.Parent = billboard

	local stickerCorner = Instance.new("UICorner")
	stickerCorner.CornerRadius = UDim.new(0, 8)
	stickerCorner.Parent = stickerLabel

	activeStickers[userId] = billboard

	billboard.StudsOffset = Vector3.new(0, 2, 0)
	PlayTween(billboard, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, 3, 0)
	})

	task.delay(3, function()
		if billboard and billboard.Parent then
			PlayTween(billboard, TweenInfo.new(0.2), { StudsOffset = Vector3.new(0, 4, 0) })
			PlayTween(stickerLabel, TweenInfo.new(0.2), { BackgroundTransparency = 1, TextTransparency = 1 })
			task.wait(0.2)
			billboard:Destroy()
			if activeStickers[userId] == billboard then
				activeStickers[userId] = nil
			end
		end
	end)
end

-- Find local player's stats from results
local function FindPlayerStats(results: any, userId: number): (number, number, number, number, number, number)
	local coins, kills, demolitions, powerups, xp, tilesOwned = 0, 0, 0, 0, 0, 0
	if results then
		for _, result in ipairs(results) do
			if result.userId == userId then
				coins = result.coins or 0
				kills = result.kills or 0
				demolitions = result.demolitions or 0
				powerups = result.powerupsCollected or 0
				xp = result.xp or 0
				tilesOwned = result.tilesOwned or 0
				break
			end
		end
	end
	-- Ensure minimum rewards are always shown
	coins = math.max(coins, 50)
	xp = math.max(xp, 100)
	return coins, kills, demolitions, powerups, xp, tilesOwned
end

-- Find local player's XP progression from results
local function FindPlayerXPProgression(results: any, userId: number): (number, number)
	local xpBefore, xpAfter = 0, 0
	if results then
		for _, result in ipairs(results) do
			if result.userId == userId then
				xpBefore = result.xpBefore or 0
				xpAfter = result.xpAfter or 0
				break
			end
		end
	end
	return xpBefore, xpAfter
end

-- Typewriter count-up animation with ding sounds and achieve on land (reusable for coins, XP, etc.)
local function AnimateCountUp(label: TextLabel, finalValue: number)
	-- Ensure label is visible and not transparent
	label.Visible = true
	label.TextTransparency = 0
	label.Text = "0"
	if finalValue == 0 then return end

	local duration = 0.8
	local steps = math.min(finalValue, 40)
	local stepTime = duration / steps

	-- Play XPDing every few steps
	local dingInterval = math.max(1, math.floor(steps / 8))

	for i = 1, steps do
		local value = math.floor((i / steps) * finalValue)
		-- Format large numbers
		if value >= 1000 then
			label.Text = string.format("%.1fK", value / 1000)
		else
			label.Text = tostring(value)
		end

		if xpDingSound and (i % dingInterval == 1 or steps <= 8) then
			xpDingSound:Play()
		end

		task.wait(stepTime)
	end

	-- Set final value
	if finalValue >= 1000 then
		label.Text = string.format("%.1fK", finalValue / 1000)
	else
		label.Text = tostring(finalValue)
	end

	-- Play achieve sound when landing on final number
	if achieveSound then achieveSound:Play() end

	-- Pulse effect at final value
	local originalSize = label.Size
	local pulseSize = UDim2.new(
		originalSize.X.Scale * 1.3, originalSize.X.Offset * 1.3,
		originalSize.Y.Scale * 1.3, originalSize.Y.Offset * 1.3
	)

	local grow = PlayTween(label, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = pulseSize,
	})
	grow.Completed:Wait()

	PlayTween(label, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = originalSize,
	})
end

-- Typewriter for progress bar "X/Y" format (with XPDing sound on each tick)
local function AnimateProgressCountUp(label: TextLabel, startVal: number, endVal: number, maxVal: number)
	if startVal == endVal then
		label.Text = endVal .. "/" .. maxVal
		return
	end

	local duration = 0.6
	local diff = math.abs(endVal - startVal)
	local steps = math.min(diff, 30)
	if steps == 0 then steps = 1 end
	local stepTime = duration / steps

	-- Play XPDing every few steps so it's not overwhelming
	local dingInterval = math.max(1, math.floor(steps / 8))

	for i = 1, steps do
		local value = math.floor(startVal + (i / steps) * (endVal - startVal))
		label.Text = value .. "/" .. maxVal

		if xpDingSound and (i % dingInterval == 1 or steps <= 8) then
			xpDingSound:Play()
		end

		task.wait(stepTime)
	end

	label.Text = endVal .. "/" .. maxVal
end

-- Scale-pop animation for a label (size 0 -> original)
local function AnimateScaleIn(label: TextLabel, originalSize: UDim2, delay_: number)
	label.Size = UDim2.new(0, 0, 0, 0)
	label.Visible = true

	task.delay(delay_, function()
		PlayTween(label, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = originalSize,
		})
	end)
end

-- Scale-out animation for a label
local function AnimateScaleOut(label: TextLabel, delay_: number)
	task.delay(delay_, function()
		local tween = PlayTween(label, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 0, 0, 0),
		})
		tween.Completed:Wait()
		label.Visible = false
	end)
end

-- Show the XP progress bar with fill animation
local function ShowXPProgress(xpBefore: number, xpAfter: number)
	if not isShowing then return end

	local levelBefore, progressBefore, neededBefore = Constants.GetLevelInfo(xpBefore)
	local levelAfter, progressAfter, neededAfter = Constants.GetLevelInfo(xpAfter)
	local didLevelUp = levelAfter > levelBefore

	-- Set initial state
	local startRatio = neededBefore > 0 and math.clamp(progressBefore / neededBefore, 0, 1) or 0
	xpFill.Size = UDim2.new(startRatio, 0, xpFillOrigSize.Y.Scale, xpFillOrigSize.Y.Offset)
	xpProgressText.Text = progressBefore .. "/" .. neededBefore
	xpLevelText.Text = "Lvl. " .. levelBefore

	-- Hide elements for animate-in
	xpStarImage.Size = UDim2.new(0, 0, 0, 0)
	xpStarImage.Visible = true
	xpLevelText.Visible = false
	xpProgressText.Visible = false
	xpStudBg.Visible = false

	-- Position below screen
	xpProgressFrame.Position = UDim2.new(
		xpProgressFrameOrigPos.X.Scale,
		xpProgressFrameOrigPos.X.Offset,
		1.5,
		0
	)
	xpProgressUI.DisplayOrder = 15 -- Above cinematic bars (DisplayOrder 10)
	xpProgressUI.Enabled = true

	-- Slide up — offset above the bottom cinematic bar (10% screen height)
	local slideTarget = UDim2.new(
		xpProgressFrameOrigPos.X.Scale,
		xpProgressFrameOrigPos.X.Offset,
		xpProgressFrameOrigPos.Y.Scale - BAR_HEIGHT - 0.02,
		xpProgressFrameOrigPos.Y.Offset
	)
	local slideTween = PlayTween(xpProgressFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = slideTarget,
	})
	slideTween.Completed:Wait()
	if not isShowing then return end

	-- Animate elements in
	PlayTween(xpStarImage, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = xpStarOrigSize,
	})
	task.wait(0.1)
	xpStudBg.Visible = true
	xpLevelText.Visible = true
	xpProgressText.Visible = true
	task.wait(0.15)
	if not isShowing then return end

	-- Animate progress fill and typewriter
	if didLevelUp then
		-- Handle multi-level-ups one level at a time
		local curLevel = levelBefore
		local curProgress = progressBefore
		local curNeeded = neededBefore

		while curLevel < levelAfter do
			-- Fill bar to 100% on current level
			PlayTween(xpFill, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Size = UDim2.new(1, 0, xpFillOrigSize.Y.Scale, xpFillOrigSize.Y.Offset),
			})
			AnimateProgressCountUp(xpProgressText, curProgress, curNeeded, curNeeded)
			task.wait(0.2)
			if not isShowing then return end

			curLevel = curLevel + 1

			-- Play achieve sound on level up
			if achieveSound then achieveSound:Play() end

			-- Update level text
			xpLevelText.Text = "Lvl. " .. curLevel

			-- Pulse level text using offset-based sizing (works for both Scale and Offset labels)
			local origLevelSize = xpLevelText.Size
			local pulseLevelSize = UDim2.new(
				origLevelSize.X.Scale * 1.3, origLevelSize.X.Offset * 1.3,
				origLevelSize.Y.Scale * 1.3, origLevelSize.Y.Offset * 1.3
			)
			local levelGrow = PlayTween(xpLevelText, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = pulseLevelSize,
			})
			levelGrow.Completed:Wait()
			PlayTween(xpLevelText, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = origLevelSize,
			})
			task.wait(0.2)
			if not isShowing then return end

			-- Reset fill for next level
			xpFill.Size = UDim2.new(0, 0, xpFillOrigSize.Y.Scale, xpFillOrigSize.Y.Offset)

			-- Prep for next iteration
			curProgress = 0
			curNeeded = Constants.XP_PER_LEVEL_BASE + (curLevel - 1) * Constants.XP_PER_LEVEL_GROWTH
		end

		-- Final fill to actual progress on the final level
		local newRatio = neededAfter > 0 and math.clamp(progressAfter / neededAfter, 0, 1) or 0
		PlayTween(xpFill, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = UDim2.new(newRatio, 0, xpFillOrigSize.Y.Scale, xpFillOrigSize.Y.Offset),
		})
		AnimateProgressCountUp(xpProgressText, 0, progressAfter, neededAfter)
	else
		-- Simple fill from old to new
		local newRatio = neededAfter > 0 and math.clamp(progressAfter / neededAfter, 0, 1) or 0
		PlayTween(xpFill, TweenInfo.new(0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = UDim2.new(newRatio, 0, xpFillOrigSize.Y.Scale, xpFillOrigSize.Y.Offset),
		})
		AnimateProgressCountUp(xpProgressText, progressBefore, progressAfter, neededAfter)
	end

	-- Hold
	task.wait(1.0)
	if not isShowing then return end

	-- Slide back down
	local slideDownTween = PlayTween(xpProgressFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
		Position = UDim2.new(xpProgressFrameOrigPos.X.Scale, xpProgressFrameOrigPos.X.Offset, 1.5, 0),
	})
	slideDownTween.Completed:Wait()
	xpProgressUI.Enabled = false
end

-- Hide the XP progress bar immediately
local function HideXPProgress()
	xpProgressUI.Enabled = false
	xpProgressFrame.Position = UDim2.new(
		xpProgressFrameOrigPos.X.Scale,
		xpProgressFrameOrigPos.X.Offset,
		1.5,
		0
	)
end

-- Show the results screen
local function ShowResults(data: any)
	if isShowing then return end
	isShowing = true

	local cinematicGui = topBar and topBar.Parent :: ScreenGui?
	if cinematicGui then
		cinematicGui.Enabled = true
	end

	-- Determine if local player won (check winnerIds array for team wins)
	local winnerId = data and data.winnerId or 0
	local winnerIds = data and data.winnerIds or {}
	local didWin = (winnerId == player.UserId)
	if not didWin and #winnerIds > 0 then
		for _, id in ipairs(winnerIds) do
			if id == player.UserId then
				didWin = true
				break
			end
		end
	end
	local isDraw = (winnerId == 0)

	-- Get local player's stats
	local coins, kills, demolitions, powerups, xp, tilesOwned = FindPlayerStats(data and data.results, player.UserId)
	local xpBefore, xpAfter = FindPlayerXPProgression(data and data.results, player.UserId)

	-- Set result text and color
	local resultStroke = resultLabel:FindFirstChildOfClass("UIStroke")
	if isDraw then
		resultLabel.Text = "Draw!"
		resultLabel.TextColor3 = Color3.fromRGB(255, 215, 0) -- Gold
		if resultStroke then resultStroke.Color = Color3.fromRGB(180, 150, 0) end
	elseif didWin then
		resultLabel.Text = "You Won!"
		resultLabel.TextColor3 = Color3.fromRGB(80, 220, 100) -- Green
		if resultStroke then resultStroke.Color = Color3.fromRGB(40, 140, 50) end
	else
		local winnerName = data and data.winner or "Someone"
		resultLabel.Text = winnerName .. " Won!"
		resultLabel.TextColor3 = Color3.fromRGB(255, 70, 100) -- Red-pink
		if resultStroke then resultStroke.Color = Color3.fromRGB(160, 30, 50) end
	end

	-- Set stat texts (will be revealed via scale animation)
	-- In Color Battle, show tiles claimed instead of kills
	local isColorBattle = currentMode and currentMode.paintTiles == true
	if isColorBattle then
		killsLabel.Text = "Tiles Claimed: " .. tostring(tilesOwned)
	else
		killsLabel.Text = "Kills: " .. tostring(kills)
	end
	demosLabel.Text = "Demolitions: " .. tostring(demolitions)
	powersLabel.Text = "Powerups: " .. tostring(powerups)

	-- Reset reward values
	coinsValue.Text = "0"
	coinsValue.Visible = true
	coinsValue.TextTransparency = 0
	xpValue.Text = "0"
	xpValue.Visible = true
	xpValue.TextTransparency = 0

	print("[WinnersUI] Coins:", coins, "XP:", xp, "CoinsValue exists:", coinsValue ~= nil, "XpValue exists:", xpValue ~= nil)

	-- Capsule: hidden unless earned (not implemented yet, always hidden)
	capsuleImage.Visible = false
	capsuleValue.Visible = false

	-- === Phase 1: Cinematic bars slide in ===
	PlayTween(topBar, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, 0, 0),
	})
	PlayTween(bottomBar, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, 1 - BAR_HEIGHT, 0),
	})

	-- === Phase 2: ParentFrame slides in from top with ResultLabel visible ===
	task.delay(0.3, function()
		resultsUI.Enabled = true
		parentFrame.Visible = true

		-- Start above screen
		parentFrame.Position = UDim2.new(
			parentFrameOriginalPosition.X.Scale,
			parentFrameOriginalPosition.X.Offset,
			-0.5,
			0
		)

		-- Show result label immediately (it rides in with the frame)
		resultLabel.Visible = true

		-- Hide stats until their turn
		killsLabel.Visible = false
		demosLabel.Visible = false
		powersLabel.Visible = false
		rewardFrame.Visible = false

		-- Slide parentFrame to original position
		local slideTween = PlayTween(parentFrame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = parentFrameOriginalPosition,
		})
		slideTween.Completed:Wait()

		-- === Phase 3: Stat labels scale in one by one ===
		AnimateScaleIn(killsLabel, killsOriginalSize, 0.0)
		AnimateScaleIn(demosLabel, demosOriginalSize, 0.15)
		AnimateScaleIn(powersLabel, powersOriginalSize, 0.3)

		-- === Phase 4: Reward frame animates in last ===
		task.delay(0.55, function()
			rewardFrame.Visible = true
			coinsImage.Visible = true
			coinsValue.Visible = true
			xpImage.Visible = true
			xpValue.Visible = true

			-- Scale reward frame in (use stored original size since HideResults zeroes it)
			rewardFrame.Size = UDim2.new(0, 0, 0, 0)
			local rewardTween = PlayTween(rewardFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = rewardFrameOriginalSize,
			})
			rewardTween.Completed:Wait()

			-- === Phase 5: Coins + XP count-up in parallel ===
			task.spawn(AnimateCountUp, coinsValue, coins)
			task.spawn(AnimateCountUp, xpValue, xp)

			-- Wait for count-ups to finish (~1.1s), then show XP progress bar
			task.wait(1.2)
			task.spawn(ShowXPProgress, xpBefore, xpAfter)
		end)
	end)

end

-- Hide the results screen
local function HideResults()
	if not isShowing then return end

	-- === Animate stat labels out ===
	AnimateScaleOut(killsLabel, 0.0)
	AnimateScaleOut(demosLabel, 0.05)
	AnimateScaleOut(powersLabel, 0.1)

	-- Scale reward frame out
	task.delay(0.1, function()
		PlayTween(rewardFrame, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 0, 0, 0),
		})
	end)

	-- Slide parent frame up and out
	task.delay(0.2, function()
		PlayTween(parentFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
			Position = UDim2.new(
				parentFrameOriginalPosition.X.Scale,
				parentFrameOriginalPosition.X.Offset,
				-0.5,
				0
			),
		})
	end)

	-- Slide cinematic bars out
	PlayTween(topBar, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
		Position = UDim2.new(0, 0, -BAR_HEIGHT, 0),
	})
	PlayTween(bottomBar, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
		Position = UDim2.new(0, 0, 1, 0),
	})

	-- Hide XP progress bar
	HideXPProgress()

	task.delay(0.6, function()
		resultsUI.Enabled = false
		parentFrame.Visible = false
		resultLabel.Visible = false
		killsLabel.Visible = false
		demosLabel.Visible = false
		powersLabel.Visible = false
		rewardFrame.Visible = false
		capsuleImage.Visible = false
		capsuleValue.Visible = false
		xpImage.Visible = false
		xpValue.Visible = false

		local cinematicGui = topBar and topBar.Parent :: ScreenGui?
		if cinematicGui then
			cinematicGui.Enabled = false
		end

		isShowing = false
	end)
end

-- Show full-screen black fade (used during "Preparing" to hide respawn/teleport)
local function ShowPreparingFade()
	if not fadeOverlay then return end
	local cinematicGui = fadeOverlay.Parent :: ScreenGui?
	if cinematicGui then
		cinematicGui.Enabled = true
	end
	PlayTween(fadeOverlay, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0,
	})
end

-- Fade out the black overlay (called when countdown cinematic is ready)
local function HidePreparingFade()
	if not fadeOverlay then return end
	PlayTween(fadeOverlay, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	})
end

-- Show cinematic bars for countdown
local countdownBarsShown = false

local function ShowCountdownBars()
	if countdownBarsShown then return end
	countdownBarsShown = true

	local cinematicGui = topBar and topBar.Parent :: ScreenGui?
	if cinematicGui then
		cinematicGui.Enabled = true
	end

	PlayTween(topBar, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, 0, 0),
	})
	PlayTween(bottomBar, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, 1 - BAR_HEIGHT, 0),
	})
end

local function HideCountdownBars()
	if not countdownBarsShown then return end
	countdownBarsShown = false

	PlayTween(topBar, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
		Position = UDim2.new(0, 0, -BAR_HEIGHT, 0),
	})
	PlayTween(bottomBar, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
		Position = UDim2.new(0, 0, 1, 0),
	})

	task.delay(0.35, function()
		if not countdownBarsShown and not isShowing then
			local cinematicGui = topBar and topBar.Parent :: ScreenGui?
			if cinematicGui then
				cinematicGui.Enabled = false
			end
		end
	end)
end

-- Handle state changes
RoundStateChanged.OnClientEvent:Connect(function(state: string, data: any?)
	-- Track current mode from state data
	if data and type(data) == "table" and data.mode then
		currentMode = data.mode
	end

	if state == "Preparing" then
		ShowPreparingFade()
	elseif state == "RoundResults" then
		ShowResults(data)
	elseif state == "FadeToLobby" then
		HideResults()
	elseif state == Constants.STATES.INTERMISSION or state == "Intermission" then
		HideResults()
	elseif state == Constants.STATES.LOBBY or state == "Lobby" then
		HideResults()
	elseif state == Constants.STATES.COUNTDOWN then
		ShowCountdownBars()
		HidePreparingFade()
	elseif state == Constants.STATES.PLAYING or state == "Playing" then
		HideCountdownBars()
		HideResults()
	end
end)

-- Handle sticker display
task.spawn(function()
	while not ShowSticker do
		task.wait(0.1)
	end
	ShowSticker.OnClientEvent:Connect(function(userId: number, stickerId: string)
		DisplaySticker(userId, stickerId)
	end)
end)

-- Initialize
InitializeUI()
CreateCinematicUI()
print("[WinnersUI] Results UI initialized")
