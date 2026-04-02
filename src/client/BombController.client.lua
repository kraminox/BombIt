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

-- Handle player death effects
PlayerDied.OnClientEvent:Connect(function(userId: number)
	local targetPlayer = Players:GetPlayerByUserId(userId)
	if not targetPlayer then return end

	local character = targetPlayer.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Create poof effect
	local poofPart = Instance.new("Part")
	poofPart.Size = Vector3.new(1, 1, 1)
	poofPart.Position = hrp.Position
	poofPart.Anchored = true
	poofPart.CanCollide = false
	poofPart.Transparency = 1
	poofPart.Parent = Workspace

	-- Particle emitter for poof
	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(Color3.fromRGB(255, 200, 200))
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(1, 0)
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1)
	})
	particles.Lifetime = NumberRange.new(0.5, 0.8)
	particles.Rate = 0
	particles.Speed = NumberRange.new(5, 10)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Parent = poofPart

	particles:Emit(30)

	task.delay(1, function()
		poofPart:Destroy()
	end)
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
print("[BombController] VFX and sound system initialized")
