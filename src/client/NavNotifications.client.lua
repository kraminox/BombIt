--!strict
-- NavNotifications.client.lua
-- Manages pulsing notification badges on NavHUD buttons
-- Badges appear when: quest completed, new item acquired, inventory changed
-- Badges dismiss when user clicks the corresponding nav button

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SyncQuests = Remotes:WaitForChild("SyncQuests", 15)
local SyncInventory = Remotes:WaitForChild("SyncInventory", 15)

-- Wait for NavHUD
local navHUD = playerGui:WaitForChild("NavHUD", 15) :: ScreenGui?
if not navHUD then
	warn("[NavNotifications] NavHUD not found")
	return
end

local navParent = navHUD:FindFirstChild("ParentFrame")
if not navParent then return end

local navFrame = navParent:FindFirstChild("NavFrame")
if not navFrame then return end

-- Badge state: track which nav frames have active notifications
local activeBadges: {[string]: boolean} = {}
local pulseTweens: {[string]: thread} = {}

-- Track previous data to detect changes
local prevQuestData: any = nil
local prevInventoryOwned: number? = nil

-- Find the Notif frame inside a nav button frame
local function GetNotif(frameName: string): Frame?
	local frame = navFrame:FindFirstChild(frameName)
	if not frame then return nil end
	local notif = frame:FindFirstChild("Notif") :: Frame?
	return notif
end

-- Start pulsing animation on a Notif frame
local function StartPulse(frameName: string)
	if activeBadges[frameName] then return end
	local notif = GetNotif(frameName)
	if not notif then return end

	activeBadges[frameName] = true
	notif.Visible = true

	-- Stop existing pulse if any
	if pulseTweens[frameName] then
		task.cancel(pulseTweens[frameName])
		pulseTweens[frameName] = nil
	end

	-- Pulse loop: scale up/down + transparency blink
	pulseTweens[frameName] = task.spawn(function()
		-- Ensure UIScale exists
		local uiScale = notif:FindFirstChildOfClass("UIScale")
		if not uiScale then
			uiScale = Instance.new("UIScale")
			uiScale.Scale = 1
			uiScale.Parent = notif
		end

		while activeBadges[frameName] do
			-- Pulse out
			local tweenOut = TweenService:Create(uiScale,
				TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Scale = 1.4 }
			)
			local fadeOut = TweenService:Create(notif,
				TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ BackgroundTransparency = 0.3 }
			)
			tweenOut:Play()
			fadeOut:Play()
			tweenOut.Completed:Wait()

			if not activeBadges[frameName] then break end

			-- Pulse in
			local tweenIn = TweenService:Create(uiScale,
				TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Scale = 0.8 }
			)
			local fadeIn = TweenService:Create(notif,
				TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ BackgroundTransparency = 0 }
			)
			tweenIn:Play()
			fadeIn:Play()
			tweenIn.Completed:Wait()
		end
	end)
end

-- Stop pulsing and hide a Notif frame
local function StopPulse(frameName: string)
	if not activeBadges[frameName] then return end
	activeBadges[frameName] = false

	if pulseTweens[frameName] then
		task.cancel(pulseTweens[frameName])
		pulseTweens[frameName] = nil
	end

	local notif = GetNotif(frameName)
	if notif then
		notif.Visible = false
		local uiScale = notif:FindFirstChildOfClass("UIScale")
		if uiScale then
			uiScale.Scale = 1
		end
		notif.BackgroundTransparency = 0
	end
end

-- Wire up click-to-dismiss on each nav button
local function WireClickDismiss(frameName: string)
	local frame = navFrame:FindFirstChild(frameName)
	if not frame then return end

	local btn = frame:FindFirstChildWhichIsA("ImageButton") or frame:FindFirstChildWhichIsA("TextButton")
	if not btn then return end

	btn.MouseButton1Click:Connect(function()
		StopPulse(frameName)
	end)
end

-- Nav frame names to watch
local NAV_FRAMES = { "QuestsFrame", "SkinsFrame", "SpinFrame", "DailyFrame" }

-- Wire up dismiss on all nav buttons
for _, frameName in ipairs(NAV_FRAMES) do
	WireClickDismiss(frameName)
end

-- Hide all notifs initially
for _, frameName in ipairs(NAV_FRAMES) do
	local notif = GetNotif(frameName)
	if notif then
		notif.Visible = false
	end
end

-- ============================================================
-- QUEST NOTIFICATIONS
-- Pulse QuestsFrame badge when any quest becomes claimable
-- ============================================================
if SyncQuests then
	SyncQuests.OnClientEvent:Connect(function(data: any?)
		if not data then return end

		-- Check if any quest is complete but not claimed
		local hasClaimable = false

		if data.dailyQuests then
			for _, quest in ipairs(data.dailyQuests) do
				if not quest.claimed and (quest.progress or 0) >= (quest.goal or 1) then
					hasClaimable = true
					break
				end
			end
		end

		if not hasClaimable and data.weeklyQuests then
			for _, quest in ipairs(data.weeklyQuests) do
				if not quest.claimed and (quest.progress or 0) >= (quest.goal or 1) then
					hasClaimable = true
					break
				end
			end
		end

		if hasClaimable then
			StartPulse("QuestsFrame")
		else
			StopPulse("QuestsFrame")
		end

		prevQuestData = data
	end)
end

-- ============================================================
-- INVENTORY NOTIFICATIONS
-- Pulse SkinsFrame badge when new items are acquired
-- ============================================================
if SyncInventory then
	SyncInventory.OnClientEvent:Connect(function(inv: any?)
		if not inv then return end

		-- Count total owned items
		local totalOwned = 0
		if inv.ownedSkins then totalOwned = totalOwned + #inv.ownedSkins end
		if inv.ownedDances then totalOwned = totalOwned + #inv.ownedDances end
		if inv.ownedTitles then totalOwned = totalOwned + #inv.ownedTitles end
		if inv.ownedExplosions then totalOwned = totalOwned + #inv.ownedExplosions end

		-- If we had a previous count and it increased, show notification
		if prevInventoryOwned ~= nil and totalOwned > prevInventoryOwned then
			StartPulse("SkinsFrame")
		end

		prevInventoryOwned = totalOwned
	end)
end

print("[NavNotifications] Notification badges initialized")
