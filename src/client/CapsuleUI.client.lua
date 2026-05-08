--!strict
-- CapsuleUI.client.lua
-- Pack opening animation for capsule purchases

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BombSkins = require(Shared:WaitForChild("BombSkins"))

-- Sound effects
local SoundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
local UISounds = SoundsFolder and SoundsFolder:FindFirstChild("UI")
local hoverSound: Sound? = UISounds and UISounds:FindFirstChild("Hover") :: Sound? or nil
local clickSound: Sound? = UISounds and UISounds:FindFirstChild("Click") :: Sound? or nil
local uiOpenSound: Sound? = UISounds and UISounds:FindFirstChild("UIOpen") :: Sound? or nil
local day7RewardSound: Sound? = UISounds and UISounds:FindFirstChild("Day7Reward") :: Sound? or nil

-- Wait for UI elements
local capsuleUI = playerGui:WaitForChild("CapsuleUI")
local darkBG = capsuleUI:WaitForChild("DarkBG")
local capsuleImage = darkBG:WaitForChild("CapsuleImage")
local mouseIcon = darkBG:WaitForChild("MouseIcon")
local title = darkBG:WaitForChild("Title")
local rewardsFrame = darkBG:WaitForChild("RewardsFrame")

-- Store original properties for reset
local capsuleOriginalSize = capsuleImage.Size
local capsuleOriginalPosition = capsuleImage.Position
local titleOriginalSize = title.Size
local titleOriginalPosition = title.Position

-- Animation state
local isAnimating = false
local hoverConnections: {RBXScriptConnection} = {}
local flareTweens: {Tween} = {}

-- Helper: create a tween and play it, returning the tween
local function PlayTween(instance: Instance, info: TweenInfo, props: {[string]: any}): Tween
	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

-- Helper: wait for a tween to complete
local function WaitForTween(tween: Tween)
	tween.Completed:Wait()
end

-- Initialize everything as hidden
local function InitializeUI()
	darkBG.Visible = false
	darkBG.BackgroundTransparency = 1
	capsuleImage.Visible = false
	mouseIcon.Visible = false
	title.Visible = false
	rewardsFrame.Visible = false

	-- Hide all reward frames
	for _, child in ipairs(rewardsFrame:GetChildren()) do
		if child:IsA("Frame") then
			child.Visible = false
		end
	end
end

-- Phase 1: Fade in dark background
local function AnimateDarkBGIn()
	darkBG.Visible = true
	darkBG.BackgroundTransparency = 1

	local tween = PlayTween(darkBG, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.3,
	})
	WaitForTween(tween)
end

-- Phase 2: Capsule image expands from center
local function AnimateCapsuleIn()
	capsuleImage.Visible = true

	-- Start tiny at center
	capsuleImage.Size = UDim2.new(0, 0, 0, 0)
	capsuleImage.Position = capsuleOriginalPosition
	capsuleImage.AnchorPoint = capsuleImage.AnchorPoint
	capsuleImage.Rotation = 0

	-- Expand with overshoot
	local tween = PlayTween(capsuleImage, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = capsuleOriginalSize,
	})
	WaitForTween(tween)
end

-- Phase 3: Mouse icon slides in from bottom-right (hint indicator)
local function AnimateMouseIn()
	mouseIcon.Visible = true
	mouseIcon.Size = UDim2.new(0, 40, 0, 40)
	mouseIcon.ImageTransparency = 0
	mouseIcon.Position = UDim2.new(0.95, 0, 0.95, 0)

	local tween = PlayTween(mouseIcon, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.58, 0, 0.58, 0),
	})
	WaitForTween(tween)
end

-- Phase 4+5: Wait for player to click/tap capsule 5 times with shake feedback
local CLICKS_REQUIRED = 5
local function WaitForPlayerClicks()
	local clickCount = 0
	local finished = false

	-- Make capsule clickable
	capsuleImage.Active = true

	-- Shake angles get more intense with each click
	local shakePatterns = {
		{ 3, -3 },                     -- click 1: gentle
		{ 5, -5, 4 },                  -- click 2
		{ 6, -7, 6, -5 },              -- click 3
		{ 8, -9, 8, -7, 6 },           -- click 4
		{ 10, -12, 11, -10, 9, -8 },   -- click 5: intense
	}

	local scaleBoosts = { 1.05, 1.08, 1.12, 1.16, 1.22 }

	local clickConn: RBXScriptConnection? = nil
	clickConn = capsuleImage.InputBegan:Connect(function(input: InputObject)
		if finished then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		clickCount += 1
		local idx = math.min(clickCount, #shakePatterns)
		if clickSound then clickSound:Play() end

		-- Scale punch: quick enlarge then back
		local boost = scaleBoosts[idx] or 1.1
		local bigSize = UDim2.new(
			capsuleOriginalSize.X.Scale * boost, capsuleOriginalSize.X.Offset * boost,
			capsuleOriginalSize.Y.Scale * boost, capsuleOriginalSize.Y.Offset * boost
		)
		PlayTween(capsuleImage, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = bigSize,
		})
		task.delay(0.06, function()
			if not finished then
				PlayTween(capsuleImage, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Size = capsuleOriginalSize,
				})
			end
		end)

		-- Shake rotation
		local pattern = shakePatterns[idx]
		local shakeInfo = TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		task.spawn(function()
			for _, angle in ipairs(pattern) do
				if finished then break end
				local t = PlayTween(capsuleImage, shakeInfo, { Rotation = angle })
				WaitForTween(t)
			end
			if not finished then
				PlayTween(capsuleImage, TweenInfo.new(0.04), { Rotation = 0 })
			end
		end)

		if clickCount >= CLICKS_REQUIRED then
			finished = true
		end
	end)

	-- Wait until player has clicked enough times (poll)
	while not finished do
		task.wait(0.05)
	end

	if clickConn then
		clickConn:Disconnect()
	end
	capsuleImage.Active = false

	-- Brief pause before explosion
	task.wait(0.15)
end

-- Phase 6: Capsule explosion (shrink first, then mini capsules burst out)
local function AnimateCapsuleExplode()
	-- Hide mouse icon
	PlayTween(mouseIcon, TweenInfo.new(0.15), {
		ImageTransparency = 1,
	})

	-- Start shrinking the capsule
	local shrinkTween = PlayTween(capsuleImage, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = UDim2.new(0, 0, 0, 0),
		Rotation = 360,
	})

	-- Wait until capsule is already mostly shrunk, then spawn the mini clones
	task.wait(0.25)

	local numFragments = 8
	local fragments = {}

	for i = 1, numFragments do
		local fragment = Instance.new("ImageLabel")
		fragment.Name = "Fragment_" .. i
		fragment.Image = capsuleImage.Image
		fragment.ImageColor3 = capsuleImage.ImageColor3
		fragment.BackgroundTransparency = 1
		fragment.Size = UDim2.new(0, 80, 0, 80)
		fragment.Position = capsuleImage.Position
		fragment.AnchorPoint = capsuleImage.AnchorPoint
		fragment.Rotation = 0
		fragment.ZIndex = capsuleImage.ZIndex - 1
		fragment.Visible = true
		fragment.Parent = darkBG
		table.insert(fragments, fragment)
	end

	-- Burst fragments beyond screen edges
	local burstInfo = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	for i, fragment in ipairs(fragments) do
		local angle = (i / numFragments) * math.pi * 2
		local distance = 1.2 + math.random() * 0.4
		local offsetX = math.cos(angle) * distance
		local offsetY = math.sin(angle) * distance

		PlayTween(fragment, burstInfo, {
			Position = UDim2.new(
				capsuleImage.Position.X.Scale + offsetX,
				0,
				capsuleImage.Position.Y.Scale + offsetY,
				0
			),
			Size = UDim2.new(0, 50, 0, 50),
			Rotation = math.random(-360, 360),
			ImageTransparency = 0.5,
		})
	end

	-- Wait for capsule shrink to finish
	WaitForTween(shrinkTween)
	capsuleImage.Visible = false

	-- Wait for fragments to fly off-screen
	task.wait(0.5)

	-- Clean up
	for _, fragment in ipairs(fragments) do
		fragment:Destroy()
	end
	mouseIcon.Visible = false
end

-- Category display names
local CATEGORY_DISPLAY = {
	bombs = "Bomb",
	emotes = "Emote",
	titles = "Title",
}

-- Populate a single RewardFrame with reward data (sets text/image data only, not Visible)
local function PopulateRewardFrame(frame: Frame, rewardData: any)
	if not rewardData then return end

	local rarityColor = BombSkins.RarityColors[rewardData.rarity] or Color3.fromRGB(180, 180, 180)

	local rarityLabel = frame:FindFirstChild("RarityLabel")
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		rarityLabel.Text = rewardData.rarity
		rarityLabel.TextColor3 = rarityColor
		local stroke = rarityLabel:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			stroke.Color = Color3.new(rarityColor.R * 0.4, rarityColor.G * 0.4, rarityColor.B * 0.4)
		end
	end

	local nameLabel = frame:FindFirstChild("Name")
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = rewardData.itemName or ""
	end

	local categoryLabel = frame:FindFirstChild("CategoryLabel")
	if categoryLabel and categoryLabel:IsA("TextLabel") then
		local displayName = CATEGORY_DISPLAY[rewardData.category] or rewardData.category
		categoryLabel.Text = "+1 " .. displayName
	end

	local imageLabel = frame:FindFirstChild("ImageLabel")
	if imageLabel and imageLabel:IsA("ImageLabel") then
		if rewardData.imageId and rewardData.imageId ~= "" and rewardData.category ~= "titles" then
			imageLabel.Image = rewardData.imageId
		end
	end

	-- Show TitlesLabel for title rewards, hide for everything else
	local titlesLabel = frame:FindFirstChild("TitlesLabel")
	if titlesLabel and titlesLabel:IsA("TextLabel") then
		if rewardData.category == "titles" then
			titlesLabel.Text = rewardData.itemName or ""
			titlesLabel.Visible = true
		else
			titlesLabel.Visible = false
		end
	end
end

-- Phase 7: Reward frames animate in (shows only 1 frame with reward data)
local function AnimateRewardsIn(rewardData: any?)
	rewardsFrame.Visible = true

	-- Collect reward frames, use only the first
	local rewardFrames = {}
	for _, child in ipairs(rewardsFrame:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(rewardFrames, child)
		end
	end
	table.sort(rewardFrames, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)

	local activeFrame = rewardFrames[1]
	for i, frame in ipairs(rewardFrames) do
		if i > 1 then frame.Visible = false end
	end
	if not activeFrame then return end

	-- Find elements by name
	local imageLabel = activeFrame:FindFirstChild("ImageLabel") :: ImageLabel?
	local yellowFlare = activeFrame:FindFirstChild("YellowFlare") :: ImageLabel?
	local cloudImage = activeFrame:FindFirstChild("CloudImage") :: ImageLabel?
	local whiteFlare = activeFrame:FindFirstChild("WhiteFlare") :: ImageLabel?
	local categoryLabel = activeFrame:FindFirstChild("CategoryLabel") :: TextLabel?
	local nameLabel = activeFrame:FindFirstChild("Name") :: TextLabel?
	local rarityLabel = activeFrame:FindFirstChild("RarityLabel") :: TextLabel?

	-- Store original sizes before any animation
	local yellowOrigSize = yellowFlare and yellowFlare.Size or UDim2.new(0, 0, 0, 0)
	local whiteOrigSize = whiteFlare and whiteFlare.Size or UDim2.new(0, 0, 0, 0)
	local cloudOrigSize = cloudImage and cloudImage.Size or UDim2.new(0, 0, 0, 0)
	local imageOrigSize = imageLabel and imageLabel.Size or UDim2.new(0, 0, 0, 0)

	-- Populate reward data (text, colors, images — not visibility)
	if rewardData then
		PopulateRewardFrame(activeFrame, rewardData)
	end

	local isLegendary = rewardData and rewardData.rarity == "Legendary"
	local hasImage = rewardData and rewardData.imageId and rewardData.imageId ~= "" and rewardData.category ~= "titles"

	-- Show and expand the frame from center
	activeFrame.Visible = true
	activeFrame.Size = UDim2.new(0, 0, 0, 0)
	local expandTween = PlayTween(activeFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 150, 0, 150),
	})
	WaitForTween(expandTween)

	-- Legendary: animate flares and cloud from center, enlarging + rotating
	if isLegendary then
		if yellowFlare then
			yellowFlare.Size = UDim2.new(0, 0, 0, 0)
			yellowFlare.Rotation = 0
			yellowFlare.Visible = true
		end
		if whiteFlare then
			whiteFlare.Size = UDim2.new(0, 0, 0, 0)
			whiteFlare.Rotation = 0
			whiteFlare.Visible = true
		end
		if cloudImage then
			cloudImage.Size = UDim2.new(0, 0, 0, 0)
			cloudImage.Visible = true
		end

		-- Play Day7Reward sound when lights come in
		if day7RewardSound then
			day7RewardSound:Play()
		end

		-- Enlarge all three simultaneously
		if yellowFlare then
			PlayTween(yellowFlare, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = yellowOrigSize,
			})
		end
		if whiteFlare then
			PlayTween(whiteFlare, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = whiteOrigSize,
			})
		end
		if cloudImage then
			PlayTween(cloudImage, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = cloudOrigSize,
			})
		end

		-- Start continuous rotation at slightly different speeds
		if yellowFlare then
			local t = TweenService:Create(yellowFlare,
				TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false),
				{ Rotation = 360 })
			t:Play()
			table.insert(flareTweens, t)
		end
		if whiteFlare then
			local t = TweenService:Create(whiteFlare,
				TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false),
				{ Rotation = -360 })
			t:Play()
			table.insert(flareTweens, t)
		end

		task.wait(0.5)
	end

	-- Animate item image in (scale from center)
	if hasImage and imageLabel then
		imageLabel.Size = UDim2.new(0, 0, 0, 0)
		imageLabel.ImageTransparency = 0
		imageLabel.Visible = true

		local imgTween = PlayTween(imageLabel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = imageOrigSize,
		})
		WaitForTween(imgTween)
	end

	-- Animate labels in (fade)
	local labels = { categoryLabel, nameLabel, rarityLabel }
	for _, label in ipairs(labels) do
		if label and label:IsA("TextLabel") then
			label.TextTransparency = 1
			label.Visible = true
		end
	end
	for _, label in ipairs(labels) do
		if label and label:IsA("TextLabel") then
			PlayTween(label, TweenInfo.new(0.25), { TextTransparency = 0 })
		end
	end
	task.wait(0.3)

	-- Hover effects on the item image
	if imageLabel and imageLabel:IsA("ImageLabel") and imageLabel.Visible then
		local origSz = imageLabel.Size
		local hoverSz = UDim2.new(
			origSz.X.Scale * 1.15, origSz.X.Offset * 1.15,
			origSz.Y.Scale * 1.15, origSz.Y.Offset * 1.15
		)
		local enterConn = imageLabel.MouseEnter:Connect(function()
			if hoverSound then hoverSound:Play() end
			PlayTween(imageLabel, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = hoverSz,
			})
		end)
		local leaveConn = imageLabel.MouseLeave:Connect(function()
			PlayTween(imageLabel, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = origSz,
			})
		end)
		table.insert(hoverConnections, enterConn)
		table.insert(hoverConnections, leaveConn)
	end
end

-- Phase 8: Rewards shrink out, dark screen fades
local function AnimateClose()
	-- Cancel flare rotation tweens
	for _, tween in ipairs(flareTweens) do
		tween:Cancel()
	end
	flareTweens = {}

	-- Disconnect hover effects
	for _, conn in ipairs(hoverConnections) do
		conn:Disconnect()
	end
	hoverConnections = {}

	-- Shrink reward frames
	for _, child in ipairs(rewardsFrame:GetChildren()) do
		if child:IsA("Frame") then
			PlayTween(child, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
				Size = UDim2.new(0, 0, 0, 0),
			})
		end
	end

	task.wait(0.3)
	rewardsFrame.Visible = false

	-- Fade out dark BG
	local fadeTween = PlayTween(darkBG, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	})
	WaitForTween(fadeTween)

	darkBG.Visible = false
end

-- Reset UI to initial state
local function ResetUI()
	-- Cancel any lingering flare tweens
	for _, tween in ipairs(flareTweens) do
		tween:Cancel()
	end
	flareTweens = {}

	capsuleImage.Size = capsuleOriginalSize
	capsuleImage.Position = capsuleOriginalPosition
	capsuleImage.Rotation = 0
	capsuleImage.Visible = false
	capsuleImage.ImageTransparency = 0
	mouseIcon.Visible = false
	mouseIcon.ImageTransparency = 0
	mouseIcon.Size = UDim2.new(0, 40, 0, 40)
	mouseIcon.Position = UDim2.new(0.95, 0, 0.95, 0)
	title.Visible = false
	rewardsFrame.Visible = false

	for _, child in ipairs(rewardsFrame:GetChildren()) do
		if child:IsA("Frame") then
			child.Visible = false
			-- Reset all children to hidden for next use
			for _, desc in ipairs(child:GetChildren()) do
				if desc:IsA("ImageLabel") or desc:IsA("TextLabel") then
					desc.Visible = false
				end
			end
		end
	end

	capsuleUI.Enabled = false
	isAnimating = false
end

-- Main animation sequence
local function PlayPackOpening(rewardData: any?)
	if isAnimating then return end
	isAnimating = true

	-- Enable the ScreenGui so elements are visible
	capsuleUI.Enabled = true

	-- Phase 1: Dark BG fades in
	AnimateDarkBGIn()

	-- Phase 2: Capsule expands from center
	AnimateCapsuleIn()

	-- Show title
	title.Visible = true
	if title:IsA("TextLabel") then
		title.TextTransparency = 1
		PlayTween(title, TweenInfo.new(0.3), { TextTransparency = 0 })
	end

	task.wait(0.3)

	-- Phase 3: Mouse icon slides in as hint
	AnimateMouseIn()

	-- Phase 4+5: Wait for player to click capsule 5 times
	WaitForPlayerClicks()

	-- Phase 6: Capsule explodes
	AnimateCapsuleExplode()

	-- Hide title
	if title:IsA("TextLabel") then
		PlayTween(title, TweenInfo.new(0.2), { TextTransparency = 1 })
	end
	task.wait(0.2)
	title.Visible = false

	-- Phase 7: Rewards animate in
	AnimateRewardsIn(rewardData)

	-- Hold rewards on screen
	task.wait(2)

	-- Phase 8: Close everything
	AnimateClose()

	-- Reset for next use
	ResetUI()
end

-- Initialize
InitializeUI()
capsuleUI.Enabled = false

-- Bindable so other client scripts (InventoryUI) can trigger the animation
local triggerEvent = Instance.new("BindableEvent")
triggerEvent.Name = "TriggerPackOpening"
triggerEvent.Parent = capsuleUI

triggerEvent.Event:Connect(function(rewardData: any?)
	PlayPackOpening(rewardData)
end)

-- ForceClose: instantly hide all capsule UI elements (used by RoundStartCloser)
local function ForceCloseUI()
	if not isAnimating and not capsuleUI.Enabled then return end
	for _, tween in ipairs(flareTweens) do
		tween:Cancel()
	end
	flareTweens = {}
	for _, conn in ipairs(hoverConnections) do
		conn:Disconnect()
	end
	hoverConnections = {}
	darkBG.Visible = false
	capsuleImage.Visible = false
	mouseIcon.Visible = false
	title.Visible = false
	rewardsFrame.Visible = false
	capsuleUI.Enabled = false
	isAnimating = false
end

local forceCloseEvent = Instance.new("BindableEvent")
forceCloseEvent.Name = "ForceClose"
forceCloseEvent.Parent = capsuleUI
forceCloseEvent.Event:Connect(function()
	ForceCloseUI()
end)

print("[CapsuleUI] Pack opening animation initialized")
