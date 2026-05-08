--!strict
-- CameraController.client.lua
-- Bird's eye view camera during gameplay with bouncing arrow indicator

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local MapData = require(Shared:WaitForChild("MapData"))

-- Initialize grid CFrame from Canvas (client-side)
local function InitializeGridFromCanvas()
	local canvasPart = Workspace:FindFirstChild("Canvas") :: BasePart?
	if canvasPart then
		local canvasCFrame = canvasPart.CFrame
		local canvasSize = canvasPart.Size

		-- Grid origin is at corner of canvas in local space, then transformed to world space
		local localCorner = Vector3.new(-canvasSize.X / 2, canvasSize.Y / 2, -canvasSize.Z / 2)
		local worldCorner = canvasCFrame:PointToWorldSpace(localCorner)

		-- Create the grid CFrame: position at corner, rotation from canvas
		local gridCFrame = CFrame.new(worldCorner) * (canvasCFrame - canvasCFrame.Position)
		MapData.SetGridCFrame(gridCFrame)
	end
end

-- Initialize grid on load
InitializeGridFromCanvas()

-- Wait for remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged")
local PlayerDied = Remotes:WaitForChild("PlayerDied")
local ColorBattleSync = Remotes:WaitForChild("ColorBattleSync", 10)

-- Camera settings (base values)
local BASE_CAMERA_HEIGHT = 22 -- Height above player
local BASE_CAMERA_DISTANCE = 18 -- Distance behind player (more tilt to see character)
local CAMERA_FOV = 50 -- More zoomed in

-- AFK state: read from BoolValue created by AFKToggle
local isAFK = false

-- Camera state
local cameraMode = "lobby"
local spectateTarget: Player? = nil
local winnerCharacter: Model? = nil
local cinematicStartTime = 0
local cinematicStartAngle = 0

-- Countdown cinematic state
local countdownStartTime = 0

-- Transition state (countdown_cinematic → gameplay)
local transitionStartTime = 0
local transitionDuration = 1.0
local transitionStartCFrame: CFrame? = nil

-- Arrow indicator (player self-arrow)
local arrowGui: BillboardGui? = nil
local arrowBounceConnection: RBXScriptConnection? = nil

-- Enemy direction arrows
local ENEMY_ARROW_RADIUS = 3.5 -- Studs from player center
local ENEMY_ARROW_LERP_SPEED = 15 -- Higher = snappier interpolation
local ENEMY_ARROW_FAR_COLOR = Color3.fromRGB(255, 255, 255) -- White when far
local ENEMY_ARROW_CLOSE_COLOR = Color3.fromRGB(255, 40, 40) -- Red when close
local TEAMMATE_ARROW_COLOR = Color3.fromRGB(100, 230, 120) -- Lighter green for teammates (matches nameplate)
local ENEMY_ARROW_MAX_DIST = 30 -- Distance at which arrow is fully "far" color
local ENEMY_ARROW_MIN_DIST = 5 -- Distance at which arrow is fully "close" color
local enemyArrowParts: {[Player]: Part} = {}
local enemyArrowsActive = false

-- Team tracking (updated when round state changes)
local currentTeamSize = 1
local colorAssignments: {[number]: number} = {} -- userId -> colorIndex
local teamAssignments: {[number]: number} = {} -- userId -> teamIndex

-- Load arrow icon from Assets/UI
local Assets = ReplicatedStorage:WaitForChild("Assets")
local UIAssets = Assets:WaitForChild("UI")
local ArrowIconAsset = UIAssets:WaitForChild("ArrowIcon")
local arrowIconImage = if ArrowIconAsset:IsA("ImageLabel") then ArrowIconAsset.Image else ""

-- Get arena center (from Canvas part)
local function GetArenaCenter(): Vector3
	local canvas = Workspace:FindFirstChild("Canvas")
	if canvas and canvas:IsA("BasePart") then
		return canvas.Position
	end
	-- Fallback to grid-based calculation
	local centerX = (Constants.GRID_WIDTH * Constants.TILE_SIZE) / 2
	local centerZ = (Constants.GRID_HEIGHT * Constants.TILE_SIZE) / 2
	return Vector3.new(centerX, 0, centerZ)
end

-- Create bouncing arrow indicator
local function CreateArrowIndicator()
	if arrowGui then return end

	arrowGui = Instance.new("BillboardGui")
	arrowGui.Name = "PlayerArrow"
	arrowGui.Size = UDim2.new(0, 40, 0, 50)
	arrowGui.StudsOffset = Vector3.new(0, 5, 0)
	arrowGui.AlwaysOnTop = true
	arrowGui.MaxDistance = 200

	-- Arrow image (using text as fallback)
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.Size = UDim2.new(1, 0, 1, 0)
	arrow.BackgroundTransparency = 1
	arrow.Text = "▼"
	arrow.TextColor3 = Color3.fromRGB(0, 255, 100)
	arrow.TextScaled = true
	arrow.Font = Enum.Font.GothamBold
	arrow.Parent = arrowGui

	-- Add stroke for visibility
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 2
	stroke.Parent = arrow

	return arrowGui
end

-- Start bouncing animation
local function StartArrowBounce()
	if arrowBounceConnection then
		arrowBounceConnection:Disconnect()
	end

	local startTime = tick()
	arrowBounceConnection = RunService.Heartbeat:Connect(function()
		if arrowGui then
			-- Bounce between 4 and 6 studs above player
			local bounce = math.sin((tick() - startTime) * 5) * 1
			arrowGui.StudsOffset = Vector3.new(0, 5 + bounce, 0)
		end
	end)
end

-- Attach arrow to player
local function AttachArrowToPlayer()
	local character = player.Character
	if not character then return end

	local head = character:FindFirstChild("Head")
	if not head then return end

	if not arrowGui then
		CreateArrowIndicator()
	end

	if arrowGui then
		arrowGui.Adornee = head
		arrowGui.Parent = player.PlayerGui
		StartArrowBounce()
	end
end

-- Remove arrow
local function RemoveArrow()
	if arrowBounceConnection then
		arrowBounceConnection:Disconnect()
		arrowBounceConnection = nil
	end
	if arrowGui then
		arrowGui.Parent = nil
	end
end

-- Find nearest alive player for spectating
local function FindNearestAlivePlayer(): Player?
	local myPos = GetArenaCenter()
	local character = player.Character
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			myPos = hrp.Position
		end
	end

	local nearestPlayer: Player? = nil
	local nearestDistance = math.huge

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player and otherPlayer.Character then
			-- Only consider players in the arena (have PlayerStats)
			local hasPlayerStats = otherPlayer.Character:FindFirstChild("PlayerStats") ~= nil
			local humanoid = otherPlayer.Character:FindFirstChild("Humanoid") :: Humanoid?
			if hasPlayerStats and humanoid and humanoid.Health > 0 then
				local hrp = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local distance = (hrp.Position - myPos).Magnitude
					if distance < nearestDistance then
						nearestDistance = distance
						nearestPlayer = otherPlayer
					end
				end
			end
		end
	end

	return nearestPlayer
end

-- Create an enemy direction arrow part + billboard
local function CreateEnemyArrow(): Part
	local part = Instance.new("Part")
	part.Name = "EnemyArrow"
	part.Size = Vector3.new(0.5, 0.5, 0.5)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ArrowBillboard"
	billboard.Size = UDim2.new(0, 40, 0, 40)
	billboard.StudsOffset = Vector3.new(0, 0, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 200
	billboard.Parent = part

	-- Arrow icon from Assets/UI
	local arrowLabel = Instance.new("ImageLabel")
	arrowLabel.Name = "ArrowImage"
	arrowLabel.Size = UDim2.new(1, 0, 1, 0)
	arrowLabel.BackgroundTransparency = 1
	arrowLabel.Image = arrowIconImage
	arrowLabel.ScaleType = Enum.ScaleType.Fit
	arrowLabel.Parent = billboard

	return part
end

-- Get or create an arrow for a specific enemy player
local function GetEnemyArrow(enemyPlayer: Player): Part
	if not enemyArrowParts[enemyPlayer] then
		enemyArrowParts[enemyPlayer] = CreateEnemyArrow()
	end
	return enemyArrowParts[enemyPlayer]
end

-- Remove arrow for a specific player
local function RemoveEnemyArrow(enemyPlayer: Player)
	if enemyArrowParts[enemyPlayer] then
		enemyArrowParts[enemyPlayer]:Destroy()
		enemyArrowParts[enemyPlayer] = nil
	end
end

-- Remove all enemy arrows
local function RemoveAllEnemyArrows()
	for enemyPlayer, part in pairs(enemyArrowParts) do
		part:Destroy()
	end
	enemyArrowParts = {}
	enemyArrowsActive = false
end

-- Update enemy arrow positions and rotations
local function UpdateEnemyArrows(dt: number)
	if not enemyArrowsActive then return end

	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local myPos = hrp.Position
	local lerpAlpha = math.clamp(ENEMY_ARROW_LERP_SPEED * dt, 0, 1)

	-- Track which enemies are alive
	local aliveEnemies: {[Player]: boolean} = {}

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player and otherPlayer.Character then
			-- Only show arrows for players in the arena (have PlayerStats from SetupArenaCharacter)
			local hasPlayerStats = otherPlayer.Character:FindFirstChild("PlayerStats") ~= nil
			local humanoid = otherPlayer.Character:FindFirstChild("Humanoid") :: Humanoid?
			if hasPlayerStats and humanoid and humanoid.Health > 0 then
				local otherHrp = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
				if otherHrp then
					aliveEnemies[otherPlayer] = true

					-- Calculate direction on the XZ plane
					local direction = (otherHrp.Position - myPos)
					local flatDir = Vector3.new(direction.X, 0, direction.Z)
					local dist = flatDir.Magnitude
					if dist < 0.1 then continue end
					flatDir = flatDir.Unit

					-- Target position for arrow
					local targetPos = myPos + flatDir * ENEMY_ARROW_RADIUS + Vector3.new(0, 1, 0)

					-- Lerp position for smooth movement
					local arrowPart = GetEnemyArrow(otherPlayer)
					arrowPart.Position = arrowPart.Position:Lerp(targetPos, lerpAlpha)

					-- Calculate rotation angle for the arrow image
					local angle = math.atan2(flatDir.X, flatDir.Z)

					-- Get camera's forward direction (flattened) to calculate screen-relative rotation
					local camLook = camera.CFrame.LookVector
					local camAngle = math.atan2(camLook.X, camLook.Z)

					-- Relative angle = world angle - camera angle
					local relativeAngle = angle - camAngle
					local rotationDeg = math.deg(relativeAngle)

					-- Check if teammate (same teamIndex in team modes)
					local isTeammate = false
					if currentTeamSize > 1 then
						local myTeam = teamAssignments[player.UserId]
						local theirTeam = teamAssignments[otherPlayer.UserId]
						if myTeam and theirTeam and myTeam == theirTeam then
							isTeammate = true
						end
					end

					-- Color: green for teammates, red-white gradient for enemies
					local arrowColor
					if isTeammate then
						arrowColor = TEAMMATE_ARROW_COLOR
					else
						local distFactor = math.clamp((dist - ENEMY_ARROW_MIN_DIST) / (ENEMY_ARROW_MAX_DIST - ENEMY_ARROW_MIN_DIST), 0, 1)
						arrowColor = ENEMY_ARROW_CLOSE_COLOR:Lerp(ENEMY_ARROW_FAR_COLOR, distFactor)
					end

					-- Apply rotation and color to the arrow image inside the billboard
					local billboard = arrowPart:FindFirstChild("ArrowBillboard")
					if billboard then
						local arrowImage = billboard:FindFirstChild("ArrowImage")
						if arrowImage then
							arrowImage.Rotation = -rotationDeg
							arrowImage.ImageColor3 = arrowColor
						end
					end
				end
			end
		end
	end

	-- Remove arrows for dead/gone enemies
	for enemyPlayer, _ in pairs(enemyArrowParts) do
		if not aliveEnemies[enemyPlayer] then
			RemoveEnemyArrow(enemyPlayer)
		end
	end
end

-- Update camera based on mode
local function UpdateCamera(deltaTime: number?)
	if cameraMode == "lobby" then
		camera.CameraType = Enum.CameraType.Custom
		return
	end

	if cameraMode == "preparing" then
		-- Hold camera still during round preparation (screen is blacked out)
		camera.CameraType = Enum.CameraType.Scriptable
		return
	end

	-- Apply zoom level to camera distance
	local zoomedHeight = BASE_CAMERA_HEIGHT
	local zoomedDistance = BASE_CAMERA_DISTANCE

	if cameraMode == "countdown" or cameraMode == "gameplay" or cameraMode == "transition_to_gameplay" then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = CAMERA_FOV

		-- Compute the target overhead gameplay CFrame
		local targetGameplayCFrame: CFrame? = nil
		local character = player.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local targetPos = hrp.Position
				local canvas = Workspace:FindFirstChild("Canvas")
				if canvas and canvas:IsA("BasePart") then
					local rawBehind = -canvas.CFrame.LookVector
					local behindDir = Vector3.new(rawBehind.X, 0, rawBehind.Z)
					if behindDir.Magnitude > 0 then behindDir = behindDir.Unit end
					local cameraPos = targetPos + Vector3.new(0, zoomedHeight, 0) + behindDir * zoomedDistance
					targetGameplayCFrame = CFrame.lookAt(cameraPos, targetPos, canvas.CFrame.LookVector)
				else
					local cameraPos = targetPos + Vector3.new(0, zoomedHeight, zoomedDistance)
					targetGameplayCFrame = CFrame.lookAt(cameraPos, targetPos)
				end
			end
		end

		if cameraMode == "transition_to_gameplay" then
			-- Smoothly lerp from the orbit camera to the gameplay overhead camera
			local elapsed = tick() - transitionStartTime
			local alpha = math.clamp(elapsed / transitionDuration, 0, 1)
			-- Ease-out cubic for smooth deceleration
			alpha = 1 - (1 - alpha) ^ 3

			if targetGameplayCFrame and transitionStartCFrame then
				camera.CFrame = transitionStartCFrame:Lerp(targetGameplayCFrame, alpha)
				-- Lerp FOV from cinematic (45) to gameplay
				camera.FieldOfView = 45 + (CAMERA_FOV - 45) * alpha
			end

			if alpha >= 1 then
				cameraMode = "gameplay"
			end
		elseif targetGameplayCFrame then
			camera.CFrame = targetGameplayCFrame
		end
		return
	end

	if cameraMode == "spectate" then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = CAMERA_FOV

		-- Follow spectate target or arena center with grid-aligned view
		local targetPos = GetArenaCenter()
		if spectateTarget and spectateTarget.Character then
			local hrp = spectateTarget.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				targetPos = hrp.Position
			end
		end

		-- Use Canvas CFrame directly to align camera with the grid
		local canvas = Workspace:FindFirstChild("Canvas")
		if canvas and canvas:IsA("BasePart") then
			-- Flatten to horizontal so canvas tilt doesn't push camera vertically
			local rawBehind = -canvas.CFrame.LookVector
			local behindDir = Vector3.new(rawBehind.X, 0, rawBehind.Z)
			if behindDir.Magnitude > 0 then behindDir = behindDir.Unit end
			local cameraPos = targetPos + Vector3.new(0, zoomedHeight, 0) + behindDir * zoomedDistance
			camera.CFrame = CFrame.lookAt(cameraPos, targetPos, canvas.CFrame.LookVector)
		else
			local cameraPos = targetPos + Vector3.new(0, zoomedHeight, zoomedDistance)
			camera.CFrame = CFrame.lookAt(cameraPos, targetPos)
		end
		return
	end

	if cameraMode == "countdown_cinematic" then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 45

		-- Slow orbit around the local player's character
		local character = player.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local targetPos = hrp.Position + Vector3.new(0, 1.5, 0)
				local elapsed = tick() - countdownStartTime
				local orbitSpeed = 0.4 -- Slow orbit
				local orbitRadius = 10
				local orbitHeight = 6
				local angle = cinematicStartAngle + elapsed * orbitSpeed

				local cameraPos = targetPos + Vector3.new(
					math.cos(angle) * orbitRadius,
					orbitHeight,
					math.sin(angle) * orbitRadius
				)

				camera.CFrame = CFrame.lookAt(cameraPos, targetPos)
			end
		else
			-- Fallback: overview of arena
			local arenaCenter = GetArenaCenter()
			camera.CFrame = CFrame.lookAt(arenaCenter + Vector3.new(0, 25, 18), arenaCenter)
		end
		return
	end

	if cameraMode == "winner_cinematic" then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 40

		-- Orbit the winner's character at player height
		if winnerCharacter and winnerCharacter.Parent then
			local hrp = winnerCharacter:FindFirstChild("HumanoidRootPart")
			if hrp then
				local targetPos = hrp.Position + Vector3.new(0, 1.5, 0) -- Look at upper chest/head
				local elapsed = tick() - cinematicStartTime
				local orbitSpeed = 0.3 -- Slow orbit
				local orbitRadius = 8
				local angle = cinematicStartAngle + elapsed * orbitSpeed

				local cameraPos = targetPos + Vector3.new(
					math.cos(angle) * orbitRadius,
					0, -- Same height as target, no elevation
					math.sin(angle) * orbitRadius
				)

				camera.CFrame = CFrame.lookAt(cameraPos, targetPos)
			end
		else
			-- Fallback: no winner character found, use arena center overhead
			local arenaCenter = GetArenaCenter()
			camera.CFrame = CFrame.lookAt(arenaCenter + Vector3.new(0, 20, 15), arenaCenter)
		end
		return
	end

end

-- State changes
-- Track color assignments for team detection
if ColorBattleSync then
	ColorBattleSync.OnClientEvent:Connect(function(action: string, assignData: any?)
		if action == "AssignColors" and type(assignData) == "table" then
			colorAssignments = {}
			for k, v in pairs(assignData) do
				colorAssignments[tonumber(k) or k] = v
			end
		elseif action == "AssignTeams" and type(assignData) == "table" then
			-- Remote tables may have string keys; normalize to number keys
			teamAssignments = {}
			for k, v in pairs(assignData) do
				teamAssignments[tonumber(k) or k] = v
			end
		end
	end)
end

RoundStateChanged.OnClientEvent:Connect(function(state: string, data: any?)
	-- Track team size from mode data
	if data and type(data) == "table" and data.mode then
		currentTeamSize = data.mode.teamSize or 1
	end

	-- AFK players stay on lobby camera during game states
	if isAFK and (state == "Preparing" or state == Constants.STATES.COUNTDOWN or state == "Countdown" or state == Constants.STATES.PLAYING) then
		cameraMode = "lobby"
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
		RemoveArrow()
		RemoveAllEnemyArrows()
		return
	end

	if state == "Preparing" then
		-- Lock camera during round preparation so respawn/teleport is hidden
		cameraMode = "preparing"
		camera.CameraType = Enum.CameraType.Scriptable
		RemoveArrow()
		RemoveAllEnemyArrows()
	elseif state == Constants.STATES.LOBBY then
		cameraMode = "lobby"
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
		RemoveArrow()
		RemoveAllEnemyArrows()
		-- Remove any leftover blur effects from UIs that didn't clean up
		for _, child in ipairs(Lighting:GetChildren()) do
			if child:IsA("BlurEffect") then
				child:Destroy()
			end
		end
		-- Reset camera subject to local player
		if player.Character then
			camera.CameraSubject = player.Character:FindFirstChild("Humanoid")
		end
	elseif state == Constants.STATES.COUNTDOWN then
		-- Only initialize orbit once (countdown ticks also send "Countdown")
		if cameraMode ~= "countdown_cinematic" then
			cameraMode = "countdown_cinematic"
			countdownStartTime = tick()
			-- Start orbit from in front of the local player
			local character = player.Character
			if character then
				local hrp = character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local lookDir = hrp.CFrame.LookVector
					cinematicStartAngle = math.atan2(lookDir.Z, lookDir.X)
				end
			end
			RemoveArrow()
			RemoveAllEnemyArrows()
		end
	elseif state == Constants.STATES.PLAYING then
		-- Smooth transition from countdown orbit to gameplay overhead
		if cameraMode == "countdown_cinematic" then
			transitionStartCFrame = camera.CFrame
			transitionStartTime = tick()
			cameraMode = "transition_to_gameplay"
		else
			cameraMode = "gameplay"
		end
		AttachArrowToPlayer()
		enemyArrowsActive = true
	elseif state == "RoundResults" then
		RemoveArrow()
		RemoveAllEnemyArrows()
		-- Find the winner's character for cinematic camera
		winnerCharacter = nil
		if data and data.winnerId and data.winnerId ~= 0 then
			local winnerPlayer = Players:GetPlayerByUserId(data.winnerId)
			if winnerPlayer and winnerPlayer.Character then
				winnerCharacter = winnerPlayer.Character
			end
		end
		-- Brief delay so winner emote animation replicates before camera switches
		task.delay(0.5, function()
			cinematicStartTime = tick()
			-- Calculate start angle so camera begins in front of the winner
			if winnerCharacter then
				local hrp = winnerCharacter:FindFirstChild("HumanoidRootPart")
				if hrp then
					local lookDir = hrp.CFrame.LookVector
					cinematicStartAngle = math.atan2(lookDir.Z, lookDir.X)
				else
					cinematicStartAngle = 0
				end
			else
				cinematicStartAngle = 0
			end
			cameraMode = "winner_cinematic"
		end)
	elseif state == "FadeToLobby" then
		winnerCharacter = nil
		-- If we were in freecam (dead), transition to lobby so CharacterAdded
		-- doesn't accidentally restore gameplay camera when we spawn in lobby
		if cameraMode == "freecam" then
			cameraMode = "lobby"
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70
		end
	elseif state == Constants.STATES.INTERMISSION then
		cameraMode = "lobby"
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
		RemoveArrow()
		RemoveAllEnemyArrows()
		-- Remove any leftover blur effects
		for _, child in ipairs(Lighting:GetChildren()) do
			if child:IsA("BlurEffect") then
				child:Destroy()
			end
		end
	end
end)

-- Player death
PlayerDied.OnClientEvent:Connect(function(userId: number)
	if userId == player.UserId then
		-- Reset to normal camera with no restrictions
		cameraMode = "freecam"
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70 -- Default FOV
		RemoveArrow()
		RemoveAllEnemyArrows()

		-- Reset camera subject to player's character for free movement
		if player.Character then
			local humanoid = player.Character:FindFirstChild("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
				-- Reset movement to normal
				humanoid.WalkSpeed = 18
				humanoid.JumpPower = 50
				humanoid.JumpHeight = 7.2
			end
		end
	elseif cameraMode == "spectate" and spectateTarget and spectateTarget.UserId == userId then
		spectateTarget = FindNearestAlivePlayer()
	end
end)

-- Character respawn
player.CharacterAdded:Connect(function(character)
	if cameraMode == "spectate" then
		cameraMode = "gameplay"
		spectateTarget = nil
	elseif cameraMode == "freecam" then
		-- Player respawned in respawn mode — restore top-down camera
		cameraMode = "gameplay"
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = CAMERA_FOV
	end

	-- Attach arrow when character loads
	task.wait(0.5) -- Wait for character to fully load
	if cameraMode == "gameplay" or cameraMode == "countdown" then
		AttachArrowToPlayer()
		enemyArrowsActive = true
	end
end)


-- AFK state listener: when toggled AFK mid-game, snap to lobby camera
task.spawn(function()
	local afkVal = player:FindFirstChild("IsAFK") :: BoolValue?
	if not afkVal then
		afkVal = player:WaitForChild("IsAFK", 10) :: BoolValue?
	end
	if afkVal then
		isAFK = afkVal.Value
		afkVal.Changed:Connect(function(value: boolean)
			isAFK = value
			if isAFK then
				-- Force back to lobby camera immediately
				cameraMode = "lobby"
				camera.CameraType = Enum.CameraType.Custom
				camera.FieldOfView = 70
				RemoveArrow()
				RemoveAllEnemyArrows()
				if player.Character then
					camera.CameraSubject = player.Character:FindFirstChild("Humanoid")
				end
			end
		end)
	end
end)

-- Initialize
RunService.RenderStepped:Connect(function(deltaTime)
	UpdateCamera(deltaTime)
	UpdateEnemyArrows(deltaTime)
end)
print("[CameraController] Bird's eye camera with arrow indicator initialized")
