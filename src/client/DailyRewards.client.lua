--!strict
-- DailyRewards.client.lua
-- Shows daily rewards UI on first join with blur + animations

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Camera = workspace.CurrentCamera

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
local clitterSound: Sound? = UISounds and UISounds:FindFirstChild("Clitter") :: Sound? or nil
local achieveSound: Sound? = UISounds and UISounds:FindFirstChild("Achieve") :: Sound? or nil
local failSound: Sound? = UISounds and UISounds:FindFirstChild("Fail") :: Sound? or nil

-- Wait for UI
local dailyRewardsUI = playerGui:WaitForChild("DailyRewardsUI") :: ScreenGui
local parentFrame = dailyRewardsUI:WaitForChild("ParentFrame") :: Frame
local topFrame = parentFrame:WaitForChild("TopFrame") :: Frame
local bottomFrame = parentFrame:WaitForChild("BottomFrame") :: Frame
local itemsHolder = bottomFrame:WaitForChild("ItemsHolder") :: ScrollingFrame
local dayTemplate = itemsHolder:WaitForChild("DayTemplate") :: Frame
local itemFrame = bottomFrame:FindFirstChild("ItemFrame") :: Frame?
local closeBtn = topFrame:FindFirstChildOfClass("TextButton")

-- Reward announce label (lives in NavHUD)
local navHUD = playerGui:WaitForChild("NavHUD") :: ScreenGui
local rewardAnnounce = navHUD:WaitForChild("RewardAnnounce") :: TextLabel

-- State
local isOpen = false
local blurEffect: BlurEffect? = nil
local originalFOV: number = Camera.FieldOfView
local UI_ZOOM_FOV = 15
local lightRotationConn: RBXScriptConnection? = nil
local hoverConnections: {RBXScriptConnection} = {}
local dayFrames: {Frame} = {}

-- ============================================================
-- TWEEN HELPERS
-- ============================================================
local function PlayTween(inst: Instance, info: TweenInfo, props: {[string]: any}): Tween
	local tween = TweenService:Create(inst, info, props)
	tween:Play()
	return tween
end

local function WaitForTween(tween: Tween)
	tween.Completed:Wait()
end

-- ============================================================
-- CONFETTI EFFECT (reusable)
-- ============================================================
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 85, 85),
	Color3.fromRGB(85, 255, 85),
	Color3.fromRGB(85, 170, 255),
	Color3.fromRGB(255, 255, 85),
	Color3.fromRGB(255, 85, 255),
	Color3.fromRGB(85, 255, 255),
	Color3.fromRGB(255, 170, 50),
	Color3.fromRGB(180, 85, 255),
}

local function SpawnConfetti(origin: GuiObject)
	local centerX = origin.AbsolutePosition.X + origin.AbsoluteSize.X / 2
	local centerY = origin.AbsolutePosition.Y + origin.AbsoluteSize.Y / 2
	local numParticles = 24

	for i = 1, numParticles do
		local confetti = Instance.new("Frame")
		confetti.Name = "Confetti"
		confetti.BackgroundColor3 = CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)]
		confetti.BorderSizePixel = 0
		confetti.AnchorPoint = Vector2.new(0.5, 0.5)
		confetti.Size = UDim2.fromOffset(math.random(4, 8), math.random(10, 16))
		confetti.Position = UDim2.fromOffset(centerX, centerY)
		confetti.Rotation = math.random(0, 360)
		confetti.ZIndex = 100
		confetti.Parent = dailyRewardsUI

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 2)
		corner.Parent = confetti

		local angle = (i / numParticles) * math.pi * 2 + (math.random() - 0.5)
		local dist = math.random(80, 200)
		local targetX = centerX + math.cos(angle) * dist
		local targetY = centerY + math.sin(angle) * dist - math.random(30, 80)

		PlayTween(confetti, TweenInfo.new(
			0.6 + math.random() * 0.4,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		), {
			Position = UDim2.fromOffset(targetX, targetY),
			Rotation = math.random(-720, 720),
			BackgroundTransparency = 0.9,
			Size = UDim2.fromOffset(math.random(2, 4), math.random(4, 8)),
		})

		task.delay(1.3, function()
			confetti:Destroy()
		end)
	end
end

-- ============================================================
-- REWARD DISPLAY DATA (7-day cycle)
-- ============================================================
-- type: "coins" | "capsule" | "skin" | "celebration"
-- rarity: only needed for skin/celebration (maps to BombSkins.RarityColors)
local REWARD_DISPLAY = {
	{ label = "500 Coins",          image = BombSkins.Images.Coin,            quantity = 500,  type = "coins" },
	{ label = "Capsule",            image = BombSkins.Images.Capsule,         quantity = 2,    type = "capsule" },
	{ label = "Bomb Skin",          image = "rbxassetid://86460687705734",     quantity = 1,    type = "skin",        rarity = "Rare" },
	{ label = "1,000 Coins",        image = BombSkins.Images.Coin,            quantity = 1000, type = "coins" },
	{ label = "Win Dance",          image = "rbxassetid://113774224641271",    quantity = 1,    type = "celebration", rarity = "Rare" },
	{ label = "Capsule",            image = BombSkins.Images.Capsule,         quantity = 3,    type = "capsule" },
}
-- Day 7 is handled separately by the ItemFrame in the RBXM

-- Convert Color3 to hex string for RichText
local function Color3ToHex(c: Color3): string
	return string.format("#%02X%02X%02X",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5))
end

-- Get the RichText color hex for a reward type
local function GetRewardColorHex(data: {[string]: any}): string
	if data.type == "coins" then
		return "#FFD700" -- gold
	elseif data.type == "capsule" then
		return "#FF3C3C" -- red
	elseif data.type == "skin" or data.type == "celebration" then
		local rarityColor = BombSkins.RarityColors[data.rarity]
		if rarityColor then
			return Color3ToHex(rarityColor)
		end
	end
	return "#FFFFFF"
end

-- Show the reward announce label with colored text
local function AnnounceReward(data: {[string]: any})
	rewardAnnounce.RichText = true
	local hex = GetRewardColorHex(data)
	local rewardName = data.label
	if data.quantity and data.quantity > 1 and data.type ~= "coins" then
		rewardName = data.quantity .. " " .. data.label .. "s"
	end
	rewardAnnounce.Text = 'You got <font color="' .. hex .. '">' .. rewardName .. '!</font>'
	rewardAnnounce.Visible = true

	-- Fade out after a few seconds
	local origStrokeTransparency = rewardAnnounce.TextStrokeTransparency
	task.delay(3, function()
		local tween = PlayTween(rewardAnnounce, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		WaitForTween(tween)
		rewardAnnounce.Visible = false
		rewardAnnounce.TextTransparency = 0
		rewardAnnounce.TextStrokeTransparency = origStrokeTransparency
	end)
end

-- Server-backed daily reward state (fetched on init)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GetDailyRewardStatus = Remotes:WaitForChild("GetDailyRewardStatus", 15)
local ClaimDailyReward = Remotes:WaitForChild("ClaimDailyReward", 15)

local currentDay = 1
local claimedToday = false
local claimedThisSession: {[number]: boolean} = {} -- track visual claim state during session

-- ============================================================
-- SETUP DAY CARD
-- ============================================================
local function SetupDayCard(frame: Frame, dayNum: number)
	local data = REWARD_DISPLAY[dayNum]
	if not data then return end

	-- DayLabel
	local dayLabel = frame:FindFirstChild("DayLabel", true) :: TextLabel?
	if dayLabel then
		dayLabel.Text = "Day " .. dayNum
	end

	-- ImageLabel (the reward item image inside the day card)
	local itemImage = frame:FindFirstChild("ImageLabel") :: ImageLabel?
	if itemImage then
		itemImage.Image = data.image
		itemImage.ZIndex = 4
		-- Capsule images should always use Fit so they don't stretch
		if data.image == BombSkins.Images.Capsule then
			itemImage.ScaleType = Enum.ScaleType.Fit
		end
	end

	-- QuantityLabel
	local quantity = frame:FindFirstChild("QuantityLabel", true) :: TextLabel?
	if quantity then
		quantity.Text = "x" .. data.quantity
		quantity.Visible = true
		quantity.ZIndex = 5
	end

	-- ClaimBtn
	local claimBtn = frame:FindFirstChild("ClaimBtn", true) :: TextButton?
	if not claimBtn then
		-- Fallback: find any TextButton
		for _, child in ipairs(frame:GetDescendants()) do
			if child:IsA("TextButton") then
				claimBtn = child :: TextButton
				break
			end
		end
	end
	if not claimBtn then return end

	-- Find ClaimLabel (child of button or frame)
	local claimText = claimBtn:FindFirstChild("ClaimLabel", true) :: TextLabel?
	if not claimText then
		claimText = frame:FindFirstChild("ClaimLabel", true) :: TextLabel?
	end

	-- Also check if button itself has text
	local buttonHasText = claimBtn.Text ~= ""

	-- Hover effect on ALL claim buttons regardless of state
	claimBtn.AutoButtonColor = false
	local btnScale = claimBtn:FindFirstChildOfClass("UIScale")
	if not btnScale then
		btnScale = Instance.new("UIScale")
		btnScale.Scale = 1
		btnScale.Parent = claimBtn
	end

	local enterConn = claimBtn.MouseEnter:Connect(function()
		if hoverSound then hoverSound:Play() end
		PlayTween(btnScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1.1,
		})
	end)
	local leaveConn = claimBtn.MouseLeave:Connect(function()
		PlayTween(btnScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1,
		})
	end)
	table.insert(hoverConnections, enterConn)
	table.insert(hoverConnections, leaveConn)

	-- Determine this card's visual state
	local isCurrentDay = (dayNum == currentDay)
	local isAlreadyClaimed = (dayNum < currentDay) or (isCurrentDay and claimedToday)

	if isCurrentDay and not claimedToday then
		-- ========== CLAIMABLE ==========
		claimBtn.Active = true
		if claimText then claimText.Text = "Claim" end
		if buttonHasText then claimBtn.Text = "Claim" end

		-- Claim handler
		claimBtn.MouseButton1Click:Connect(function()
			if claimedThisSession[dayNum] then return end
			if clickSound then clickSound:Play() end

			-- Call server
			if ClaimDailyReward then
				local result = ClaimDailyReward:InvokeServer()
				if not result or not result.success then
					if failSound then failSound:Play() end
					return
				end
			end

			if achieveSound then achieveSound:Play() end
			claimedThisSession[dayNum] = true
			claimedToday = true

			-- Confetti burst
			SpawnConfetti(claimBtn)

			-- Announce reward
			AnnounceReward(data)

			-- Change text to "Claimed"
			if claimText then claimText.Text = "Claimed" end
			if buttonHasText then claimBtn.Text = "Claimed" end

			-- Gray out frame
			PlayTween(frame, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
				BackgroundColor3 = Color3.fromRGB(140, 140, 140),
			})

			-- Gray out button
			PlayTween(claimBtn, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
				BackgroundColor3 = Color3.fromRGB(100, 100, 100),
			})

			-- UIStroke on claim text → dark gray
			if claimText then
				local stroke = claimText:FindFirstChildOfClass("UIStroke")
				if stroke then
					PlayTween(stroke, TweenInfo.new(0.35), { Color = Color3.fromRGB(60, 60, 60) })
				end
			end

			-- UIStroke on button → dark gray
			local btnStroke = claimBtn:FindFirstChildOfClass("UIStroke")
			if btnStroke then
				PlayTween(btnStroke, TweenInfo.new(0.35), { Color = Color3.fromRGB(80, 80, 80) })
			end

			-- UIStroke on frame → dark gray
			local frameStroke = frame:FindFirstChildOfClass("UIStroke")
			if frameStroke then
				PlayTween(frameStroke, TweenInfo.new(0.35), { Color = Color3.fromRGB(100, 100, 100) })
			end

			-- UIGradient → disable for flat gray look
			local gradient = frame:FindFirstChildOfClass("UIGradient")
			if gradient then
				gradient.Enabled = false
			end

			-- Hide shine image
			local light = frame:FindFirstChild("LightImage", true)
			if light then light.Visible = false end

			claimBtn.Active = false
		end)

	elseif isAlreadyClaimed then
		-- ========== ALREADY CLAIMED ==========
		if claimText then claimText.Text = "Claimed" end
		if buttonHasText then claimBtn.Text = "Claimed" end
		frame.BackgroundColor3 = Color3.fromRGB(140, 140, 140)
		claimBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		claimBtn.Active = false
		claimBtn.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				if failSound then failSound:Play() end
			end
		end)

		if claimText then
			local stroke = claimText:FindFirstChildOfClass("UIStroke")
			if stroke then stroke.Color = Color3.fromRGB(60, 60, 60) end
		end
		local btnStroke = claimBtn:FindFirstChildOfClass("UIStroke")
		if btnStroke then btnStroke.Color = Color3.fromRGB(80, 80, 80) end
		local frameStroke = frame:FindFirstChildOfClass("UIStroke")
		if frameStroke then frameStroke.Color = Color3.fromRGB(100, 100, 100) end
		local gradient = frame:FindFirstChildOfClass("UIGradient")
		if gradient then gradient.Enabled = false end
		local light = frame:FindFirstChild("LightImage", true)
		if light then light.Visible = false end
	else
		-- ========== FUTURE / LOCKED ==========
		claimBtn.Active = false
		if claimText then claimText.Text = "Locked" end
		if buttonHasText then claimBtn.Text = "Locked" end
		frame.BackgroundTransparency = 0.3
		claimBtn.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				if failSound then failSound:Play() end
			end
		end)
	end
end

-- ============================================================
-- BLUR
-- ============================================================
local function AddBlur()
	blurEffect = Instance.new("BlurEffect")
	blurEffect.Name = "DailyRewardsBlur"
	blurEffect.Size = 0
	blurEffect.Parent = Lighting
	PlayTween(blurEffect, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = 24,
	})

	-- Camera zoom in
	originalFOV = Camera.FieldOfView
	PlayTween(Camera, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = originalFOV + UI_ZOOM_FOV,
	})
end

local function RemoveBlur()
	if blurEffect then
		local tween = PlayTween(blurEffect, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = 0,
		})
		WaitForTween(tween)
		blurEffect:Destroy()
		blurEffect = nil
	end

	-- Camera zoom out
	PlayTween(Camera, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = originalFOV,
	})
end

-- ============================================================
-- LIGHT IMAGE ROTATION
-- ============================================================
local function StartLightRotation()
	lightRotationConn = RunService.Heartbeat:Connect(function(dt)
		for _, frame in ipairs(dayFrames) do
			local lightImage = frame:FindFirstChild("LightImage", true) :: ImageLabel?
			if lightImage and lightImage.Parent then
				lightImage.Rotation += 20 * dt
			end
		end
	end)
end

local function StopLightRotation()
	if lightRotationConn then
		lightRotationConn:Disconnect()
		lightRotationConn = nil
	end
end

-- ============================================================
-- ANIMATE UI
-- ============================================================
local function AnimateIn()
	-- Pre-initialize: attach UIScale(0) to images and buttons BEFORE anything is visible
	local animTargets: {{element: GuiObject, scale: UIScale}} = {}
	for _, frame in ipairs(dayFrames) do
		local img = frame:FindFirstChild("ImageLabel") :: ImageLabel?
		if not img then
			img = frame:FindFirstChild("ItemImage") :: ImageLabel?
		end
		if img then
			local s = Instance.new("UIScale")
			s.Scale = 0
			s.Parent = img
			table.insert(animTargets, {element = img, scale = s})
		end

		local btn = frame:FindFirstChild("ClaimBtn", true) :: TextButton?
		if not btn then
			btn = frame:FindFirstChild("EquipBtn", true) :: TextButton?
		end
		if btn then
			local s = Instance.new("UIScale")
			s.Scale = 0
			s.Parent = btn
			table.insert(animTargets, {element = btn, scale = s})
		end
	end

	-- Now show the UI and scale the ParentFrame in
	dailyRewardsUI.Enabled = true
	parentFrame.Visible = true

	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 0
	uiScale.Parent = parentFrame

	local scaleTween = PlayTween(uiScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	})
	WaitForTween(scaleTween)
	uiScale:Destroy()

	-- Stagger pop-in for images and buttons (already at scale 0, so no visible shrink)
	for i, target in ipairs(animTargets) do
		task.delay((i - 1) * 0.04, function()
			if clitterSound then clitterSound:Play() end
			local t = PlayTween(target.scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			})
			WaitForTween(t)
			target.scale:Destroy()
		end)
	end

	-- Wait for all staggered pops to finish
	task.wait(#animTargets * 0.04 + 0.35)
end

local function AnimateOut()
	-- Scale ParentFrame out
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 1
	uiScale.Parent = parentFrame

	local scaleTween = PlayTween(uiScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Scale = 0,
	})
	WaitForTween(scaleTween)
	uiScale:Destroy()

	parentFrame.Visible = false
	dailyRewardsUI.Enabled = false
end

-- ============================================================
-- OPEN / CLOSE
-- ============================================================
-- Close other popups (mutual exclusion)
local POPUP_GUIS = {"StoreUI", "InventoryUI", "QuestsUI", "DailyRewardsUI", "SpinUI", "CapsuleUI", "ConfigUI"}

local function CloseOtherPopups()
	for _, guiName in ipairs(POPUP_GUIS) do
		if guiName ~= "DailyRewardsUI" then
			local gui = playerGui:FindFirstChild(guiName)
			if gui then
				local fc = gui:FindFirstChild("ForceClose")
				if fc and fc:IsA("BindableEvent") then
					fc:Fire()
				end
			end
		end
	end
end

local function OpenDailyRewards()
	if isOpen then return end
	CloseOtherPopups()
	isOpen = true
	if uiOpenSound then uiOpenSound:Play() end
	AddBlur()
	AnimateIn()
	StartLightRotation()
end

local function CloseDailyRewards()
	if not isOpen then return end
	isOpen = false

	if clickSound then clickSound:Play() end
	StopLightRotation()

	-- Disconnect hover connections
	for _, conn in ipairs(hoverConnections) do
		conn:Disconnect()
	end
	hoverConnections = {}

	AnimateOut()
	RemoveBlur()
end

-- ============================================================
-- INITIALIZE
-- ============================================================
local function Initialize()
	-- Ensure UI starts disabled
	dailyRewardsUI.Enabled = false

	-- Fetch daily reward state from server
	if GetDailyRewardStatus then
		local ok, status = pcall(function()
			return GetDailyRewardStatus:InvokeServer()
		end)
		if ok and status then
			currentDay = status.currentDay or 1
			claimedToday = status.claimedToday or false
		end
	end

	-- Hide the original template — we clone from it, never show it directly
	dayTemplate.Visible = false

	-- Clone 6 day cards (Days 1–6); Day 7 is the pre-built ItemFrame
	for i = 1, 6 do
		local card = dayTemplate:Clone()
		card.Name = "Day" .. i
		card.LayoutOrder = i
		card.Visible = true
		card.Parent = itemsHolder
		SetupDayCard(card, i)
		table.insert(dayFrames, card)
	end

	-- Day 7 — the ItemFrame is already in the RBXM, just set its state
	if itemFrame then
		table.insert(dayFrames, itemFrame)
		local equipBtn = itemFrame:FindFirstChild("EquipBtn") :: TextButton?
		local equipLabel = equipBtn and equipBtn:FindFirstChildOfClass("TextLabel")
		local day7Claimable = (currentDay == 7 and not claimedToday)
		if day7Claimable then
			-- Claimable
			if equipBtn then
				equipBtn.Active = true
				equipBtn.MouseButton1Click:Connect(function()
					if claimedThisSession[7] then return end
					if clickSound then clickSound:Play() end

					-- Call server
					if ClaimDailyReward then
						local result = ClaimDailyReward:InvokeServer()
						if not result or not result.success then
							if failSound then failSound:Play() end
							return
						end
					end

					if achieveSound then achieveSound:Play() end
					claimedThisSession[7] = true
					claimedToday = true
					SpawnConfetti(equipBtn)
					AnnounceReward({ label = "Default Dance", type = "celebration", rarity = "Epic", quantity = 1 })
					if equipLabel then equipLabel.Text = "Claimed" end
					PlayTween(equipBtn, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
						BackgroundColor3 = Color3.fromRGB(100, 100, 100),
					})
					PlayTween(itemFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
						BackgroundColor3 = Color3.fromRGB(140, 140, 140),
					})
					equipBtn.Active = false
				end)
			end
		elseif currentDay == 7 and claimedToday then
			-- Already claimed today
			if equipLabel then equipLabel.Text = "Claimed" end
			if equipBtn then
				equipBtn.Active = false
				equipBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
			end
			itemFrame.BackgroundColor3 = Color3.fromRGB(140, 140, 140)
		else
			-- Locked
			if equipLabel then equipLabel.Text = "Locked" end
			if equipBtn then
				equipBtn.Active = false
			end
			itemFrame.BackgroundTransparency = 0.3
		end
	end

	-- Close button
	if closeBtn then
		closeBtn.MouseButton1Click:Connect(function()
			task.spawn(CloseDailyRewards)
		end)

		-- Close button hover effect
		local origSize = closeBtn.Size
		local hoverSize = UDim2.new(
			origSize.X.Scale, math.floor(origSize.X.Offset * 1.1),
			origSize.Y.Scale, math.floor(origSize.Y.Offset * 1.1)
		)
		closeBtn.MouseEnter:Connect(function()
			if hoverSound then hoverSound:Play() end
			PlayTween(closeBtn, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = hoverSize,
			})
		end)
		closeBtn.MouseLeave:Connect(function()
			PlayTween(closeBtn, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = origSize,
			})
		end)
	end

	-- Show on first join after a brief delay
	task.delay(2, function()
		OpenDailyRewards()
	end)
end

Initialize()

-- ForceClose: instantly hide UI without animation (used by RoundStartCloser)
local function ForceCloseUI()
	if not isOpen then return end
	isOpen = false
	StopLightRotation()
	for _, conn in ipairs(hoverConnections) do
		conn:Disconnect()
	end
	hoverConnections = {}
	parentFrame.Visible = false
	dailyRewardsUI.Enabled = false
	if blurEffect then
		blurEffect:Destroy()
		blurEffect = nil
	end
	Camera.FieldOfView = originalFOV
end

local forceCloseEvent = Instance.new("BindableEvent")
forceCloseEvent.Name = "ForceClose"
forceCloseEvent.Parent = dailyRewardsUI
forceCloseEvent.Event:Connect(function()
	ForceCloseUI()
end)

print("[DailyRewards] Initialized")
