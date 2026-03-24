--!strict
-- MinimapUI.client.lua
-- Displays a real-time minimap in the bottom right corner
-- DISABLED: Bird's eye view shows entire map, minimap not needed

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local MapData = require(Shared:WaitForChild("MapData"))

-- Wait for remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RoundStateChanged = Remotes:WaitForChild("RoundStateChanged")

-- Minimap DISABLED - bird's eye view shows entire map
print("[MinimapUI] Minimap disabled - using bird's eye camera view")
