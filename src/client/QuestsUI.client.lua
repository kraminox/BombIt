--!strict
-- QuestsUI.client.lua
-- Wires up the existing QuestsUI ScreenGui with quest data from QuestService
-- Uses the card template already in QuestsFrame to display daily/weekly quests

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Sound effects
local SoundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
local UISounds = SoundsFolder and SoundsFolder:FindFirstChild("UI")
local clickSound: Sound? = UISounds and UISounds:FindFirstChild("Click") :: Sound? or nil
local uiOpenSound: Sound? = UISounds and UISounds:FindFirstChild("UIOpen") :: Sound? or nil
local achieveSound: Sound? = UISounds and UISounds:FindFirstChild("Achieve") :: Sound? or nil
local cheersSound: Sound? = UISounds and UISounds:FindFirstChild("Cheers") :: Sound? or nil
local hoverSound: Sound? = UISounds and UISounds:FindFirstChild("Hover") :: Sound? or nil

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SyncQuests = Remotes:WaitForChild("SyncQuests", 15)
local ClaimQuest = Remotes:WaitForChild("ClaimQuest", 15)

-- Wait for existing QuestsUI ScreenGui (placed in StarterGui, cloned to PlayerGui)
local questsGui = playerGui:WaitForChild("QuestsUI") :: ScreenGui
local parentFrame = questsGui:WaitForChild("ParentFrame") :: Frame
local topFrame = parentFrame:WaitForChild("TopFrame") :: Frame
local questsFrame = parentFrame:WaitForChild("QuestsFrame") :: Frame
local resetTimerLabel = parentFrame:FindFirstChild("ResetTimer") :: TextLabel?

-- TopFrame buttons
local closeBtn = topFrame:FindFirstChild("CloseBtn")
local dailyBtn = topFrame:FindFirstChild("DailyBtn")
local weeklyBtn = topFrame:FindFirstChild("WeeklyBtn")

-- State
local isOpen = false
local isAnimating = false
local blurEffect: BlurEffect? = nil
local questData: any = nil
local currentTab = "daily"
local activeCards: {Instance} = {}

-- Helper: play tween
local function PlayTween(instance: Instance, info: TweenInfo, props: {[string]: any}): Tween
	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

-- ============================================================
-- CONFETTI EFFECT (ported from DailyRewards)
-- ============================================================
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 85, 85),
	Color3.fromRGB(85, 255, 85),
	Color3.fromRGB(85, 170, 255),
	Color3.fromRGB(255, 255, 85),
	Color3.fromRGB(255, 85, 255),
	Color3.fromRGB(85, 255, 255),
	Color3.fromRGB(255, 170, 50),
	Color3.fromRGB(180, 85, 255),
}

local function SpawnConfetti(origin: GuiObject)
	local centerX = origin.AbsolutePosition.X + origin.AbsoluteSize.X / 2
	local centerY = origin.AbsolutePosition.Y + origin.AbsoluteSize.Y / 2
	local numParticles = 24

	for i = 1, numParticles do
		local confetti = Instance.new("Frame")
		confetti.Name = "Confetti"
		confetti.BackgroundColor3 = CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)]
		confetti.BorderSizePixel = 0
		confetti.AnchorPoint = Vector2.new(0.5, 0.5)
		confetti.Size = UDim2.fromOffset(math.random(4, 8), math.random(10, 16))
		confetti.Position = UDim2.fromOffset(centerX, centerY)
		confetti.Rotation = math.random(0, 360)
		confetti.ZIndex = 100
		confetti.Parent = questsGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 2)
		corner.Parent = confetti

		local angle = (i / numParticles) * math.pi * 2 + (math.random() - 0.5)
		local dist = math.random(80, 200)
		local targetX = centerX + math.cos(angle) * dist
		local targetY = centerY + math.sin(angle) * dist - math.random(30, 80)

		PlayTween(confetti, TweenInfo.new(
			0.6 + math.random() * 0.4,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		), {
			Position = UDim2.fromOffset(targetX, targetY),
			Rotation = math.random(-720, 720),
			BackgroundTransparency = 0.9,
			Size = UDim2.fromOffset(math.random(2, 4), math.random(4, 8)),
		})

		task.delay(1.3, function()
			confetti:Destroy()
		end)
	end
end

-- ============================================================
-- REWARD ANNOUNCE (shows banner in NavHUD)
-- ============================================================
local function AnnounceQuestReward(coinsAmount: number?)
	local navHUD = playerGui:FindFirstChild("NavHUD")
	if not navHUD then return end

	local rewardAnnounce = navHUD:FindFirstChild("RewardAnnounce") :: TextLabel?
	if not rewardAnnounce then return end

	rewardAnnounce.RichText = true
	if coinsAmount and coinsAmount > 0 then
		rewardAnnounce.Text = 'Quest Complete: <font color="#FFD700">+' .. tostring(coinsAmount) .. ' Coins!</font>'
	else
		rewardAnnounce.Text = '<font color="#FFD700">Quest Complete!</font>'
	end
	rewardAnnounce.Visible = true
	rewardAnnounce.TextTransparency = 0

	local origStrokeTransparency = rewardAnnounce.TextStrokeTransparency
	task.delay(3, function()
		local tween = PlayTween(rewardAnnounce, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		tween.Completed:Wait()
		rewardAnnounce.Visible = false
		rewardAnnounce.TextTransparency = 0
		rewardAnnounce.TextStrokeTransparency = origStrokeTransparency
	end)
end

-- ============================================================
-- MONEY LABEL UPDATE HELPER
-- ============================================================
local function UpdateMoneyLabel()
	local pStats = player:FindFirstChild("PersistentStats")
	if not pStats then return end
	local coinsVal = pStats:FindFirstChild("TotalCoins") :: IntValue?
	if not coinsVal then return end

	local navHUD = playerGui:FindFirstChild("NavHUD")
	if not navHUD then return end
	local navParent = navHUD:FindFirstChild("ParentFrame")
	if not navParent then return end
	local moneyLabel = navParent:FindFirstChild("MoneyLabel", true) :: TextLabel?
	if moneyLabel then
		moneyLabel.Text = tostring(coinsVal.Value)
	end
end

-- Find card template (named QuestTemplate in the existing UI)
local templateInstance = questsFrame:FindFirstChild("QuestTemplate")
if not templateInstance then
	-- Fallback: first Frame child
	for _, child in ipairs(questsFrame:GetChildren()) do
		if child:IsA("Frame") then
			templateInstance = child
			break
		end
	end
end

if not templateInstance then
	warn("[QuestsUI] No card template found in QuestsFrame")
	return
end

local cardTemplate = templateInstance:Clone() :: Frame
templateInstance:Destroy()

-- Ensure UIScale exists on parentFrame for animations
local function EnsureUIScale(): UIScale
	local scale = parentFrame:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Scale = 0
		scale.Parent = parentFrame
	end
	return scale :: UIScale
end

-- Clear active quest cards
local function ClearCards()
	for _, card in ipairs(activeCards) do
		if card and card.Parent then
			card:Destroy()
		end
	end
	activeCards = {}
end

-- Create a quest card from template
local function CreateCard(quest: any, layoutOrder: number): Frame
	local card = cardTemplate:Clone()
	card.Name = "Quest_" .. (quest.id or "unknown")
	card.LayoutOrder = layoutOrder
	card.Visible = true

	local isComplete = (quest.progress or 0) >= (quest.goal or 1)
	local isClaimed = quest.claimed == true
	local progress = math.clamp((quest.progress or 0) / math.max(quest.goal or 1, 1), 0, 1)

	-- Quest description
	local questLabel = card:FindFirstChild("QuestLabel") :: TextLabel?
	if questLabel and questLabel:IsA("TextLabel") then
		questLabel.Text = quest.description or "Unknown Quest"
	end

	-- Progress bar (ProgressBar > Frame [fill] + ProgressText)
	local progressBar = card:FindFirstChild("ProgressBar") :: Frame?
	if progressBar then
		-- Fill bar: the child Frame inside ProgressBar (not a layout/corner/etc)
		for _, child in ipairs(progressBar:GetChildren()) do
			if child:IsA("Frame") then
				child.Size = UDim2.new(progress, 0, child.Size.Y.Scale, child.Size.Y.Offset)
				break
			end
		end
		-- Progress text
		local progressText = progressBar:FindFirstChild("ProgressText") :: TextLabel?
		if progressText and progressText:IsA("TextLabel") then
			progressText.Text = tostring(math.min(quest.progress or 0, quest.goal)) .. "/" .. tostring(quest.goal)
		end
	end

	-- Reward display (RewardFrame > CapsuleImage, CoinsImage, SpinImage, AmountLabel)
	local rewardFrame = card:FindFirstChild("RewardFrame") :: Frame?
	if rewardFrame then
		local capsuleImage = rewardFrame:FindFirstChild("CapsuleImage")
		local coinsImage = rewardFrame:FindFirstChild("CoinsImage")
		local spinImage = rewardFrame:FindFirstChild("SpinImage")
		local amountLabel = rewardFrame:FindFirstChild("AmountLabel") :: TextLabel?

		if quest.reward then
			local hasCapsule = quest.reward.capsule ~= nil
			local hasCoins = quest.reward.coins ~= nil

			-- Show the correct reward icon (coins take priority when both exist)
			if coinsImage then coinsImage.Visible = hasCoins end
			if capsuleImage then capsuleImage.Visible = hasCapsule and not hasCoins end
			if spinImage then spinImage.Visible = false end

			-- Set amount text
			if amountLabel and amountLabel:IsA("TextLabel") then
				if hasCoins then
					amountLabel.Text = "+" .. tostring(quest.reward.coins)
				elseif hasCapsule then
					amountLabel.Text = quest.reward.capsule
				end
			end
		end
	end

	-- Claim button (ClaimBtn > ClaimLabel + Darken [lock overlay])
	local claimBtn = card:FindFirstChild("ClaimBtn")
	if claimBtn then
		local claimLabel = claimBtn:FindFirstChild("ClaimLabel") :: TextLabel?
		local darken = claimBtn:FindFirstChild("Darken")

		if isClaimed then
			-- Already claimed: show "Claimed", no lock
			if claimLabel then claimLabel.Text = "Claimed" end
			if darken then darken.Visible = false end
		elseif isComplete then
			-- Ready to claim: show "Claim!", no lock
			if claimLabel then claimLabel.Text = "Claim!" end
			if darken then darken.Visible = false end

			if claimBtn:IsA("TextButton") or claimBtn:IsA("ImageButton") then
				(claimBtn :: GuiButton).MouseButton1Click:Connect(function()
					if clickSound then clickSound:Play() end
					if ClaimQuest then
						local result = ClaimQuest:InvokeServer(quest.id)
						if result and result.success then
							if achieveSound then achieveSound:Play() end
							if cheersSound then cheersSound:Play() end

							-- Confetti burst from the claim button
							SpawnConfetti(claimBtn :: GuiObject)

							-- Show reward announce
							local rewardCoins = quest.reward and quest.reward.coins
							AnnounceQuestReward(rewardCoins)

							-- Update MoneyLabel from PersistentStats
							task.delay(0.2, UpdateMoneyLabel)
						end
					end
				end)
			end
		else
			-- Not complete: show lock overlay
			if claimLabel then claimLabel.Text = "Claim!" end
			if darken then darken.Visible = true end
		end
	end

	card.Parent = questsFrame
	table.insert(activeCards, card)
	return card
end

-- Populate quests for current tab
local function PopulateQuests()
	ClearCards()
	if not questData then return end

	local quests = if currentTab == "daily" then questData.dailyQuests else questData.weeklyQuests
	if not quests then return end

	for i, quest in ipairs(quests) do
		CreateCard(quest, i)
	end
end

-- Update reset timer countdown
local function UpdateResetTimer()
	if not resetTimerLabel then return end

	local now = os.time()
	local utcDate = os.date("!*t", now) :: any

	local secondsLeft: number
	if currentTab == "daily" then
		-- Time until midnight UTC
		secondsLeft = (24 - utcDate.hour) * 3600 - utcDate.min * 60 - utcDate.sec
	else
		-- Time until next Monday midnight UTC
		local wday = utcDate.wday :: number
		local daysUntilMonday = (9 - wday) % 7
		if daysUntilMonday == 0 then daysUntilMonday = 7 end
		secondsLeft = daysUntilMonday * 86400 - utcDate.hour * 3600 - utcDate.min * 60 - utcDate.sec
	end

	local hours = math.floor(secondsLeft / 3600)
	local mins = math.floor((secondsLeft % 3600) / 60)
	local secs = secondsLeft % 60
	resetTimerLabel.Text = string.format("Resets in %d:%02d:%02d", hours, mins, secs)
end

-- Tab switching
local function SetTab(tab: string)
	currentTab = tab
	PopulateQuests()
	UpdateResetTimer()
end

-- Open UI
-- Close other popups (mutual exclusion)
local POPUP_GUIS = {"StoreUI", "InventoryUI", "QuestsUI", "DailyRewardsUI", "SpinUI", "CapsuleUI", "ConfigUI"}

local function CloseOtherPopups()
	for _, guiName in ipairs(POPUP_GUIS) do
		if guiName ~= "QuestsUI" then
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

	if uiOpenSound then uiOpenSound:Play() end

	SetTab(currentTab)
	questsGui.Enabled = true
	parentFrame.Visible = true

	blurEffect = Instance.new("BlurEffect")
	blurEffect.Size = 0
	blurEffect.Parent = Lighting
	PlayTween(blurEffect, TweenInfo.new(0.3), { Size = 10 })

	local scale = EnsureUIScale()
	scale.Scale = 0
	local tween = PlayTween(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	})
	tween.Completed:Wait()

	isOpen = true
	isAnimating = false
end

-- Close UI
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

	tween.Completed:Wait()

	parentFrame.Visible = false
	questsGui.Enabled = false

	if blurEffect then
		blurEffect:Destroy()
		blurEffect = nil
	end

	isOpen = false
	isAnimating = false
end

-- Wire up TopFrame buttons
if closeBtn and (closeBtn:IsA("TextButton") or closeBtn:IsA("ImageButton")) then
	closeBtn.MouseButton1Click:Connect(function()
		CloseUI()
	end)
end

if dailyBtn and (dailyBtn:IsA("TextButton") or dailyBtn:IsA("ImageButton")) then
	dailyBtn.MouseButton1Click:Connect(function()
		if clickSound then clickSound:Play() end
		SetTab("daily")
	end)
end

if weeklyBtn and (weeklyBtn:IsA("TextButton") or weeklyBtn:IsA("ImageButton")) then
	weeklyBtn.MouseButton1Click:Connect(function()
		if clickSound then clickSound:Play() end
		SetTab("weekly")
	end)
end

-- Listen for quest data sync from server
if SyncQuests then
	SyncQuests.OnClientEvent:Connect(function(data: any?)
		if data then
			questData = data
			if isOpen then
				PopulateQuests()
			end
		end
	end)
end

-- Reset timer loop (only does work when UI is visible)
task.spawn(function()
	while true do
		if not questsFrame or not questsFrame.Visible then task.wait(5) continue end
		if isOpen then
			UpdateResetTimer()
		end
		task.wait(1)
	end
end)

-- Initialize: start hidden
questsGui.Enabled = false
parentFrame.Visible = false

-- NavHUD QuestsFrame integration
task.spawn(function()
	local navHUD = playerGui:WaitForChild("NavHUD", 15)
	if not navHUD then return end

	local navParent = navHUD:FindFirstChild("ParentFrame")
	if not navParent then return end

	local navFrame = navParent:FindFirstChild("NavFrame")
	if not navFrame then return end

	local navQuestsFrame = navFrame:FindFirstChild("QuestsFrame")
	if not navQuestsFrame then return end

	local questsImageBtn = navQuestsFrame:FindFirstChildWhichIsA("ImageButton")
	local questsTextLabel = navQuestsFrame:FindFirstChildWhichIsA("TextLabel")

	if not questsImageBtn then return end

	-- Hover effect
	local originalBtnSize = questsImageBtn.Size
	local hoverBtnSize = UDim2.new(
		originalBtnSize.X.Scale * 1.12, originalBtnSize.X.Offset * 1.12,
		originalBtnSize.Y.Scale * 1.12, originalBtnSize.Y.Offset * 1.12
	)
	local originalTextColor = questsTextLabel and questsTextLabel.TextColor3 or Color3.new(1, 1, 1)
	local hoverTextColor = Color3.fromRGB(255, 240, 130)

	questsImageBtn.MouseEnter:Connect(function()
		if hoverSound then hoverSound:Play() end
		PlayTween(questsImageBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = hoverBtnSize,
		})
		if questsTextLabel then
			PlayTween(questsTextLabel, TweenInfo.new(0.12), {
				TextColor3 = hoverTextColor,
			})
		end
	end)

	questsImageBtn.MouseLeave:Connect(function()
		PlayTween(questsImageBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = originalBtnSize,
		})
		if questsTextLabel then
			PlayTween(questsTextLabel, TweenInfo.new(0.12), {
				TextColor3 = originalTextColor,
			})
		end
	end)

	questsImageBtn.MouseButton1Click:Connect(function()
		-- Click pulse
		PlayTween(questsImageBtn, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(
				originalBtnSize.X.Scale * 0.88, originalBtnSize.X.Offset * 0.88,
				originalBtnSize.Y.Scale * 0.88, originalBtnSize.Y.Offset * 0.88
			),
		}).Completed:Connect(function()
			PlayTween(questsImageBtn, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
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

-- Expose open for other scripts
local openEvent = Instance.new("BindableEvent")
openEvent.Name = "OpenQuests"
openEvent.Parent = questsGui
openEvent.Event:Connect(function()
	if not isOpen then
		OpenUI()
	end
end)

-- ForceClose: instantly hide UI without animation (used by RoundStartCloser)
local function ForceCloseUI()
	if not isOpen and not isAnimating then return end
	parentFrame.Visible = false
	questsGui.Enabled = false
	if blurEffect then
		blurEffect:Destroy()
		blurEffect = nil
	end
	isOpen = false
	isAnimating = false
end

local forceCloseEvent = Instance.new("BindableEvent")
forceCloseEvent.Name = "ForceClose"
forceCloseEvent.Parent = questsGui
forceCloseEvent.Event:Connect(function()
	ForceCloseUI()
end)

print("[QuestsUI] Quest UI initialized")
