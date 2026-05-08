--!strict
-- SkinShop.client.lua
-- Populates the StoreUI capsule shop with rotating item previews per rarity frame
-- Each frame shows 4 items: 3 from the capsule's rarity + 1 bonus from the next tier (10%)
-- Items rotate every 5 seconds with a fade transition to showcase the full pool

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BombSkins = require(Shared:WaitForChild("BombSkins"))
local WinDances = require(Shared:WaitForChild("WinDances"))
local Titles = require(Shared:WaitForChild("Titles"))
local ExplosionSkins = require(Shared:WaitForChild("ExplosionSkins"))
local Economy = require(Shared:WaitForChild("Economy"))

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BuyCapsuleRemote = Remotes:WaitForChild("BuyCapsule") :: RemoteFunction

-- Sounds
local SoundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
local UISounds = SoundsFolder and SoundsFolder:FindFirstChild("UI")
local purchaseSound: Sound? = UISounds and UISounds:FindFirstChild("GamepassPurchase") :: Sound? or nil
local hoverSound: Sound? = UISounds and UISounds:FindFirstChild("Hover") :: Sound? or nil
local clickSound: Sound? = UISounds and UISounds:FindFirstChild("Click") :: Sound? or nil

-- RewardAnnounce (lives in NavHUD)
local navHUD = playerGui:WaitForChild("NavHUD", 15) :: ScreenGui?
local rewardAnnounce: TextLabel? = nil
if navHUD then
	rewardAnnounce = navHUD:FindFirstChild("RewardAnnounce") :: TextLabel?
end

-- Wait for StoreUI
local storeGui = playerGui:WaitForChild("StoreUI", 15) :: ScreenGui?
if not storeGui then
	warn("[SkinShop] StoreUI ScreenGui not found")
	return
end

local parentFrame = storeGui:WaitForChild("ParentFrame") :: Frame
local shopFrame = parentFrame:FindFirstChild("ShopFrame")
if not shopFrame then
	warn("[SkinShop] ShopFrame not found in ParentFrame")
	return
end

-- ============================================================
-- CONFETTI EFFECT
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

local function SpawnConfetti()
	local center = parentFrame.AbsolutePosition + parentFrame.AbsoluteSize / 2
	for _ = 1, 40 do
		local piece = Instance.new("Frame")
		piece.Size = UDim2.fromOffset(math.random(6, 12), math.random(6, 12))
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = UDim2.fromOffset(center.X, center.Y)
		piece.BackgroundColor3 = CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)]
		piece.BorderSizePixel = 0
		piece.Rotation = math.random(0, 360)
		piece.ZIndex = 100

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, math.random(0, 1) == 0 and 2 or 6)
		corner.Parent = piece

		piece.Parent = storeGui

		local angle = math.rad(math.random(0, 360))
		local dist = math.random(150, 350)
		local targetX = center.X + math.cos(angle) * dist
		local targetY = center.Y + math.sin(angle) * dist - math.random(50, 150)

		local moveTween = TweenService:Create(piece,
			TweenInfo.new(math.random(60, 120) / 100, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = UDim2.fromOffset(targetX, targetY),
				Rotation = math.random(-360, 360),
			}
		)
		local fadeTween = TweenService:Create(piece,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		)

		moveTween:Play()
		task.delay(0.7, function()
			fadeTween:Play()
			fadeTween.Completed:Once(function()
				piece:Destroy()
			end)
		end)
	end
end

-- ============================================================
-- REWARD ANNOUNCE
-- ============================================================
local function ShowRewardAnnounce(message: string, color: Color3?)
	if not rewardAnnounce then return end
	local hex = "#FFFFFF"
	if color then
		hex = string.format("#%02X%02X%02X",
			math.floor(color.R * 255),
			math.floor(color.G * 255),
			math.floor(color.B * 255))
	end
	rewardAnnounce.RichText = true
	rewardAnnounce.Text = '<font color="' .. hex .. '">' .. message .. '</font>'
	rewardAnnounce.TextTransparency = 0
	rewardAnnounce.TextStrokeTransparency = rewardAnnounce.TextStrokeTransparency
	rewardAnnounce.Visible = true

	local origStroke = rewardAnnounce.TextStrokeTransparency
	task.delay(3, function()
		local tween = TweenService:Create(rewardAnnounce,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		)
		tween:Play()
		tween.Completed:Wait()
		rewardAnnounce.Visible = false
		rewardAnnounce.TextTransparency = 0
		rewardAnnounce.TextStrokeTransparency = origStroke
	end)
end

-- ============================================================
-- POST-PURCHASE CELEBRATION
-- ============================================================
local function CelebratePurchase(message: string, rarityColor: Color3?)
	if purchaseSound then purchaseSound:Play() end
	SpawnConfetti()
	ShowRewardAnnounce(message, rarityColor or Color3.fromRGB(255, 215, 0))
end

-- ============================================================
-- SHARED HELPERS
-- ============================================================

-- Find the image label in a slot (could be named "Icon" or "ImageLabel")
local function FindSlotImage(slot: Frame): ImageLabel?
	local img = slot:FindFirstChild("Icon") :: ImageLabel?
	if img and img:IsA("ImageLabel") then return img end
	img = slot:FindFirstChild("ImageLabel") :: ImageLabel?
	if img and img:IsA("ImageLabel") then return img end
	return nil
end

-- ============================================================
-- HOVER EFFECTS
-- ============================================================

-- Icon hover: scale the icon inside an item slot
local function AddIconHover(slot: Frame)
	local icon = FindSlotImage(slot)
	if not icon then return end

	local origSize = icon.Size
	local hoverSize = UDim2.new(
		origSize.X.Scale * 1.12, origSize.X.Offset * 1.12,
		origSize.Y.Scale * 1.12, origSize.Y.Offset * 1.12
	)

	slot.MouseEnter:Connect(function()
		if hoverSound then hoverSound:Play() end
		TweenService:Create(icon,
			TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = hoverSize }
		):Play()
	end)
	slot.MouseLeave:Connect(function()
		TweenService:Create(icon,
			TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = origSize }
		):Play()
	end)
end

-- Button hover: size pulse on buy buttons
local function AddButtonHover(btn: GuiButton)
	local origSize = btn.Size
	local hoverSize = UDim2.new(
		origSize.X.Scale * 1.08, origSize.X.Offset * 1.08,
		origSize.Y.Scale * 1.08, origSize.Y.Offset * 1.08
	)

	btn.MouseEnter:Connect(function()
		if hoverSound then hoverSound:Play() end
		TweenService:Create(btn,
			TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = hoverSize }
		):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn,
			TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = origSize }
		):Play()
	end)
end

-- ============================================================
-- ITEM POOL: collect all items grouped by rarity
-- ============================================================
type ItemEntry = { name: string, imageId: string, rarity: string }

local itemsByRarity: {[string]: {ItemEntry}} = {}

-- Init rarity buckets
for _, r in ipairs({ "Common", "Uncommon", "Rare", "Epic", "Legendary" }) do
	itemsByRarity[r] = {}
end

-- Collect skins (skip default_bomb which has chance = 0, skip items without images)
for _, skin in ipairs(BombSkins.Skins) do
	if skin.chance > 0 and skin.imageId ~= "" and itemsByRarity[skin.rarity] then
		table.insert(itemsByRarity[skin.rarity], {
			name = skin.name,
			imageId = skin.imageId,
			rarity = skin.rarity,
		})
	end
end

-- Collect dances (only those with images)
for _, dance in ipairs(WinDances.Dances) do
	if dance.imageId ~= "" and itemsByRarity[dance.rarity] then
		table.insert(itemsByRarity[dance.rarity], {
			name = dance.name,
			imageId = dance.imageId,
			rarity = dance.rarity,
		})
	end
end

-- Collect explosion skins (skip default which has chance = 0, skip items without images)
for _, explosion in ipairs(ExplosionSkins.Skins) do
	if explosion.chance > 0 and explosion.imageId ~= "" and itemsByRarity[explosion.rarity] then
		table.insert(itemsByRarity[explosion.rarity], {
			name = explosion.name,
			imageId = explosion.imageId,
			rarity = explosion.rarity,
		})
	end
end

-- Next rarity tier for bonus items
local NEXT_RARITY: {[string]: string} = {
	Common = "Uncommon",
	Uncommon = "Rare",
	Rare = "Epic",
	Epic = "Legendary",
}

-- Frame name mapping
local RARITY_FRAME_NAMES: {[string]: string} = {
	Legendary = "LegendaryFrame",
	Epic = "EpicFrame",
	Rare = "RareFrame",
	Uncommon = "UncommonFrame",
}

-- ============================================================
-- HELPERS
-- ============================================================

-- Shuffle array in place (Fisher-Yates)
local function Shuffle(t: {any})
	for i = #t, 2, -1 do
		local j = math.random(1, i)
		t[i], t[j] = t[j], t[i]
	end
end

-- Pick N random items from a pool (without repeating within one pick)
local function PickRandom(pool: {ItemEntry}, count: number, exclude: {ItemEntry}?): {ItemEntry}
	if #pool == 0 then return {} end

	-- Build a shuffled copy
	local copy = table.clone(pool)
	Shuffle(copy)

	local result = {}
	for _, item in ipairs(copy) do
		if #result >= count then break end
		-- Skip items already in exclude set (avoid duplicates across slots)
		local dominated = false
		if exclude then
			for _, ex in ipairs(exclude) do
				if ex.name == item.name then
					dominated = true
					break
				end
			end
		end
		if not dominated then
			table.insert(result, item)
		end
	end
	return result
end

-- Update a slot's visuals (image, name, chance, stroke color)
local function UpdateSlotVisuals(slot: Frame, itemData: ItemEntry, chance: number)
	-- Image (check "Icon" first, then "ImageLabel")
	local imageLabel = FindSlotImage(slot)
	if imageLabel then
		imageLabel.Image = itemData.imageId
		imageLabel.ImageTransparency = 0
		imageLabel.Visible = true
		imageLabel.ZIndex = 1
	end

	-- Name label (template may have placeholder text we need to overwrite)
	local nameLabel = slot:FindFirstChild("Label") :: TextLabel?
	if not nameLabel then
		-- Search common name patterns (skip Chance/ChanceLabel)
		for _, child in ipairs(slot:GetChildren()) do
			if child:IsA("TextLabel") and child.Name ~= "Chance" and child.Name ~= "ChanceLabel" then
				nameLabel = child :: TextLabel
				break
			end
		end
	end
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = itemData.name
		nameLabel.TextTransparency = 0
		nameLabel.ZIndex = 2
	end

	-- Chance label
	local chanceLabel = slot:FindFirstChild("ChanceLabel") :: TextLabel?
	if not chanceLabel then
		chanceLabel = slot:FindFirstChild("Chance") :: TextLabel?
	end
	if chanceLabel and chanceLabel:IsA("TextLabel") then
		chanceLabel.Text = tostring(chance) .. "%"
		chanceLabel.TextTransparency = 0
	end

	-- UIStroke color
	local rarityColor = BombSkins.RarityColors[itemData.rarity]
	if rarityColor then
		local stroke = slot:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			stroke.Color = rarityColor
		end
	end
end

-- Create the 4 item slots from a template
local function CreateSlots(imageLabels: Frame, itemTemplate: Frame): {Frame}
	itemTemplate.Visible = false

	local slots = {}
	for i = 1, 4 do
		local slot = itemTemplate:Clone()
		slot.Name = "Item" .. tostring(i)
		slot.Visible = true
		slot.LayoutOrder = i
		slot.Parent = imageLabels

		-- Ensure an image element exists (template may use "Icon" or "ImageLabel")
		local img = FindSlotImage(slot)
		if not img then
			local vp = slot:FindFirstChild("ViewportFrame")
			if vp then vp.Visible = false end
			img = Instance.new("ImageLabel")
			img.Name = "Icon"
			img.Size = UDim2.new(1, 0, 1, 0)
			img.BackgroundTransparency = 1
			img.ScaleType = Enum.ScaleType.Fit
			img.Parent = slot
		end

		-- Add icon hover effect
		AddIconHover(slot)

		table.insert(slots, slot)
	end
	return slots
end

-- Fade all slots out, swap content, fade back in
local FADE_TIME = 0.3
local function TransitionSlots(slots: {Frame}, items: {ItemEntry}, chances: {number})
	-- Collect all fadeable children per slot
	local fadeTweens = {}
	for _, slot in ipairs(slots) do
		-- Fade image
		local img = FindSlotImage(slot)
		if img then
			table.insert(fadeTweens, TweenService:Create(img,
				TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ ImageTransparency = 1 }
			))
		end
		-- Fade all TextLabels (name + chance)
		for _, child in ipairs(slot:GetChildren()) do
			if child:IsA("TextLabel") then
				table.insert(fadeTweens, TweenService:Create(child,
					TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ TextTransparency = 1 }
				))
			end
		end
	end
	for _, tw in ipairs(fadeTweens) do tw:Play() end
	task.wait(FADE_TIME)

	-- Swap content
	for i, slot in ipairs(slots) do
		local item = items[i]
		if item then
			UpdateSlotVisuals(slot, item, chances[i] or 0)
		end
	end

	-- Fade in
	local fadeInTweens = {}
	for _, slot in ipairs(slots) do
		local img = FindSlotImage(slot)
		if img and img.Visible then
			table.insert(fadeInTweens, TweenService:Create(img,
				TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ ImageTransparency = 0 }
			))
		end
		for _, child in ipairs(slot:GetChildren()) do
			if child:IsA("TextLabel") then
				table.insert(fadeInTweens, TweenService:Create(child,
					TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ TextTransparency = 0 }
				))
			end
		end
	end
	for _, tw in ipairs(fadeInTweens) do tw:Play() end
end

-- ============================================================
-- PURCHASE HELPERS
-- ============================================================
local purchasing = false -- debounce

-- Rarity display names for announcements
local RARITY_DISPLAY: {[string]: string} = {
	Uncommon = "Uncommon",
	Rare = "Rare",
	Epic = "Epic",
	Legendary = "Legendary",
	Random = "Random",
}

-- Buy capsule with coins
local function BuyWithCoins(rarity: string)
	if purchasing then return end
	purchasing = true
	if clickSound then clickSound:Play() end

	local result = BuyCapsuleRemote:InvokeServer(rarity)
	if result and result.success then
		local rarityColor = BombSkins.RarityColors[rarity]
		CelebratePurchase("Successfully Bought 1 " .. (RARITY_DISPLAY[rarity] or rarity) .. " Capsule!", rarityColor)
	else
		local reason = result and result.reason or "unknown"
		if reason == "not_enough_coins" then
			warn("[SkinShop] Not enough coins for " .. rarity .. " capsule")
		else
			warn("[SkinShop] Purchase failed: " .. reason)
		end
	end

	task.wait(0.5) -- small cooldown
	purchasing = false
end

-- Rainbow frame for purchase prompt ambiance
local bannerUI = playerGui:FindFirstChild("BannerUI")
local rainbowFrame = bannerUI and bannerUI:FindFirstChild("RainbowFrame") :: Frame? or nil

-- Buy capsule with Robux (dev product)
-- productId: the dev product ID
-- label: display text for the announce (e.g. "3 Legendary Capsules")
local function BuyWithRobux(productId: number, label: string?, rarityColor: Color3?)
	if purchasing then return end
	purchasing = true
	if clickSound then clickSound:Play() end

	-- Show and spin rainbow frame while purchase prompt is up
	local spinActive = true
	local rainbowSpinTween: Tween? = nil
	if rainbowFrame then
		rainbowFrame.BackgroundTransparency = 1
		rainbowFrame.Visible = true
		rainbowFrame.Rotation = 0
		-- Fade in
		TweenService:Create(rainbowFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0,
		}):Play()
		-- Continuous spin
		task.spawn(function()
			while spinActive do
				rainbowSpinTween = TweenService:Create(rainbowFrame,
					TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
					{ Rotation = rainbowFrame.Rotation + 360 })
				rainbowSpinTween:Play()
				rainbowSpinTween.Completed:Wait()
			end
		end)
	end

	-- Helper to fade out and hide rainbow
	local function HideRainbow()
		spinActive = false
		if rainbowSpinTween then rainbowSpinTween:Cancel() end
		if rainbowFrame then
			local fadeOut = TweenService:Create(rainbowFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				BackgroundTransparency = 1,
			})
			fadeOut:Play()
			fadeOut.Completed:Connect(function()
				rainbowFrame.Visible = false
				rainbowFrame.Rotation = 0
			end)
		end
	end

	-- Listen for the purchase completion
	local conn: RBXScriptConnection?
	conn = MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, purchasedProductId, wasPurchased)
		if userId ~= player.UserId or purchasedProductId ~= productId then return end
		if conn then conn:Disconnect() end

		HideRainbow()

		if wasPurchased then
			CelebratePurchase("Successfully Bought " .. (label or "Capsule") .. "!", rarityColor or Color3.fromRGB(255, 215, 0))
		end
	end)

	MarketplaceService:PromptProductPurchase(player, productId)

	-- Timeout cleanup in case prompt is dismissed without event
	task.delay(60, function()
		if conn then conn:Disconnect() end
		HideRainbow()
	end)

	task.wait(1) -- cooldown while prompt is open
	purchasing = false
end

-- Find a clickable button inside a frame (BuyBtn, or the frame itself if it's a button)
local function FindClickable(frame: Instance): GuiButton?
	local btn = frame:FindFirstChild("BuyBtn")
	if btn and (btn:IsA("TextButton") or btn:IsA("ImageButton")) then
		return btn :: GuiButton
	end
	if frame:IsA("TextButton") or frame:IsA("ImageButton") then
		return frame :: GuiButton
	end
	-- Search direct children for any button
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("TextButton") or child:IsA("ImageButton") then
			return child :: GuiButton
		end
	end
	return nil
end

-- Hook up buy buttons for a rarity frame (coin + robux)
local function SetupBuyButtons(rarityFrame: Frame, rarity: string)
	-- Log all clickable buttons found in this frame for debugging
	local allButtons: {GuiButton} = {}
	for _, child in ipairs(rarityFrame:GetDescendants()) do
		if child:IsA("TextButton") or child:IsA("ImageButton") then
			table.insert(allButtons, child :: GuiButton)
			print("[SkinShop] Found button in " .. rarityFrame.Name .. ": " .. child:GetFullName())
		end
	end

	-- Connect all buttons that contain "coin" in their name or parent name -> coin purchase
	-- Connect all buttons that contain "robux" or "buy" in their name or parent name -> robux purchase
	local coinConnected = false
	local robuxConnected = false

	local rarityColor = BombSkins.RarityColors[rarity]
	local rarityLabel = RARITY_DISPLAY[rarity] or rarity

	for _, btn in ipairs(allButtons) do
		local btnNameLower = btn.Name:lower()
		local parentNameLower = if btn.Parent then btn.Parent.Name:lower() else ""

		if not coinConnected and (btnNameLower:find("coin") or parentNameLower:find("coin")) then
			btn.MouseButton1Click:Connect(function()
				BuyWithCoins(rarity)
			end)
			AddButtonHover(btn)
			coinConnected = true
			print("[SkinShop] Connected COIN buy: " .. btn:GetFullName())
		elseif not robuxConnected and (btnNameLower:find("robux") or parentNameLower:find("robux")
			or btnNameLower:find("buy") or parentNameLower:find("buy")) then
			local devProduct = Economy.CAPSULE_DEV_PRODUCTS[rarity]
			if devProduct then
				btn.MouseButton1Click:Connect(function()
					BuyWithRobux(devProduct.productId, "1 " .. rarityLabel .. " Capsule", rarityColor)
				end)
				AddButtonHover(btn)
				robuxConnected = true
				print("[SkinShop] Connected ROBUX buy: " .. btn:GetFullName())
			end
		end
	end

	-- Fallback: if we found buttons but couldn't match names, connect first two
	if not coinConnected and not robuxConnected and #allButtons >= 2 then
		allButtons[1].MouseButton1Click:Connect(function()
			BuyWithCoins(rarity)
		end)
		AddButtonHover(allButtons[1])
		print("[SkinShop] Fallback COIN buy: " .. allButtons[1]:GetFullName())

		local devProduct = Economy.CAPSULE_DEV_PRODUCTS[rarity]
		if devProduct then
			allButtons[2].MouseButton1Click:Connect(function()
				BuyWithRobux(devProduct.productId, "1 " .. rarityLabel .. " Capsule", rarityColor)
			end)
			AddButtonHover(allButtons[2])
			print("[SkinShop] Fallback ROBUX buy: " .. allButtons[2]:GetFullName())
		end
	elseif not coinConnected and not robuxConnected and #allButtons == 1 then
		local coinPrice = Economy.CAPSULE_PRICES[rarity]
		if coinPrice then
			allButtons[1].MouseButton1Click:Connect(function()
				BuyWithCoins(rarity)
			end)
			AddButtonHover(allButtons[1])
			print("[SkinShop] Single-button COIN buy: " .. allButtons[1]:GetFullName())
		else
			local devProduct = Economy.CAPSULE_DEV_PRODUCTS[rarity]
			if devProduct then
				allButtons[1].MouseButton1Click:Connect(function()
					BuyWithRobux(devProduct.productId, "1 " .. rarityLabel .. " Capsule", rarityColor)
				end)
				AddButtonHover(allButtons[1])
				print("[SkinShop] Single-button ROBUX buy: " .. allButtons[1]:GetFullName())
			end
		end
	end
end

-- ============================================================
-- SETUP: create slots and start rotation for each rarity
-- ============================================================
local ROTATE_INTERVAL = 5 -- seconds between rotations

local function SetupRarityFrame(rarity: string)
	local frameName = RARITY_FRAME_NAMES[rarity]
	if not frameName then return end

	local rarityFrame = shopFrame:FindFirstChild(frameName) :: Frame?
	if not rarityFrame then
		warn("[SkinShop] " .. frameName .. " not found")
		return
	end

	local imageLabels = rarityFrame:FindFirstChild("ImageLabels") :: Frame?
	if not imageLabels then
		warn("[SkinShop] ImageLabels not found in " .. frameName)
		return
	end

	local itemTemplate = imageLabels:FindFirstChild("ItemTemplate") :: Frame?
	if not itemTemplate then
		warn("[SkinShop] ItemTemplate not found in " .. frameName)
		return
	end

	-- Create 4 slots
	local slots = CreateSlots(imageLabels, itemTemplate)

	-- Get item pools
	local mainPool = itemsByRarity[rarity] or {}
	local nextRarity = NEXT_RARITY[rarity]
	local bonusPool = nextRarity and itemsByRarity[nextRarity] or {}

	-- Pick initial items and populate
	local function RefreshItems(): ({ItemEntry}, {number})
		local mainItems = PickRandom(mainPool, 3)
		local bonusItem = PickRandom(bonusPool, 1, mainItems)

		local items: {ItemEntry} = {}
		local chances: {number} = {}

		for _, item in ipairs(mainItems) do
			table.insert(items, item)
			table.insert(chances, 30)
		end

		-- 4th slot: bonus from next rarity at 10%
		if #bonusItem > 0 then
			table.insert(items, bonusItem[1])
			table.insert(chances, 10)
		elseif #mainItems > 0 then
			-- Fallback: use another main item if no bonus pool
			local extra = PickRandom(mainPool, 1, mainItems)
			if #extra > 0 then
				table.insert(items, extra[1])
				table.insert(chances, 10)
			end
		end

		return items, chances
	end

	-- Initial population (no fade, just set directly)
	local initItems, initChances = RefreshItems()
	for i, slot in ipairs(slots) do
		if initItems[i] then
			UpdateSlotVisuals(slot, initItems[i], initChances[i])
		end
	end

	-- Start rotation loop (only rotates when shop is visible)
	task.spawn(function()
		while true do
			if not shopFrame or not parentFrame.Visible then task.wait(1) continue end
			task.wait(ROTATE_INTERVAL)
			local newItems, newChances = RefreshItems()
			TransitionSlots(slots, newItems, newChances)
		end
	end)

	-- Set coin price
	local coinPrice = Economy.CAPSULE_PRICES[rarity]
	if coinPrice then
		local coinPriceLabel = rarityFrame:FindFirstChild("CoinPrice") :: TextLabel?
		if not coinPriceLabel then
			for _, child in ipairs(rarityFrame:GetDescendants()) do
				if child:IsA("TextLabel") and child.Name == "CoinPrice" then
					coinPriceLabel = child :: TextLabel
					break
				end
			end
		end
		if coinPriceLabel and coinPriceLabel:IsA("TextLabel") then
			coinPriceLabel.Text = tostring(coinPrice)
		end
	end

	-- Set robux price
	local devProduct = Economy.CAPSULE_DEV_PRODUCTS[rarity]
	if devProduct then
		local robuxPriceLabel = rarityFrame:FindFirstChild("RobuxPrice") :: TextLabel?
		if not robuxPriceLabel then
			for _, child in ipairs(rarityFrame:GetDescendants()) do
				if child:IsA("TextLabel") and child.Name == "RobuxPrice" then
					robuxPriceLabel = child :: TextLabel
					break
				end
			end
		end
		if robuxPriceLabel and robuxPriceLabel:IsA("TextLabel") then
			robuxPriceLabel.Text = "R$ " .. tostring(devProduct.robux)
		end
	end

	-- Hook up buy buttons
	SetupBuyButtons(rarityFrame, rarity)

	print("[SkinShop] " .. frameName .. " ready (" .. #mainPool .. " items + " .. #bonusPool .. " bonus pool)")
end

-- Setup Legendary frame (Robux-only, no bonus tier, still rotates)
local function SetupLegendaryFrame()
	local legendaryFrame = shopFrame:FindFirstChild("LegendaryFrame") :: Frame?
	if not legendaryFrame then
		warn("[SkinShop] LegendaryFrame not found")
		return
	end

	local imageLabels = legendaryFrame:FindFirstChild("ImageLabels") :: Frame?
	if not imageLabels then return end

	local itemTemplate = imageLabels:FindFirstChild("ItemTemplate") :: Frame?
	if not itemTemplate then return end

	local slots = CreateSlots(imageLabels, itemTemplate)
	local pool = itemsByRarity["Legendary"] or {}
	print("[SkinShop] Legendary pool size:", #pool, "| Slots created:", #slots)

	local function RefreshItems(): ({ItemEntry}, {number})
		local items = PickRandom(pool, 4)
		local chances = {}
		for _ in ipairs(items) do
			table.insert(chances, 25)
		end
		return items, chances
	end

	-- Initial population
	local initItems, initChances = RefreshItems()
	print("[SkinShop] Legendary initial items picked:", #initItems)
	for i, slot in ipairs(slots) do
		if initItems[i] then
			UpdateSlotVisuals(slot, initItems[i], initChances[i])
			print("[SkinShop] Legendary slot", i, "->", initItems[i].name, "|", "img:", FindSlotImage(slot) ~= nil)
		end
	end

	-- Rotation loop (only rotates when shop is visible)
	task.spawn(function()
		while true do
			if not shopFrame or not parentFrame.Visible then task.wait(1) continue end
			task.wait(ROTATE_INTERVAL)
			local newItems, newChances = RefreshItems()
			TransitionSlots(slots, newItems, newChances)
		end
	end)

	-- Set purchase button prices, click handlers, and hover (1/3/5 capsules)
	local purchaseButtons = legendaryFrame:FindFirstChild("PurchaseButtons") :: Frame?
	local legendaryColor = BombSkins.RarityColors["Legendary"]
	if purchaseButtons then
		local buttonMap = {
			{ frameName = "1CapsulesBuyFrame", key = "Legendary1", count = 1 },
			{ frameName = "3CapsulesBuyFrame", key = "Legendary3", count = 3 },
			{ frameName = "5CapsulesBuyFrame", key = "Legendary5", count = 5 },
		}

		for _, entry in ipairs(buttonMap) do
			local btnFrame = purchaseButtons:FindFirstChild(entry.frameName)
			if not btnFrame then continue end

			local devProduct = Economy.CAPSULE_DEV_PRODUCTS[entry.key]
			if devProduct then
				-- PrizeLabel holds the price text
				local prizeLabel = btnFrame:FindFirstChild("PrizeLabel") :: TextLabel?
				if prizeLabel and prizeLabel:IsA("TextLabel") then
					prizeLabel.Text = "R$ " .. tostring(devProduct.robux)
				end

				-- Hook up click handler with label
				local capsuleLabel = tostring(entry.count) .. " Legendary Capsule" .. (entry.count > 1 and "s" or "")
				local btn = FindClickable(btnFrame)
				if btn then
					btn.MouseButton1Click:Connect(function()
						BuyWithRobux(devProduct.productId, capsuleLabel, legendaryColor)
					end)
					AddButtonHover(btn)
				end
			end
		end
	end

	print("[SkinShop] LegendaryFrame ready (" .. #pool .. " items)")
end

-- Setup Random capsule frame (shows mix of all rarities, rotates)
local function SetupRandomFrame()
	local randomFrame = shopFrame:FindFirstChild("RandomFrame") :: Frame?
	if not randomFrame then
		randomFrame = shopFrame:FindFirstChild("Random") :: Frame?
	end
	if not randomFrame then
		warn("[SkinShop] RandomFrame not found")
		return
	end

	local imageLabels = randomFrame:FindFirstChild("ImageLabels") :: Frame?
	if not imageLabels then return end

	local itemTemplate = imageLabels:FindFirstChild("ItemTemplate") :: Frame?
	if not itemTemplate then return end

	local slots = CreateSlots(imageLabels, itemTemplate)

	-- Random capsule picks one from each of 4 different rarities
	local randomRarities = { "Common", "Uncommon", "Rare", "Epic" }
	local randomChances = { 35, 30, 20, 15 }

	local function RefreshItems(): ({ItemEntry}, {number})
		local items: {ItemEntry} = {}
		local chances: {number} = {}
		for i, rarity in ipairs(randomRarities) do
			local pool = itemsByRarity[rarity] or {}
			local picked = PickRandom(pool, 1)
			if #picked > 0 then
				table.insert(items, picked[1])
				table.insert(chances, randomChances[i])
			end
		end
		return items, chances
	end

	-- Initial population
	local initItems, initChances = RefreshItems()
	for i, slot in ipairs(slots) do
		if initItems[i] then
			UpdateSlotVisuals(slot, initItems[i], initChances[i])
		end
	end

	-- Rotation loop (only rotates when shop is visible)
	task.spawn(function()
		while true do
			if not shopFrame or not parentFrame.Visible then task.wait(1) continue end
			task.wait(ROTATE_INTERVAL)
			local newItems, newChances = RefreshItems()
			TransitionSlots(slots, newItems, newChances)
		end
	end)

	-- Set robux price and click handler
	local devProduct = Economy.CAPSULE_DEV_PRODUCTS.Random
	if devProduct then
		local robuxPriceLabel = randomFrame:FindFirstChild("RobuxPrice") :: TextLabel?
		if not robuxPriceLabel then
			for _, child in ipairs(randomFrame:GetDescendants()) do
				if child:IsA("TextLabel") and child.Name == "RobuxPrice" then
					robuxPriceLabel = child :: TextLabel
					break
				end
			end
		end
		if robuxPriceLabel and robuxPriceLabel:IsA("TextLabel") then
			robuxPriceLabel.Text = "R$ " .. tostring(devProduct.robux)
		end

		-- Find and hook buy button
		local robuxBuyBtn = randomFrame:FindFirstChild("RobuxBuyBtn") or randomFrame:FindFirstChild("RobuxButton")
		if not robuxBuyBtn then
			for _, child in ipairs(randomFrame:GetDescendants()) do
				if (child:IsA("TextButton") or child:IsA("ImageButton"))
					and (child.Name:lower():find("robux") or child.Name:lower():find("buy")) then
					robuxBuyBtn = child
					break
				end
			end
		end
		if robuxBuyBtn then
			local btn = FindClickable(robuxBuyBtn)
			if btn then
				btn.MouseButton1Click:Connect(function()
					BuyWithRobux(devProduct.productId, "1 Random Capsule", Color3.fromRGB(255, 255, 255))
				end)
				AddButtonHover(btn)
			end
		end
	end

	-- Coin buy button for Random
	local randomCoinPrice = Economy.CAPSULE_PRICES["Random"]
	if randomCoinPrice then
		SetupBuyButtons(randomFrame :: Frame, "Random")
	end

	print("[SkinShop] RandomFrame ready")
end

-- ============================================================
-- RUN
-- ============================================================
for _, rarity in ipairs({ "Uncommon", "Rare", "Epic" }) do
	SetupRarityFrame(rarity)
end
SetupLegendaryFrame()
SetupRandomFrame()

print("[SkinShop] Store UI fully populated with rotating previews")
