--!strict
-- InventoryUI.client.lua
-- Inventory system UI: browse owned items across 4 categories, equip/unequip, open capsules

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Camera = workspace.CurrentCamera

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BombSkins = require(Shared:WaitForChild("BombSkins"))
local WinDances = require(Shared:WaitForChild("WinDances"))
local Titles = require(Shared:WaitForChild("Titles"))
local ExplosionSkins = require(Shared:WaitForChild("ExplosionSkins"))

-- Sound effects
local SoundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
local UISounds = SoundsFolder and SoundsFolder:FindFirstChild("UI")
local hoverSound: Sound? = UISounds and UISounds:FindFirstChild("Hover") :: Sound? or nil
local clickSound: Sound? = UISounds and UISounds:FindFirstChild("Click") :: Sound? or nil
local uiOpenSound: Sound? = UISounds and UISounds:FindFirstChild("UIOpen") :: Sound? or nil
local successSound: Sound? = UISounds and UISounds:FindFirstChild("Success") :: Sound? or nil
local equipSound: Sound? = UISounds and UISounds:FindFirstChild("EquipSound") :: Sound? or nil
local openBoxSound: Sound? = UISounds and UISounds:FindFirstChild("OpenBox") :: Sound? or nil

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local EquipItemRemote = Remotes:WaitForChild("EquipItem", 10)
local UnequipItemRemote = Remotes:WaitForChild("UnequipItem", 10)
local OpenCapsuleRemote = Remotes:WaitForChild("OpenCapsule", 10)
local SyncInventory = Remotes:WaitForChild("SyncInventory", 10)
local GetInventoryRemote = Remotes:WaitForChild("GetInventory", 10)

-- Buffer early inventory sync (server may fire before UI loads)
local pendingInventoryData: any = nil
local uiReady = false
local earlyConn: RBXScriptConnection? = nil
if SyncInventory then
	earlyConn = SyncInventory.OnClientEvent:Connect(function(inventoryData: any)
		if not uiReady then
			pendingInventoryData = inventoryData
		end
	end)
end

-- Wait for UI
local inventoryGui = playerGui:WaitForChild("InventoryUI") :: ScreenGui
local parentFrame = inventoryGui:WaitForChild("ParentFrame") :: Frame
local topFrame = parentFrame:WaitForChild("TopFrame") :: Frame
local bottomFrame = parentFrame:WaitForChild("BottomFrame") :: Frame
local navButtons = parentFrame:WaitForChild("NavButtons") :: Frame

local uiTitle = topFrame:WaitForChild("UITitle") :: TextLabel
local closeBtn = topFrame:WaitForChild("CloseBtn")

local itemsHolder = bottomFrame:WaitForChild("ItemsHolder") :: Frame

-- Nav buttons
local skinsButton = navButtons:FindFirstChild("SkinsButton") :: ImageButton
local capsuleButton = navButtons:FindFirstChild("CapsuleButton") :: ImageButton
local emoteButton = navButtons:FindFirstChild("EmoteButton") :: ImageButton
local titlesButton = navButtons:FindFirstChild("TitlesButton") :: ImageButton
local explosionsButton = navButtons:FindFirstChild("ExplosionsButton") :: ImageButton

-- Templates (grab references then hide)
local commonTemplate = itemsHolder:FindFirstChild("CommonTemplate") :: Frame
local uncommonTemplate = itemsHolder:FindFirstChild("UncommonTemplate") :: Frame
local rareTemplate = itemsHolder:FindFirstChild("RareTemplate") :: Frame
local epicTemplate = itemsHolder:FindFirstChild("EpicTemplate") :: Frame
local legendaryTemplate = itemsHolder:FindFirstChild("LegendaryTemplate") :: Frame
local buyMoreButton = itemsHolder:FindFirstChild("BuyMoreButton") :: Frame

-- Hide all templates
if commonTemplate then commonTemplate.Visible = false end
if uncommonTemplate then uncommonTemplate.Visible = false end
if rareTemplate then rareTemplate.Visible = false end
if epicTemplate then epicTemplate.Visible = false end
if legendaryTemplate then legendaryTemplate.Visible = false end

-- State
local currentCategory = "bombs" -- bombs, capsules, emotes, titles, explosions
local currentInventory: any = nil
local isOpen = false
local isAnimating = false
local activeCards: {Frame} = {}
local cardConnections: {RBXScriptConnection} = {}
local blurEffect: BlurEffect? = nil
local originalFOV: number = Camera.FieldOfView
local UI_ZOOM_FOV = 15 -- how much to increase FOV when UI is open

-- Confetti colors
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 100, 100),
	Color3.fromRGB(100, 255, 100),
	Color3.fromRGB(100, 100, 255),
	Color3.fromRGB(255, 255, 100),
	Color3.fromRGB(255, 100, 255),
	Color3.fromRGB(100, 255, 255),
}

-- Spawn confetti burst from a screen position
local function SpawnConfetti(origin: GuiObject)
	local centerX = origin.AbsolutePosition.X + origin.AbsoluteSize.X / 2
	local centerY = origin.AbsolutePosition.Y + origin.AbsoluteSize.Y / 2

	for _ = 1, 24 do
		local confetti = Instance.new("Frame")
		confetti.Name = "Confetti"
		confetti.BackgroundColor3 = CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)]
		confetti.BorderSizePixel = 0
		confetti.AnchorPoint = Vector2.new(0.5, 0.5)
		confetti.Size = UDim2.fromOffset(math.random(4, 8), math.random(10, 16))
		confetti.Position = UDim2.fromOffset(centerX, centerY)
		confetti.Rotation = math.random(0, 360)
		confetti.ZIndex = 100
		confetti.Parent = inventoryGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.3, 0)
		corner.Parent = confetti

		local angle = math.rad(math.random(0, 360))
		local dist = math.random(80, 200)
		local targetX = centerX + math.cos(angle) * dist
		local targetY = centerY + math.sin(angle) * dist

		TweenService:Create(confetti, TweenInfo.new(
			math.random(80, 130) / 100,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		), {
			Position = UDim2.fromOffset(targetX, targetY),
			Rotation = math.random(-180, 180),
			BackgroundTransparency = 1,
		}):Play()

		task.delay(1.3, function()
			confetti:Destroy()
		end)
	end
end

-- Show reward announce for quick capsule opens
local function AnnounceQuickOpen(rewardData: any)
	if not rewardData then return end

	local navHUD = playerGui:FindFirstChild("NavHUD")
	if not navHUD then return end

	local rewardAnnounce = navHUD:FindFirstChild("RewardAnnounce") :: TextLabel?
	if not rewardAnnounce then return end

	local rarityColor = BombSkins.RarityColors[rewardData.rarity] or Color3.fromRGB(180, 180, 180)
	local hexColor = string.format("#%02X%02X%02X",
		math.floor(rarityColor.R * 255),
		math.floor(rarityColor.G * 255),
		math.floor(rarityColor.B * 255)
	)

	local itemName = rewardData.itemName or "Item"
	rewardAnnounce.RichText = true
	rewardAnnounce.Text = 'Opened <font color="' .. hexColor .. '">' .. itemName .. '!</font>'
	rewardAnnounce.Visible = true
	rewardAnnounce.TextTransparency = 0
	local origStroke = rewardAnnounce.TextStrokeTransparency

	task.delay(2.5, function()
		local tw = TweenService:Create(rewardAnnounce, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		tw:Play()
		tw.Completed:Wait()
		rewardAnnounce.Visible = false
		rewardAnnounce.TextTransparency = 0
		rewardAnnounce.TextStrokeTransparency = origStroke
	end)
end

-- Capsule images per rarity
local CAPSULE_IMAGES = {
	Common = BombSkins.Images.Capsule,
	Uncommon = BombSkins.Images.Capsule,
	Rare = BombSkins.Images.Capsule,
	Epic = BombSkins.Images.Capsule,
	Legendary = BombSkins.Images.Capsule,
}

-- Map rarity to template
local function GetTemplateForRarity(rarity: string): Frame?
	if rarity == "Common" then
		return commonTemplate
	elseif rarity == "Uncommon" then
		return uncommonTemplate
	elseif rarity == "Rare" then
		return rareTemplate
	elseif rarity == "Epic" then
		return epicTemplate
	elseif rarity == "Legendary" then
		return legendaryTemplate
	end
	return commonTemplate
end

-- Helper: play tween and return it
local function PlayTween(instance: Instance, info: TweenInfo, props: {[string]: any}): Tween
	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

-- Helper: compute a darker shade of a color for UIStroke
local function DarkerColor(color: Color3): Color3
	return Color3.new(color.R * 0.4, color.G * 0.4, color.B * 0.4)
end

-- Helper: add UIScale to parentFrame if not present
local function EnsureUIScale(): UIScale
	local scale = parentFrame:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Scale = 0
		scale.Parent = parentFrame
	end
	return scale :: UIScale
end

-- Forward declarations for functions used in CreateCard but defined later
local MinimizeUI: (callback: (() -> ())?) -> ()

-- Clear all spawned item cards
local function ClearCards()
	for _, conn in ipairs(cardConnections) do
		conn:Disconnect()
	end
	cardConnections = {}
	for _, card in ipairs(activeCards) do
		card:Destroy()
	end
	activeCards = {}
end

-- Get the equipped item id for the current category
local function GetEquippedId(): string
	if not currentInventory then return "" end
	if currentCategory == "bombs" then
		return currentInventory.equippedSkin or "default_bomb"
	elseif currentCategory == "emotes" then
		return currentInventory.equippedDance or ""
	elseif currentCategory == "titles" then
		return currentInventory.equippedTitle or ""
	elseif currentCategory == "explosions" then
		return currentInventory.equippedExplosion or "default_red_explosion"
	end
	return ""
end

-- Update the equipped highlight on all cards using EquipText visibility
local function UpdateEquippedHighlight()
	local equippedId = GetEquippedId()
	for _, card in ipairs(activeCards) do
		local cardId = card:GetAttribute("ItemId")
		local equipText = card:FindFirstChild("EquipText")
		local lightImage = card:FindFirstChild("LightImage")
		local isEquipped = (cardId == equippedId)

		-- Show/hide the EquipText label
		if equipText then
			equipText.Visible = isEquipped
		end

		-- Dim non-equipped cards
		if lightImage and lightImage:IsA("ImageLabel") then
			if isEquipped then
				if lightImage.ImageTransparency > 0.1 then
					PlayTween(lightImage, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						ImageTransparency = 0,
					})
				end
			else
				if lightImage.ImageTransparency < 0.6 then
					PlayTween(lightImage, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						ImageTransparency = 0.7,
					})
				end
			end
		end
	end
end

-- Spawn a card from the appropriate template
local function CreateCard(itemId: string, itemData: any, category: string, layoutOrder: number, capsuleIdx: number?): Frame?
	local rarity = itemData.rarity or "Common"
	local template = GetTemplateForRarity(rarity)
	if not template then return nil end

	local card = template:Clone()
	card.Name = "Item_" .. itemId
	card.Visible = true
	card.LayoutOrder = layoutOrder
	card:SetAttribute("ItemId", itemId)
	card:SetAttribute("Category", category)
	if capsuleIdx then
		card:SetAttribute("CapsuleIndex", capsuleIdx)
	end

	-- Override stroke color for Uncommon (uses CommonTemplate)
	if rarity == "Uncommon" then
		local stroke = card:FindFirstChildWhichIsA("UIStroke")
		if stroke then
			stroke.Color = BombSkins.RarityColors.Uncommon or Color3.fromRGB(80, 200, 120)
		end
	end

	-- Set card image and label
	local cardImage = card:FindFirstChild("ItemImage")
	local cardLabel = card:FindFirstChild("ItemLabel")

	if category == "titles" then
		-- Titles: hide image, show label with title name
		if cardImage and cardImage:IsA("ImageLabel") then
			cardImage.Visible = false
		end
		if cardLabel and cardLabel:IsA("TextLabel") then
			cardLabel.Visible = true
			cardLabel.Text = itemData.name or ""
			local rarityColor = BombSkins.RarityColors[rarity]
			if rarityColor then
				cardLabel.TextColor3 = rarityColor
				local labelStroke = cardLabel:FindFirstChildWhichIsA("UIStroke")
				if labelStroke then
					labelStroke.Color = DarkerColor(rarityColor)
				end
			end
		end
	elseif category == "capsules" then
		-- Capsules: show capsule image
		if cardImage and cardImage:IsA("ImageLabel") then
			cardImage.Visible = true
			cardImage.Image = CAPSULE_IMAGES[rarity] or BombSkins.Images.Capsule
			cardImage.ScaleType = Enum.ScaleType.Fit
		end
		if cardLabel and cardLabel:IsA("TextLabel") then
			cardLabel.Visible = true
			cardLabel.Text = rarity
		end
	else
		-- Bombs/Emotes/Explosions: show item image
		if cardImage and cardImage:IsA("ImageLabel") then
			cardImage.Visible = true
			cardImage.Image = itemData.imageId or ""
			cardImage.ScaleType = Enum.ScaleType.Fit
		end
		if cardLabel and cardLabel:IsA("TextLabel") then
			cardLabel.Visible = true
			cardLabel.Text = itemData.name or ""
		end
	end

	-- Ensure EquipText starts hidden
	local equipText = card:FindFirstChild("EquipText")
	if equipText then
		equipText.Visible = false
	end

	-- Invisible button for click detection — auto equip/unequip on click
	local invisBtn = card:FindFirstChild("InvisibleBtn")
	if invisBtn and invisBtn:IsA("TextButton") then
		local conn = invisBtn.MouseButton1Click:Connect(function()
			if clickSound then clickSound:Play() end

			if category == "capsules" then
				-- Open capsule flow
				if capsuleIdx then
					-- Block inventory syncs from repopulating during the flow
					isAnimating = true
					local result = OpenCapsuleRemote:InvokeServer(capsuleIdx)
					if not result or not result.success or not result.reward then
						isAnimating = false
						return
					end
					local rewardData = result.reward

					-- Check skip capsule opens setting
					local skipVal = playerGui:FindFirstChild("SkipCapsuleOpens")
					local shouldSkip = skipVal and skipVal:IsA("BoolValue") and (skipVal :: BoolValue).Value

					if shouldSkip then
						-- Skip full animation but still give feedback
						if openBoxSound then openBoxSound:Play() end

						-- Show confetti from the clicked card
						if invisBtn then
							SpawnConfetti(invisBtn :: GuiObject)
						end

						-- Announce what was received
						AnnounceQuickOpen(rewardData)

						isAnimating = false
						-- Inventory already updated server-side, SyncInventory will fire
						return
					end

					MinimizeUI(function()
						local capsuleUIScreen = playerGui:FindFirstChild("CapsuleUI")
						if capsuleUIScreen then
							local trigger = capsuleUIScreen:FindFirstChild("TriggerPackOpening")
							if trigger and trigger:IsA("BindableEvent") then
								trigger:Fire(rewardData)
								task.wait(8)
							end
						end
						ClearCards()
						inventoryGui.Enabled = false
						if blurEffect then
							blurEffect:Destroy()
							blurEffect = nil
						end
						isOpen = false
						isAnimating = false
					end)
				end
				return
			end

			-- Normal equip/unequip toggle
			local equippedId = GetEquippedId()
			if itemId == equippedId then
				-- Already equipped → unequip (unless default)
				if category == "bombs" and itemId == "default_bomb" then return end
				if category == "emotes" and itemId == "billy_bounce" then return end
				if category == "explosions" and itemId == "default_red_explosion" then return end
				if equipSound then equipSound:Play() end
				UnequipItemRemote:FireServer(category)
				-- Optimistic local update
				if category == "bombs" then
					currentInventory.equippedSkin = "default_bomb"
				elseif category == "emotes" then
					currentInventory.equippedDance = "billy_bounce"
				elseif category == "titles" then
					currentInventory.equippedTitle = ""
				elseif category == "explosions" then
					currentInventory.equippedExplosion = "default_red_explosion"
				end
			else
				-- Equip
				if equipSound then equipSound:Play() end
				EquipItemRemote:FireServer(category, itemId)
				-- Optimistic local update
				if category == "bombs" then
					currentInventory.equippedSkin = itemId
				elseif category == "emotes" then
					currentInventory.equippedDance = itemId
				elseif category == "titles" then
					currentInventory.equippedTitle = itemId
				elseif category == "explosions" then
					currentInventory.equippedExplosion = itemId
				end
			end
			UpdateEquippedHighlight()
		end)
		table.insert(cardConnections, conn)

		-- Hover effects on ItemImage (not the card frame, to avoid UIListLayout issues)
		if cardImage and cardImage:IsA("ImageLabel") and cardImage.Visible then
			local imgOrigSize = cardImage.Size
			local imgHoverSize = UDim2.new(
				imgOrigSize.X.Scale * 1.08, imgOrigSize.X.Offset * 1.08,
				imgOrigSize.Y.Scale * 1.08, imgOrigSize.Y.Offset * 1.08
			)
			local hoverIn = invisBtn.MouseEnter:Connect(function()
				if hoverSound then hoverSound:Play() end
				PlayTween(cardImage, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = imgHoverSize,
					Rotation = -5,
				})
			end)
			local hoverOut = invisBtn.MouseLeave:Connect(function()
				PlayTween(cardImage, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = imgOrigSize,
					Rotation = 0,
				})
			end)
			table.insert(cardConnections, hoverIn)
			table.insert(cardConnections, hoverOut)
		elseif cardLabel and cardLabel:IsA("TextLabel") and cardLabel.Visible then
			-- For titles (no image), do a subtle scale on the label
			local lblOrigSize = cardLabel.Size
			local lblHoverSize = UDim2.new(
				lblOrigSize.X.Scale * 1.08, lblOrigSize.X.Offset * 1.08,
				lblOrigSize.Y.Scale * 1.08, lblOrigSize.Y.Offset * 1.08
			)
			local hoverIn = invisBtn.MouseEnter:Connect(function()
				if hoverSound then hoverSound:Play() end
				PlayTween(cardLabel, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = lblHoverSize,
				})
			end)
			local hoverOut = invisBtn.MouseLeave:Connect(function()
				PlayTween(cardLabel, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = lblOrigSize,
				})
			end)
			table.insert(cardConnections, hoverIn)
			table.insert(cardConnections, hoverOut)
		end
	end

	card.Parent = itemsHolder
	table.insert(activeCards, card)

	return card
end

-- Rarity sort order
local RARITY_ORDER = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

-- Sort items by rarity tier (Common first → Exotic last)
local function SortByRarity(items: {{id: string, data: any, capsuleIdx: number?}})
	table.sort(items, function(a, b)
		local orderA = RARITY_ORDER[a.data.rarity] or 0
		local orderB = RARITY_ORDER[b.data.rarity] or 0
		if orderA ~= orderB then
			return orderA < orderB
		end
		return a.data.name < b.data.name
	end)
end

-- Populate the grid for the current category
local function PopulateGrid()
	ClearCards()
	if not currentInventory then return end

	local layoutOrder = 1

	if currentCategory == "bombs" then
		uiTitle.Text = "bombs"
		local ownedSkins = currentInventory.ownedSkins or {}
		local items = {}
		for _, skinId in ipairs(ownedSkins) do
			local skinData = BombSkins.GetSkinById(skinId)
			if skinData then
				table.insert(items, { id = skinId, data = skinData, capsuleIdx = nil })
			end
		end
		SortByRarity(items)
		for _, item in ipairs(items) do
			CreateCard(item.id, item.data, "bombs", layoutOrder)
			layoutOrder += 1
		end

	elseif currentCategory == "capsules" then
		uiTitle.Text = "capsules"
		local ownedCapsules = currentInventory.ownedCapsules or {}
		local items = {}
		for i, capsule in ipairs(ownedCapsules) do
			local rarity = capsule.rarity or "Common"
			local capsuleData = { name = rarity .. " Capsule", rarity = rarity, imageId = CAPSULE_IMAGES[rarity] }
			table.insert(items, { id = "capsule_" .. i, data = capsuleData, capsuleIdx = i })
		end
		SortByRarity(items)
		for _, item in ipairs(items) do
			CreateCard(item.id, item.data, "capsules", layoutOrder, item.capsuleIdx)
			layoutOrder += 1
		end

	elseif currentCategory == "emotes" then
		uiTitle.Text = "emotes"
		local ownedDances = currentInventory.ownedDances or {}
		local items = {}
		for _, danceId in ipairs(ownedDances) do
			local danceData = WinDances.GetById(danceId)
			if danceData then
				table.insert(items, { id = danceId, data = danceData, capsuleIdx = nil })
			end
		end
		SortByRarity(items)
		for _, item in ipairs(items) do
			CreateCard(item.id, item.data, "emotes", layoutOrder)
			layoutOrder += 1
		end

	elseif currentCategory == "titles" then
		uiTitle.Text = "titles"
		local ownedTitles = currentInventory.ownedTitles or {}
		local items = {}
		for _, titleId in ipairs(ownedTitles) do
			local titleData = Titles.GetById(titleId)
			if titleData then
				table.insert(items, { id = titleId, data = titleData, capsuleIdx = nil })
			end
		end
		SortByRarity(items)
		for _, item in ipairs(items) do
			CreateCard(item.id, item.data, "titles", layoutOrder)
			layoutOrder += 1
		end

	elseif currentCategory == "explosions" then
		uiTitle.Text = "effects"
		local ownedExplosions = currentInventory.ownedExplosions or {}
		local items = {}
		for _, explosionId in ipairs(ownedExplosions) do
			local explosionData = ExplosionSkins.GetById(explosionId)
			if explosionData then
				table.insert(items, { id = explosionId, data = explosionData, capsuleIdx = nil })
			end
		end
		SortByRarity(items)
		for _, item in ipairs(items) do
			CreateCard(item.id, item.data, "explosions", layoutOrder)
			layoutOrder += 1
		end
	end

	-- Make sure BuyMoreButton is at end
	if buyMoreButton then
		buyMoreButton.LayoutOrder = 100101
		buyMoreButton.Visible = true
	end

	UpdateEquippedHighlight()
end

-- Switch category
local function SwitchCategory(category: string)
	if category == currentCategory and #activeCards > 0 then return end
	currentCategory = category
	PopulateGrid()
end

-- Open the inventory UI
-- Close other popups (mutual exclusion)
local POPUP_GUIS = {"StoreUI", "InventoryUI", "QuestsUI", "DailyRewardsUI", "SpinUI", "CapsuleUI", "ConfigUI"}

local function CloseOtherPopups()
	for _, guiName in ipairs(POPUP_GUIS) do
		if guiName ~= "InventoryUI" then
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

	-- Pre-populate cards before showing so content is visible immediately
	if #activeCards == 0 then
		PopulateGrid()
	end

	-- Play UI open sound
	if uiOpenSound then uiOpenSound:Play() end

	inventoryGui.Enabled = true
	parentFrame.Visible = true

	-- Add blur
	blurEffect = Instance.new("BlurEffect")
	blurEffect.Size = 0
	blurEffect.Parent = Lighting
	PlayTween(blurEffect, TweenInfo.new(0.3), { Size = 10 })

	-- Camera zoom in
	originalFOV = Camera.FieldOfView
	PlayTween(Camera, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = originalFOV + UI_ZOOM_FOV,
	})

	-- Scale in
	local scale = EnsureUIScale()
	scale.Scale = 0
	local tween = PlayTween(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	})
	tween.Completed:Wait()

	isOpen = true
	isAnimating = false
end

-- Close the inventory UI
local function CloseUI()
	if not isOpen or isAnimating then return end
	isAnimating = true

	if clickSound then clickSound:Play() end

	local scale = EnsureUIScale()
	local tween = PlayTween(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Scale = 0,
	})

	-- Remove blur
	if blurEffect then
		PlayTween(blurEffect, TweenInfo.new(0.3), { Size = 0 })
	end

	-- Camera zoom out
	PlayTween(Camera, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = originalFOV,
	})

	tween.Completed:Wait()

	parentFrame.Visible = false
	inventoryGui.Enabled = false

	if blurEffect then
		blurEffect:Destroy()
		blurEffect = nil
	end

	isOpen = false
	isAnimating = false
end

-- Minimize UI (for capsule opening / store)
function MinimizeUI(callback: (() -> ())?)
	if not isOpen then return end
	isAnimating = true

	local scale = EnsureUIScale()
	local tween = PlayTween(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Scale = 0,
	})

	-- Remove blur during animation
	if blurEffect then
		PlayTween(blurEffect, TweenInfo.new(0.25), { Size = 0 })
	end

	tween.Completed:Wait()
	parentFrame.Visible = false
	isAnimating = false

	if callback then
		callback()
	end
end


-- BuyMoreButton handler — close inventory, open store
local function OnBuyMoreClicked()
	if isAnimating then return end
	if clickSound then clickSound:Play() end
	CloseUI()
	-- Fire the StoreUI's OpenStore BindableEvent after close finishes
	task.defer(function()
		local storeUI = playerGui:FindFirstChild("StoreUI") :: ScreenGui?
		if storeUI then
			local openStore = storeUI:FindFirstChild("OpenStore")
			if openStore and openStore:IsA("BindableEvent") then
				openStore:Fire()
			end
		end
	end)
end

-- Nav button click with pulse animation
local function AnimateNavButton(button: ImageButton)
	local origSize = button.Size
	local pulseSize = UDim2.new(
		origSize.X.Scale * 1.15, origSize.X.Offset * 1.15,
		origSize.Y.Scale * 1.15, origSize.Y.Offset * 1.15
	)
	local tween1 = PlayTween(button, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = pulseSize,
	})
	tween1.Completed:Connect(function()
		PlayTween(button, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = origSize,
		})
	end)
end

-- Connect nav buttons
if skinsButton then
	skinsButton.MouseButton1Click:Connect(function()
		if clickSound then clickSound:Play() end
		AnimateNavButton(skinsButton)
		SwitchCategory("bombs")
	end)
end

if capsuleButton then
	capsuleButton.MouseButton1Click:Connect(function()
		if clickSound then clickSound:Play() end
		AnimateNavButton(capsuleButton)
		SwitchCategory("capsules")
	end)
end

if emoteButton then
	emoteButton.MouseButton1Click:Connect(function()
		if clickSound then clickSound:Play() end
		AnimateNavButton(emoteButton)
		SwitchCategory("emotes")
	end)
end

if titlesButton then
	titlesButton.MouseButton1Click:Connect(function()
		if clickSound then clickSound:Play() end
		AnimateNavButton(titlesButton)
		SwitchCategory("titles")
	end)
end

if explosionsButton then
	explosionsButton.MouseButton1Click:Connect(function()
		if clickSound then clickSound:Play() end
		AnimateNavButton(explosionsButton)
		SwitchCategory("explosions")
	end)
end

-- Connect close button (TextButton with child TextLabel blocking clicks)
if closeBtn and (closeBtn:IsA("TextButton") or closeBtn:IsA("ImageButton")) then
	closeBtn.MouseButton1Click:Connect(function()
		CloseUI()
	end)
	-- Prevent child TextLabel from eating clicks
	for _, child in ipairs(closeBtn:GetChildren()) do
		if child:IsA("TextLabel") then
			child.Active = false
			child.Interactable = false
		end
	end
end

-- Connect BuyMoreButton (it's a Frame with an InvisibleBtn child)
if buyMoreButton then
	local buyMoreBtn = buyMoreButton:FindFirstChild("InvisibleBtn")
	if buyMoreBtn and buyMoreBtn:IsA("TextButton") then
		buyMoreBtn.MouseButton1Click:Connect(OnBuyMoreClicked)
	end
end

-- Process inventory data (called from early buffer and future syncs)
local function ProcessInventorySync(inventoryData: any)
	local isFirstSync = (currentInventory == nil)
	currentInventory = inventoryData

	-- On first sync, pre-populate bombs so the UI is ready when opened
	if isFirstSync then
		currentCategory = "bombs"
		PopulateGrid()
		return
	end

	-- Refresh if UI is open
	if isOpen and not isAnimating then
		PopulateGrid()
	end
end

-- Disconnect early buffer and use the real handler going forward
if earlyConn then earlyConn:Disconnect() end
uiReady = true
if SyncInventory then
	SyncInventory.OnClientEvent:Connect(function(inventoryData: any)
		ProcessInventorySync(inventoryData)
	end)
end

-- Process any buffered inventory data from before UI was ready
if pendingInventoryData then
	ProcessInventorySync(pendingInventoryData)
	pendingInventoryData = nil
end

-- Fallback: if no inventory was received yet, pull from server
if not currentInventory and GetInventoryRemote then
	task.spawn(function()
		local ok, inv = pcall(function()
			return GetInventoryRemote:InvokeServer()
		end)
		if ok and inv and not currentInventory then
			ProcessInventorySync(inv)
		end
	end)
end

-- Initialize: UI starts disabled
inventoryGui.Enabled = false
parentFrame.Visible = false

-- Expose open/close for other scripts via BindableEvent
local openEvent = Instance.new("BindableEvent")
openEvent.Name = "OpenInventory"
openEvent.Parent = inventoryGui

openEvent.Event:Connect(function()
	if not isOpen then
		OpenUI()
	end
end)

-- NavHUD SkinsFrame integration: click to open inventory with bombs tab
task.spawn(function()
	local navHUD = playerGui:WaitForChild("NavHUD", 15)
	if not navHUD then return end

	local navParent = navHUD:FindFirstChild("ParentFrame")
	if not navParent then return end

	local navFrame = navParent:FindFirstChild("NavFrame")
	if not navFrame then return end

	local skinsFrame = navFrame:FindFirstChild("SkinsFrame")
	if not skinsFrame then return end

	local skinsImageBtn = skinsFrame:FindFirstChildWhichIsA("ImageButton")
	local skinsTextLabel = skinsFrame:FindFirstChildWhichIsA("TextLabel")

	if not skinsImageBtn then return end

	-- Store original colors for hover
	local originalTextColor = skinsTextLabel and skinsTextLabel.TextColor3 or Color3.new(1, 1, 1)
	local hoverTextColor = Color3.fromRGB(255, 240, 130) -- slight yellow
	local originalBtnSize = skinsImageBtn.Size

	local hoverBtnSize = UDim2.new(
		originalBtnSize.X.Scale * 1.12, originalBtnSize.X.Offset * 1.12,
		originalBtnSize.Y.Scale * 1.12, originalBtnSize.Y.Offset * 1.12
	)

	-- Hover: resize image button + tint text yellow
	skinsImageBtn.MouseEnter:Connect(function()
		if hoverSound then hoverSound:Play() end
		PlayTween(skinsImageBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = hoverBtnSize,
		})
		if skinsTextLabel then
			PlayTween(skinsTextLabel, TweenInfo.new(0.12), {
				TextColor3 = hoverTextColor,
			})
		end
	end)

	skinsImageBtn.MouseLeave:Connect(function()
		PlayTween(skinsImageBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = originalBtnSize,
		})
		if skinsTextLabel then
			PlayTween(skinsTextLabel, TweenInfo.new(0.12), {
				TextColor3 = originalTextColor,
			})
		end
	end)

	-- Click: pulse feedback then open inventory with bombs
	skinsImageBtn.MouseButton1Click:Connect(function()
		-- Click pulse: quick shrink then bounce back
		PlayTween(skinsImageBtn, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(
				originalBtnSize.X.Scale * 0.88, originalBtnSize.X.Offset * 0.88,
				originalBtnSize.Y.Scale * 0.88, originalBtnSize.Y.Offset * 0.88
			),
		}).Completed:Connect(function()
			PlayTween(skinsImageBtn, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = originalBtnSize,
			})
		end)

		if isOpen then
			CloseUI()
		else
			currentCategory = "bombs"
			-- Re-populate if category changed while closed
			if #activeCards == 0 or currentCategory ~= "bombs" then
				PopulateGrid()
			end
			OpenUI()
		end
	end)
end)

-- ForceClose: instantly hide UI without animation (used by RoundStartCloser)
local function ForceCloseUI()
	if not isOpen and not isAnimating then return end
	parentFrame.Visible = false
	inventoryGui.Enabled = false
	if blurEffect then
		blurEffect:Destroy()
		blurEffect = nil
	end
	Camera.FieldOfView = originalFOV
	isOpen = false
	isAnimating = false
end

local forceCloseEvent = Instance.new("BindableEvent")
forceCloseEvent.Name = "ForceClose"
forceCloseEvent.Parent = inventoryGui
forceCloseEvent.Event:Connect(function()
	ForceCloseUI()
end)

print("[InventoryUI] Initialized")
