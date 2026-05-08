--!strict
-- RoundStartCloser.client.lua
-- Closes all popup UIs when the round starts (player teleported to map)
-- Each UI exposes a "ForceClose" BindableEvent for instant dismissal

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged")

-- All popup UIs that should be force-closed when round starts
local POPUP_UI_NAMES = {
	"StoreUI",
	"InventoryUI",
	"QuestsUI",
	"DailyRewardsUI",
	"SpinUI",
	"CapsuleUI",
	"ConfigUI",
}

-- Fire the ForceClose BindableEvent on a ScreenGui if it exists
local function ForceCloseUI(guiName: string)
	local gui = playerGui:FindFirstChild(guiName)
	if not gui then return end

	local forceClose = gui:FindFirstChild("ForceClose")
	if forceClose and forceClose:IsA("BindableEvent") then
		forceClose:Fire()
	end
end

-- Listen for round start (Preparing = players about to be teleported to map)
RoundStateChanged.OnClientEvent:Connect(function(state: string, _data: any?)
	if state == "Preparing" then
		for _, guiName in ipairs(POPUP_UI_NAMES) do
			ForceCloseUI(guiName)
		end
	end
end)

print("[RoundStartCloser] Listening for round start")
