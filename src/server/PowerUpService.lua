--!strict
-- PowerUpService.lua
-- Manages power-up spawning, collection, and effects

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local GameState = require(Shared:WaitForChild("GameState"))
local MapData = require(Shared:WaitForChild("MapData"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PowerUpCollected = Remotes:WaitForChild("PowerUpCollected")
local SyncPlayerData = Remotes:WaitForChild("SyncPlayerData")

local PowerUpService = {}

-- Active power-ups tracking
local activePowerUps = {} :: {[BasePart]: {type: string, gridX: number, gridY: number}}
local activeCoins = {} :: {[Instance]: {gridX: number, gridY: number}}

-- Model templates
local coinTemplate: Instance? = nil

-- Power-up type weights for random selection
local powerUpWeights = {
	{type = "BOMB_UP", weight = 25},
	{type = "FIRE_UP", weight = 25},
	{type = "SPEED_UP", weight = 20},
	{type = "SHIELD", weight = 15},
	{type = "SKULL", weight = 15},
}

local totalWeight = 0
for _, entry in ipairs(powerUpWeights) do
	totalWeight = totalWeight + entry.weight
end

function PowerUpService.Initialize()
	-- Load coin template from ReplicatedStorage
	coinTemplate = ReplicatedStorage:FindFirstChild("GoldCoin")
	if coinTemplate then
		print("[PowerUpService] Found GoldCoin template")
	else
		warn("[PowerUpService] GoldCoin not found in ReplicatedStorage, using fallback")
	end

	print("[PowerUpService] Initialized")
end

-- Select random power-up type based on weights
local function SelectRandomPowerUpType(): string
	local roll = math.random(1, totalWeight)
	local cumulative = 0

	for _, entry in ipairs(powerUpWeights) do
		cumulative = cumulative + entry.weight
		if roll <= cumulative then
			return entry.type
		end
	end

	return "BOMB_UP" -- Fallback
end

-- Create power-up visual model
local function CreatePowerUpModel(powerUpType: string): BasePart
	local powerUpData = Constants.POWERUP_TYPES[powerUpType]

	local part = Instance.new("Part")
	part.Name = "PowerUp_" .. powerUpType
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.5, 3, 3)
	part.Color = powerUpData.color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CFrame = CFrame.Angles(0, 0, math.rad(90))

	-- Add BillboardGui for icon
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "IconGui"
	billboard.Size = UDim2.new(0, 50, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.new(1, 0, 1, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = powerUpData.icon
	iconLabel.TextScaled = true
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.Parent = billboard

	-- Add glow effect
	local light = Instance.new("PointLight")
	light.Color = powerUpData.color
	light.Brightness = 2
	light.Range = 6
	light.Parent = part

	CollectionService:AddTag(part, "PowerUp")

	return part
end

-- Create coin model (uses GoldCoin from ReplicatedStorage)
local function CreateCoinModel(): Instance
	if coinTemplate then
		local coin = coinTemplate:Clone()
		coin.Name = "Coin"

		-- Setup the cloned coin
		if coin:IsA("BasePart") then
			coin.Anchored = true
			coin.CanCollide = false
			coin.Transparency = 0 -- Make sure it's visible
		elseif coin:IsA("Model") then
			for _, part in ipairs(coin:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
					part.CanCollide = false
					part.Transparency = 0
				end
			end
		end

		-- Add glow effect
		local mainPart = coin:IsA("BasePart") and coin or coin:FindFirstChildWhichIsA("BasePart")
		if mainPart then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 215, 0)
			light.Brightness = 1.5
			light.Range = 5
			light.Parent = mainPart
		end

		CollectionService:AddTag(coin, "Coin")
		print("[PowerUpService] Created coin from template, type:", coin.ClassName)
		return coin
	end

	print("[PowerUpService] WARNING: No coin template, using fallback")

	-- Fallback to basic cylinder
	local coin = Instance.new("Part")
	coin.Name = "Coin"
	coin.Shape = Enum.PartType.Cylinder
	coin.Size = Vector3.new(0.3, 1.5, 1.5)
	coin.Color = Color3.fromRGB(255, 215, 0) -- Gold
	coin.Material = Enum.Material.Neon
	coin.Anchored = true
	coin.CanCollide = false
	coin.CFrame = CFrame.Angles(0, 0, math.rad(90))

	-- Add glow effect
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 215, 0)
	light.Brightness = 1
	light.Range = 4
	light.Parent = coin

	CollectionService:AddTag(coin, "Coin")

	return coin
end

-- Spawn a random power-up at grid position
function PowerUpService.SpawnRandomPowerUp(gridX: number, gridY: number)
	local powerUpType = SelectRandomPowerUpType()
	PowerUpService.SpawnPowerUp(powerUpType, gridX, gridY)
end

-- Spawn specific power-up at grid position
function PowerUpService.SpawnPowerUp(powerUpType: string, gridX: number, gridY: number)
	local arenaFolder = Workspace:FindFirstChild("Arena")
	if not arenaFolder then return end

	local worldPos = MapData.GridToWorld(gridX, gridY)

	local powerUp = CreatePowerUpModel(powerUpType)
	powerUp.Position = worldPos + Vector3.new(0, 0.5, 0)
	powerUp.Parent = arenaFolder

	-- Store reference
	activePowerUps[powerUp] = {
		type = powerUpType,
		gridX = gridX,
		gridY = gridY,
	}

	-- Spinning animation
	task.spawn(function()
		while powerUp and powerUp.Parent do
			powerUp.CFrame = powerUp.CFrame * CFrame.Angles(0, math.rad(2), 0)
			task.wait()
		end
	end)

	-- Use proximity-based collection (more reliable than Touch events)
	local COLLECT_DISTANCE = 4 -- Horizontal distance (ignoring Y)

	-- Helper to get horizontal distance (XZ plane only)
	local function GetHorizontalDistance(pos1: Vector3, pos2: Vector3): number
		local dx = pos1.X - pos2.X
		local dz = pos1.Z - pos2.Z
		return math.sqrt(dx * dx + dz * dz)
	end

	local debugCounter = 0
	task.spawn(function()
		while powerUp and powerUp.Parent do
			local powerUpPos = powerUp.Position

			for _, checkPlayer in ipairs(Players:GetPlayers()) do
				local character = checkPlayer.Character

				-- Debug every 60 frames (~3 seconds)
				debugCounter = debugCounter + 1
				if debugCounter % 60 == 0 then
					print("[PowerUp] Player:", checkPlayer.Name, "Character:", character and character.Name or "NIL")
					if character then
						local hrp = character:FindFirstChild("HumanoidRootPart")
						print("[PowerUp] HRP:", hrp and hrp.Name or "NOT FOUND")
						if hrp then
							local hDist = GetHorizontalDistance(hrp.Position, powerUpPos)
							print("[PowerUp] HRP Pos:", hrp.Position, "PowerUp:", powerUpPos, "HorizDist:", hDist)
						end
					end
				end

				if character then
					-- Try HumanoidRootPart first
					local hrp = character:FindFirstChild("HumanoidRootPart")
					if hrp and hrp:IsA("BasePart") then
						local distance = GetHorizontalDistance(hrp.Position, powerUpPos)
						if distance < COLLECT_DISTANCE then
							print("[PowerUp] COLLECTED by", checkPlayer.Name, "HorizDist:", distance)
							PowerUpService.CollectPowerUp(powerUp, checkPlayer)
							return
						end
					end

					-- Also check Torso as backup
					local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
					if torso and torso:IsA("BasePart") then
						local distance = GetHorizontalDistance(torso.Position, powerUpPos)
						if distance < COLLECT_DISTANCE then
							print("[PowerUp] COLLECTED (via Torso) by", checkPlayer.Name, "HorizDist:", distance)
							PowerUpService.CollectPowerUp(powerUp, checkPlayer)
							return
						end
					end

					-- Final fallback: any BasePart
					local anyPart = character:FindFirstChildWhichIsA("BasePart")
					if anyPart then
						local distance = GetHorizontalDistance(anyPart.Position, powerUpPos)
						if distance < COLLECT_DISTANCE then
							print("[PowerUp] COLLECTED (via anyPart) by", checkPlayer.Name)
							PowerUpService.CollectPowerUp(powerUp, checkPlayer)
							return
						end
					end
				end
			end

			task.wait(0.05)
		end
	end)
end

-- Spawn coin at grid position
function PowerUpService.SpawnCoin(gridX: number, gridY: number)
	local arenaFolder = Workspace:FindFirstChild("Arena")
	if not arenaFolder then
		warn("[PowerUpService] No Arena folder!")
		return
	end

	local worldPos = MapData.GridToWorld(gridX, gridY)
	print("[PowerUpService] Spawning coin at grid", gridX, gridY, "world", worldPos)

	local coin = CreateCoinModel()
	print("[PowerUpService] Created coin:", coin, "Template was:", coinTemplate)

	-- Position the coin (size is 1.3, 0.24, 1.3 - so hover slightly above ground)
	local coinPos = worldPos + Vector3.new(0, 1, 0)

	if coin:IsA("BasePart") then
		coin.CFrame = CFrame.new(coinPos)
	elseif coin:IsA("Model") then
		local primary = coin.PrimaryPart or coin:FindFirstChildWhichIsA("BasePart")
		if primary then
			coin:SetPrimaryPartCFrame(CFrame.new(coinPos))
		end
	end

	coin.Parent = arenaFolder
	print("[PowerUpService] Coin parented to Arena, position:", coin:IsA("BasePart") and coin.Position or "Model")

	-- Store reference
	activeCoins[coin] = {
		gridX = gridX,
		gridY = gridY,
	}

	-- Spinning animation
	task.spawn(function()
		while coin and coin.Parent do
			if coin:IsA("BasePart") then
				coin.CFrame = coin.CFrame * CFrame.Angles(0, math.rad(3), 0)
			elseif coin:IsA("Model") then
				local primary = coin.PrimaryPart or coin:FindFirstChildWhichIsA("BasePart")
				if primary then
					coin:SetPrimaryPartCFrame(primary.CFrame * CFrame.Angles(0, math.rad(3), 0))
				end
			end
			task.wait()
		end
	end)

	-- Use proximity-based collection (more reliable than Touch events)
	local COLLECT_DISTANCE = 4 -- Horizontal distance (ignoring Y)

	-- Helper to get horizontal distance (XZ plane only)
	local function GetHorizontalDistance(pos1: Vector3, pos2: Vector3): number
		local dx = pos1.X - pos2.X
		local dz = pos1.Z - pos2.Z
		return math.sqrt(dx * dx + dz * dz)
	end

	task.spawn(function()
		while coin and coin.Parent do
			local coinPos
			if coin:IsA("BasePart") then
				coinPos = coin.Position
			elseif coin:IsA("Model") then
				local primary = coin.PrimaryPart or coin:FindFirstChildWhichIsA("BasePart")
				if primary then
					coinPos = primary.Position
				end
			end

			if coinPos then
				for _, checkPlayer in ipairs(Players:GetPlayers()) do
					local character = checkPlayer.Character
					if character then
						-- Try HumanoidRootPart first
						local hrp = character:FindFirstChild("HumanoidRootPart")
						if hrp and hrp:IsA("BasePart") then
							local distance = GetHorizontalDistance(hrp.Position, coinPos)
							if distance < COLLECT_DISTANCE then
								print("[Coin] Collecting! HorizDist:", distance)
								PowerUpService.CollectCoin(coin, checkPlayer)
								return
							end
						end

						-- Also check Torso as backup
						local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
						if torso and torso:IsA("BasePart") then
							local distance = GetHorizontalDistance(torso.Position, coinPos)
							if distance < COLLECT_DISTANCE then
								print("[Coin] Collecting (via Torso)! HorizDist:", distance)
								PowerUpService.CollectCoin(coin, checkPlayer)
								return
							end
						end

						-- Final fallback: any BasePart
						local anyPart = character:FindFirstChildWhichIsA("BasePart")
						if anyPart then
							local distance = GetHorizontalDistance(anyPart.Position, coinPos)
							if distance < COLLECT_DISTANCE then
								print("[Coin] Collecting (via anyPart)!")
								PowerUpService.CollectCoin(coin, checkPlayer)
								return
							end
						end
					end
				end
			end

			task.wait(0.05)
		end
	end)
end

-- Collect power-up
function PowerUpService.CollectPowerUp(powerUp: BasePart, player: Player)
	local data = activePowerUps[powerUp]
	if not data then return end

	local playerData = GameState.players[player.UserId]
	if not playerData or not playerData.isAlive then return end

	-- Remove from tracking
	activePowerUps[powerUp] = nil

	-- Apply effect
	GameState.ApplyPowerUp(playerData, data.type)

	-- Notify client
	PowerUpCollected:FireClient(player, data.type)
	SyncPlayerData:FireClient(player, playerData)

	-- Collection effect
	local tween = TweenService:Create(powerUp, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = Vector3.new(0.1, 0.1, 0.1),
		Transparency = 1
	})
	tween:Play()
	tween.Completed:Connect(function()
		powerUp:Destroy()
	end)
end

-- Collect coin
function PowerUpService.CollectCoin(coin: Instance, player: Player)
	local data = activeCoins[coin]
	if not data then return end

	local playerData = GameState.players[player.UserId]
	if not playerData or not playerData.isAlive then return end

	-- Remove from tracking
	activeCoins[coin] = nil

	-- Add coin
	playerData.coins = playerData.coins + 1

	-- Notify client
	PowerUpCollected:FireClient(player, "COIN")
	SyncPlayerData:FireClient(player, playerData)

	-- Check for coin grab mode win
	if GameState.currentMode.collectCoins and playerData.coins >= (GameState.currentMode.coinTarget or 10) then
		-- This player wins!
		-- RoundSystem will handle this via periodic checks
	end

	-- Collection effect - animate all parts
	local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)

	if coin:IsA("BasePart") then
		local tween = TweenService:Create(coin, tweenInfo, {
			Size = Vector3.new(0.1, 0.1, 0.1),
			Transparency = 1
		})
		tween:Play()
		tween.Completed:Connect(function()
			coin:Destroy()
		end)
	elseif coin:IsA("Model") then
		local firstPart = true
		for _, part in ipairs(coin:GetDescendants()) do
			if part:IsA("BasePart") then
				local tween = TweenService:Create(part, tweenInfo, {
					Size = part.Size * 0.1,
					Transparency = 1
				})
				tween:Play()
				if firstPart then
					tween.Completed:Connect(function()
						coin:Destroy()
					end)
					firstPart = false
				end
			end
		end
	else
		coin:Destroy()
	end
end

-- Clear all power-ups
function PowerUpService.ClearAllPowerUps()
	for powerUp, _ in pairs(activePowerUps) do
		if powerUp and powerUp.Parent then
			powerUp:Destroy()
		end
	end
	activePowerUps = {}

	for coin, _ in pairs(activeCoins) do
		if coin and coin.Parent then
			coin:Destroy()
		end
	end
	activeCoins = {}
end

-- Spawn initial coins for Coin Grab mode
function PowerUpService.SpawnInitialCoins(count: number)
	local spawned = 0
	local attempts = 0
	local maxAttempts = 200

	while spawned < count and attempts < maxAttempts do
		attempts = attempts + 1

		local x = math.random(1, Constants.GRID_WIDTH)
		local y = math.random(1, Constants.GRID_HEIGHT)

		if MapData.IsWalkable(x, y) and not MapData.IsSpawnCorner(x, y) then
			PowerUpService.SpawnCoin(x, y)
			spawned = spawned + 1
		end
	end

	print("[PowerUpService] Spawned " .. spawned .. " initial coins")
end

return PowerUpService
