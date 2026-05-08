--!strict
-- ServerAnnouncements.client.lua
-- Displays server chat announcements with colored rich text

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ServerAnnouncement = Remotes:WaitForChild("ServerAnnouncement", 15)

-- ============================================================
-- RICH TEXT HELPERS
-- ============================================================

-- Interpolate between two Color3 values
local function LerpColor(c1: Color3, c2: Color3, t: number): Color3
	return Color3.new(
		c1.R + (c2.R - c1.R) * t,
		c1.G + (c2.G - c1.G) * t,
		c1.B + (c2.B - c1.B) * t
	)
end

-- Color a single string with a solid color
local function ColorText(text: string, color: Color3): string
	local r = math.floor(color.R * 255)
	local g = math.floor(color.G * 255)
	local b = math.floor(color.B * 255)
	return string.format('<font color="rgb(%d,%d,%d)">%s</font>', r, g, b, text)
end

-- Apply a two-color gradient across each character of text
local function GradientText(text: string, color1: Color3, color2: Color3): string
	local result = ""
	local len = utf8.len(text) or #text
	local i = 0
	for _, codepoint in utf8.codes(text) do
		local char = utf8.char(codepoint)
		local t = if len > 1 then i / (len - 1) else 0
		local color = LerpColor(color1, color2, t)
		result = result .. ColorText(char, color)
		i += 1
	end
	return result
end

-- Apply a cycling wave gradient (green -> cyan -> green) across characters
local function WaveGradientText(text: string, color1: Color3, color2: Color3, offset: number?): string
	local result = ""
	local len = utf8.len(text) or #text
	local off = offset or 0
	local i = 0
	for _, codepoint in utf8.codes(text) do
		local char = utf8.char(codepoint)
		-- Sine wave creates smooth cycling between the two colors
		local t = (math.sin((i / math.max(len - 1, 1)) * math.pi * 2 + off) + 1) / 2
		local color = LerpColor(color1, color2, t)
		result = result .. ColorText(char, color)
		i += 1
	end
	return result
end

-- Bold wrapper
local function Bold(text: string): string
	return "<b>" .. text .. "</b>"
end

-- ============================================================
-- COLORS
-- ============================================================
local GREEN = Color3.fromRGB(85, 255, 127)
local CYAN = Color3.fromRGB(85, 255, 255)
local GOLD = Color3.fromRGB(255, 215, 50)
local DARK_GOLD = Color3.fromRGB(200, 160, 30)
local LIGHT_GREEN = Color3.fromRGB(120, 255, 160)
local SOFT_YELLOW = Color3.fromRGB(255, 255, 150)
local GRAY = Color3.fromRGB(180, 180, 180)

-- ============================================================
-- DISPLAY MESSAGE IN CHAT
-- ============================================================
local systemChannel: any = nil

local function GetSystemChannel(): any
	if systemChannel then return systemChannel end
	local channels = TextChatService:FindFirstChild("TextChannels")
	if channels then
		systemChannel = channels:FindFirstChild("RBXSystem")
	end
	return systemChannel
end

local function DisplayMessage(richText: string)
	local channel = GetSystemChannel()
	if channel then
		pcall(function()
			channel:DisplaySystemMessage(richText)
		end)
	end
end

-- ============================================================
-- FORMAT ANNOUNCEMENT TYPES
-- ============================================================

local function FormatReminder(data: any): string
	local reminderType = data.type or "code"

	if reminderType == "code" then
		return Bold(ColorText("[SERVER] ", GREEN) .. ColorText(data.text, LIGHT_GREEN))
	elseif reminderType == "social" then
		return Bold(ColorText("[SERVER] ", CYAN) .. GradientText(data.text, CYAN, GREEN))
	elseif reminderType == "beta" then
		return Bold(ColorText("[SERVER] ", SOFT_YELLOW) .. ColorText(data.text, GRAY))
	end

	return Bold(ColorText("[SERVER] " .. data.text, GREEN))
end

local function FormatPurchaseLuck(data: any): string
	local name = data.playerName or "Someone"
	local msg = name .. " just bought 2x Server Luck! Open Some Capsules!"
	-- Green-cyan wave gradient
	return Bold(WaveGradientText(msg, GREEN, CYAN, 0))
end

local function FormatLegendaryDrop(data: any): string
	local name = data.playerName or "Someone"
	local itemName = data.itemName or "Legendary Item"
	return Bold(
		ColorText(name, GOLD)
		.. ColorText(" just got a ", SOFT_YELLOW)
		.. GradientText(itemName, GOLD, DARK_GOLD)
		.. ColorText("!", SOFT_YELLOW)
	)
end

local function FormatPurchaseLegendary(data: any): string
	local name = data.playerName or "Someone"
	local count = data.count or 1
	return Bold(GradientText(
		name .. " just bought " .. tostring(count) .. " Legendary Capsule" .. (if count > 1 then "s" else "") .. "!",
		GOLD, DARK_GOLD
	))
end

local function FormatPurchaseVIP(data: any): string
	local name = data.playerName or "Someone"
	return Bold(GradientText(name .. " just bought VIP!", GOLD, DARK_GOLD))
end

-- ============================================================
-- ANIMATED LUCK MESSAGE (send multiple shifted gradients)
-- ============================================================
local function DisplayAnimatedLuck(data: any)
	local name = (data.playerName or "Someone")
	local msg = name .. " just bought 2x Server Luck! Open Some Capsules!"
	local richText = Bold(WaveGradientText(msg, GREEN, CYAN, 0))
	DisplayMessage(richText)
end

-- ============================================================
-- LISTEN FOR SERVER ANNOUNCEMENTS
-- ============================================================
if ServerAnnouncement then
	(ServerAnnouncement :: RemoteEvent).OnClientEvent:Connect(function(announcementType: string, data: any)
		if announcementType == "reminder" then
			DisplayMessage(FormatReminder(data))

		elseif announcementType == "purchase_luck" then
			DisplayAnimatedLuck(data)

		elseif announcementType == "legendary_drop" then
			DisplayMessage(FormatLegendaryDrop(data))

		elseif announcementType == "purchase_legendary" then
			DisplayMessage(FormatPurchaseLegendary(data))

		elseif announcementType == "purchase_vip" then
			DisplayMessage(FormatPurchaseVIP(data))
		end
	end)
end

print("[ServerAnnouncements] Listening for announcements")
