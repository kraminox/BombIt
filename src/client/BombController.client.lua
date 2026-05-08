--!strict
-- BombController.client.lua
-- Client-side bomb VFX, sounds, and effects

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local BombSkins = require(Shared:WaitForChild("BombSkins"))

-- Wait for remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AdminEvent = Remotes:WaitForChild("AdminEvent")
local PlayerDied = Remotes:WaitForChild("PlayerDied")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged")

-- Sound cache
local sounds = {} :: {[string]: Sound}

-- Create sounds
local function CreateSound(name: string, soundId: string): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Volume = 0.25 -- Lighter sound effects
	sound.Parent = SoundService
	sounds[name] = sound
	return sound
end

-- Initialize sounds
local function InitializeSounds()
	CreateSound("Explosion", Constants.SOUNDS.EXPLOSION)
	CreateSound("PowerUp", Constants.SOUNDS.POWERUP)
	CreateSound("PlaceBomb", Constants.SOUNDS.PLACE_BOMB)
	CreateSound("Countdown", Constants.SOUNDS.COUNTDOWN)
	CreateSound("Win", Constants.SOUNDS.WIN)
end

-- Play sound at position (3D sound)
local function PlaySoundAt(soundName: string, position: Vector3)
	local templateSound = sounds[soundName]
	if not templateSound then return end

	-- Create temporary sound at position
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = position
	part.Parent = Workspace

	local sound = templateSound:Clone()
	sound.Parent = part
	sound:Play()

	-- Clean up after sound finishes
	sound.Ended:Connect(function()
		part:Destroy()
	end)

	-- Fallback cleanup
	task.delay(5, function()
		if part.Parent then
			part:Destroy()
		end
	end)
end

-- Play UI sound (2D)
local function PlayUISound(soundName: string)
	local sound = sounds[soundName]
	if sound then
		sound:Play()
	end
end

-- Camera shake effect (defined before use)
local function CameraShake(intensity: number, duration: number)
	local camera = Workspace.CurrentCamera
	if not camera then return end

	local startTime = tick()

	local connection
	connection = game:GetService("RunService").RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		if elapsed > duration then
			connection:Disconnect()
			return
		end

		local progress = elapsed / duration
		local currentIntensity = intensity * (1 - progress) -- Fade out

		local offsetX = (math.random() - 0.5) * 2 * currentIntensity
		local offsetY = (math.random() - 0.5) * 2 * currentIntensity

		-- Apply small random offset to camera
		camera.CFrame = camera.CFrame * CFrame.new(offsetX, offsetY, 0)
	end)
end

-- Watch for bombs being added (server handles placement sound)
local function OnBombAdded(bomb: Instance)
	if not bomb:IsA("Model") then return end
end

-- Watch for explosions (explosion parts)
local function OnExplosionAdded(explosion: Instance)
	if not explosion:IsA("BasePart") then return end
	if explosion.Name ~= "Explosion" then return end

	-- Play explosion sound
	PlaySoundAt("Explosion", explosion.Position)

	-- Camera shake
	local character = player.Character
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local distance = (hrp.Position - explosion.Position).Magnitude
			if distance < 30 then
				-- Shake intensity based on distance
				local intensity = math.clamp(1 - distance / 30, 0.1, 1) * 0.3
				CameraShake(intensity, 0.2)
			end
		end
	end
end

-- Black fade transition screen
local function CreateDeathFade()
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DeathFade"
	screenGui.DisplayOrder = 100
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	return screenGui, frame
end

local deathFadeGui, deathFadeFrame = CreateDeathFade()

local function PlayDeathFade()
	deathFadeFrame.BackgroundTransparency = 1
	-- Fade to black
	local fadeIn = TweenService:Create(deathFadeFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 0,
	})
	fadeIn:Play()

	-- Hold black, then fade out
	task.delay(1, function()
		local fadeOut = TweenService:Create(deathFadeFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		})
		fadeOut:Play()
	end)
end

-- Play ragdoll crumble death VFX on a character
local function PlayDeathVFX(character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Dark charred highlight while crumbling
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(20, 20, 20)
	highlight.FillTransparency = 0
	highlight.OutlineColor = Color3.fromRGB(50, 50, 50)
	highlight.OutlineTransparency = 0.3
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character

	-- Hide any existing highlights
	for _, child in ipairs(character:GetDescendants()) do
		if child:IsA("Highlight") and child ~= highlight then
			child.Enabled = false
		end
	end

	-- Collect all visible body parts to shrink (skip HumanoidRootPart)
	local bodyParts: {BasePart} = {}
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			table.insert(bodyParts, part)
		end
	end

	-- Shrink body parts with staggered timing for cascading crumble
	for _, part in ipairs(bodyParts) do
		local delay_ = 0.15 + math.random() * 0.4 -- 0.15s to 0.55s stagger
		task.delay(delay_, function()
			if not part or not part.Parent then return end

			local tweenInfo = TweenInfo.new(
				0.3 + math.random() * 0.25, -- 0.3-0.55s shrink duration
				Enum.EasingStyle.Back,
				Enum.EasingDirection.In
			)

			TweenService:Create(part, tweenInfo, {
				Size = part.Size * 0.02,
				Transparency = 0.9,
			}):Play()
		end)
	end

	-- Fade highlight as parts crumble away
	task.delay(0.4, function()
		if highlight and highlight.Parent then
			TweenService:Create(highlight, TweenInfo.new(0.6), {
				FillTransparency = 1,
				OutlineTransparency = 1,
			}):Play()
		end
	end)

	-- Dust/crumble particles at death position
	local dustPart = Instance.new("Part")
	dustPart.Size = Vector3.new(1, 1, 1)
	dustPart.Position = hrp.Position
	dustPart.Anchored = true
	dustPart.CanCollide = false
	dustPart.Transparency = 1
	dustPart.Parent = Workspace

	-- Dust cloud
	local dust = Instance.new("ParticleEmitter")
	dust.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 170, 150)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 95, 85)),
	})
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.5, 1.5),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.5, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Lifetime = NumberRange.new(0.6, 1.2)
	dust.Rate = 0
	dust.Speed = NumberRange.new(2, 6)
	dust.SpreadAngle = Vector2.new(120, 120)
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-40, 40)
	dust.Parent = dustPart
	dust:Emit(18)

	-- Small debris chunks that fall
	local debris = Instance.new("ParticleEmitter")
	debris.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 55, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 28, 25)),
	})
	debris.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	debris.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	debris.Lifetime = NumberRange.new(0.4, 0.8)
	debris.Rate = 0
	debris.Speed = NumberRange.new(5, 12)
	debris.SpreadAngle = Vector2.new(60, 60)
	debris.EmissionDirection = Enum.NormalId.Top
	debris.Acceleration = Vector3.new(0, -30, 0) -- Gravity pull on debris
	debris.Parent = dustPart
	debris:Emit(25)

	-- Faint embers from the explosion
	local embers = Instance.new("ParticleEmitter")
	embers.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 140, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 40, 10)),
	})
	embers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(1, 0),
	})
	embers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	embers.Lifetime = NumberRange.new(0.3, 0.7)
	embers.Rate = 0
	embers.Speed = NumberRange.new(3, 8)
	embers.SpreadAngle = Vector2.new(90, 90)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Parent = dustPart
	embers:Emit(12)

	-- Clean up particle anchor after effects finish
	task.delay(2.5, function()
		if dustPart and dustPart.Parent then
			dustPart:Destroy()
		end
	end)
end

-- Handle player death
PlayerDied.OnClientEvent:Connect(function(userId: number)
	local targetPlayer = Players:GetPlayerByUserId(userId)
	if not targetPlayer then return end

	local character = targetPlayer.Character
	if not character then return end

	-- Play charred death VFX for all players (including local)
	PlayDeathVFX(character)
end)

-- Handle admin events
AdminEvent.OnClientEvent:Connect(function(eventId: string)
	if eventId == "MAP_BREAK" then
		-- Big camera shake
		CameraShake(1, 0.5)
		PlayUISound("Explosion")

	elseif eventId == "COIN_RAIN" then
		-- Coin rain visual (coins handled by server, just add some sparkle)
		task.spawn(function()
			for _ = 1, 10 do
				PlayUISound("PowerUp")
				task.wait(0.3)
			end
		end)

	elseif eventId == "BOMB_PARTY" then
		-- Visual indicator
		local screenGui = player:WaitForChild("PlayerGui"):FindFirstChild("GameUI")
		if screenGui then
			local indicator = Instance.new("TextLabel")
			indicator.Size = UDim2.new(1, 0, 0, 50)
			indicator.Position = UDim2.new(0, 0, 0.1, 0)
			indicator.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
			indicator.BackgroundTransparency = 0.3
			indicator.Text = "🎉 BOMB PARTY! 🎉"
			indicator.TextColor3 = Color3.new(1, 1, 1)
			indicator.TextSize = 30
			indicator.Font = Enum.Font.GothamBold
			indicator.Parent = screenGui

			task.delay(10, function()
				indicator:Destroy()
			end)
		end

	elseif eventId == "SPEED_GOD" then
		local screenGui = player:WaitForChild("PlayerGui"):FindFirstChild("GameUI")
		if screenGui then
			local indicator = Instance.new("TextLabel")
			indicator.Size = UDim2.new(1, 0, 0, 50)
			indicator.Position = UDim2.new(0, 0, 0.1, 0)
			indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 100)
			indicator.BackgroundTransparency = 0.3
			indicator.Text = "⚡ SPEED GOD! ⚡"
			indicator.TextColor3 = Color3.new(0, 0, 0)
			indicator.TextSize = 30
			indicator.Font = Enum.Font.GothamBold
			indicator.Parent = screenGui

			task.delay(10, function()
				indicator:Destroy()
			end)
		end
	end
end)

-- Monitor for bombs being added
CollectionService:GetInstanceAddedSignal("Bomb"):Connect(OnBombAdded)

-- Swap BOMB_UP powerup model to show the local player's equipped skin
local SyncInventory = Remotes:WaitForChild("SyncInventory", 10)
local equippedSkinId = "default_bomb"

-- Forward-declare so it can be referenced in the SyncInventory callback below
local SwapBombUpModel

-- Track equipped skin from inventory syncs
if not SyncInventory then
	warn("[BombController] SyncInventory remote not found")
end

if SyncInventory then
	SyncInventory.OnClientEvent:Connect(function(inv)
		if inv and inv.equippedSkin and inv.equippedSkin ~= "" then
			local oldSkin = equippedSkinId
			equippedSkinId = inv.equippedSkin

			-- If the skin just changed (e.g. first sync or player equipped a new skin),
			-- re-swap any existing BOMB_UP powerups in the arena
			if oldSkin ~= equippedSkinId and SwapBombUpModel then
				for _, instance in ipairs(CollectionService:GetTagged("PowerUp")) do
					if instance.Name == "PowerUp_BOMB_UP" and instance.Parent then
						SwapBombUpModel(instance)
					end
				end
			end
		end
	end)
end

-- Replace a BOMB_UP powerup model with the player's equipped skin visually
SwapBombUpModel = function(powerUp: Instance)
	-- Skip swap if using default skin or no skin equipped
	if equippedSkinId == "default_bomb" or equippedSkinId == "" then return end

	local skinData = BombSkins.GetSkinById(equippedSkinId)
	if not skinData then return end

	-- If the skin uses the same model as Default Bomb, no visual swap needed
	if skinData.modelName == "Default Bomb" then return end

	local skinModel = BombSkins.GetSkinModel(skinData)
	if not skinModel then return end

	-- Check if this powerup was already swapped (avoid double-swapping)
	if powerUp:GetAttribute("SkinSwapped") then return end
	powerUp:SetAttribute("SkinSwapped", true)

	local clone = skinModel:Clone()

	-- Get the existing PrimaryPart (server animates this)
	local existingPrimary = powerUp:IsA("Model") and (powerUp.PrimaryPart or powerUp:FindFirstChildWhichIsA("BasePart")) or nil
	if not existingPrimary then
		clone:Destroy()
		return
	end

	-- Hide all existing parts (don't destroy -- server still animates PrimaryPart)
	for _, child in ipairs(powerUp:GetDescendants()) do
		if child:IsA("BasePart") then
			child.Transparency = 1
		elseif child:IsA("ParticleEmitter") then
			child.Enabled = false
		elseif child:IsA("Light") then
			child.Enabled = false
		end
	end

	-- Position the clone at the existing primary's location
	if clone:IsA("Model") then
		local clonePrimary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
		if clonePrimary then
			clone:SetPrimaryPartCFrame(existingPrimary.CFrame)
		end

		-- Weld all skin parts to the existing PrimaryPart so they follow the server animation
		for _, part in ipairs(clone:GetDescendants()) do
			if part:IsA("BasePart") then
				local offset = existingPrimary.CFrame:ToObjectSpace(part.CFrame)
				part.Anchored = false
				part.CanCollide = false
				part.Massless = true

				local weld = Instance.new("Weld")
				weld.Part0 = existingPrimary
				weld.Part1 = part
				weld.C0 = offset
				weld.Parent = part

				part.Parent = powerUp
			end
		end
	end

	clone:Destroy()
end

-- Watch for BOMB_UP powerups spawning
CollectionService:GetInstanceAddedSignal("PowerUp"):Connect(function(instance)
	if instance.Name == "PowerUp_BOMB_UP" then
		SwapBombUpModel(instance)
	end
end)

-- Also swap any existing BOMB_UP powerups
for _, instance in ipairs(CollectionService:GetTagged("PowerUp")) do
	if instance.Name == "PowerUp_BOMB_UP" then
		SwapBombUpModel(instance)
	end
end

-- Monitor for explosions
local arenaFolder = Workspace:WaitForChild("Arena", 10)
if arenaFolder then
	arenaFolder.ChildAdded:Connect(function(child)
		if child.Name == "Explosion" then
			OnExplosionAdded(child)
		end
	end)
end

-- Also watch the workspace directly for explosions
Workspace.DescendantAdded:Connect(function(descendant)
	if descendant.Name == "Explosion" and descendant:IsA("BasePart") then
		OnExplosionAdded(descendant)
	end
end)

-- Handle explosion VFX particle emission (server :Emit() doesn't replicate)
local function OnExplosionVFX(vfx: Instance)
	-- Emit all particle emitters client-side
	for _, emitter in ipairs(vfx:GetDescendants()) do
		if emitter:IsA("ParticleEmitter") then
			if emitter.Rate > 0 then
				emitter.Enabled = true
			end
			local burst = emitter:GetAttribute("EmitCount") or 20
			emitter:Emit(burst)
		end
	end

	-- Also trigger sound + camera shake
	if vfx:IsA("BasePart") then
		OnExplosionAdded(vfx)
	elseif vfx:IsA("Model") and vfx.PrimaryPart then
		OnExplosionAdded(vfx.PrimaryPart)
	end

	-- Disable emitters after burst
	task.delay(0.5, function()
		if vfx and vfx.Parent then
			for _, emitter in ipairs(vfx:GetDescendants()) do
				if emitter:IsA("ParticleEmitter") then
					emitter.Enabled = false
				end
			end
		end
	end)
end

CollectionService:GetInstanceAddedSignal("ExplosionVFX"):Connect(OnExplosionVFX)
for _, vfx in ipairs(CollectionService:GetTagged("ExplosionVFX")) do
	OnExplosionVFX(vfx)
end

-- Initialize
InitializeSounds()

-- Preload all assets so first rounds don't have delays
task.spawn(function()
	local ContentProvider = game:GetService("ContentProvider")
	local assetsToPreload = {}

	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if assetsFolder then
		for _, descendant in ipairs(assetsFolder:GetDescendants()) do
			if descendant:IsA("Sound") or descendant:IsA("Animation") or descendant:IsA("Decal")
				or descendant:IsA("Texture") or descendant:IsA("ParticleEmitter")
				or descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
				table.insert(assetsToPreload, descendant)
			end
		end
	end

	if #assetsToPreload > 0 then
		pcall(function()
			ContentProvider:PreloadAsync(assetsToPreload)
		end)
		print("[BombController] Preloaded " .. #assetsToPreload .. " assets")
	end
end)

-- Handle round end fade to lobby transition
RoundStateChanged.OnClientEvent:Connect(function(eventType: string, data: any?)
	if eventType == "FadeToLobby" then
		PlayDeathFade()
	end
end)

print("[BombController] VFX and sound system initialized")
