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
-- Dev product IDs for legendary capsule purchases
local LEGENDARY_1_PRODUCT = Economy.CAPSULE_DEV_PRODUCTS.Legendary1.productId
local LEGENDARY_3_PRODUCT = Economy.CAPSULE_DEV_PRODUCTS.Legendary3.productId
local LEGENDARY_5_PRODUCT = Economy.CAPSULE_DEV_PRODUCTS.Legendary5.productId

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
-- Helper: find BuyBtn (or BuyFrame) and connect click regardless of instance type
local function WireBuyBtn(parentFrame: Frame, gamepassId: number)
	-- Look for BuyBtn inside BuyFrame, or directly in parentFrame
	local buyBtn = parentFrame:FindFirstChild("BuyBtn", true)
	if not buyBtn then
		-- Fallback: use BuyFrame itself
		buyBtn = parentFrame:FindFirstChild("BuyFrame")
	end
	if not buyBtn then return end

	if buyBtn:IsA("TextButton") or buyBtn:IsA("ImageButton") then
		(buyBtn :: GuiButton).MouseButton1Click:Connect(function()
			PromptGamepass(gamepassId)
		end)
	elseif buyBtn:IsA("Frame") then
		-- BuyBtn is a Frame — find a button child, or use InputBegan
		local innerBtn = buyBtn:FindFirstChildWhichIsA("TextButton") or buyBtn:FindFirstChildWhichIsA("ImageButton")
		if innerBtn then
			(innerBtn :: GuiButton).MouseButton1Click:Connect(function()
				PromptGamepass(gamepassId)
			end)
		else
			-- Make frame clickable via InputBegan
			buyBtn.Active = true
			(buyBtn :: Frame).InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					PromptGamepass(gamepassId)
				end
			end)
		end
	end
end

local function WireBuyButtons()
	if not gamepassFrame then return end

	-- VIP Pass
	local vipFrame = gamepassFrame:FindFirstChild("VIPFrame") :: Frame?
	if vipFrame then
		WireBuyBtn(vipFrame, Economy.GAMEPASS_VIP)
	end

	-- 2x Coins
	local doubleCoinsFrame = gamepassFrame:FindFirstChild("2xCoinsFrame") :: Frame?
	if doubleCoinsFrame then
		WireBuyBtn(doubleCoinsFrame, Economy.GAMEPASS_2X_COINS)
	end

	-- All Blue Pack
	local allBlueFrame = gamepassFrame:FindFirstChild("AllBluePack") :: Frame?
	if allBlueFrame then
		WireBuyBtn(allBlueFrame, Economy.GAMEPASS_ALL_BLUE)
	end
end

-- ============================================================
-- CAPSULE DEV PRODUCT PURCHASES (ShopFrame)
-- ============================================================
local function PromptDevProduct(productId: number)
	if purchasing then return end
	purchasing = true
	if clickSound then clickSound:Play() end

	MarketplaceService:PromptProductPurchase(player, productId)

	task.wait(1)
	purchasing = false
end

-- Wire a single BuyBtn inside a frame to a dev product
local function WireDevProductBtn(frame: Instance, productId: number)
	local buyBtn = frame:FindFirstChild("BuyBtn", true)
	if not buyBtn then return end

	if buyBtn:IsA("TextButton") or buyBtn:IsA("ImageButton") then
		(buyBtn :: GuiButton).MouseButton1Click:Connect(function()
			PromptDevProduct(productId)
		end)
	elseif buyBtn:IsA("Frame") then
		local innerBtn = buyBtn:FindFirstChildWhichIsA("TextButton") or buyBtn:FindFirstChildWhichIsA("ImageButton")
		if innerBtn then
			(innerBtn :: GuiButton).MouseButton1Click:Connect(function()
				PromptDevProduct(productId)
			end)
		else
			buyBtn.Active = true
			(buyBtn :: Frame).InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					PromptDevProduct(productId)
				end
			end)
		end
	end
end

local function WireCapsuleBuyButtons()
	if not shopFrame then return end

	-- Look for legendary capsule buy frames
	-- These contain BuyBtn children with Price labels showing R$ amounts
	local leg1Frame = shopFrame:FindFirstChild("Legendary1Frame")
		or shopFrame:FindFirstChild("Legendary1")
		or shopFrame:FindFirstChild("1CapsuleFrame")
	local leg3Frame = shopFrame:FindFirstChild("Legendary3Frame")
		or shopFrame:FindFirstChild("Legendary3")
		or shopFrame:FindFirstChild("3CapsuleFrame")
		or shopFrame:FindFirstChild("3CapsulesFrame")
	local leg5Frame = shopFrame:FindFirstChild("Legendary5Frame")
		or shopFrame:FindFirstChild("Legendary5")
		or shopFrame:FindFirstChild("5CapsuleFrame")
		or shopFrame:FindFirstChild("5CapsulesFrame")

	-- If named frames not found, search by scanning children for BuyBtn + Price patterns
	if not leg1Frame or not leg3Frame or not leg5Frame then
		-- Collect all child frames that have a BuyBtn descendant
		local buyFrames: {Instance} = {}
		for _, child in ipairs(shopFrame:GetChildren()) do
			if child:IsA("Frame") and child:FindFirstChild("BuyBtn", true) then
				table.insert(buyFrames, child)
			end
		end

		-- Match frames to products by price text
		for _, frame in ipairs(buyFrames) do
			local priceLabel = frame:FindFirstChild("Price", true)
			if priceLabel and priceLabel:IsA("TextLabel") then
				local priceText = priceLabel.Text
				if string.find(priceText, "60") and not leg1Frame then
					leg1Frame = frame
				elseif string.find(priceText, "150") and not leg3Frame then
					leg3Frame = frame
				elseif string.find(priceText, "300") and not leg5Frame then
					leg5Frame = frame
				end
			end
		end
	end

	if leg1Frame then
		WireDevProductBtn(leg1Frame, LEGENDARY_1_PRODUCT)
	end
	if leg3Frame then
		WireDevProductBtn(leg3Frame, LEGENDARY_3_PRODUCT)
	end
	if leg5Frame then
		WireDevProductBtn(leg5Frame, LEGENDARY_5_PRODUCT)
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

-- Wire buy buttons
WireBuyButtons()
WireCapsuleBuyButtons()

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
