--!strict
-- StoreUI.client.lua
-- Opens StoreUI when player touches ShopInteract or NavHUD StoreFrame button,
-- with tab switching between ShopFrame (capsules) and GamepassFrame (Robux store),
-- gamepass purchase prompts with rainbow frame ambiance.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera

-- Sound effects
local SoundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
local UISounds = SoundsFolder and SoundsFolder:FindFirstChild("UI")
local clickSound: Sound? = UISounds and UISounds:FindFirstChild("Click") :: Sound? or nil
local storeOpenSound: Sound? = UISounds and UISounds:FindFirstChild("StoreOpen") :: Sound? or nil
local hoverSound: Sound? = UISounds and UISounds:FindFirstChild("Hover") :: Sound? or nil

-- Wait for StoreUI
local storeGui = playerGui:WaitForChild("StoreUI") :: ScreenGui
local parentFrame = storeGui:WaitForChild("ParentFrame") :: Frame
local topFrame = parentFrame:FindFirstChild("TopFrame") :: Frame?
local closeFrame = topFrame and topFrame:FindFirstChild("CloseFrame") :: Frame?
local closeBtn = closeFrame and closeFrame:FindFirstChild("CloseBtn")
local titleLabel = topFrame and topFrame:FindFirstChild("TextLabel") :: TextLabel? or nil

-- Tab frames
local shopFrame = parentFrame:FindFirstChild("ShopFrame") :: Frame?
local gamepassFrame = parentFrame:FindFirstChild("GamepassFrame") :: Frame?

-- Rainbow frame (lives in BannerUI)
local bannerUI = playerGui:FindFirstChild("BannerUI")
local rainbowFrame = bannerUI and bannerUI:FindFirstChild("RainbowFrame") :: Frame? or nil

-- State
local isOpen = false
local isAnimating = false
local purchasing = false
local blurEffect: BlurEffect? = nil
local originalFOV: number = Camera.FieldOfView
local UI_ZOOM_FOV = 15
local currentTab: string = "capsule" -- "capsule" | "gamepass"

-- Helper: play tween and return it
local function PlayTween(instance: Instance, info: TweenInfo, props: {[string]: any}): Tween
	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

-- Ensure UIScale exists on parentFrame
local function EnsureUIScale(): UIScale
	local scale = parentFrame:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Scale = 0
		scale.Parent = parentFrame
	end
	return scale :: UIScale
end

-- ============================================================
-- TAB SWITCHING
-- ============================================================
local function SetTab(tab: string)
	currentTab = tab
	if tab == "capsule" then
		if shopFrame then shopFrame.Visible = true end
		if gamepassFrame then gamepassFrame.Visible = false end
		if titleLabel then titleLabel.Text = "Capsule Store" end
	else
		if shopFrame then shopFrame.Visible = false end
		if gamepassFrame then gamepassFrame.Visible = true end
		if titleLabel then titleLabel.Text = "RBX Store" end
	end
end

-- ============================================================
-- GAMEPASS ITEM POPULATION
-- ============================================================
local VIP_ITEMS = {
	{ name = "Bee Bomb", imageId = "rbxassetid://117704920081015" },
	{ name = "Gold Explosion", imageId = "rbxassetid://130152535290985" },
	{ name = "Confetti Explosion", imageId = "rbxassetid://88976904255248" },
	{ name = "Default Dance", imageId = "rbxassetid://97831368846889" },
}

local ALL_BLUE_ITEMS = {
	{ name = "Lightning Explosion", imageId = "rbxassetid://113022396372768" },
	{ name = "Water Explosion", imageId = "rbxassetid://135369264988888" },
	{ name = "Dynamite Blue", imageId = "rbxassetid://80034204252028" },
}

local function PopulateItemList(containerFrame: Frame?, items: {{name: string, imageId: string}})
	if not containerFrame then return end

	-- Find the ImageLabels container (frame with UIListLayout)
	local imageLabels = containerFrame:FindFirstChild("ImageLabels") :: Frame?
	if not imageLabels then return end

	-- Find the ItemTemplate inside ImageLabels (first Frame child)
	local itemTemplate: Frame? = nil
	for _, child in ipairs(imageLabels:GetChildren()) do
		if child:IsA("Frame") then
			itemTemplate = child :: Frame
			break
		end
	end
	if not itemTemplate then return end

	-- Clone the template, then hide the original
	local template = itemTemplate:Clone()
	itemTemplate.Visible = false

	-- Clone template for each item
	for i, item in ipairs(items) do
		local entry = template:Clone()
		entry.Name = "Item_" .. i
		entry.LayoutOrder = i
		entry.Visible = true

		-- Set icon image (look for ImageLabel named Icon, or first ImageLabel)
		local icon = entry:FindFirstChild("Icon") :: ImageLabel?
		if not icon then
			icon = entry:FindFirstChildWhichIsA("ImageLabel") :: ImageLabel?
		end
		if icon then
			icon.Image = item.imageId
		end

		-- Set label text (look for TextLabel)
		local label = entry:FindFirstChildWhichIsA("TextLabel")
		if label then
			label.Text = item.name
		end

		entry.Parent = imageLabels
	end

	template:Destroy()
end

local function PopulateGamepassItems()
	if not gamepassFrame then return end

	local vipFrame = gamepassFrame:FindFirstChild("VIPFrame") :: Frame?
	PopulateItemList(vipFrame, VIP_ITEMS)

	local allBlueFrame = gamepassFrame:FindFirstChild("AllBluePack") :: Frame?
	PopulateItemList(allBlueFrame, ALL_BLUE_ITEMS)
end

-- ============================================================
-- RAINBOW FRAME HELPERS (replicates SkinShop pattern)
-- ============================================================
local function ShowRainbow(): (boolean, Tween?) -- returns spinActive flag setter and tween ref
	if not rainbowFrame then return false, nil end

	rainbowFrame.BackgroundTransparency = 1
	rainbowFrame.Visible = true
	rainbowFrame.Rotation = 0
	-- Fade in
	TweenService:Create(rainbowFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0,
	}):Play()

	return true, nil
end

local function HideRainbow(spinTween: Tween?)
	if spinTween then spinTween:Cancel() end
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

-- ============================================================
-- GAMEPASS PURCHASE
-- ============================================================
local function PromptGamepass(gamepassId: number)
	if purchasing then return end
	purchasing = true
	if clickSound then clickSound:Play() end

	-- Show and spin rainbow frame
	local spinActive = true
	local rainbowSpinTween: Tween? = nil
	if rainbowFrame then
		rainbowFrame.BackgroundTransparency = 1
		rainbowFrame.Visible = true
		rainbowFrame.Rotation = 0
		TweenService:Create(rainbowFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0,
		}):Play()
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

	local function hideRainbow()
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

	-- Listen for purchase completion
	local conn: RBXScriptConnection?
	conn = MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, wasPurchased)
		if plr ~= player or passId ~= gamepassId then return end
		if conn then conn:Disconnect() end
		hideRainbow()
	end)

	MarketplaceService:PromptGamePassPurchase(player, gamepassId)

	-- Timeout cleanup
	task.delay(60, function()
		if conn then conn:Disconnect() end
		hideRainbow()
	end)

	task.wait(1)
	purchasing = false
end

-- ============================================================
-- WIRE BUY BUTTONS
-- ============================================================
local function WireBuyButtons()
	if not gamepassFrame then return end

	-- VIP Pass buy button
	local vipFrame = gamepassFrame:FindFirstChild("VIPFrame") :: Frame?
	if vipFrame then
		local buyBtn = vipFrame:FindFirstChild("BuyBtn", true)
		if buyBtn and (buyBtn:IsA("TextButton") or buyBtn:IsA("ImageButton")) then
			(buyBtn :: GuiButton).MouseButton1Click:Connect(function()
				PromptGamepass(Economy.GAMEPASS_VIP)
			end)
		end
	end

	-- 2x Coins buy button
	local doubleCoinsFrame = gamepassFrame:FindFirstChild("2xCoinsFrame") or gamepassFrame:FindFirstChild("DoubleCoinsFrame")
	if doubleCoinsFrame then
		local buyBtn = doubleCoinsFrame:FindFirstChild("BuyBtn", true)
		if buyBtn and (buyBtn:IsA("TextButton") or buyBtn:IsA("ImageButton")) then
			(buyBtn :: GuiButton).MouseButton1Click:Connect(function()
				PromptGamepass(Economy.GAMEPASS_2X_COINS)
			end)
		end
	end

	-- All Blue Pack buy button
	local allBlueFrame = gamepassFrame:FindFirstChild("AllBluePack") :: Frame?
	if allBlueFrame then
		local buyBtn = allBlueFrame:FindFirstChild("BuyBtn", true)
		if buyBtn and (buyBtn:IsA("TextButton") or buyBtn:IsA("ImageButton")) then
			(buyBtn :: GuiButton).MouseButton1Click:Connect(function()
				PromptGamepass(Economy.GAMEPASS_ALL_BLUE)
			end)
		end
	end
end

-- ============================================================
-- CLOSE OTHER POPUPS (mutual exclusion)
-- ============================================================
local POPUP_GUIS = {"StoreUI", "InventoryUI", "QuestsUI", "DailyRewardsUI", "SpinUI", "CapsuleUI", "ConfigUI"}

local function CloseOtherPopups()
	for _, guiName in ipairs(POPUP_GUIS) do
		if guiName ~= "StoreUI" then
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

-- ============================================================
-- OPEN / CLOSE UI
-- ============================================================
local function OpenUI(tab: string?)
	if isOpen or isAnimating then return end
	CloseOtherPopups()
	isAnimating = true

	-- Set tab before showing
	SetTab(tab or currentTab)

	-- Play store open sound
	if storeOpenSound then storeOpenSound:Play() end

	storeGui.Enabled = true
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

-- Close StoreUI
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
	storeGui.Enabled = false

	if blurEffect then
		blurEffect:Destroy()
		blurEffect = nil
	end

	isOpen = false
	isAnimating = false
end

-- Connect CloseBtn
if closeBtn and (closeBtn:IsA("TextButton") or closeBtn:IsA("ImageButton")) then
	closeBtn.MouseButton1Click:Connect(function()
		CloseUI()
	end)
	-- Prevent child TextLabels from eating clicks
	for _, child in ipairs(closeBtn:GetChildren()) do
		if child:IsA("TextLabel") then
			child.Active = false
			child.Interactable = false
		end
	end
end

-- Initialize: UI starts disabled
storeGui.Enabled = false
parentFrame.Visible = false

-- Populate gamepass items and wire buy buttons
PopulateGamepassItems()
WireBuyButtons()

-- ShopInteract: open StoreUI (capsule tab) when player touches the proximity part
local function SetupShopInteract()
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then return end

	local interactables = lobby:FindFirstChild("Interactables")
	if not interactables then return end

	local capsuleShop = interactables:FindFirstChild("CapsuleShop")
	if not capsuleShop then return end

	local shopInteract = capsuleShop:FindFirstChild("ShopInteract")
	if not shopInteract then return end

	-- Get the touchable part (either the instance itself or find one inside a Model)
	local touchPart: BasePart? = nil
	if shopInteract:IsA("BasePart") then
		touchPart = shopInteract
	elseif shopInteract:IsA("Model") then
		touchPart = shopInteract:FindFirstChildWhichIsA("BasePart", true)
	end
	if not touchPart then return end

	-- Use Touched event to detect player stepping on the interact part
	touchPart.Touched:Connect(function(hit: BasePart)
		local character = player.Character
		if not character then return end
		if not hit:IsDescendantOf(character) then return end
		if not isOpen and not isAnimating then
			OpenUI("capsule")
		end
	end)

end

SetupShopInteract()

-- Expose open for other scripts via BindableEvent (accepts optional tab argument)
local openEvent = Instance.new("BindableEvent")
openEvent.Name = "OpenStore"
openEvent.Parent = storeGui

openEvent.Event:Connect(function(tab: string?)
	if not isOpen then
		OpenUI(tab or "capsule")
	end
end)

-- ForceClose: instantly hide UI without animation (used by RoundStartCloser)
local function ForceCloseUI()
	if not isOpen and not isAnimating then return end
	parentFrame.Visible = false
	storeGui.Enabled = false
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
forceCloseEvent.Parent = storeGui
forceCloseEvent.Event:Connect(function()
	ForceCloseUI()
end)

-- ============================================================
-- NavHUD StoreFrame integration (same pattern as QuestsUI)
-- ============================================================
task.spawn(function()
	local navHUD = playerGui:WaitForChild("NavHUD", 15)
	if not navHUD then return end

	local navParent = navHUD:FindFirstChild("ParentFrame")
	if not navParent then return end

	local navFrame = navParent:FindFirstChild("NavFrame")
	if not navFrame then return end

	local navStoreFrame = navFrame:FindFirstChild("StoreFrame")
	if not navStoreFrame then return end

	local storeImageBtn = navStoreFrame:FindFirstChildWhichIsA("ImageButton")
	local storeTextLabel = navStoreFrame:FindFirstChildWhichIsA("TextLabel")

	if not storeImageBtn then return end

	-- Hover effect
	local originalBtnSize = storeImageBtn.Size
	local hoverBtnSize = UDim2.new(
		originalBtnSize.X.Scale * 1.12, originalBtnSize.X.Offset * 1.12,
		originalBtnSize.Y.Scale * 1.12, originalBtnSize.Y.Offset * 1.12
	)
	local originalTextColor = storeTextLabel and storeTextLabel.TextColor3 or Color3.new(1, 1, 1)
	local hoverTextColor = Color3.fromRGB(255, 240, 130)

	storeImageBtn.MouseEnter:Connect(function()
		if hoverSound then hoverSound:Play() end
		PlayTween(storeImageBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = hoverBtnSize,
		})
		if storeTextLabel then
			PlayTween(storeTextLabel, TweenInfo.new(0.12), {
				TextColor3 = hoverTextColor,
			})
		end
	end)

	storeImageBtn.MouseLeave:Connect(function()
		PlayTween(storeImageBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = originalBtnSize,
		})
		if storeTextLabel then
			PlayTween(storeTextLabel, TweenInfo.new(0.12), {
				TextColor3 = originalTextColor,
			})
		end
	end)

	storeImageBtn.MouseButton1Click:Connect(function()
		-- Click pulse
		PlayTween(storeImageBtn, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(
				originalBtnSize.X.Scale * 0.88, originalBtnSize.X.Offset * 0.88,
				originalBtnSize.Y.Scale * 0.88, originalBtnSize.Y.Offset * 0.88
			),
		}).Completed:Connect(function()
			PlayTween(storeImageBtn, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = originalBtnSize,
			})
		end)

		if isOpen then
			CloseUI()
		else
			OpenUI("gamepass")
		end
	end)
end)

print("[StoreUI] Store UI initialized")
