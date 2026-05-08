--!strict
-- GroupChest.client.lua
-- When player touches GroupChest > RewardInteract, prompt to join group.
-- If already in group, request server to grant rewards (1000 coins + Legendary capsule).

local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestGroupReward = Remotes:WaitForChild("RequestGroupReward") :: RemoteFunction

-- Sound effects
local SoundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
local UISounds = SoundsFolder and SoundsFolder:FindFirstChild("UI")
local achieveSound: Sound? = UISounds and UISounds:FindFirstChild("Achieve") :: Sound? or nil
local failSound: Sound? = UISounds and UISounds:FindFirstChild("Fail") :: Sound? or nil

-- Group ID
local GROUP_ID = 511584075

-- Cooldown to prevent spam
local isCooldown = false

-- Find GroupChest > RewardInteract in workspace
local function FindRewardInteract(): BasePart?
	for attempt = 1, 10 do
		local groupChest = workspace:FindFirstChild("GroupChest", true)
		if groupChest then
			local ri = groupChest:FindFirstChild("RewardInteract")
			if ri and ri:IsA("BasePart") then
				return ri
			end
		end
		task.wait(1)
	end
	return nil
end

local function SendNotification(title: string, text: string)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = title,
			Text = text,
			Duration = 4,
		})
	end)
end

local function OnTouched(hit: BasePart)
	local character = player.Character
	if not character then return end
	if not hit:IsDescendantOf(character) then return end
	if isCooldown then return end

	isCooldown = true

	-- Request server to check group membership and grant rewards
	local result = RequestGroupReward:InvokeServer()

	if result then
		if result.status == "success" then
			if achieveSound then achieveSound:Play() end
			SendNotification("Group Reward!", "You received $1,000 and a Legendary Capsule!")
		elseif result.status == "already_claimed" then
			if failSound then failSound:Play() end
			SendNotification("Already Claimed", "You already collected the group reward!")
		elseif result.status == "not_in_group" then
			if failSound then failSound:Play() end
			-- Prompt the native Roblox group join dialog
			pcall(function()
				GroupService:PromptJoinAsync(player, GROUP_ID)
			end)
			SendNotification("Join Our Group!", "Join the group to claim $1,000 and a Legendary Capsule!")
		end
	end

	task.wait(2)
	isCooldown = false
end

-- Initialize
task.spawn(function()
	local rewardInteract = FindRewardInteract()
	if not rewardInteract then
		warn("[GroupChest] RewardInteract not found")
		return
	end

	print("[GroupChest] RewardInteract found, connecting touch event")
	rewardInteract.Touched:Connect(OnTouched)
end)
