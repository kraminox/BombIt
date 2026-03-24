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

-- Wait for remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged")
local PlayerDied = Remotes:WaitForChild("PlayerDied")

-- Camera settings
local CAMERA_HEIGHT = 22 -- Height above player
local CAMERA_DISTANCE = 18 -- Distance behind player (more tilt to see character)
local CAMERA_FOV = 50 -- More zoomed in

-- Camera state
local cameraMode = "lobby"
local spectateTarget: Player? = nil

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
local function UpdateCamera()
	if cameraMode == "lobby" then
		camera.CameraType = Enum.CameraType.Custom
		return
	end

	if cameraMode == "countdown" or cameraMode == "gameplay" then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = CAMERA_FOV

		-- Follow the player's character with tilted view
		local character = player.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local targetPos = hrp.Position
				-- Camera positioned above and behind (offset on Z axis for tilt)
				local cameraPos = targetPos + Vector3.new(0, CAMERA_HEIGHT, CAMERA_DISTANCE)
				camera.CFrame = CFrame.lookAt(cameraPos, targetPos)
			end
		end
		return
	end

	if cameraMode == "spectate" then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = CAMERA_FOV

		-- Follow spectate target or arena center
		local targetPos = GetArenaCenter()
		if spectateTarget and spectateTarget.Character then
			local hrp = spectateTarget.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				targetPos = hrp.Position
			end
		end
		local cameraPos = targetPos + Vector3.new(0, CAMERA_HEIGHT, CAMERA_DISTANCE)
		camera.CFrame = CFrame.lookAt(cameraPos, targetPos)
		return
	end

	if cameraMode == "winners" then
		-- Camera looking at podium
		local podiumCenter = Vector3.new(0, 4, 50)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(podiumCenter + Vector3.new(0, 8, 25), podiumCenter)
		camera.FieldOfView = 50
		return
	end
end

-- State changes
RoundStateChanged.OnClientEvent:Connect(function(state: string, data: any?)
	if state == Constants.STATES.LOBBY then
		cameraMode = "lobby"
		camera.CameraType = Enum.CameraType.Custom
		RemoveArrow()
		-- Reset camera subject to local player
		if player.Character then
			camera.CameraSubject = player.Character:FindFirstChild("Humanoid")
		end
	elseif state == Constants.STATES.COUNTDOWN then
		cameraMode = "countdown"
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
		RemoveArrow()
	end
end)

-- Player death
PlayerDied.OnClientEvent:Connect(function(userId: number)
	if userId == player.UserId then
		cameraMode = "spectate"
		spectateTarget = FindNearestAlivePlayer()
		RemoveArrow()
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

-- Initialize
RunService.RenderStepped:Connect(UpdateCamera)
print("[CameraController] Bird's eye camera with arrow indicator initialized")
