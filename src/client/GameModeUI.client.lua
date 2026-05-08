--!strict
-- GameModeUI.client.lua
-- Slot machine-style game mode selector that plays during intermission/lobby countdown
-- Uses vertical scrolling text (ClipsDescendants) for a real slot-reel effect.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ModeSelection = Remotes:WaitForChild("ModeSelection", 10)
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged")

-- UI references (found dynamically from pre-built ScreenGui)
local parentFrame: Frame? = nil
local playersLabel: TextLabel? = nil
local modeLabel: TextLabel? = nil

-- Banner references — IntermissionFrame inside BannerUI
local bannerUI: ScreenGui? = nil
local intermissionFrame: Frame? = nil
local bannerTextLabel: TextLabel? = nil
local bannerTextShadow: TextLabel? = nil

-- Store original properties for reset
local originalSize: UDim2? = nil
local originalPosition: UDim2? = nil
local originalAnchorPoint: Vector2? = nil

-- State
local isAnimating = false

-- Find the ParentFrame in PlayerGui
local function FindParentFrame()
	for _, gui in ipairs(playerGui:GetChildren()) do
		if gui:IsA("ScreenGui") then
			local pf = gui:FindFirstChild("ParentFrame")
			if pf and pf:IsA("Frame") then
				local lh = pf:FindFirstChild("ListHolder")
				if lh then
					local pl = lh:FindFirstChild("Players")
					local ml = lh:FindFirstChild("Mode")
					if pl and ml then
						parentFrame = pf
						playersLabel = pl :: TextLabel
						modeLabel = ml :: TextLabel
						return true
					end
				end
			end
		end
	end
	return false
end

-- Find banner UI references — use IntermissionFrame, not BackgroundImage
local function FindBannerUI()
	local bui = playerGui:FindFirstChild("BannerUI")
	if bui and bui:IsA("ScreenGui") then
		bannerUI = bui
		local imf = bui:FindFirstChild("IntermissionFrame")
		if imf and imf:IsA("Frame") then
			intermissionFrame = imf
			bannerTextLabel = imf:FindFirstChild("TextLabel") :: TextLabel?
			bannerTextShadow = imf:FindFirstChild("TextShadow") :: TextLabel?
		end
	end
end

-- Set banner text helper
local function SetBannerText(text: string)
	if bannerTextLabel then
		bannerTextLabel.Text = text
	end
	if bannerTextShadow then
		bannerTextShadow.Text = text
	end
	if intermissionFrame then
		intermissionFrame.Visible = true
	end
	if bannerUI then
		bannerUI.Enabled = true
	end
end

-- Create a child TextLabel that mirrors the parent label's text style
local function CreateSlotLabel(parent: TextLabel, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = parent.TextColor3
	label.FontFace = parent.FontFace
	label.TextScaled = parent.TextScaled
	label.TextSize = parent.TextSize
	label.TextStrokeColor3 = parent.TextStrokeColor3
	label.TextStrokeTransparency = parent.TextStrokeTransparency
	label.TextXAlignment = parent.TextXAlignment
	label.TextYAlignment = parent.TextYAlignment
	label.ZIndex = parent.ZIndex + 1
	label.Parent = parent
	return label
end

-- Animate a single slot with vertical scrolling (real slot-reel effect)
-- Text slides downward: current text exits bottom, new text enters from top.
local function AnimateSlot(label: TextLabel, options: {{name: string}}, finalValue: string, duration: number)
	-- Enable clipping so text outside the label bounds is hidden
	label.ClipsDescendants = true
	local origText = label.Text
	label.Text = "" -- Hide parent's own text; child labels render instead

	-- Create the initial "current" label sitting at center
	local currentLabel = CreateSlotLabel(label, origText)
	currentLabel.Position = UDim2.new(0, 0, 0, 0)

	local elapsed = 0
	local interval = 0.05

	while elapsed < duration - interval do
		local nextText = options[math.random(1, #options)].name

		-- New label starts above (clipped out of view)
		local nextLabel = CreateSlotLabel(label, nextText)
		nextLabel.Position = UDim2.new(0, 0, -1, 0)

		-- Tween both: current slides down+out, next slides into place
		local tweenTime = math.min(interval * 0.9, 0.15)
		local ti = TweenInfo.new(tweenTime, Enum.EasingStyle.Linear)
		TweenService:Create(currentLabel, ti, { Position = UDim2.new(0, 0, 1, 0) }):Play()
		local t = TweenService:Create(nextLabel, ti, { Position = UDim2.new(0, 0, 0, 0) })
		t:Play()
		t.Completed:Wait()

		currentLabel:Destroy()
		currentLabel = nextLabel

		elapsed = elapsed + interval
		interval = math.min(interval * 1.3, 0.5)
	end

	-- Final value — slide in with a satisfying bounce
	local finalLabel = CreateSlotLabel(label, finalValue)
	finalLabel.Position = UDim2.new(0, 0, -1, 0)

	local landTween = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(currentLabel, landTween, { Position = UDim2.new(0, 0, 1, 0) }):Play()
	local ft = TweenService:Create(finalLabel, landTween, { Position = UDim2.new(0, 0, 0, 0) })
	ft:Play()
	ft.Completed:Wait()

	currentLabel:Destroy()

	-- Clean up: restore parent text, remove child
	label.Text = finalValue
	finalLabel:Destroy()
end

-- Pulsate the ParentFrame (scale size up 10% and back, 3 times)
local function PulsateFrame(frame: Frame)
	local baseSize = frame.Size
	local bigSize = UDim2.new(
		baseSize.X.Scale * 1.1, baseSize.X.Offset * 1.1,
		baseSize.Y.Scale * 1.1, baseSize.Y.Offset * 1.1
	)
	local tweenUp = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweenDown = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	for _ = 1, 3 do
		local grow = TweenService:Create(frame, tweenUp, { Size = bigSize })
		grow:Play()
		grow.Completed:Wait()
		local shrink = TweenService:Create(frame, tweenDown, { Size = baseSize })
		shrink:Play()
		shrink.Completed:Wait()
	end
end

-- Shrink and reposition ParentFrame under the IntermissionFrame banner
local function ShrinkAndPersist(frame: Frame)
	if not intermissionFrame or not intermissionFrame:IsA("GuiObject") then return end

	-- Calculate position centered below the IntermissionFrame
	local bannerAbsPos = intermissionFrame.AbsolutePosition
	local bannerAbsSize = intermissionFrame.AbsoluteSize
	local screenSize = frame.Parent and (frame.Parent :: GuiObject).AbsoluteSize or Vector2.new(1920, 1080)

	local centerX = (bannerAbsPos.X + bannerAbsSize.X / 2) / screenSize.X
	local belowY = (bannerAbsPos.Y + bannerAbsSize.Y + 5) / screenSize.Y

	-- Target size: ~50% width, ~60% height of original
	local targetSize = UDim2.new(
		(originalSize :: UDim2).X.Scale * 0.5, (originalSize :: UDim2).X.Offset * 0.5,
		(originalSize :: UDim2).Y.Scale * 0.6, (originalSize :: UDim2).Y.Offset * 0.6
	)

	frame.AnchorPoint = Vector2.new(0.5, 0)
	local tween = TweenService:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = targetSize,
		Position = UDim2.new(centerX, 0, belowY, 0),
	})
	tween:Play()
	tween.Completed:Wait()
end

-- Hide and reset ParentFrame to original state
local function HideAndReset()
	if not parentFrame then return end

	parentFrame.Visible = false
	if originalSize then
		parentFrame.Size = originalSize
	end
	if originalPosition then
		parentFrame.Position = originalPosition
	end
	if originalAnchorPoint then
		parentFrame.AnchorPoint = originalAnchorPoint
	end
	if playersLabel then
		playersLabel.Text = "Players"
		playersLabel.ClipsDescendants = false
		-- Clean up any leftover child labels
		for _, child in ipairs(playersLabel:GetChildren()) do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
	end
	if modeLabel then
		modeLabel.Text = "Mode"
		modeLabel.ClipsDescendants = false
		for _, child in ipairs(modeLabel:GetChildren()) do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
	end

	isAnimating = false
end

-- Run the full slot animation sequence
local function RunModeSelection(formatId: string, typeId: string)
	if isAnimating then return end
	if not parentFrame or not playersLabel or not modeLabel then return end

	isAnimating = true

	-- Resolve display names
	local formatName = "FFA"
	for _, fmt in ipairs(Constants.PLAYER_FORMATS) do
		if fmt.id == formatId then
			formatName = fmt.name
			break
		end
	end

	local typeName = "Standard"
	for _, gt in ipairs(Constants.GAME_TYPES) do
		if gt.id == typeId then
			typeName = gt.name
			break
		end
	end

	-- Step 1: Banner text
	SetBannerText("Choosing Game Mode...")

	-- Step 2: Slide ParentFrame down from above screen
	local frame = parentFrame :: Frame
	frame.Position = UDim2.new(
		(originalPosition :: UDim2).X.Scale, (originalPosition :: UDim2).X.Offset,
		-0.3, 0
	)
	frame.Visible = true

	local slideIn = TweenService:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = originalPosition :: UDim2,
	})
	slideIn:Play()
	slideIn.Completed:Wait()

	-- Step 3: Spin both slots concurrently with different durations
	local dur1 = 2.0 + math.random() * 1.0 -- 2.0-3.0s
	local dur2 = 2.0 + math.random() * 1.0

	local slot1Done = false
	local slot2Done = false

	task.spawn(function()
		AnimateSlot(playersLabel :: TextLabel, Constants.PLAYER_FORMATS, formatName, dur1)
		slot1Done = true
	end)

	task.spawn(function()
		AnimateSlot(modeLabel :: TextLabel, Constants.GAME_TYPES, typeName, dur2)
		slot2Done = true
	end)

	-- Wait for both to finish
	while not slot1Done or not slot2Done do
		task.wait(0.05)
	end

	-- Step 4: Both landed — update banner, pulsate
	SetBannerText("Mode Chosen:")
	PulsateFrame(frame)

	-- Brief pause after pulsate
	task.wait(0.3)

	-- Step 5: Shrink + reposition under banner
	ShrinkAndPersist(frame)

	isAnimating = false
end

-- Wait for UI to be available
task.spawn(function()
	local maxWait = 15
	local elapsed = 0
	while not FindParentFrame() and elapsed < maxWait do
		task.wait(0.5)
		elapsed = elapsed + 0.5
	end

	if parentFrame then
		-- Store original properties
		originalSize = parentFrame.Size
		originalPosition = parentFrame.Position
		originalAnchorPoint = parentFrame.AnchorPoint

		-- Hide initially
		parentFrame.Visible = false

		-- Find banner
		FindBannerUI()
	else
		warn("[GameModeUI] Could not find ParentFrame in PlayerGui")
	end
end)

-- Event: server sends chosen format + type
if ModeSelection then
	ModeSelection.OnClientEvent:Connect(function(formatId: string, typeId: string)
		if not parentFrame then
			FindParentFrame()
			if parentFrame then
				originalSize = parentFrame.Size
				originalPosition = parentFrame.Position
				originalAnchorPoint = parentFrame.AnchorPoint
				parentFrame.Visible = false
			end
		end
		if not bannerUI then
			FindBannerUI()
		end
		if parentFrame then
			task.spawn(RunModeSelection, formatId, typeId)
		end
	end)
else
	warn("[GameModeUI] ModeSelection remote not found, mode UI will not function")
end

-- Event: hide on round end / lobby transitions
RoundStateChanged.OnClientEvent:Connect(function(state: string, _data: any?)
	if state == "FadeToLobby"
		or state == Constants.STATES.LOBBY
		or state == Constants.STATES.INTERMISSION then
		HideAndReset()
	end
end)

print("[GameModeUI] Initialized")
