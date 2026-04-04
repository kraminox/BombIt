--!strict
-- CameraController.client.lua
-- Bird's eye view camera during gameplay with bouncing arrow indicator

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

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
local SyncPlayerData = Remotes:WaitForChild("SyncPlayerData")

-- Camera settings (base values)
local BASE_CAMERA_HEIGHT = 22 -- Height above player
local BASE_CAMERA_DISTANCE = 18 -- Distance behind player (more tilt to see character)
local CAMERA_FOV = 50 -- More zoomed in

-- Camera state
local cameraMode = "lobby"
local spectateTarget: Player? = nil
local currentZoomLevel = 1.0 -- Zoom multiplier (higher = more zoomed out)
local targetZoomLevel = 1.0 -- Target for smooth interpolation
local ZOOM_LERP_SPEED = 3 -- How fast to animate zoom changes

-- Arrow indicator
local arrowGui: BillboardGui? = nil
local arrowBounceConnection: RBXScriptConnection? = nil

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
			local humanoid = otherPlayer.Character:FindFirstChild("Humanoid") :: Humanoid?
			if humanoid and humanoid.Health > 0 then
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

-- Update camera based on mode
local function UpdateCamera(deltaTime: number?)
	-- Smoothly interpolate zoom level towards target
	local dt = deltaTime or 0.016 -- Default to ~60fps if no deltaTime
	if currentZoomLevel ~= targetZoomLevel then
		local diff = targetZoomLevel - currentZoomLevel
		local step = diff * math.min(1, ZOOM_LERP_SPEED * dt)
		currentZoomLevel = currentZoomLevel + step

		-- Snap if very close
		if math.abs(targetZoomLevel - currentZoomLevel) < 0.001 then
			currentZoomLevel = targetZoomLevel
		end
	end

	if cameraMode == "lobby" then
		camera.CameraType = Enum.CameraType.Custom
		return
	end

	-- Apply zoom level to camera distance
	local zoomedHeight = BASE_CAMERA_HEIGHT * currentZoomLevel
	local zoomedDistance = BASE_CAMERA_DISTANCE * currentZoomLevel

	if cameraMode == "countdown" or cameraMode == "gameplay" then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = CAMERA_FOV

		-- Follow the player's character with overhead tilted view aligned to canvas rotation
		local character = player.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local targetPos = hrp.Position

				-- Use Canvas CFrame directly to align camera with the grid
				local canvas = Workspace:FindFirstChild("Canvas")
				if canvas and canvas:IsA("BasePart") then
					-- Canvas.LookVector is the direction the canvas faces (-Z in canvas local)
					-- Position camera: above player, offset in canvas's +Z direction (behind)
					-- Flatten to horizontal so canvas tilt doesn't push camera vertically
					local rawBehind = -canvas.CFrame.LookVector
					local behindDir = Vector3.new(rawBehind.X, 0, rawBehind.Z)
					if behindDir.Magnitude > 0 then behindDir = behindDir.Unit end
					local cameraPos = targetPos + Vector3.new(0, zoomedHeight, 0) + behindDir * zoomedDistance

					-- Use canvas's LookVector as up so grid edges align with screen edges
					camera.CFrame = CFrame.lookAt(cameraPos, targetPos, canvas.CFrame.LookVector)
				else
					-- Fallback if canvas not found
					local cameraPos = targetPos + Vector3.new(0, zoomedHeight, zoomedDistance)
					camera.CFrame = CFrame.lookAt(cameraPos, targetPos)
				end
			end
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

	if cameraMode == "winners" then
		-- Camera looking at podium (capturing all 3 positions with 1st place centered)
		-- 1st place is at Y=9, 2nd at Y=7, 3rd at Y=5 - look at center height
		local podiumCenter = Vector3.new(0, 7, 50)
		camera.CameraType = Enum.CameraType.Scriptable
		-- Position camera higher and further back to capture tall 1st place podium
		camera.CFrame = CFrame.lookAt(podiumCenter + Vector3.new(0, 6, 28), podiumCenter)
		camera.FieldOfView = 55
		return
	end
end

-- State changes
RoundStateChanged.OnClientEvent:Connect(function(state: string, data: any?)
	if state == Constants.STATES.LOBBY then
		cameraMode = "lobby"
		camera.CameraType = Enum.CameraType.Custom
		currentZoomLevel = 1.0 -- Reset zoom instantly
		targetZoomLevel = 1.0
		RemoveArrow()
		-- Reset camera subject to local player
		if player.Character then
			camera.CameraSubject = player.Character:FindFirstChild("Humanoid")
		end
	elseif state == Constants.STATES.COUNTDOWN then
		cameraMode = "countdown"
		currentZoomLevel = 1.0 -- Reset zoom instantly for new round
		targetZoomLevel = 1.0
		AttachArrowToPlayer()
	elseif state == Constants.STATES.PLAYING then
		cameraMode = "gameplay"
		AttachArrowToPlayer()
	elseif state == Constants.STATES.ROUND_END or state == "RoundResults" then
		cameraMode = "winners"
		RemoveArrow()
	elseif state == Constants.STATES.INTERMISSION then
		cameraMode = "lobby"
		camera.CameraType = Enum.CameraType.Custom
		currentZoomLevel = 1.0 -- Reset zoom instantly
		targetZoomLevel = 1.0
		RemoveArrow()
	end
end)

-- Player death
PlayerDied.OnClientEvent:Connect(function(userId: number)
	if userId == player.UserId then
		-- Reset to normal camera with no restrictions
		cameraMode = "freecam"
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70 -- Default FOV
		currentZoomLevel = 1.0
		targetZoomLevel = 1.0
		RemoveArrow()

		-- Reset camera subject to player's character for free movement
		if player.Character then
			local humanoid = player.Character:FindFirstChild("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
				-- Reset movement to normal
				humanoid.WalkSpeed = 16
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
	end

	-- Attach arrow when character loads
	task.wait(0.5) -- Wait for character to fully load
	if cameraMode == "gameplay" or cameraMode == "countdown" then
		AttachArrowToPlayer()
	end
end)

-- Listen for player data sync (for zoom level)
SyncPlayerData.OnClientEvent:Connect(function(data)
	if data and data.zoomLevel then
		targetZoomLevel = data.zoomLevel
	end
end)

-- Initialize
RunService.RenderStepped:Connect(function(deltaTime)
	UpdateCamera(deltaTime)
end)
print("[CameraController] Bird's eye camera with arrow indicator initialized")
