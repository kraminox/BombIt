--!strict
-- SideNavBar.client.lua
-- Handles 2x Luck (dev product prompt) and Invite buttons

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local SocialService = game:GetService("SocialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local Constants = require(Shared:WaitForChild("Constants"))

-- Sound effects
local SoundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
local UISounds = SoundsFolder and SoundsFolder:FindFirstChild("UI")
local clickSound: Sound? = UISounds and UISounds:FindFirstChild("Click") :: Sound? or nil
local hoverSound: Sound? = UISounds and UISounds:FindFirstChild("Hover") :: Sound? or nil
local achieveSound: Sound? = UISounds and UISounds:FindFirstChild("Achieve") :: Sound? or nil

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LuckBoostActivated = Remotes:WaitForChild("LuckBoostActivated", 15)
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged")

-- Wait for SideNavBar UI
local sideNavBar = playerGui:WaitForChild("SideNavBar") :: ScreenGui
local parentFrame = sideNavBar:WaitForChild("ParentFrame") :: Frame
local navFrame = parentFrame:WaitForChild("NavFrame") :: Frame

local luckFrame = navFrame:FindFirstChild("2xLuckFrame") :: Frame?
local inviteFrame = navFrame:FindFirstChild("InviteFrame") :: Frame?
local freeSkinFrame = navFrame:FindFirstChild("FreeSkinFrame") :: Frame?

-- State
local luckBoostActive = false
local luckBoostEndTime = 0
local luckTimerLabel: TextLabel? = nil

-- Helper: play tween
local function PlayTween(instance: Instance, info: TweenInfo, props: {[string]: any}): Tween
	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

-- Wire up a nav button with hover/click effects
local function WireButton(frame: Frame?, onClick: () -> ())
	if not frame then return end

	local imageBtn = frame:FindFirstChildWhichIsA("ImageButton")
	if not imageBtn then return end

	local textLabel = frame:FindFirstChildWhichIsA("TextLabel")
	local originalBtnSize = imageBtn.Size
	local hoverBtnSize = UDim2.new(
		originalBtnSize.X.Scale * 1.12, originalBtnSize.X.Offset * 1.12,
		originalBtnSize.Y.Scale * 1.12, originalBtnSize.Y.Offset * 1.12
	)
	local originalTextColor = textLabel and textLabel.TextColor3 or Color3.new(1, 1, 1)
	local hoverTextColor = Color3.fromRGB(255, 240, 130)

	imageBtn.MouseEnter:Connect(function()
		if hoverSound then hoverSound:Play() end
		PlayTween(imageBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = hoverBtnSize,
		})
		if textLabel then
			PlayTween(textLabel, TweenInfo.new(0.12), {
				TextColor3 = hoverTextColor,
			})
		end
	end)

	imageBtn.MouseLeave:Connect(function()
		PlayTween(imageBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = originalBtnSize,
		})
		if textLabel then
			PlayTween(textLabel, TweenInfo.new(0.12), {
				TextColor3 = originalTextColor,
			})
		end
	end)

	imageBtn.MouseButton1Click:Connect(function()
		-- Click pulse
		PlayTween(imageBtn, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(
				originalBtnSize.X.Scale * 0.88, originalBtnSize.X.Offset * 0.88,
				originalBtnSize.Y.Scale * 0.88, originalBtnSize.Y.Offset * 0.88
			),
		}).Completed:Connect(function()
			PlayTween(imageBtn, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = originalBtnSize,
			})
		end)

		onClick()
	end)
end

-- ============================================================
-- 2x LUCK BUTTON
-- ============================================================
WireButton(luckFrame, function()
	if luckBoostActive then return end
	if clickSound then clickSound:Play() end
	MarketplaceService:PromptProductPurchase(player, Economy.DEV_PRODUCT_2X_LUCK)
end)

-- Listen for luck boost activation from server
if LuckBoostActivated then
	(LuckBoostActivated :: RemoteEvent).OnClientEvent:Connect(function(duration: number)
		luckBoostActive = true
		luckBoostEndTime = tick() + duration

		if achieveSound then achieveSound:Play() end

		-- Show timer on the text label
		if luckFrame then
			luckTimerLabel = luckFrame:FindFirstChildWhichIsA("TextLabel")
		end

		-- Update timer display
		task.spawn(function()
			while luckBoostActive and tick() < luckBoostEndTime do
				local remaining = math.max(0, math.ceil(luckBoostEndTime - tick()))
				local mins = math.floor(remaining / 60)
				local secs = remaining % 60
				if luckTimerLabel then
					luckTimerLabel.Text = string.format("%d:%02d", mins, secs)
				end
				task.wait(1)
			end

			-- Boost expired
			luckBoostActive = false
			if luckTimerLabel then
				luckTimerLabel.Text = "2x Luck"
			end
		end)
	end)
end

-- ============================================================
-- INVITE BUTTON
-- ============================================================
WireButton(inviteFrame, function()
	if clickSound then clickSound:Play() end
	pcall(function()
		SocialService:PromptGameInvite(player)
	end)
end)

-- ============================================================
-- HIDE DURING GAMEPLAY
-- ============================================================
local HIDE_STATES = {
	[Constants.STATES.PREPARING or "Preparing"] = true,
	[Constants.STATES.COUNTDOWN or "Countdown"] = true,
	[Constants.STATES.PLAYING or "Playing"] = true,
	["Preparing"] = true,
	["Countdown"] = true,
	["Playing"] = true,
	["RoundResults"] = true,
}

RoundStateChanged.OnClientEvent:Connect(function(state: string)
	if HIDE_STATES[state] then
		sideNavBar.Enabled = false
	else
		sideNavBar.Enabled = true
	end
end)

-- ============================================================
-- FREE SKIN TIMER + CLAIM
-- ============================================================
if freeSkinFrame then
	local ClaimFreeSkin = Remotes:WaitForChild("ClaimFreeSkin", 15) :: RemoteFunction?
	local GetFreeSkinStatus = Remotes:WaitForChild("GetFreeSkinStatus", 15) :: RemoteFunction?

	-- Check if already claimed
	local alreadyClaimed = false
	if GetFreeSkinStatus then
		local ok, result = pcall(function()
			return GetFreeSkinStatus:InvokeServer()
		end)
		if ok and result == true then
			alreadyClaimed = true
		end
	end

	if alreadyClaimed then
		freeSkinFrame.Visible = false
	else
		freeSkinFrame.Visible = true

		local timerLabel = freeSkinFrame:FindFirstChild("Timer") :: TextLabel?
		local label = freeSkinFrame:FindFirstChild("Label") :: TextLabel?
		local imageBtn = freeSkinFrame:FindFirstChildWhichIsA("ImageButton")

		local FREE_SKIN_DURATION = 10 * 60 -- 10 minutes in seconds
		local startTime = tick()
		local canClaim = false

		-- Timer countdown
		task.spawn(function()
			while not canClaim and not alreadyClaimed do
				local elapsed = tick() - startTime
				local remaining = math.max(0, FREE_SKIN_DURATION - elapsed)

				if remaining <= 0 then
					canClaim = true
					if timerLabel then
						timerLabel.Text = "CLAIM!"
					end
					break
				end

				local mins = math.floor(remaining / 60)
				local secs = math.floor(remaining % 60)
				if timerLabel then
					timerLabel.Text = string.format("%02d:%02d", mins, secs)
				end
				task.wait(1)
			end
		end)

		-- Click handler
		if imageBtn then
			imageBtn.MouseButton1Click:Connect(function()
				if alreadyClaimed then return end
				if not canClaim then return end
				if not ClaimFreeSkin then return end

				if clickSound then clickSound:Play() end

				local ok, result = pcall(function()
					return ClaimFreeSkin:InvokeServer()
				end)

				if ok and result == true then
					alreadyClaimed = true
					if achieveSound then achieveSound:Play() end
					-- Flash the label briefly then hide
					if label then
						label.Text = "CLAIMED!"
					end
					if timerLabel then
						timerLabel.Text = ""
					end
					task.delay(1.5, function()
						freeSkinFrame.Visible = false
					end)
				end
			end)
		end
	end
end

print("[SideNavBar] Initialized")
