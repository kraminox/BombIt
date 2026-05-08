--!strict
-- SpinWheel.client.lua
-- Spin wheel UI: populates slices from Economy data, requests spins from server,
-- animates to server-chosen result, manages button state.
-- Opens via RewardInteract touch, closes via CloseBtn with animated transitions.
-- Continuously rotates the physical Wheel billboard in the lobby.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera

-- Shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestSpin = Remotes:WaitForChild("RequestSpin") :: RemoteEvent
local SpinResult = Remotes:WaitForChild("SpinResult") :: RemoteEvent
local GetSpinStatus = Remotes:WaitForChild("GetSpinStatus") :: RemoteFunction

-- Wait for UI
local spinUI = playerGui:WaitForChild("SpinUI", 15) :: ScreenGui?
if not spinUI then
	warn("[SpinWheel] SpinUI not found")
	return
end

local darkBG = spinUI:WaitForChild("DarkBG") :: Frame
local parentFrame = spinUI:WaitForChild("ParentFrame") :: Frame
local spinImage = parentFrame:WaitForChild("SpinImage") :: ImageLabel
local spinButton = parentFrame:FindFirstChild("SpinButton") :: Frame?

-- Close button: ParentFrame > CloseButton (Frame) > CloseBtn (TextButton)
local closeBtnFrame = parentFrame:FindFirstChild("CloseButton")
local closeBtn: TextButton? = closeBtnFrame and closeBtnFrame:FindFirstChild("CloseBtn") :: TextButton? or nil

-- SpinLabel inside SpinButton (used to update button text)
local spinLabel: TextLabel? = spinButton and spinButton:FindFirstChild("SpinLabel") :: TextLabel? or nil

-- Result text label
local resultLabel: TextLabel? = parentFrame:FindFirstChild("TextLabel") :: TextLabel?

-- Sound effects
local SoundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
local UISounds = SoundsFolder and SoundsFolder:FindFirstChild("UI")
local tickSound: Sound? = UISounds and UISounds:FindFirstChild("Tick") :: Sound? or nil
local openBoxSound: Sound? = UISounds and UISounds:FindFirstChild("OpenBox") :: Sound? or nil
local whooshSound: Sound? = UISounds and UISounds:FindFirstChild("Whoosh") :: Sound? or nil
local hoverSound: Sound? = UISounds and UISounds:FindFirstChild("Hover") :: Sound? or nil
local clickSound: Sound? = UISounds and UISounds:FindFirstChild("Click") :: Sound? or nil
local uiOpenSound: Sound? = UISounds and UISounds:FindFirstChild("UIOpen") :: Sound? or nil
local cashierSound: Sound? = UISounds and UISounds:FindFirstChild("Cashier") :: Sound? or nil
local cheersSound: Sound? = UISounds and UISounds:FindFirstChild("Cheers") :: Sound? or nil
local failSound: Sound? = UISounds and UISounds:FindFirstChild("Fail") :: Sound? or nil

-- NavHUD money label for typewriter effect
local navHUD: ScreenGui? = nil
local moneyLabel: TextLabel? = nil

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

	-- Set initial coin display from PersistentStats
	if moneyLabel then
		local pStats = player:WaitForChild("PersistentStats", 10)
		if pStats then
			local coinsVal = pStats:FindFirstChild("TotalCoins")
			if coinsVal and coinsVal:IsA("IntValue") then
				moneyLabel.Text = "$" .. tostring(coinsVal.Value)
			end
		end
	end
end)

local NUM_SLICES = #Economy.SPIN_WHEEL_SLOTS
local isSpinning = false
local isOpen = false
local isAnimating = false

-- Forward declarations
local OpenUI: () -> ()
local CloseUI: () -> ()

-- Blur / camera state
local blurEffect: BlurEffect? = nil
local originalFOV: number = 70
local UI_ZOOM_FOV = 15

-- Idle rotation (only active when UI is open and not spinning)
local IDLE_SPEED = 15 -- degrees per second
local idleConnection: RBXScriptConnection? = nil

local function StartIdleRotation()
	if idleConnection then return end
	idleConnection = RunService.RenderStepped:Connect(function(dt)
		spinImage.Rotation = (spinImage.Rotation + IDLE_SPEED * dt) % 360
	end)
end

local function StopIdleRotation()
	if idleConnection then
		idleConnection:Disconnect()
		idleConnection = nil
	end
end

-- Spin status tracking
local freeSpinsLeft = 0
local paidSpinsLeft = 0
local totalCoins = 0

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
-- POPULATE SLICES (shared helper for UI and billboard)
-- ============================================================
local function PopulateSlices(parent: Instance)
	for _, slotData in ipairs(Economy.SPIN_WHEEL_SLOTS) do
		local sliceFrame = parent:FindFirstChild(slotData.sliceName)
		if not sliceFrame then continue end

		local imageFrame = sliceFrame:FindFirstChild("ImageFrame")
		if imageFrame then
			local icon = imageFrame:FindFirstChild("Icon") :: ImageLabel?
			if icon then
				icon.Image = slotData.imageId or ""
			end
		end

		local title = sliceFrame:FindFirstChild("Title") :: TextLabel?
		if title then
			title.Text = slotData.name
		end

		local chance = sliceFrame:FindFirstChild("Chance") :: TextLabel?
		if chance then
			chance.Text = tostring(slotData.chance) .. "%"
		end
	end
end

-- Populate the UI wheel
PopulateSlices(spinImage)

-- ============================================================
-- WORKSPACE WHEEL: billboard population + continuous rotation
-- ============================================================
local rewardInteract: BasePart? = nil
local billboardSpinImage: ImageLabel? = nil

-- Search for the Wheel first (unique to spin model), then find RewardInteract as sibling
task.spawn(function()
	-- Find the Wheel part (contains the SpinBillboard SurfaceGui)
	local wheelPart: Instance? = nil
	for attempt = 1, 10 do
		wheelPart = workspace:FindFirstChild("Wheel", true)
		if wheelPart then break end
		task.wait(1)
	end

	if not wheelPart then
		warn("[SpinWheel] Wheel not found in workspace")
		return
	end

	-- RewardInteract is a sibling of Wheel inside the same parent model
	local parentModel = wheelPart.Parent
	if parentModel then
		local ri = parentModel:FindFirstChild("RewardInteract")
		if ri and ri:IsA("BasePart") then
			rewardInteract = ri
		end
	end

	if not rewardInteract then
		warn("[SpinWheel] RewardInteract not found as sibling of Wheel")
	end

	-- Find the billboard SurfaceGui on the Wheel
	if wheelPart then
		local spinBillboard = wheelPart:FindFirstChild("SpinBillboard")
			or wheelPart:FindFirstChild("LeaderboardGui")
		if spinBillboard and spinBillboard:IsA("SurfaceGui") then
			billboardSpinImage = spinBillboard:FindFirstChild("SpinImage") :: ImageLabel?
		end
	end

	-- Populate billboard slices with Economy data
	if billboardSpinImage then
		PopulateSlices(billboardSpinImage)
	end

	-- Continuous billboard rotation
	if billboardSpinImage then
		RunService.RenderStepped:Connect(function(dt)
			if billboardSpinImage then
				billboardSpinImage.Rotation = (billboardSpinImage.Rotation + 20 * dt) % 360
			end
		end)
	end

	-- RewardInteract touch → open UI
	if rewardInteract then
		print("[SpinWheel] RewardInteract found, connecting touch event")
		rewardInteract.Touched:Connect(function(hit: BasePart)
			local character = player.Character
			if not character then return end
			if not hit:IsDescendantOf(character) then return end
			if isOpen or isAnimating then return end
			OpenUI()
		end)

	end
end)

-- ============================================================
-- OPEN / CLOSE ANIMATIONS (matches DailyRewards / InventoryUI)
-- ============================================================

-- Initialize UI as hidden
spinUI.Enabled = false
darkBG.Visible = false
parentFrame.Visible = false
darkBG.BackgroundTransparency = 1

local function EnsureUIScale(): UIScale
	local scale = parentFrame:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Scale = 1
		scale.Parent = parentFrame
	end
	return scale :: UIScale
end

-- Close other popups (mutual exclusion)
local POPUP_GUIS = {"StoreUI", "InventoryUI", "QuestsUI", "DailyRewardsUI", "SpinUI", "CapsuleUI", "ConfigUI"}

local function CloseOtherPopups()
	for _, guiName in ipairs(POPUP_GUIS) do
		if guiName ~= "SpinUI" then
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

OpenUI = function()
	if isOpen or isAnimating then return end
	CloseOtherPopups()
	isAnimating = true

	-- Clear previous result text
	if resultLabel then
		resultLabel.Text = ""
	end

	-- Play UI open sound
	if uiOpenSound then uiOpenSound:Play() end

	spinUI.Enabled = true
	darkBG.Visible = true
	parentFrame.Visible = true
	darkBG.BackgroundTransparency = 1

	-- Fade in dark background
	PlayTween(darkBG, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.3,
	})

	-- Add blur
	blurEffect = Instance.new("BlurEffect")
	blurEffect.Name = "SpinWheelBlur"
	blurEffect.Size = 0
	blurEffect.Parent = Lighting
	PlayTween(blurEffect, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = 10,
	})

	-- Camera zoom in
	originalFOV = Camera.FieldOfView
	PlayTween(Camera, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = originalFOV + UI_ZOOM_FOV,
	})

	-- Scale in the wheel
	local scale = EnsureUIScale()
	scale.Scale = 0
	local tween = PlayTween(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	})
	WaitForTween(tween)

	isOpen = true
	isAnimating = false
	StartIdleRotation()
end

CloseUI = function()
	if not isOpen then return end
	if isAnimating then return end -- prevent double-close during animation
	isAnimating = true
	StopIdleRotation()

	-- Scale out the wheel
	local scale = EnsureUIScale()
	local scaleTween = PlayTween(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Scale = 0,
	})

	-- Fade out dark background
	PlayTween(darkBG, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	})

	-- Remove blur
	if blurEffect then
		PlayTween(blurEffect, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = 0,
		})
	end

	-- Camera zoom out
	PlayTween(Camera, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = originalFOV,
	})

	WaitForTween(scaleTween)

	darkBG.Visible = false
	parentFrame.Visible = false
	spinUI.Enabled = false

	if blurEffect then
		blurEffect:Destroy()
		blurEffect = nil
	end

	isOpen = false
	isAnimating = false
end

-- Close button click
if closeBtn then
	closeBtn.MouseButton1Click:Connect(function()
		if isSpinning then return end
		-- Safety: ensure isAnimating is not stuck from a previous operation
		if clickSound then clickSound:Play() end
		task.spawn(CloseUI)
	end)

	-- Close button hover effect
	closeBtn.AutoButtonColor = false
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

-- ============================================================
-- CONFETTI EFFECT
-- ============================================================
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 215, 0),   -- Gold
	Color3.fromRGB(255, 100, 100),  -- Red
	Color3.fromRGB(100, 200, 255),  -- Blue
	Color3.fromRGB(100, 255, 150),  -- Green
	Color3.fromRGB(255, 150, 255),  -- Pink
	Color3.fromRGB(255, 180, 50),   -- Orange
}

local function SpawnConfetti()
	local center = spinImage.AbsolutePosition + spinImage.AbsoluteSize / 2
	for _ = 1, 40 do
		local piece = Instance.new("Frame")
		piece.Size = UDim2.fromOffset(math.random(6, 12), math.random(6, 12))
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = UDim2.fromOffset(center.X, center.Y)
		piece.BackgroundColor3 = CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)]
		piece.BorderSizePixel = 0
		piece.Rotation = math.random(0, 360)
		piece.ZIndex = 100

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, math.random(0, 1) == 0 and 2 or 6)
		corner.Parent = piece

		piece.Parent = parentFrame

		-- Random burst direction
		local angle = math.rad(math.random(0, 360))
		local dist = math.random(150, 350)
		local targetX = center.X + math.cos(angle) * dist
		local targetY = center.Y + math.sin(angle) * dist - math.random(50, 150)

		local moveTween = TweenService:Create(piece,
			TweenInfo.new(math.random(60, 120) / 100, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = UDim2.fromOffset(targetX, targetY),
				Rotation = math.random(-360, 360),
			}
		)
		local fadeTween = TweenService:Create(piece,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		)

		moveTween:Play()
		task.delay(0.7, function()
			fadeTween:Play()
			fadeTween.Completed:Once(function()
				piece:Destroy()
			end)
		end)
	end
end

-- ============================================================
-- SPIN MECHANICS
-- ============================================================

-- Calculate the rotation angle to land on a specific slice
local function GetSliceAngle(sliceIndex: number): number
	local sliceSize = 360 / NUM_SLICES
	local centerAngle = (sliceIndex - 1) * sliceSize
	local jitter = (math.random() - 0.5) * sliceSize * 0.6
	return centerAngle + jitter
end

-- Update button text/state based on spin availability
local function UpdateButtonState()
	if isSpinning or not spinButton then return end

	if freeSpinsLeft > 0 then
		spinButton.Active = true
		spinButton.BackgroundTransparency = 0
		if spinLabel then spinLabel.Text = "FREE SPIN" end
	elseif paidSpinsLeft > 0 and totalCoins >= Economy.EXTRA_SPIN_COST then
		spinButton.Active = true
		spinButton.BackgroundTransparency = 0
		if spinLabel then spinLabel.Text = "SPIN (" .. Economy.EXTRA_SPIN_COST .. ")" end
	else
		spinButton.Active = false
		spinButton.BackgroundTransparency = 0.5
		if spinLabel then
			if paidSpinsLeft <= 0 and freeSpinsLeft <= 0 then
				spinLabel.Text = "NO SPINS"
			else
				spinLabel.Text = "SPIN (" .. Economy.EXTRA_SPIN_COST .. ")"
			end
		end
	end
end

-- Show result text with a brief pulse
local function ShowResult(rewardName: string)
	if not resultLabel then return end
	resultLabel.Text = "You got " .. rewardName .. "!"
	resultLabel.Visible = true
	resultLabel.TextTransparency = 0

	-- Pulse: scale up then back
	local originalSize = resultLabel.TextSize
	local pulseTween = TweenService:Create(
		resultLabel,
		TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ TextSize = originalSize + 6 }
	)
	pulseTween:Play()
	pulseTween.Completed:Wait()

	local shrinkTween = TweenService:Create(
		resultLabel,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextSize = originalSize }
	)
	shrinkTween:Play()
end

-- Animate the NavHUD MoneyLabel with a typewriter count-up
local function AnimateMoneyLabel(coinsEarned: number, newTotal: number)
	if not moneyLabel or coinsEarned <= 0 then return end

	local startVal = newTotal - coinsEarned
	if startVal < 0 then startVal = 0 end

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

	moneyLabel.Text = "$" .. tostring(newTotal)

	-- Quick pulse on the money label
	local origSize = moneyLabel.Size
	local pulseSize = UDim2.new(
		origSize.X.Scale * 1.15, math.floor(origSize.X.Offset * 1.15),
		origSize.Y.Scale * 1.15, math.floor(origSize.Y.Offset * 1.15)
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

-- Animate wheel to the server-chosen slot
local function AnimateToSlot(slotIndex: number, rewardName: string, rewardType: string?)
	local fullSpins = math.random(4, 6) * 360
	local targetSliceAngle = GetSliceAngle(slotIndex)
	local totalRotation = fullSpins + (360 - targetSliceAngle)

	-- Reset rotation to avoid huge accumulated values
	spinImage.Rotation = spinImage.Rotation % 360
	local startRotation = spinImage.Rotation
	local endRotation = startRotation + totalRotation

	local spinTween = TweenService:Create(
		spinImage,
		TweenInfo.new(5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Rotation = endRotation }
	)

	-- Track slice EDGE crossings for tick sounds
	-- Slice centers are at (i-1)*sliceSize; divider lines (black edges) are
	-- offset by half a slice from centers, so we shift by sliceSize/2 to align
	-- tick detection with the actual divider lines crossing the pin at the top.
	local sliceSize = 360 / NUM_SLICES
	local edgeOffset = sliceSize / 2
	local lastEdge = math.floor(((startRotation + edgeOffset) % 360) / sliceSize)
	local tickConnection: RBXScriptConnection? = nil

	tickConnection = RunService.RenderStepped:Connect(function()
		local adjusted = (spinImage.Rotation + edgeOffset) % 360
		local currentEdge = math.floor(adjusted / sliceSize)
		if currentEdge ~= lastEdge then
			lastEdge = currentEdge
			if tickSound then
				tickSound:Play()
			end
		end
	end)

	spinTween:Play()
	spinTween.Completed:Wait()

	-- Clean up tick tracker
	if tickConnection then
		tickConnection:Disconnect()
		tickConnection = nil
	end

	spinImage.Rotation = spinImage.Rotation % 360

	-- Play context-specific landing sound
	local rType = rewardType or "coins"
	if rType == "legendary" then
		-- Legendary capsule: OpenBox + Cheers
		if openBoxSound then openBoxSound:Play() end
		if cheersSound then cheersSound:Play() end
	elseif rType == "capsule" then
		if openBoxSound then openBoxSound:Play() end
	else
		if cashierSound then cashierSound:Play() end
	end

	-- Confetti burst
	SpawnConfetti()

	-- Pulse the wheel on landing (scale 1 → 1.08 → 1)
	local wheelScale = spinImage:FindFirstChildOfClass("UIScale")
	if not wheelScale then
		wheelScale = Instance.new("UIScale")
		wheelScale.Scale = 1
		wheelScale.Parent = spinImage
	end
	local pulseUp = PlayTween(wheelScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1.08,
	})
	WaitForTween(pulseUp)
	local pulseDown = PlayTween(wheelScale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = 1,
	})
	WaitForTween(pulseDown)

	-- Show reward
	ShowResult(rewardName)

	task.wait(1.5)
	isSpinning = false
	isAnimating = false -- ensure close button works after spin
	UpdateButtonState()
	if isOpen then
		StartIdleRotation()
	end
end

-- Handle spin button click
local function OnSpinClicked()
	if isSpinning then return end

	-- Quick client-side eligibility check (server is authoritative)
	if freeSpinsLeft <= 0 and (paidSpinsLeft <= 0 or totalCoins < Economy.EXTRA_SPIN_COST) then
		if failSound then failSound:Play() end
		return
	end

	isSpinning = true
	StopIdleRotation()
	if spinButton then
		spinButton.Active = false
		spinButton.BackgroundTransparency = 0.5
	end

	-- Clear previous result
	if resultLabel then
		resultLabel.Text = ""
	end

	-- Play click + whoosh sounds
	if clickSound then clickSound:Play() end
	if whooshSound then whooshSound:Play() end

	-- Fire request to server
	RequestSpin:FireServer()

	-- Safety timeout: if server never responds, reset spin state after 15 seconds
	task.delay(15, function()
		if isSpinning then
			isSpinning = false
			isAnimating = false
			UpdateButtonState()
			if isOpen then StartIdleRotation() end
		end
	end)
end

-- Track whether we've been force-closed mid-spin (round started)
local pendingReward: string? = nil
local forceClosing = false

-- Force close: instantly hides UI without animation, used when round starts
local function ForceCloseUI()
	if not isOpen and not isSpinning then return end
	forceClosing = true

	StopIdleRotation()

	-- Instantly hide everything
	darkBG.Visible = false
	parentFrame.Visible = false
	spinUI.Enabled = false

	if blurEffect then
		blurEffect:Destroy()
		blurEffect = nil
	end

	-- Restore camera
	Camera.FieldOfView = originalFOV

	isOpen = false
	isAnimating = false
	-- Note: isSpinning stays true if mid-spin; SpinResult handler will announce reward
end

-- Listen for server result
SpinResult.OnClientEvent:Connect(function(data)
	if not data or not data.slotIndex then return end

	-- Track old coins before updating (for typewriter delta)
	local oldCoins = totalCoins

	-- Update local state from server
	freeSpinsLeft = data.freeSpinsLeft or 0
	paidSpinsLeft = data.paidSpinsLeft or 0
	totalCoins = data.totalCoins or 0

	-- Use server-sent rewardType for landing SFX
	local rewardType = data.rewardType or "coins"
	local rewardName = data.rewardName or "a reward"

	-- If UI was force-closed mid-spin, skip animation and announce via RewardAnnounce
	if forceClosing or not isOpen then
		isSpinning = false
		forceClosing = false

		-- Announce reward via RewardAnnounce label in NavHUD
		task.spawn(function()
			local nav = playerGui:FindFirstChild("NavHUD")
			if not nav then return end
			local announce = nav:FindFirstChild("RewardAnnounce") :: TextLabel?
			if not announce then return end

			announce.RichText = true
			announce.Text = '<font color="#FFD700">Spin: You got ' .. rewardName .. '!</font>'
			announce.TextTransparency = 0
			announce.Visible = true

			task.wait(3)
			local fade = TweenService:Create(announce,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ TextTransparency = 1 }
			)
			fade:Play()
			fade.Completed:Wait()
			announce.Visible = false
			announce.TextTransparency = 0
		end)

		-- Update money display
		if moneyLabel then
			moneyLabel.Text = "$" .. tostring(totalCoins)
		end
		UpdateButtonState()
		return
	end

	-- Normal flow: animate to the server-chosen slot
	AnimateToSlot(data.slotIndex, rewardName, rewardType)

	-- Update NavHUD money display after animation finishes
	local coinsEarned = totalCoins - oldCoins
	if coinsEarned > 0 then
		-- Count-up typewriter effect for coin rewards
		task.spawn(AnimateMoneyLabel, coinsEarned, totalCoins)
	elseif moneyLabel then
		-- Just set the final value (paid spin cost deduction, etc.)
		moneyLabel.Text = "$" .. tostring(totalCoins)
	end
end)

-- Connect spin button (Frame — use InputBegan for click detection)
if spinButton then
	spinButton.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			OnSpinClicked()
		end
	end)

	-- Spin button hover effect
	local spinOrigSize = spinButton.Size
	local spinHoverSize = UDim2.new(
		spinOrigSize.X.Scale, math.floor(spinOrigSize.X.Offset * 1.1),
		spinOrigSize.Y.Scale, math.floor(spinOrigSize.Y.Offset * 1.1)
	)
	spinButton.MouseEnter:Connect(function()
		if isSpinning then return end
		if hoverSound then hoverSound:Play() end
		PlayTween(spinButton, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = spinHoverSize,
		})
	end)
	spinButton.MouseLeave:Connect(function()
		PlayTween(spinButton, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = spinOrigSize,
		})
	end)
end

-- Fetch initial spin status from server
task.spawn(function()
	local status = GetSpinStatus:InvokeServer()
	if status then
		freeSpinsLeft = status.freeSpinsLeft or 0
		paidSpinsLeft = status.paidSpinsLeft or 0
		totalCoins = status.totalCoins or 0
	end
	UpdateButtonState()
end)

-- Expose force close for round-start cleanup
local forceCloseEvent = Instance.new("BindableEvent")
forceCloseEvent.Name = "ForceClose"
forceCloseEvent.Parent = spinUI
forceCloseEvent.Event:Connect(function()
	ForceCloseUI()
end)

print("[SpinWheel] Spin wheel initialized with " .. NUM_SLICES .. " slices")
