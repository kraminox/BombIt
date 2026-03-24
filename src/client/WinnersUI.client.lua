--!strict
-- WinnersUI.client.lua
-- Winners podium UI with emotes and stickers

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

-- Wait for remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged")

-- These are created by the server during RoundSystem.Initialize
local PlayEmote
local ShowSticker

task.spawn(function()
	PlayEmote = Remotes:WaitForChild("PlayEmote", 10)
	ShowSticker = Remotes:WaitForChild("ShowSticker", 10)
end)

-- UI elements
local screenGui: ScreenGui
local emoteFrame: Frame
local stickerFrame: Frame

-- Track active stickers
local activeStickers = {}

-- Create UI
local function CreateUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "WinnersUI"
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	-- Combined emotes & stickers frame (bottom center) - single compact bar
	emoteFrame = Instance.new("Frame")
	emoteFrame.Name = "ActionsFrame"
	emoteFrame.Size = UDim2.new(0, 400, 0, 50)
	emoteFrame.Position = UDim2.new(0.5, -200, 1, -70)
	emoteFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	emoteFrame.BackgroundTransparency = 0.2
	emoteFrame.Parent = screenGui

	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 25)
	frameCorner.Parent = emoteFrame

	local actionsContainer = Instance.new("Frame")
	actionsContainer.Name = "Container"
	actionsContainer.Size = UDim2.new(1, -20, 1, -10)
	actionsContainer.Position = UDim2.new(0, 10, 0, 5)
	actionsContainer.BackgroundTransparency = 1
	actionsContainer.Parent = emoteFrame

	local actionsLayout = Instance.new("UIListLayout")
	actionsLayout.FillDirection = Enum.FillDirection.Horizontal
	actionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	actionsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	actionsLayout.Padding = UDim.new(0, 8)
	actionsLayout.Parent = actionsContainer

	-- Create emote buttons (just icons)
	for _, emote in ipairs(Constants.EMOTES) do
		local btn = Instance.new("TextButton")
		btn.Name = emote.id
		btn.Size = UDim2.new(0, 36, 0, 36)
		btn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
		btn.Text = emote.icon
		btn.TextSize = 18
		btn.Font = Enum.Font.GothamBold
		btn.Parent = actionsContainer

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(1, 0)
		btnCorner.Parent = btn

		btn.MouseButton1Click:Connect(function()
			if PlayEmote then
				PlayEmote:FireServer(emote.id)
			end
		end)

		btn.MouseEnter:Connect(function()
			TweenService:Create(btn, TweenInfo.new(0.1), {
				BackgroundColor3 = Color3.fromRGB(70, 70, 90),
				Size = UDim2.new(0, 40, 0, 40)
			}):Play()
		end)

		btn.MouseLeave:Connect(function()
			TweenService:Create(btn, TweenInfo.new(0.1), {
				BackgroundColor3 = Color3.fromRGB(50, 50, 60),
				Size = UDim2.new(0, 36, 0, 36)
			}):Play()
		end)
	end

	-- Divider
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(0, 2, 0.6, 0)
	divider.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
	divider.BorderSizePixel = 0
	divider.Parent = actionsContainer

	-- Create sticker buttons (compact text)
	for _, sticker in ipairs(Constants.STICKERS) do
		local btn = Instance.new("TextButton")
		btn.Name = sticker.id
		btn.Size = UDim2.new(0, 36, 0, 36)
		btn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
		btn.Text = string.sub(sticker.text, 1, 2)
		btn.TextColor3 = sticker.color
		btn.TextSize = 12
		btn.Font = Enum.Font.GothamBold
		btn.Parent = actionsContainer

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(1, 0)
		btnCorner.Parent = btn

		btn.MouseButton1Click:Connect(function()
			if ShowSticker then
				ShowSticker:FireServer(sticker.id)
			end
		end)

		btn.MouseEnter:Connect(function()
			TweenService:Create(btn, TweenInfo.new(0.1), {
				BackgroundColor3 = Color3.fromRGB(70, 70, 90),
				Size = UDim2.new(0, 40, 0, 40)
			}):Play()
		end)

		btn.MouseLeave:Connect(function()
			TweenService:Create(btn, TweenInfo.new(0.1), {
				BackgroundColor3 = Color3.fromRGB(50, 50, 60),
				Size = UDim2.new(0, 36, 0, 36)
			}):Play()
		end)
	end

	-- Unused but kept for compatibility
	stickerFrame = emoteFrame
end

-- Show sticker above player's head
local function DisplaySticker(userId: number, stickerId: string)
	local targetPlayer = Players:GetPlayerByUserId(userId)
	if not targetPlayer or not targetPlayer.Character then return end

	local head = targetPlayer.Character:FindFirstChild("Head")
	if not head then return end

	-- Find sticker data
	local stickerData
	for _, sticker in ipairs(Constants.STICKERS) do
		if sticker.id == stickerId then
			stickerData = sticker
			break
		end
	end

	if not stickerData then return end

	-- Remove existing sticker for this player
	if activeStickers[userId] then
		activeStickers[userId]:Destroy()
	end

	-- Create sticker billboard
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

	-- Animate in
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	TweenService:Create(billboard, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, 3, 0)
	}):Play()

	-- Remove after 3 seconds
	task.delay(3, function()
		if billboard and billboard.Parent then
			TweenService:Create(billboard, TweenInfo.new(0.2), {
				StudsOffset = Vector3.new(0, 4, 0)
			}):Play()
			TweenService:Create(stickerLabel, TweenInfo.new(0.2), {
				BackgroundTransparency = 1,
				TextTransparency = 1
			}):Play()
			task.wait(0.2)
			billboard:Destroy()
			if activeStickers[userId] == billboard then
				activeStickers[userId] = nil
			end
		end
	end)
end

-- Show winners UI (just the action bar)
local function Show()
	screenGui.Enabled = true

	-- Animate in from bottom
	emoteFrame.Position = UDim2.new(0.5, -200, 1, 50)
	TweenService:Create(emoteFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, -200, 1, -70)
	}):Play()
end

-- Hide winners UI
local function Hide()
	TweenService:Create(emoteFrame, TweenInfo.new(0.3), {
		Position = UDim2.new(0.5, -200, 1, 50)
	}):Play()

	task.delay(0.3, function()
		screenGui.Enabled = false
	end)
end

-- Handle state changes
RoundStateChanged.OnClientEvent:Connect(function(state: string, data: any?)
	if state == "RoundResults" or state == Constants.STATES.ROUND_END or state == "RoundEnd" then
		Show()
	elseif state == Constants.STATES.INTERMISSION or state == "Intermission" then
		Hide()
	elseif state == Constants.STATES.LOBBY or state == "Lobby" then
		Hide()
	elseif state == Constants.STATES.PLAYING or state == "Playing" then
		Hide()
	end
end)

-- Handle sticker display from other players
task.spawn(function()
	while not ShowSticker do
		task.wait(0.1)
	end
	ShowSticker.OnClientEvent:Connect(function(userId: number, stickerId: string)
		DisplaySticker(userId, stickerId)
	end)
end)

-- Initialize
CreateUI()
print("[WinnersUI] Initialized")
