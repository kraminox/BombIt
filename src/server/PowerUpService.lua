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

local Debris = game:GetService("Debris")

local PowerUpService = {}

-- Active power-ups tracking
local activePowerUps = {} :: {[Instance]: {type: string, gridX: number, gridY: number}}
local activeCoins = {} :: {[Instance]: {gridX: number, gridY: number}}

-- Model templates
local coinTemplate: Instance? = nil
local powerUpTemplates = {} :: {[string]: Instance}

-- Sound effects
local SoundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
local SoundVFXFolder = SoundsFolder and SoundsFolder:FindFirstChild("VFX")
local ItemSound = SoundVFXFolder and SoundVFXFolder:FindFirstChild("Item")
local CoinSound = SoundVFXFolder and SoundVFXFolder:FindFirstChild("Coin")

-- Power-up type weights for random selection (bombs and range more common)
local powerUpWeights = {
	{type = "BOMB_UP", weight = 35},
	{type = "FIRE_UP", weight = 35},
	{type = "SPEED_UP", weight = 20},
	{type = "ZOOM_OUT", weight = 10},
}

local totalWeight = 0
for _, entry in ipairs(powerUpWeights) do
	totalWeight = totalWeight + entry.weight
end

function PowerUpService.Initialize()
	-- Load coin template from ReplicatedStorage/Assets/Misc/Coin
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local miscFolder = assetsFolder and assetsFolder:FindFirstChild("Misc")
	coinTemplate = miscFolder and miscFolder:FindFirstChild("Coin")

	if coinTemplate then
		print("[PowerUpService] Found Coin template")
	else
		warn("[PowerUpService] Coin not found in ReplicatedStorage/Assets/Misc, using fallback")
	end

	-- Load powerup mesh templates from ReplicatedStorage/Assets/Powerups
	local powerupsFolder = assetsFolder and assetsFolder:FindFirstChild("Powerups")

	if powerupsFolder then
		for powerUpType, data in pairs(Constants.POWERUP_TYPES) do
			local meshName = data.mesh
			local template = powerupsFolder:FindFirstChild(meshName)
			if template then
				powerUpTemplates[powerUpType] = template
				print("[PowerUpService] Loaded powerup template:", meshName, "for", powerUpType)
			else
				warn("[PowerUpService] Missing powerup template:", meshName)
			end
		end
	else
		warn("[PowerUpService] Powerups folder not found at ReplicatedStorage/Assets/Powerups")
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


-- Create power-up visual model from mesh template
local function CreatePowerUpModel(powerUpType: string): Instance?
	local template = powerUpTemplates[powerUpType]
	if not template then
		warn("[PowerUpService] No template for powerup type:", powerUpType)
		return nil
	end

	local powerUp = template:Clone()
	powerUp.Name = "PowerUp_" .. powerUpType

	-- Setup the cloned model
	if powerUp:IsA("BasePart") then
		powerUp.Anchored = true
		powerUp.CanCollide = false
	elseif powerUp:IsA("Model") then
		for _, part in ipairs(powerUp:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
			end
		end
	end

	-- Add glow effect
	local mainPart = powerUp:IsA("BasePart") and powerUp or powerUp:FindFirstChildWhichIsA("BasePart")
	if mainPart then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 255, 200) -- Warm glow
		light.Brightness = 1.5
		light.Range = 6
		light.Parent = mainPart
	end

	CollectionService:AddTag(powerUp, "PowerUp")

	return powerUp
end

-- Create coin model (uses Coin from ReplicatedStorage/Assets/Misc)
local function CreateCoinModel(): Instance
	if coinTemplate then
		local coin = coinTemplate:Clone()
		coin.Name = "Coin"

		-- Setup the cloned coin - ensure anchored and no collision
		if coin:IsA("BasePart") then
			coin.Anchored = true
			coin.CanCollide = false
		elseif coin:IsA("Model") then
			for _, part in ipairs(coin:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
					part.CanCollide = false
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
		return coin
	end

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
	if not powerUp then return end

	-- Position the powerup (higher for better visibility)
	local spawnPos = worldPos + Vector3.new(0, 3, 0)
	if powerUp:IsA("BasePart") then
		powerUp.CFrame = CFrame.new(spawnPos)
	elseif powerUp:IsA("Model") then
		local primary = powerUp.PrimaryPart or powerUp:FindFirstChildWhichIsA("BasePart")
		if primary then
			powerUp:SetPrimaryPartCFrame(CFrame.new(spawnPos))
		end
	end

	powerUp.Parent = arenaFolder

	-- Store reference
	activePowerUps[powerUp] = {
		type = powerUpType,
		gridX = gridX,
		gridY = gridY,
	}

	-- Bouncing and spinning animation
	task.spawn(function()
		local startY = spawnPos.Y
		local startTime = tick()
		local bounceHeight = 0.5
		local bounceSpeed = 3

		while powerUp and powerUp.Parent do
			-- Calculate bounce offset
			local elapsed = tick() - startTime
			local bounceOffset = math.sin(elapsed * bounceSpeed) * bounceHeight

			if powerUp:IsA("BasePart") then
				local currentPos = powerUp.Position
				powerUp.CFrame = CFrame.new(currentPos.X, startY + bounceOffset, currentPos.Z) * CFrame.Angles(0, math.rad(elapsed * 90), 0)
			elseif powerUp:IsA("Model") then
				local primary = powerUp.PrimaryPart or powerUp:FindFirstChildWhichIsA("BasePart")
				if primary then
					local currentPos = primary.Position
					powerUp:SetPrimaryPartCFrame(CFrame.new(currentPos.X, startY + bounceOffset, currentPos.Z) * CFrame.Angles(0, math.rad(elapsed * 90), 0))
				end
			end
			task.wait()
		end
	end)

	-- Use proximity-based collection
	local COLLECT_DISTANCE = 4

	-- Helper to get horizontal distance (XZ plane only)
	local function GetHorizontalDistance(pos1: Vector3, pos2: Vector3): number
		local dx = pos1.X - pos2.X
		local dz = pos1.Z - pos2.Z
		return math.sqrt(dx * dx + dz * dz)
	end

	task.spawn(function()
		while powerUp and powerUp.Parent do
			-- Get powerup position
			local powerUpPos
			if powerUp:IsA("BasePart") then
				powerUpPos = powerUp.Position
			elseif powerUp:IsA("Model") then
				local primary = powerUp.PrimaryPart or powerUp:FindFirstChildWhichIsA("BasePart")
				if primary then
					powerUpPos = primary.Position
				end
			end

			if powerUpPos then
				for _, checkPlayer in ipairs(Players:GetPlayers()) do
					local character = checkPlayer.Character
					if character then
						local hrp = character:FindFirstChild("HumanoidRootPart")
						if hrp and hrp:IsA("BasePart") then
							local distance = GetHorizontalDistance(hrp.Position, powerUpPos)
							if distance < COLLECT_DISTANCE then
								PowerUpService.CollectPowerUp(powerUp, checkPlayer)
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

-- Spawn coin at grid position
function PowerUpService.SpawnCoin(gridX: number, gridY: number)
	local arenaFolder = Workspace:FindFirstChild("Arena")
	if not arenaFolder then
		warn("[PowerUpService] No Arena folder!")
		return
	end

	local worldPos = MapData.GridToWorld(gridX, gridY)

	local coin = CreateCoinModel()

	-- Position the coin higher for better visibility
	local coinPos = worldPos + Vector3.new(0, 3, 0)

	if coin:IsA("BasePart") then
		coin.CFrame = CFrame.new(coinPos)
	elseif coin:IsA("Model") then
		local primary = coin.PrimaryPart or coin:FindFirstChildWhichIsA("BasePart")
		if primary then
			coin:SetPrimaryPartCFrame(CFrame.new(coinPos))
		end
	end

	coin.Parent = arenaFolder

	-- Store reference
	activeCoins[coin] = {
		gridX = gridX,
		gridY = gridY,
	}

	-- Bouncing and spinning animation
	task.spawn(function()
		local startY = coinPos.Y
		local startTime = tick()
		local bounceHeight = 0.5
		local bounceSpeed = 3

		while coin and coin.Parent do
			-- Calculate bounce offset
			local elapsed = tick() - startTime
			local bounceOffset = math.sin(elapsed * bounceSpeed) * bounceHeight

			if coin:IsA("BasePart") then
				local currentPos = coin.Position
				coin.CFrame = CFrame.new(currentPos.X, startY + bounceOffset, currentPos.Z) * CFrame.Angles(0, math.rad(elapsed * 90), 0)
			elseif coin:IsA("Model") then
				local primary = coin.PrimaryPart or coin:FindFirstChildWhichIsA("BasePart")
				if primary then
					local currentPos = primary.Position
					coin:SetPrimaryPartCFrame(CFrame.new(currentPos.X, startY + bounceOffset, currentPos.Z) * CFrame.Angles(0, math.rad(elapsed * 90), 0))
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
function PowerUpService.CollectPowerUp(powerUp: Instance, player: Player)
	local data = activePowerUps[powerUp]
	if not data then return end

	local playerData = GameState.players[player.UserId]
	if not playerData or not playerData.isAlive then return end

	-- Remove from tracking
	activePowerUps[powerUp] = nil

	-- Apply effect
	GameState.ApplyPowerUp(playerData, data.type)

	-- Get position for sound before destroying
	local soundPos = MapData.GridToWorld(data.gridX, data.gridY)

	-- Play item pickup sound on a separate part (so it doesn't get cut off)
	if ItemSound then
		local arenaFolder = Workspace:FindFirstChild("Arena")
		if arenaFolder then
			local soundPart = Instance.new("Part")
			soundPart.Anchored = true
			soundPart.CanCollide = false
			soundPart.Transparency = 1
			soundPart.Size = Vector3.new(1, 1, 1)
			soundPart.Position = soundPos + Vector3.new(0, 1, 0)
			soundPart.Parent = arenaFolder

			local sound = ItemSound:Clone()
			sound.Parent = soundPart
			sound:Play()
			Debris:AddItem(soundPart, sound.TimeLength + 0.5)
		end
	end

	-- Notify client
	PowerUpCollected:FireClient(player, data.type)
	SyncPlayerData:FireClient(player, playerData)

	-- Update character stats for nameplate UI
	local character = player.Character
	if character then
		local statsFolder = character:FindFirstChild("PlayerStats")
		if statsFolder then
			local bombCount = statsFolder:FindFirstChild("BombCount")
			if bombCount then bombCount.Value = playerData.bombCount end

			local bombRange = statsFolder:FindFirstChild("BombRange")
			if bombRange then bombRange.Value = playerData.bombRange end

			local speed = statsFolder:FindFirstChild("Speed")
			if speed then speed.Value = playerData.speed end
		end
	end

	-- Collection effect - animate all parts
	local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)

	if powerUp:IsA("BasePart") then
		local tween = TweenService:Create(powerUp, tweenInfo, {
			Size = Vector3.new(0.1, 0.1, 0.1),
			Transparency = 1
		})
		tween:Play()
		tween.Completed:Connect(function()
			powerUp:Destroy()
		end)
	elseif powerUp:IsA("Model") then
		local firstPart = true
		for _, part in ipairs(powerUp:GetDescendants()) do
			if part:IsA("BasePart") then
				local tween = TweenService:Create(part, tweenInfo, {
					Size = part.Size * 0.1,
					Transparency = 1
				})
				tween:Play()
				if firstPart then
					tween.Completed:Connect(function()
						powerUp:Destroy()
					end)
					firstPart = false
				end
			end
		end
	else
		powerUp:Destroy()
	end
end

-- Collect coin
function PowerUpService.CollectCoin(coin: Instance, player: Player)
	local data = activeCoins[coin]
	if not data then return end

	local playerData = GameState.players[player.UserId]
	if not playerData or not playerData.isAlive then return end

	-- Remove from tracking
	activeCoins[coin] = nil

	-- Get position for sound before destroying
	local soundPos = MapData.GridToWorld(data.gridX, data.gridY)

	-- Play coin pickup sound on a separate part (so it doesn't get cut off)
	local soundToPlay = CoinSound or ItemSound
	if soundToPlay then
		local arenaFolder = Workspace:FindFirstChild("Arena")
		if arenaFolder then
			local soundPart = Instance.new("Part")
			soundPart.Anchored = true
			soundPart.CanCollide = false
			soundPart.Transparency = 1
			soundPart.Size = Vector3.new(1, 1, 1)
			soundPart.Position = soundPos + Vector3.new(0, 1, 0)
			soundPart.Parent = arenaFolder

			local sound = soundToPlay:Clone()
			sound.Parent = soundPart
			sound:Play()
			Debris:AddItem(soundPart, sound.TimeLength + 0.5)
		end
	end

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
