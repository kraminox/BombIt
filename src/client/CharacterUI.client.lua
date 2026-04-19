--!strict
-- CharacterUI.client.lua
-- Controls the character customization screen viewport animations and buttons

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CharacterSelected = Remotes:WaitForChild("CharacterSelected")

-- Currently selected character (defaults to 1)
local selectedCharacterId = 1

-- Track which cosmetic groups are currently applied to the character
local appliedCosmetics: {[string]: boolean} = {}

-- Wait for the CharacterUI ScreenGui (built in Studio, lives in StarterGui)
local CharacterUI = playerGui:WaitForChild("CharacterUI") :: ScreenGui
local ParentFrame = CharacterUI:WaitForChild("ParentFrame")
local OuterFrame = ParentFrame:WaitForChild("OuterFrame")
local CharacterHolder = OuterFrame:WaitForChild("CharacterHolder")
local ViewportFrame = CharacterHolder:WaitForChild("ViewportFrame") :: ViewportFrame
local Character = ViewportFrame:WaitForChild("Character") :: Model

-- Assets holder and template for cosmetic items
local AssetsHolder = OuterFrame:WaitForChild("AssetsHolder")
local ViewTemplate = AssetsHolder:WaitForChild("ViewTemplate") :: ViewportFrame

-- Buttons
local CloseButton = OuterFrame:WaitForChild("CloseButton") :: GuiButton
local SaveChangesButton = OuterFrame:WaitForChild("SaveChangesButton") :: GuiButton
local NeverMindButton = OuterFrame:WaitForChild("NeverMindButton") :: GuiButton

-- Animation IDs
local ANIM_IDS = {
	idle = "rbxassetid://93531440131609",
	wave = "rbxassetid://507770239",
	jump = "rbxassetid://507765000",
}

-- Characters folder for switching character models
local CharactersFolder = ReplicatedStorage:WaitForChild("Characters")

-- Cosmetics root folder
local CosmeticsFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Cosmetics")

-- Module-level animation state (updated when character switches)
local idleTrack: AnimationTrack? = nil
local waveTrack: AnimationTrack? = nil
local jumpTrack: AnimationTrack? = nil

-- ViewportFrame requires a WorldModel for animations to play
local worldModel = ViewportFrame:FindFirstChildOfClass("WorldModel")
if not worldModel then
	worldModel = Instance.new("WorldModel")
	worldModel.Parent = ViewportFrame
end

-- ============================================================
-- Character Viewport Setup
-- ============================================================

-- Set up a character model in the viewport with animations
local function SetupViewportCharacter(newCharacter: Model)
	-- Stop old animations
	if idleTrack then idleTrack:Stop(0) end
	if waveTrack then waveTrack:Stop(0) end
	if jumpTrack then jumpTrack:Stop(0) end
	idleTrack = nil
	waveTrack = nil
	jumpTrack = nil

	-- Remove old character if different
	if Character and Character ~= newCharacter and Character.Parent then
		Character:Destroy()
	end

	Character = newCharacter
	Character.Parent = worldModel

	-- Remove AnimationController - it conflicts with Humanoid for joint ownership
	local animCtrl = Character:FindFirstChildOfClass("AnimationController")
	if animCtrl then animCtrl:Destroy() end

	-- Anchor HumanoidRootPart so character doesn't fall, unanchor everything else so joints can animate
	for _, part in ipairs(Character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = (part.Name == "HumanoidRootPart")
		end
	end

	-- Get or create Humanoid
	local humanoid = Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("[CharacterUI] No Humanoid found on viewport character")
		return
	end

	-- Get or create Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	task.wait() -- let engine process changes before loading animations

	-- Load all animations
	local loadedTracks: {[string]: AnimationTrack} = {}
	for name, animId in pairs(ANIM_IDS) do
		local animation = Instance.new("Animation")
		animation.AnimationId = animId

		local success, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)

		if success and track then
			loadedTracks[name] = track
		else
			warn("[CharacterUI] Failed to load animation:", name)
		end
	end

	-- Configure and start tracks
	idleTrack = loadedTracks["idle"]
	if idleTrack then
		idleTrack.Looped = true
		idleTrack.Priority = Enum.AnimationPriority.Idle
		idleTrack:Play(0)
		idleTrack:AdjustSpeed(0.3)
	end

	waveTrack = loadedTracks["wave"]
	if waveTrack then
		waveTrack.Looped = false
		waveTrack.Priority = Enum.AnimationPriority.Action
	end

	jumpTrack = loadedTracks["jump"]
	if jumpTrack then
		jumpTrack.Looped = false
		jumpTrack.Priority = Enum.AnimationPriority.Action
	end
end

-- Manually attach an accessory to the character by welding the Handle
-- to the matching attachment point. Required because Humanoid:AddAccessory()
-- doesn't work inside ViewportFrames.
local function AttachAccessoryToCharacter(character: Model, accessory: Accessory)
	local handle = accessory:FindFirstChild("Handle") :: BasePart?
	if not handle then
		accessory.Parent = character
		return
	end

	-- Find an attachment inside the Handle
	local handleAttachment: Attachment? = nil
	for _, child in ipairs(handle:GetChildren()) do
		if child:IsA("Attachment") then
			handleAttachment = child :: Attachment
			break
		end
	end

	if not handleAttachment then
		accessory.Parent = character
		return
	end

	-- Find the matching attachment on the character's body parts
	local targetAttachment: Attachment? = nil
	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("Attachment") and desc.Name == handleAttachment.Name and desc.Parent:IsA("BasePart") then
			targetAttachment = desc :: Attachment
			break
		end
	end

	if not targetAttachment then
		accessory.Parent = character
		return
	end

	-- Weld the handle to the target body part
	-- Use Weld (not WeldConstraint) to match how Roblox internally attaches accessories
	local targetPart = targetAttachment.Parent :: BasePart
	handle.Anchored = false

	local weld = Instance.new("Weld")
	weld.Name = "AccessoryWeld"
	weld.Part0 = targetPart
	weld.Part1 = handle
	weld.C0 = targetAttachment.CFrame
	weld.C1 = handleAttachment.CFrame
	weld.Parent = handle

	accessory.Parent = character
end

-- Body parts to hide when matching cosmetics are equipped
local COSMETIC_HIDE_MAP = {
	Shoe = {"LeftFoot", "RightFoot"},
}

-- Apply all Outfit1 accessories to the viewport character
local function ApplyOutfitToCharacter(characterId: number)
	if not Character then return end

	-- Remove existing cosmetic accessories
	for _, child in ipairs(Character:GetChildren()) do
		if child:IsA("Accessory") and child:GetAttribute("CosmeticItem") then
			child:Destroy()
		end
	end

	-- Reset all hideable body parts to visible
	for _, partNames in pairs(COSMETIC_HIDE_MAP) do
		for _, partName in ipairs(partNames) do
			local part = Character:FindFirstChild(partName) :: BasePart?
			if part then
				part.Transparency = 0
			end
		end
	end

	local charData = Constants.CHARACTERS[characterId]
	if not charData then return end

	local charCosmeticsFolder = CosmeticsFolder:FindFirstChild(charData.cosmeticsFolder)
	if not charCosmeticsFolder then return end

	local outfitFolder = charCosmeticsFolder:FindFirstChild("Outfit1")
	if not outfitFolder then return end

	-- Check which body parts need hiding based on accessory names
	for _, accessory in ipairs(outfitFolder:GetChildren()) do
		if accessory:IsA("Accessory") then
			for keyword, partNames in pairs(COSMETIC_HIDE_MAP) do
				if string.find(accessory.Name, keyword) then
					for _, partName in ipairs(partNames) do
						local part = Character:FindFirstChild(partName) :: BasePart?
						if part then
							part.Transparency = 1
						end
					end
				end
			end
		end
	end

	for _, accessory in ipairs(outfitFolder:GetChildren()) do
		if accessory:IsA("Accessory") then
			local clone = accessory:Clone()
			clone:SetAttribute("CosmeticItem", true)
			AttachAccessoryToCharacter(Character, clone)
		end
	end
end

-- Switch the viewport character's outfit (rig stays the same, only accessories change)
local function SwitchCharacter(characterId: number)
	ApplyOutfitToCharacter(characterId)
end

-- Initial setup with the pre-placed character
SetupViewportCharacter(Character)
ApplyOutfitToCharacter(selectedCharacterId)

-- Random wave: play every 8-15 seconds
local waveRunning = true
task.spawn(function()
	while waveRunning do
		local delay = math.random(8, 15)
		task.wait(delay)
		if not waveRunning then break end
		if waveTrack and (not jumpTrack or not jumpTrack.IsPlaying) then
			waveTrack:Play(0.2)
		end
	end
end)

-- Jump on hover
ViewportFrame.MouseEnter:Connect(function()
	if jumpTrack and not jumpTrack.IsPlaying then
		jumpTrack:Play(0.1)
	end
end)

-- Button handlers
local function CloseUI()
	CharacterUI.Enabled = false
end

CloseButton.Activated:Connect(CloseUI)
NeverMindButton.Activated:Connect(CloseUI)

SaveChangesButton.Activated:Connect(function()
	-- Build list of equipped cosmetic names
	local equippedList: {string} = {}
	for cosmeticName, isApplied in pairs(appliedCosmetics) do
		if isApplied then
			table.insert(equippedList, cosmeticName)
		end
	end

	CharacterSelected:FireServer(selectedCharacterId, equippedList)
	CloseUI()
end)

-- ============================================================
-- Character Head Display
-- ============================================================

local CharactersHolder = OuterFrame:WaitForChild("CharactersHolder")
local HeadViewTemplate = CharactersHolder:WaitForChild("ViewFrameTemplate") :: ViewportFrame
local CharacterHeadsFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("CharacterHeads")

-- Hide the template
HeadViewTemplate.Visible = false

local HEAD_FOV = 30
local HEAD_PADDING = 1.6
local HEAD_HOVER_ZOOM = 0.9
local HEAD_HOVER_TIME = 0.25

-- Track head viewport cameras for hover zoom
type HeadEntry = {
	cam: Camera,
	faceNormal: Vector3,
	origin: Vector3,
	distanceValue: NumberValue,
}
local headEntries: {HeadEntry} = {}

-- Map character name -> viewport frame for selection highlighting
local headViewports: {[string]: ViewportFrame} = {}
local HEAD_SELECT_STROKE_COLOR = Color3.fromRGB(255, 200, 50)
local HEAD_SELECT_STROKE_THICKNESS = 3

-- Forward-declare LoadCosmetics so head click handlers can call it
local LoadCosmetics: (characterId: number) -> ()

-- Find the character ID that matches a head model name
-- Head models are named like "PinkHead", "BlueHead" etc. — match against character name
local function GetCharacterIdByName(name: string): number?
	for _, charData in ipairs(Constants.CHARACTERS) do
		if charData.name == name or charData.name .. "Head" == name then
			return charData.id
		end
	end
	return nil
end

-- Update selection stroke on all head viewports
local function UpdateHeadSelection()
	for charName, viewport in pairs(headViewports) do
		local stroke = viewport:FindFirstChild("HeadSelectStroke") :: UIStroke?
		if stroke then
			local charId = GetCharacterIdByName(charName)
			local isSelected = charId == selectedCharacterId
			stroke.Transparency = if isSelected then 0 else 1
		end
	end
end

for _, headModel in ipairs(CharacterHeadsFolder:GetChildren()) do
	if not headModel:IsA("Model") then continue end

	-- Clone the model
	local headClone = headModel:Clone()

	-- Anchor all parts
	for _, part in ipairs(headClone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	-- Find the Head part - try "Head" first, then PrimaryPart, then any BasePart with FrontFace
	local headPart = headClone:FindFirstChild("Head") :: BasePart?
	if not headPart and headClone.PrimaryPart then
		headPart = headClone.PrimaryPart
	end
	if not headPart then
		for _, desc in ipairs(headClone:GetDescendants()) do
			if desc:IsA("BasePart") and desc:FindFirstChild("FrontFace") then
				headPart = desc
				break
			end
		end
	end
	if not headPart then
		warn("[CharacterUI] No head part found in", headModel.Name)
		headClone:Destroy()
		continue
	end

	-- Transform all parts so Head ends up at identity CFrame (origin, no rotation)
	local headCF = headPart.CFrame
	local headInverse = headCF:Inverse()
	for _, part in ipairs(headClone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CFrame = headInverse * part.CFrame
		end
	end

	-- Determine camera direction from FrontFace decal
	local frontFace = headPart:FindFirstChild("FrontFace") :: Decal?
	local faceNormal = Vector3.new(0, 0, -1)
	if frontFace then
		local FACE_NORMALS_HEAD: {[Enum.NormalId]: Vector3} = {
			[Enum.NormalId.Front]  = Vector3.new(0, 0, -1),
			[Enum.NormalId.Back]   = Vector3.new(0, 0,  1),
			[Enum.NormalId.Left]   = Vector3.new(-1, 0, 0),
			[Enum.NormalId.Right]  = Vector3.new(1,  0, 0),
			[Enum.NormalId.Top]    = Vector3.new(0,  1, 0),
			[Enum.NormalId.Bottom] = Vector3.new(0, -1, 0),
		}
		faceNormal = FACE_NORMALS_HEAD[frontFace.Face] or Vector3.new(0, 0, -1)
	end

	-- Clone the template
	local viewClone = HeadViewTemplate:Clone()
	viewClone.Visible = true
	viewClone.Name = headModel.Name
	viewClone.Ambient = Color3.fromRGB(200, 200, 200)
	viewClone.LightDirection = Vector3.new(-1, -1, -1)

	-- Parent head into viewport
	headClone.Parent = viewClone

	-- Set up camera
	local cam = viewClone:FindFirstChildOfClass("Camera")
	if not cam then
		cam = Instance.new("Camera")
		cam.Parent = viewClone
	end
	viewClone.CurrentCamera = cam
	cam.FieldOfView = HEAD_FOV

	-- Calculate distance from bounding box
	local size = headPart.Size
	local maxExtent = math.max(size.X, size.Y, size.Z)
	local halfFovRad = math.rad(HEAD_FOV / 2)
	local distance = (maxExtent / 2) / math.tan(halfFovRad) * HEAD_PADDING
	local camDirection = faceNormal
	cam.CFrame = CFrame.lookAt(camDirection * distance, Vector3.zero)

	-- NumberValue for hover zoom tween
	local distanceValue = Instance.new("NumberValue")
	distanceValue.Value = distance

	distanceValue.Changed:Connect(function(newDist)
		cam.CFrame = CFrame.lookAt(camDirection * newDist, Vector3.zero)
	end)

	local hoverInfo = TweenInfo.new(HEAD_HOVER_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- Selection stroke on the viewport
	local selectStroke = Instance.new("UIStroke")
	selectStroke.Name = "HeadSelectStroke"
	selectStroke.Color = HEAD_SELECT_STROKE_COLOR
	selectStroke.Thickness = HEAD_SELECT_STROKE_THICKNESS
	selectStroke.Transparency = 1
	selectStroke.Parent = viewClone

	-- Wrap the viewport in a TextButton so clicks register
	local clickWrapper = Instance.new("TextButton")
	clickWrapper.Name = headModel.Name
	clickWrapper.Size = viewClone.Size
	clickWrapper.LayoutOrder = viewClone.LayoutOrder
	clickWrapper.BackgroundTransparency = 1
	clickWrapper.Text = ""
	clickWrapper.AutoButtonColor = false
	clickWrapper.Parent = CharactersHolder

	-- Re-parent viewport inside the wrapper, fill it
	viewClone.Size = UDim2.fromScale(1, 1)
	viewClone.Parent = clickWrapper

	-- Hover zoom on wrapper
	clickWrapper.MouseEnter:Connect(function()
		TweenService:Create(distanceValue, hoverInfo, {Value = distance * HEAD_HOVER_ZOOM}):Play()
	end)

	clickWrapper.MouseLeave:Connect(function()
		TweenService:Create(distanceValue, hoverInfo, {Value = distance}):Play()
	end)

	clickWrapper.Activated:Connect(function()
		local charId = GetCharacterIdByName(headModel.Name)
		if charId and charId ~= selectedCharacterId then
			selectedCharacterId = charId
			CharacterSelected:FireServer(charId)
			UpdateHeadSelection()
			SwitchCharacter(charId)
			LoadCosmetics(charId)
		end
	end)

	-- Track this viewport by head name
	headViewports[headModel.Name] = viewClone
end

-- Show initial selection
UpdateHeadSelection()

-- ============================================================
-- Cosmetic Item Display
-- ============================================================

-- Face normal lookup (local space)
local FACE_NORMALS: {[Enum.NormalId]: Vector3} = {
	[Enum.NormalId.Front]  = Vector3.new(0, 0, -1),
	[Enum.NormalId.Back]   = Vector3.new(0, 0,  1),
	[Enum.NormalId.Left]   = Vector3.new(-1, 0, 0),
	[Enum.NormalId.Right]  = Vector3.new(1,  0, 0),
	[Enum.NormalId.Top]    = Vector3.new(0,  1, 0),
	[Enum.NormalId.Bottom] = Vector3.new(0, -1, 0),
}

local CAMERA_FOV = 30
local CAMERA_PADDING = 1.3
local ROTATION_SPEED = 0.8 -- degrees per frame
local HOVER_ZOOM_FACTOR = 0.75 -- multiplier on distance when hovered (smaller = closer)
local HOVER_TWEEN_TIME = 0.25
local SELECT_STROKE_COLOR = Color3.fromRGB(255, 200, 50) -- golden yellow
local SELECT_STROKE_THICKNESS = 3

-- Hide the template
ViewTemplate.Visible = false

-- Track all spinning items for the render loop
type ItemEntry = {
	handles: {BasePart},
	cam: Camera,
	baseDistance: number,
	distanceValue: NumberValue, -- tweened for hover zoom
	faceNormal: Vector3,
	angle: number,
}
local itemEntries: {ItemEntry} = {}

-- Load cosmetics for a given character ID
-- Pairs Left/Right accessories together and displays them as one item
LoadCosmetics = function(characterId: number)
	-- Clear existing cosmetic viewports (everything except the template and layout objects)
	for _, child in ipairs(AssetsHolder:GetChildren()) do
		if child ~= ViewTemplate and not child:IsA("UILayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	itemEntries = {}
	appliedCosmetics = {}

	-- Get the character's cosmetics folder name
	local charData = Constants.CHARACTERS[characterId]
	if not charData then return end

	local charCosmeticsFolder = CosmeticsFolder:FindFirstChild(charData.cosmeticsFolder)
	if not charCosmeticsFolder then
		warn("[CharacterUI] Cosmetics folder not found:", charData.cosmeticsFolder)
		return
	end

	local outfitFolder = charCosmeticsFolder:FindFirstChild("Outfit1")
	if not outfitFolder then
		warn("[CharacterUI] Outfit1 folder not found in", charData.cosmeticsFolder)
		return
	end

	-- ── Pair Left/Right accessories ──
	-- "RightShoe" and "LeftShoe" share base name "Shoe" and get grouped together
	local pairMap: {[string]: {left: Accessory?, right: Accessory?}} = {}
	local pairOrder: {string} = {} -- maintain insertion order
	local standalone: {Accessory} = {}

	for _, accessory in ipairs(outfitFolder:GetChildren()) do
		if not accessory:IsA("Accessory") then continue end

		local name = accessory.Name
		if name:sub(1, 5) == "Right" then
			local baseName = name:sub(6)
			if not pairMap[baseName] then
				pairMap[baseName] = {}
				table.insert(pairOrder, baseName)
			end
			pairMap[baseName].right = accessory
		elseif name:sub(1, 4) == "Left" then
			local baseName = name:sub(5)
			if not pairMap[baseName] then
				pairMap[baseName] = {}
				table.insert(pairOrder, baseName)
			end
			pairMap[baseName].left = accessory
		else
			table.insert(standalone, accessory)
		end
	end

	-- Build display groups: each group has a name and a list of source accessories
	type DisplayGroup = { name: string, accessories: {Accessory} }
	local displayGroups: {DisplayGroup} = {}

	for _, baseName in ipairs(pairOrder) do
		local pair = pairMap[baseName]
		local accs: {Accessory} = {}
		if pair.left then table.insert(accs, pair.left) end
		if pair.right then table.insert(accs, pair.right) end
		table.insert(displayGroups, { name = baseName, accessories = accs })
	end

	for _, acc in ipairs(standalone) do
		table.insert(displayGroups, { name = acc.Name, accessories = { acc } })
	end

	-- ── Create viewport for each display group ──
	for _, group in ipairs(displayGroups) do
		-- All items start applied (Outfit1 was applied to character on switch)
		appliedCosmetics[group.name] = true

		-- Get handles from all accessories in the group
		local handles: {BasePart} = {}
		for _, acc in ipairs(group.accessories) do
			local handle = acc:FindFirstChild("Handle") :: MeshPart?
			if handle then table.insert(handles, handle) end
		end
		if #handles == 0 then continue end

		-- Clone handles and position them
		local handleClones: {BasePart} = {}
		for i, handle in ipairs(handles) do
			local clone = handle:Clone()
			for _, child in ipairs(clone:GetChildren()) do
				if child:IsA("Attachment") or child.Name == "OriginalSize" or child:IsA("TouchTransmitter") then
					child:Destroy()
				end
			end
			clone.Anchored = true

			if #handles == 1 then
				-- Single item centered
				clone.CFrame = CFrame.new(0, 0, 0)
				clone:SetAttribute("OriginalOffset", Vector3.new(0, 0, 0))
			else
				-- Paired items side by side
				local offset = if i == 1 then Vector3.new(-0.5, 0, 0) else Vector3.new(0.5, 0, 0)
				clone.CFrame = CFrame.new(offset)
				clone:SetAttribute("OriginalOffset", offset)
			end

			table.insert(handleClones, clone)
		end

		-- Use first handle for camera direction
		local primaryHandle = handleClones[1]
		local frontFace = primaryHandle:FindFirstChild("FrontFace") :: Decal?
		local faceNormal = Vector3.new(0, 0, -1) -- default to Front
		if frontFace then
			faceNormal = FACE_NORMALS[frontFace.Face] or Vector3.new(0, 0, -1)
		end

		-- Clone the ViewTemplate
		local viewClone = ViewTemplate:Clone()
		viewClone.Visible = true
		viewClone.Name = group.name
		viewClone.Ambient = Color3.fromRGB(180, 180, 180)
		viewClone.LightDirection = Vector3.new(-1, -2, -1)

		-- Parent all handles into viewport
		for _, clone in ipairs(handleClones) do
			clone.Parent = viewClone
		end

		-- Set up camera
		local cam = viewClone:FindFirstChildOfClass("Camera")
		if not cam then
			cam = Instance.new("Camera")
			cam.Parent = viewClone
		end
		viewClone.CurrentCamera = cam

		-- Calculate camera distance based on combined bounding box
		local totalSize = primaryHandle.Size
		if #handleClones > 1 then
			totalSize = Vector3.new(
				totalSize.X + 1.0, -- account for side-by-side offset
				math.max(totalSize.Y, handleClones[2].Size.Y),
				math.max(totalSize.Z, handleClones[2].Size.Z)
			)
		end
		local maxExtent = math.max(totalSize.X, totalSize.Y, totalSize.Z)
		local halfFovRad = math.rad(CAMERA_FOV / 2)
		local distance = (maxExtent / 2) / math.tan(halfFovRad) * CAMERA_PADDING

		-- Initial camera position (looking at center)
		cam.CFrame = CFrame.lookAt(faceNormal * distance, Vector3.zero)
		cam.FieldOfView = CAMERA_FOV

		-- NumberValue as a tweeneable proxy for camera distance
		local distanceValue = Instance.new("NumberValue")
		distanceValue.Value = distance

		-- Store for rotation loop
		local entry: ItemEntry = {
			handles = handleClones,
			cam = cam,
			baseDistance = distance,
			distanceValue = distanceValue,
			faceNormal = faceNormal,
			angle = 0,
		}
		table.insert(itemEntries, entry)

		-- Selection UIStroke (starts visible since all items are applied on switch)
		local selectStroke = Instance.new("UIStroke")
		selectStroke.Name = "SelectStroke"
		selectStroke.Color = SELECT_STROKE_COLOR
		selectStroke.Thickness = SELECT_STROKE_THICKNESS
		selectStroke.Transparency = 0 -- starts selected
		selectStroke.Parent = viewClone

		-- Hover effect: tween the distance value, render loop handles camera positioning
		local hoverTweenInfo = TweenInfo.new(HOVER_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		viewClone.MouseEnter:Connect(function()
			TweenService:Create(distanceValue, hoverTweenInfo, {Value = distance * HOVER_ZOOM_FACTOR}):Play()
		end)

		viewClone.MouseLeave:Connect(function()
			TweenService:Create(distanceValue, hoverTweenInfo, {Value = distance}):Play()
		end)

		-- Click to toggle: apply/remove accessory on the viewport character
		local button = Instance.new("TextButton")
		button.Name = "ClickRegion"
		button.Size = UDim2.fromScale(1, 1)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.Parent = viewClone

		-- Capture group for closure
		local groupRef = group

		button.Activated:Connect(function()
			local isApplied = appliedCosmetics[groupRef.name]
			if isApplied then
				-- Remove accessories from the viewport character
				for _, acc in ipairs(groupRef.accessories) do
					local applied = Character:FindFirstChild(acc.Name)
					if applied then applied:Destroy() end
				end
				appliedCosmetics[groupRef.name] = false
			else
				-- Apply accessories to the viewport character
				for _, acc in ipairs(groupRef.accessories) do
					local accClone = acc:Clone()
					accClone:SetAttribute("CosmeticItem", true)
					AttachAccessoryToCharacter(Character, accClone)
				end
				appliedCosmetics[groupRef.name] = true
			end

			local targetTransparency = if appliedCosmetics[groupRef.name] then 0 else 1
			TweenService:Create(selectStroke, TweenInfo.new(0.15), {Transparency = targetTransparency}):Play()
		end)

		-- Parent into AssetsHolder (UIGridLayout handles positioning)
		viewClone.Parent = AssetsHolder
	end
end

-- Load cosmetics for the default character on startup
LoadCosmetics(selectedCharacterId)

-- Continuous rotation + camera update for all cosmetic items
RunService.RenderStepped:Connect(function()
	for _, entry in ipairs(itemEntries) do
		-- Spin all handles together around center
		entry.angle = entry.angle + ROTATION_SPEED
		local rotCFrame = CFrame.Angles(0, math.rad(entry.angle), 0)

		for _, handle in ipairs(entry.handles) do
			local offset = handle:GetAttribute("OriginalOffset") or Vector3.zero
			handle.CFrame = rotCFrame * CFrame.new(offset)
		end

		-- Position camera at current distance (tweened by hover)
		local camPos = entry.faceNormal * entry.distanceValue.Value
		entry.cam.CFrame = CFrame.lookAt(camPos, Vector3.zero)
	end
end)

print("[CharacterUI] Viewport animations initialized")
