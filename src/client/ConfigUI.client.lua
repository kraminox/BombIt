--!strict
-- ConfigUI.client.lua
-- Settings panel: music/SFX toggles, skip capsule opens, code redemption

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera

-- Sound effects
local SoundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
local UISounds = SoundsFolder and SoundsFolder:FindFirstChild("UI")
local clickSound: Sound? = UISounds and UISounds:FindFirstChild("Click") :: Sound? or nil
local hoverSound: Sound? = UISounds and UISounds:FindFirstChild("Hover") :: Sound? or nil
local achieveSound: Sound? = UISounds and UISounds:FindFirstChild("Achieve") :: Sound? or nil
local failSound: Sound? = UISounds and UISounds:FindFirstChild("Fail") :: Sound? or nil

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RedeemCode = Remotes:WaitForChild("RedeemCode", 15)
local GetConfigSettings = Remotes:WaitForChild("GetConfigSettings", 15)
local SaveConfigSettings = Remotes:WaitForChild("SaveConfigSettings", 15)

-- Wait for ConfigUI
local configGui = playerGui:WaitForChild("ConfigUI") :: ScreenGui
local parentFrame = configGui:WaitForChild("ParentFrame") :: Frame
local topFrame = parentFrame:FindFirstChild("TopFrame") :: Frame?
local bottomFrame = parentFrame:FindFirstChild("BottomFrame") :: Frame?
local frameHolder = bottomFrame and bottomFrame:FindFirstChild("FrameHolder") :: Frame? or nil

-- Find frames
local gameMusicFrame = frameHolder and frameHolder:FindFirstChild("GameMusicFrame") :: Frame? or nil
local sfxFrame = frameHolder and frameHolder:FindFirstChild("SFXFrame") :: Frame? or nil
local skipAnimFrame = frameHolder and frameHolder:FindFirstChild("SkipAnimation") :: Frame? or nil
local codesFrame = frameHolder and frameHolder:FindFirstChild("CodesFrame") :: Frame? or nil

-- Close button
local closeBtn = topFrame and topFrame:FindFirstChild("CloseBtn")

-- State
local isOpen = false
local isAnimating = false
local blurEffect: BlurEffect? = nil
local originalFOV: number = Camera.FieldOfView
local UI_ZOOM_FOV = 15

-- Toggle states (will be overwritten by saved settings below)
local musicEnabled = true
local sfxEnabled = true
local skipCapsuleOpens = false

-- Save current config to server
local function SaveConfig()
	if SaveConfigSettings then
		SaveConfigSettings:FireServer({
			musicEnabled = musicEnabled,
			sfxEnabled = sfxEnabled,
			skipCapsuleOpens = skipCapsuleOpens,
		})
	end
end

-- Colors
local ON_COLOR = Color3.fromRGB(75, 200, 75)
local OFF_COLOR = Color3.fromRGB(200, 90, 90)
local ON_STROKE_COLOR = Color3.fromRGB(40, 120, 40)
local OFF_STROKE_COLOR = Color3.fromRGB(140, 50, 50)

-- Helper: play tween
local function PlayTween(instance: Instance, info: TweenInfo, props: {[string]: any}): Tween
	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

-- Ensure UIScale on parentFrame
local function EnsureUIScale(): UIScale
	local scale = parentFrame:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Scale = 0
		scale.Parent = parentFrame
	end
	return scale :: UIScale
end

-- ============================================================
-- SKIP CAPSULE OPENS — expose via BoolValue so InventoryUI can read
-- ============================================================
local skipCapsuleValue = Instance.new("BoolValue")
skipCapsuleValue.Name = "SkipCapsuleOpens"
skipCapsuleValue.Value = false
skipCapsuleValue.Parent = playerGui

-- ============================================================
-- TOGGLE HELPERS
-- ============================================================
local function UpdateToggleVisual(frame: Frame?, isOn: boolean)
	if not frame then return end

	local toggleFrame = frame:FindFirstChild("ToggleFrame") :: Frame?
	if not toggleFrame then return end

	local toggleButton = toggleFrame:FindFirstChild("ToggleButton")
	local textLabel: TextLabel? = nil

	-- ToggleButton might have a TextLabel child, or the ToggleFrame might
	if toggleButton then
		textLabel = toggleButton:FindFirstChildWhichIsA("TextLabel")
	end
	if not textLabel then
		textLabel = toggleFrame:FindFirstChildWhichIsA("TextLabel")
	end

	local bgColor = if isOn then ON_COLOR else OFF_COLOR
	local strokeColor = if isOn then ON_STROKE_COLOR else OFF_STROKE_COLOR
	local labelText = if isOn then "ON" else "OFF"

	-- Animate toggle frame background
	PlayTween(toggleFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundColor3 = bgColor,
	})

	-- Also animate the toggle button background if it exists
	if toggleButton and toggleButton:IsA("GuiObject") then
		PlayTween(toggleButton :: GuiObject, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = bgColor,
		})
	end

	-- Update text on TextLabel child
	if textLabel then
		textLabel.Text = labelText
	end

	-- Also update .Text if ToggleButton is a TextButton
	if toggleButton and toggleButton:IsA("TextButton") then
		(toggleButton :: TextButton).Text = labelText
	end

	-- Update stroke colors on the text label
	if textLabel then
		for _, child in ipairs(textLabel:GetChildren()) do
			if child:IsA("UIStroke") then
				PlayTween(child, TweenInfo.new(0.2), { Color = strokeColor })
			end
		end
	end

	-- Also update stroke colors on the toggle button itself
	if toggleButton then
		for _, child in ipairs(toggleButton:GetChildren()) do
			if child:IsA("UIStroke") then
				PlayTween(child, TweenInfo.new(0.2), { Color = strokeColor })
			end
		end
	end

	-- Also update stroke colors on the toggle frame
	for _, child in ipairs(toggleFrame:GetChildren()) do
		if child:IsA("UIStroke") then
			PlayTween(child, TweenInfo.new(0.2), { Color = strokeColor })
		end
	end
end

local function WireToggle(frame: Frame?, getValue: () -> boolean, setValue: (boolean) -> ())
	if not frame then return end

	local toggleFrame = frame:FindFirstChild("ToggleFrame") :: Frame?
	if not toggleFrame then return end

	local toggleButton = toggleFrame:FindFirstChild("ToggleButton")
	local clickTarget: GuiButton? = nil

	if toggleButton and (toggleButton:IsA("TextButton") or toggleButton:IsA("ImageButton")) then
		clickTarget = toggleButton :: GuiButton
	elseif toggleFrame:IsA("TextButton") or toggleFrame:IsA("ImageButton") then
		clickTarget = toggleFrame :: GuiButton
	end

	-- Set initial visual
	UpdateToggleVisual(frame, getValue())

	if not clickTarget then
		-- Make the toggle frame clickable as fallback via InputBegan
		toggleFrame.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				if clickSound then clickSound:Play() end
				local newVal = not getValue()
				setValue(newVal)
				UpdateToggleVisual(frame, newVal)
			end
		end)
	else
		clickTarget.MouseButton1Click:Connect(function()
			if clickSound then clickSound:Play() end
			local newVal = not getValue()
			setValue(newVal)
			UpdateToggleVisual(frame, newVal)
		end)
	end
end

-- ============================================================
-- MUSIC TOGGLE
-- ============================================================
WireToggle(gameMusicFrame, function() return musicEnabled end, function(val)
	musicEnabled = val
	local bgMusic = SoundService:FindFirstChild("BGMusic") :: Sound?
	if bgMusic then
		bgMusic.Volume = if val then 0.15 else 0
	end
	SaveConfig()
end)

-- ============================================================
-- SFX TOGGLE
-- ============================================================
WireToggle(sfxFrame, function() return sfxEnabled end, function(val)
	sfxEnabled = val
	-- Mute/unmute all sounds in the Sounds folder
	if SoundsFolder then
		for _, subfolder in ipairs(SoundsFolder:GetChildren()) do
			if subfolder:IsA("Folder") then
				for _, sound in ipairs(subfolder:GetChildren()) do
					if sound:IsA("Sound") then
						if val then
							-- Restore original volume
							sound.Volume = sound:GetAttribute("OriginalVolume") or 0.5
						else
							-- Mute
							sound.Volume = 0
						end
					end
				end
			end
		end
	end
	SaveConfig()
end)

-- Store original volumes on startup so we can restore them
if SoundsFolder then
	for _, subfolder in ipairs(SoundsFolder:GetChildren()) do
		if subfolder:IsA("Folder") then
			for _, sound in ipairs(subfolder:GetChildren()) do
				if sound:IsA("Sound") and not sound:GetAttribute("OriginalVolume") then
					sound:SetAttribute("OriginalVolume", sound.Volume)
				end
			end
		end
	end
end

-- ============================================================
-- SKIP CAPSULE OPENS TOGGLE
-- ============================================================
WireToggle(skipAnimFrame, function() return skipCapsuleOpens end, function(val)
	skipCapsuleOpens = val
	skipCapsuleValue.Value = val
	SaveConfig()
end)

-- ============================================================
-- CODE REDEMPTION
-- ============================================================
local function SetupCodeRedemption()
	if not codesFrame then return end

	local textBox = codesFrame:FindFirstChildWhichIsA("TextBox") :: TextBox?
	local toggleFrame = codesFrame:FindFirstChild("ToggleFrame") :: Frame?
	local enterBtn = toggleFrame and toggleFrame:FindFirstChild("ToggleButton")

	if not textBox then return end

	local function SubmitCode()
		local code = textBox.Text
		if code == "" or code == "Enter Codes Here..." then
			if failSound then failSound:Play() end
			return
		end

		if not RedeemCode then
			if failSound then failSound:Play() end
			return
		end

		local result = RedeemCode:InvokeServer(code)
		if result and result.success then
			if achieveSound then achieveSound:Play() end
			textBox.Text = "Redeemed!"
			textBox.TextColor3 = Color3.fromRGB(80, 220, 100)

			-- Show reward announce
			local navHUD = playerGui:FindFirstChild("NavHUD")
			if navHUD then
				local rewardAnnounce = navHUD:FindFirstChild("RewardAnnounce") :: TextLabel?
				if rewardAnnounce then
					rewardAnnounce.RichText = true
					local msg = '<font color="#FFD700">Code Redeemed!</font>'
					if result.coinsGranted and result.coinsGranted > 0 then
						msg = '<font color="#FFD700">+' .. tostring(result.coinsGranted) .. ' Coins!</font>'
					end
					rewardAnnounce.Text = msg
					rewardAnnounce.Visible = true
					rewardAnnounce.TextTransparency = 0
					local origStroke = rewardAnnounce.TextStrokeTransparency
					task.delay(3, function()
						local tw = PlayTween(rewardAnnounce, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
							TextTransparency = 1,
							TextStrokeTransparency = 1,
						})
						tw.Completed:Wait()
						rewardAnnounce.Visible = false
						rewardAnnounce.TextTransparency = 0
						rewardAnnounce.TextStrokeTransparency = origStroke
					end)
				end
			end

			task.delay(1.5, function()
				textBox.Text = ""
				textBox.TextColor3 = Color3.fromRGB(100, 100, 100)
			end)
		else
			if failSound then failSound:Play() end
			local reason = result and result.reason or "error"
			if reason == "already_redeemed" then
				textBox.Text = "Already Redeemed!"
			elseif reason == "invalid_code" then
				textBox.Text = "Invalid Code!"
			else
				textBox.Text = "Error!"
			end
			textBox.TextColor3 = Color3.fromRGB(255, 70, 70)
			task.delay(1.5, function()
				textBox.Text = ""
				textBox.TextColor3 = Color3.fromRGB(100, 100, 100)
			end)
		end
	end

	-- Wire the ENTER button
	if enterBtn and (enterBtn:IsA("TextButton") or enterBtn:IsA("ImageButton")) then
		(enterBtn :: GuiButton).MouseButton1Click:Connect(function()
			SubmitCode()
		end)
	end

	-- Also submit on FocusLost (pressing Enter key in the text box)
	textBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			SubmitCode()
		end
	end)
end

SetupCodeRedemption()

-- ============================================================
-- OPEN / CLOSE (same pattern as other UIs)
-- ============================================================
-- Close other popups (mutual exclusion)
local POPUP_GUIS = {"StoreUI", "InventoryUI", "QuestsUI", "DailyRewardsUI", "SpinUI", "CapsuleUI", "ConfigUI"}

local function CloseOtherPopups()
	for _, guiName in ipairs(POPUP_GUIS) do
		if guiName ~= "ConfigUI" then
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

local function OpenUI()
	if isOpen or isAnimating then return end
	CloseOtherPopups()
	isAnimating = true

	if clickSound then clickSound:Play() end

	configGui.Enabled = true
	parentFrame.Visible = true

	-- Add blur
	blurEffect = Instance.new("BlurEffect")
	blurEffect.Size = 0
	blurEffect.Parent = Lighting
	PlayTween(blurEffect, TweenInfo.new(0.3), { Size = 10 })

	-- Camera zoom
	originalFOV = Camera.FieldOfView
	PlayTween(Camera, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = originalFOV + UI_ZOOM_FOV,
	})

	-- Scale in
	local scale = EnsureUIScale()
	scale.Scale = 0
	local tween = PlayTween(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	})
	tween.Completed:Wait()

	isOpen = true
	isAnimating = false
end

local function CloseUI()
	if not isOpen or isAnimating then return end
	isAnimating = true

	if clickSound then clickSound:Play() end

	local scale = EnsureUIScale()
	local tween = PlayTween(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Scale = 0,
	})

	if blurEffect then
		PlayTween(blurEffect, TweenInfo.new(0.3), { Size = 0 })
	end

	PlayTween(Camera, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = originalFOV,
	})

	tween.Completed:Wait()

	parentFrame.Visible = false
	configGui.Enabled = false

	if blurEffect then
		blurEffect:Destroy()
		blurEffect = nil
	end

	isOpen = false
	isAnimating = false
end

-- ============================================================
-- CLOSE BUTTON (hover + click + sounds)
-- ============================================================
if closeBtn and (closeBtn:IsA("TextButton") or closeBtn:IsA("ImageButton")) then
	local btn = closeBtn :: GuiButton
	local originalSize = btn.Size
	local hoverSize = UDim2.new(
		originalSize.X.Scale * 1.12, originalSize.X.Offset * 1.12,
		originalSize.Y.Scale * 1.12, originalSize.Y.Offset * 1.12
	)

	btn.MouseEnter:Connect(function()
		if hoverSound then hoverSound:Play() end
		PlayTween(btn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = hoverSize,
		})
	end)

	btn.MouseLeave:Connect(function()
		PlayTween(btn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = originalSize,
		})
	end)

	btn.MouseButton1Click:Connect(function()
		-- Click pulse
		PlayTween(btn, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(
				originalSize.X.Scale * 0.88, originalSize.X.Offset * 0.88,
				originalSize.Y.Scale * 0.88, originalSize.Y.Offset * 0.88
			),
		}).Completed:Connect(function()
			PlayTween(btn, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = originalSize,
			})
		end)
		CloseUI()
	end)

	-- Prevent child TextLabels from eating clicks
	for _, child in ipairs(btn:GetChildren()) do
		if child:IsA("TextLabel") then
			child.Active = false
			child.Interactable = false
		end
	end
end

-- Initialize hidden
configGui.Enabled = false
parentFrame.Visible = false

-- Expose open/close for other scripts
local openEvent = Instance.new("BindableEvent")
openEvent.Name = "OpenConfig"
openEvent.Parent = configGui
openEvent.Event:Connect(function()
	if not isOpen then
		OpenUI()
	end
end)

-- ForceClose (used by RoundStartCloser)
local function ForceCloseUI()
	if not isOpen and not isAnimating then return end
	parentFrame.Visible = false
	configGui.Enabled = false
	if blurEffect then
		blurEffect:Destroy()
		blurEffect = nil
	end
	Camera.FieldOfView = originalFOV
	isOpen = false
	isAnimating = false
end

local forceCloseEvent = Instance.new("BindableEvent")
forceCloseEvent.Name = "ForceClose"
forceCloseEvent.Parent = configGui
forceCloseEvent.Event:Connect(function()
	ForceCloseUI()
end)

-- ============================================================
-- NavHUD Config button integration
-- ============================================================
task.spawn(function()
	local navHUD = playerGui:WaitForChild("NavHUD", 15)
	if not navHUD then return end

	local navParent = navHUD:FindFirstChild("ParentFrame")
	if not navParent then return end

	local navFrame = navParent:FindFirstChild("NavFrame")
	if not navFrame then return end

	local configFrame = navFrame:FindFirstChild("ConfigFrame")
	if not configFrame then return end

	local configImageBtn = configFrame:FindFirstChildWhichIsA("ImageButton")
	local configTextLabel = configFrame:FindFirstChildWhichIsA("TextLabel")

	if not configImageBtn then return end

	local originalBtnSize = configImageBtn.Size
	local hoverBtnSize = UDim2.new(
		originalBtnSize.X.Scale * 1.12, originalBtnSize.X.Offset * 1.12,
		originalBtnSize.Y.Scale * 1.12, originalBtnSize.Y.Offset * 1.12
	)
	local originalTextColor = configTextLabel and configTextLabel.TextColor3 or Color3.new(1, 1, 1)
	local hoverTextColor = Color3.fromRGB(255, 240, 130)

	configImageBtn.MouseEnter:Connect(function()
		if hoverSound then hoverSound:Play() end
		PlayTween(configImageBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = hoverBtnSize,
		})
		if configTextLabel then
			PlayTween(configTextLabel, TweenInfo.new(0.12), {
				TextColor3 = hoverTextColor,
			})
		end
	end)

	configImageBtn.MouseLeave:Connect(function()
		PlayTween(configImageBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = originalBtnSize,
		})
		if configTextLabel then
			PlayTween(configTextLabel, TweenInfo.new(0.12), {
				TextColor3 = originalTextColor,
			})
		end
	end)

	configImageBtn.MouseButton1Click:Connect(function()
		PlayTween(configImageBtn, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(
				originalBtnSize.X.Scale * 0.88, originalBtnSize.X.Offset * 0.88,
				originalBtnSize.Y.Scale * 0.88, originalBtnSize.Y.Offset * 0.88
			),
		}).Completed:Connect(function()
			PlayTween(configImageBtn, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = originalBtnSize,
			})
		end)

		if isOpen then
			CloseUI()
		else
			OpenUI()
		end
	end)
end)

-- ============================================================
-- LOAD SAVED CONFIG ON JOIN
-- ============================================================
task.spawn(function()
	if not GetConfigSettings then return end
	local saved = GetConfigSettings:InvokeServer()
	if type(saved) ~= "table" then return end

	-- Apply music setting
	if saved.musicEnabled == false and musicEnabled then
		musicEnabled = false
		local bgMusic = SoundService:FindFirstChild("BGMusic") :: Sound?
		if bgMusic then bgMusic.Volume = 0 end
		UpdateToggleVisual(gameMusicFrame, false)
	end

	-- Apply SFX setting
	if saved.sfxEnabled == false and sfxEnabled then
		sfxEnabled = false
		if SoundsFolder then
			for _, subfolder in ipairs(SoundsFolder:GetChildren()) do
				if subfolder:IsA("Folder") then
					for _, sound in ipairs(subfolder:GetChildren()) do
						if sound:IsA("Sound") then
							sound.Volume = 0
						end
					end
				end
			end
		end
		UpdateToggleVisual(sfxFrame, false)
	end

	-- Apply skip capsule opens setting
	if saved.skipCapsuleOpens == true and not skipCapsuleOpens then
		skipCapsuleOpens = true
		skipCapsuleValue.Value = true
		UpdateToggleVisual(skipAnimFrame, true)
	end
end)

print("[ConfigUI] Initialized")
