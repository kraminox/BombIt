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

-- Watch for bomb explosions
local function OnBombAdded(bomb: Instance)
	if not bomb:IsA("Model") then return end

	-- Play place sound
	local sphere = bomb:FindFirstChild("Sphere") :: BasePart?
	if sphere then
		PlaySoundAt("PlaceBomb", sphere.Position)
	end
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

-- Play charred death VFX on a character
local function PlayDeathVFX(character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Blackout highlight (charred silhouette)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(15, 15, 15)
	highlight.FillTransparency = 0
	highlight.OutlineColor = Color3.fromRGB(40, 40, 40)
	highlight.OutlineTransparency = 0.3
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character

	-- Hide any existing highlights
	for _, child in ipairs(character:GetDescendants()) do
		if child:IsA("Highlight") and child ~= highlight then
			child.Enabled = false
		end
	end

	-- Ash emitter anchored at death position
	local ashPart = Instance.new("Part")
	ashPart.Size = Vector3.new(1, 1, 1)
	ashPart.Position = hrp.Position
	ashPart.Anchored = true
	ashPart.CanCollide = false
	ashPart.Transparency = 1
	ashPart.Parent = Workspace

	-- Rising ash/ember particles
	local ash = Instance.new("ParticleEmitter")
	ash.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 60, 60)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(40, 40, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 20, 20)),
	})
	ash.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.3, 0.8),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	ash.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.6, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	ash.Lifetime = NumberRange.new(1, 2)
	ash.Rate = 0
	ash.Speed = NumberRange.new(2, 6)
	ash.SpreadAngle = Vector2.new(40, 40)
	ash.EmissionDirection = Enum.NormalId.Top
	ash.Rotation = NumberRange.new(0, 360)
	ash.RotSpeed = NumberRange.new(-60, 60)
	ash.Parent = ashPart
	ash:Emit(25)

	-- Smoke puff
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 80, 80)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 30, 30)),
	})
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 3),
		NumberSequenceKeypoint.new(1, 4),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.4, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.6, 1.2)
	smoke.Rate = 0
	smoke.Speed = NumberRange.new(3, 8)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Parent = ashPart
	smoke:Emit(15)

	-- Embers
	local embers = Instance.new("ParticleEmitter")
	embers.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 140, 40)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 80, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 40, 10)),
	})
	embers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 0),
	})
	embers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	embers.Lifetime = NumberRange.new(0.4, 1)
	embers.Rate = 0
	embers.Speed = NumberRange.new(4, 12)
	embers.SpreadAngle = Vector2.new(120, 120)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Parent = ashPart
	embers:Emit(20)

	-- Fade highlight
	task.delay(1, function()
		if highlight and highlight.Parent then
			TweenService:Create(highlight, TweenInfo.new(0.5), {
				FillTransparency = 0.5,
				OutlineTransparency = 0.8,
			}):Play()
		end
	end)

	-- Cleanup
	task.delay(2.5, function()
		if ashPart and ashPart.Parent then
			ashPart:Destroy()
		end
		if highlight and highlight.Parent then
			highlight:Destroy()
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

-- Initialize
InitializeSounds()
-- Handle round end fade to lobby transition
RoundStateChanged.OnClientEvent:Connect(function(eventType: string, data: any?)
	if eventType == "FadeToLobby" then
		PlayDeathFade()
	end
end)

print("[BombController] VFX and sound system initialized")
