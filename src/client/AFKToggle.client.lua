--!strict
-- AFKToggle.client.lua
-- Handles AFK button in NavHUD: toggle visual state and notify server

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Sound effects
local SoundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
local UISounds = SoundsFolder and SoundsFolder:FindFirstChild("UI")
local clickSound: Sound? = UISounds and UISounds:FindFirstChild("Click") :: Sound? or nil
local hoverSound: Sound? = UISounds and UISounds:FindFirstChild("Hover") :: Sound? or nil

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SetAFK = Remotes:WaitForChild("SetAFK", 15) :: RemoteEvent?

-- State
local isAFK = false

-- Expose AFK state via a BoolValue so other client scripts (CameraController, GameUI) can read it
local afkValue = Instance.new("BoolValue")
afkValue.Name = "IsAFK"
afkValue.Value = false
afkValue.Parent = player

-- Colors
local ACTIVE_COLOR = Color3.fromRGB(75, 200, 75)   -- Green (NOT AFK)
local AFK_COLOR = Color3.fromRGB(200, 70, 70)       -- Red (AFK)
local ACTIVE_STROKE = Color3.fromRGB(40, 120, 40)
local AFK_STROKE = Color3.fromRGB(140, 40, 40)

-- Helper: play tween
local function PlayTween(instance: Instance, info: TweenInfo, props: {[string]: any}): Tween
	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

-- Find and wire the AFK button
task.spawn(function()
	local navHUD = playerGui:WaitForChild("NavHUD", 15)
	if not navHUD then return end

	local navParent = navHUD:FindFirstChild("ParentFrame")
	if not navParent then return end

	-- Try to find AFKFrame in various possible locations
	local afkFrame: GuiObject? = navParent:FindFirstChild("AFKFrame") :: GuiObject?
	if not afkFrame then
		local navFrame = navParent:FindFirstChild("NavFrame")
		if navFrame then
			afkFrame = navFrame:FindFirstChild("AFKFrame") :: GuiObject?
		end
	end
	if not afkFrame then return end

	-- Determine the clickable element:
	-- Could be a child TextButton/ImageButton, or the AFKFrame itself could be a button
	local btn: GuiButton? = afkFrame:FindFirstChildWhichIsA("TextButton") :: GuiButton?
	if not btn then
		btn = afkFrame:FindFirstChildWhichIsA("ImageButton") :: GuiButton?
	end

	-- If AFKFrame itself is a button, use it directly
	if not btn then
		if afkFrame:IsA("TextButton") or afkFrame:IsA("ImageButton") then
			btn = afkFrame :: GuiButton
		end
	end

	if not btn then return end

	local originalBtnSize = btn.Size
	local hoverBtnSize = UDim2.new(
		originalBtnSize.X.Scale * 1.08, originalBtnSize.X.Offset * 1.08,
		originalBtnSize.Y.Scale * 1.08, originalBtnSize.Y.Offset * 1.08
	)

	-- Find text label for AFK status — check multiple possible locations
	local afkLabel: TextLabel? = nil
	-- 1. TextLabel child of the button
	afkLabel = btn:FindFirstChildWhichIsA("TextLabel")
	-- 2. TextLabel child of afkFrame
	if not afkLabel and afkFrame ~= btn then
		afkLabel = afkFrame:FindFirstChildWhichIsA("TextLabel")
	end

	-- Collect all UIStroke instances to update (on button, label, and frame)
	local function GetAllStrokes(): {UIStroke}
		local strokes = {}
		-- Strokes on the label
		if afkLabel then
			for _, child in ipairs(afkLabel:GetChildren()) do
				if child:IsA("UIStroke") then
					table.insert(strokes, child)
				end
			end
		end
		-- Strokes on the button itself (if it's a TextButton with stroke)
		for _, child in ipairs(btn:GetChildren()) do
			if child:IsA("UIStroke") then
				table.insert(strokes, child)
			end
		end
		-- Strokes on the frame (if different from button)
		if afkFrame ~= btn then
			for _, child in ipairs(afkFrame:GetChildren()) do
				if child:IsA("UIStroke") then
					table.insert(strokes, child)
				end
			end
		end
		return strokes
	end

	-- Update visual state
	local function UpdateVisual()
		local bgColor = if isAFK then AFK_COLOR else ACTIVE_COLOR
		local labelText = if isAFK then "AFK" else "NOT AFK"
		local strokeColor = if isAFK then AFK_STROKE else ACTIVE_STROKE

		-- Animate frame background
		PlayTween(afkFrame :: GuiObject, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = bgColor,
		})

		-- Also animate button background if it's separate from frame
		if btn ~= afkFrame then
			PlayTween(btn, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundColor3 = bgColor,
			})
		end

		-- Update text on label
		if afkLabel then
			afkLabel.Text = labelText
		end

		-- Also update TextButton.Text if it's a TextButton
		if btn:IsA("TextButton") then
			(btn :: TextButton).Text = labelText
		end

		-- Update all stroke colors
		for _, stroke in ipairs(GetAllStrokes()) do
			PlayTween(stroke, TweenInfo.new(0.2), { Color = strokeColor })
		end
	end

	-- Hover effects
	btn.MouseEnter:Connect(function()
		if hoverSound then hoverSound:Play() end
		PlayTween(btn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = hoverBtnSize,
		})
	end)

	btn.MouseLeave:Connect(function()
		PlayTween(btn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = originalBtnSize,
		})
	end)

	-- Click handler
	btn.MouseButton1Click:Connect(function()
		if clickSound then clickSound:Play() end

		-- Click pulse animation
		PlayTween(btn, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(
				originalBtnSize.X.Scale * 0.88, originalBtnSize.X.Offset * 0.88,
				originalBtnSize.Y.Scale * 0.88, originalBtnSize.Y.Offset * 0.88
			),
		}).Completed:Connect(function()
			PlayTween(btn, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = originalBtnSize,
			})
		end)

		-- Toggle state
		isAFK = not isAFK
		afkValue.Value = isAFK
		UpdateVisual()

		-- Notify server
		if SetAFK then
			SetAFK:FireServer(isAFK)
		end
	end)

	-- Set initial visual (NOT AFK)
	UpdateVisual()

	print("[AFKToggle] AFK button initialized")
end)
