--!strict
-- KillFeed.client.lua
-- Displays kill feed entries using the pre-built TemplateKillFeed in GameUI

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlayerDied = Remotes:WaitForChild("PlayerDied")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged")

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

-- Settings
local MAX_ENTRIES = 3
local ENTRY_LIFETIME = 4 -- seconds before fade out
local ENTRY_HEIGHT = 48 -- pixel height per entry including gap
local FADE_OUT_TIME = 0.4
local ANCHOR_TOP = 80 -- pixels from top of screen
local RIGHT_MARGIN = -10 -- offset from right edge (negative = inset)

-- Template reference and its parent ScreenGui (found at runtime)
local killFeedTemplate: Frame? = nil
local feedParentGui: ScreenGui? = nil

-- Active feed entries (ordered newest first)
local activeEntries = {} :: {{frame: Frame, expiry: number}}

-- Find the template by searching ScreenGuis
local function FindTemplate()
	for _, gui in ipairs(playerGui:GetChildren()) do
		if not gui:IsA("ScreenGui") then continue end
		-- Check direct children
		local found = gui:FindFirstChild("TemplateKillFeed", true)
		if found and found:IsA("Frame") then
			feedParentGui = gui
			return found
		end
	end
	return nil
end

-- Set player headshot thumbnail on an ImageLabel
local function SetPlayerThumbnail(imageLabel: ImageLabel, userId: number)
	imageLabel.ImageTransparency = 0
	imageLabel.BackgroundTransparency = 1

	-- Studio test players have negative UserIds — no thumbnail exists, keep template default
	if userId <= 0 then return end

	task.spawn(function()
		local success, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		end)
		if success and content and imageLabel.Parent then
			imageLabel.Image = tostring(content)
		end
	end)
end

-- Reposition all active entries with tweens (stack from top-right)
local function RepositionEntries()
	for i, entry in ipairs(activeEntries) do
		local targetY = ANCHOR_TOP + (i - 1) * ENTRY_HEIGHT
		local targetPos = UDim2.new(1, RIGHT_MARGIN, 0, targetY)

		TweenService:Create(entry.frame, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = targetPos,
		}):Play()
	end
end

-- Remove an entry with fade-out slide to the right
local function RemoveEntry(entry: {frame: Frame, expiry: number})
	-- Find and remove from activeEntries
	for i, e in ipairs(activeEntries) do
		if e == entry then
			table.remove(activeEntries, i)
			break
		end
	end

	-- Slide right off screen (AnchorPoint is 1,0 so positive offset = further right)
	local frame = entry.frame
	local slideOutPos = UDim2.new(1, 300, frame.Position.Y.Scale, frame.Position.Y.Offset)

	TweenService:Create(frame, TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
		Position = slideOutPos,
	}):Play()

	task.delay(FADE_OUT_TIME + 0.05, function()
		frame:Destroy()
	end)

	-- Reposition remaining entries to fill the gap
	RepositionEntries()
end

-- Add a kill feed entry
local function AddKillFeedEntry(victimId: number, killerId: number)
	if not killFeedTemplate then
		killFeedTemplate = FindTemplate()
		if killFeedTemplate then
			killFeedTemplate.Visible = false
		end
	end
	if not killFeedTemplate or not feedParentGui then return end

	-- Clone template
	local entry = killFeedTemplate:Clone()
	entry.Name = "KillFeed_" .. math.floor(tick() * 100)
	entry.Visible = true

	-- Set anchor to top-right and start off-screen right
	entry.AnchorPoint = Vector2.new(1, 0)
	entry.Position = UDim2.new(1, 300, 0, ANCHOR_TOP)

	-- Parent FIRST so rbxthumb:// content resolves (needs to be in DataModel)
	entry.Parent = feedParentGui

	-- Set up images with player thumbnails AFTER parenting
	local frameWithList = entry:FindFirstChild("FrameWithList")
	if frameWithList then
		local killerImg = frameWithList:FindFirstChild("Killer")
		local victimImg = frameWithList:FindFirstChild("Victim")

		if killerImg and killerImg:IsA("ImageLabel") then
			-- For self-kills (killerId == 0), show victim as killer too
			local displayKillerId = if killerId > 0 then killerId else victimId
			SetPlayerThumbnail(killerImg, displayKillerId)
		end

		if victimImg and victimImg:IsA("ImageLabel") then
			SetPlayerThumbnail(victimImg, victimId)
		end
	end

	-- Add to active list (newest at index 1)
	local entryData = {
		frame = entry,
		expiry = tick() + ENTRY_LIFETIME,
	}
	table.insert(activeEntries, 1, entryData)

	-- Cap max visible entries — remove oldest without animation
	while #activeEntries > MAX_ENTRIES do
		local oldest = activeEntries[#activeEntries]
		table.remove(activeEntries, #activeEntries)
		oldest.frame:Destroy()
	end

	-- Slide all entries to their correct positions (new one slides in)
	task.defer(RepositionEntries)

	-- Schedule auto-removal
	task.delay(ENTRY_LIFETIME, function()
		if entry.Parent then
			RemoveEntry(entryData)
		end
	end)
end

-- === Elimination popup (center-bottom, only for local player's kills) ===

local eliminationTemplate: Frame? = nil
local activeElimination: Frame? = nil

local function FindEliminationTemplate()
	for _, gui in ipairs(playerGui:GetChildren()) do
		if not gui:IsA("ScreenGui") then continue end
		local found = gui:FindFirstChild("TemplateElimination", true)
		if found and found:IsA("Frame") then
			return found
		end
	end
	return nil
end

local function ShowElimination(victimId: number)
	if not eliminationTemplate then
		eliminationTemplate = FindEliminationTemplate()
		if eliminationTemplate then
			eliminationTemplate.Visible = false
		end
	end
	if not eliminationTemplate then return end

	-- Destroy previous one if still showing
	if activeElimination and activeElimination.Parent then
		activeElimination:Destroy()
	end

	local victimPlayer = Players:GetPlayerByUserId(victimId)
	local victimName = victimPlayer and victimPlayer.DisplayName or "???"

	local popup = eliminationTemplate:Clone()
	popup.Name = "Elimination_" .. victimId
	popup.Visible = true

	-- Set victim name in the TextLabel
	local textLabel = popup:FindFirstChild("TextLabel")
	if textLabel and textLabel:IsA("TextLabel") then
		textLabel.Text = "eliminated " .. victimName .. "!"
	end

	-- Set bomb icon from kill feed template's BombImage
	local imageLabel = popup:FindFirstChild("ImageLabel")
	if imageLabel and imageLabel:IsA("ImageLabel") then
		-- Copy the bomb image from the kill feed template
		if killFeedTemplate then
			local frameWithList = killFeedTemplate:FindFirstChild("FrameWithList")
			local bombImage = frameWithList and frameWithList:FindFirstChild("BombImage")
			if bombImage and bombImage:IsA("ImageLabel") then
				imageLabel.Image = bombImage.Image
				imageLabel.ImageColor3 = bombImage.ImageColor3
				imageLabel.ScaleType = bombImage.ScaleType
			end
		end
	end

	-- Parent to same ScreenGui
	local parentGui = eliminationTemplate.Parent
	while parentGui and not parentGui:IsA("ScreenGui") do
		parentGui = parentGui.Parent
	end
	popup.Parent = parentGui

	activeElimination = popup

	-- Animate in: scale from 0 with bounce
	local origSize = popup.Size
	popup.Size = UDim2.new(0, 0, 0, 0)
	TweenService:Create(popup, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = origSize,
	}):Play()

	-- Hold, then fade out
	task.delay(2.5, function()
		if popup.Parent then
			TweenService:Create(popup, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
				Size = UDim2.new(0, 0, 0, 0),
			}):Play()
			task.delay(0.35, function()
				if popup.Parent then
					popup:Destroy()
				end
				if activeElimination == popup then
					activeElimination = nil
				end
			end)
		end
	end)
end

-- Listen for kills
PlayerDied.OnClientEvent:Connect(function(victimId: number, killerId: number?)
	local kid = killerId or 0
	AddKillFeedEntry(victimId, kid)

	-- Show elimination popup only when local player killed someone else
	if kid == player.UserId and victimId ~= player.UserId then
		ShowElimination(victimId)
	end
end)

-- Clear kill feed on round end / lobby
RoundStateChanged.OnClientEvent:Connect(function(state: string, data: any?)
	if state == Constants.STATES.LOBBY or state == Constants.STATES.INTERMISSION
		or state == "FadeToLobby" then
		for _, entry in ipairs(activeEntries) do
			entry.frame:Destroy()
		end
		activeEntries = {}
		if activeElimination and activeElimination.Parent then
			activeElimination:Destroy()
			activeElimination = nil
		end
	end
end)

-- Find templates on startup
task.spawn(function()
	task.wait(2)
	killFeedTemplate = FindTemplate()
	if killFeedTemplate then
		killFeedTemplate.Visible = false
	end
	eliminationTemplate = FindEliminationTemplate()
	if eliminationTemplate then
		eliminationTemplate.Visible = false
	end
end)

print("[KillFeed] Initialized")
