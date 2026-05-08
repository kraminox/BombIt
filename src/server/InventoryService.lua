--!strict
-- InventoryService.lua
-- Server-side inventory management: ownership, equipping, capsule opening

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BombSkins = require(Shared:WaitForChild("BombSkins"))
local WinDances = require(Shared:WaitForChild("WinDances"))
local Titles = require(Shared:WaitForChild("Titles"))
local ExplosionSkins = require(Shared:WaitForChild("ExplosionSkins"))
local GameState = require(Shared:WaitForChild("GameState"))

-- Rarity upgrade chain for luck boost
local RARITY_UPGRADE: {[string]: string} = {
	Common = "Uncommon",
	Uncommon = "Rare",
	Rare = "Epic",
	Epic = "Legendary",
}

local InventoryService = {}

-- In-memory store keyed by UserId
local inventories: {[number]: any} = {}

function InventoryService.CreateDefaultInventory()
	return {
		ownedSkins = {"default_bomb"},
		ownedDances = {"billy_bounce"},
		ownedTitles = {},
		ownedExplosions = {"default_red_explosion"},
		ownedCapsules = {} :: {{rarity: string}},
		equippedSkin = "default_bomb",
		equippedDance = "billy_bounce",
		equippedTitle = "",
		equippedExplosion = "default_red_explosion",
	}
end

-- Load inventory from save data (or create default)
function InventoryService.LoadInventory(player: Player, saveData: any?)
	local inv = InventoryService.CreateDefaultInventory()

	if saveData and saveData.inventory then
		local saved = saveData.inventory
		-- Restore owned items from save
		if saved.ownedSkins and #saved.ownedSkins > 0 then
			inv.ownedSkins = saved.ownedSkins
			-- Ensure default is always owned
			local hasDefault = false
			for _, id in ipairs(inv.ownedSkins) do
				if id == "default_bomb" then hasDefault = true break end
			end
			if not hasDefault then table.insert(inv.ownedSkins, "default_bomb") end
		end
		if saved.ownedDances then
			inv.ownedDances = saved.ownedDances
			-- Ensure default dance is always owned
			local hasDefaultDance = false
			for _, id in ipairs(inv.ownedDances) do
				if id == "billy_bounce" then hasDefaultDance = true break end
			end
			if not hasDefaultDance then table.insert(inv.ownedDances, "billy_bounce") end
		end
		if saved.ownedTitles then inv.ownedTitles = saved.ownedTitles end
		if saved.ownedExplosions and #saved.ownedExplosions > 0 then
			inv.ownedExplosions = saved.ownedExplosions
			local hasDefaultExp = false
			for _, id in ipairs(inv.ownedExplosions) do
				if id == "default_red_explosion" then hasDefaultExp = true break end
			end
			if not hasDefaultExp then table.insert(inv.ownedExplosions, "default_red_explosion") end
		end
		-- Restore equipped selections
		if saved.equippedSkin and saved.equippedSkin ~= "" then
			inv.equippedSkin = saved.equippedSkin
		end
		if saved.equippedDance and saved.equippedDance ~= "" then
			inv.equippedDance = saved.equippedDance
		end
		if saved.equippedTitle and saved.equippedTitle ~= "" then
			inv.equippedTitle = saved.equippedTitle
		end
		if saved.equippedExplosion and saved.equippedExplosion ~= "" then
			inv.equippedExplosion = saved.equippedExplosion
		end
		-- Restore capsules
		if saved.ownedCapsules then
			inv.ownedCapsules = saved.ownedCapsules
		end
	end

	inventories[player.UserId] = inv
end

-- Return the inventory table for saving
function InventoryService.SaveInventory(player: Player): any?
	return inventories[player.UserId]
end

-- Get a copy of the inventory for the client
function InventoryService.GetInventory(player: Player): any?
	return inventories[player.UserId]
end

-- Clean up on leave
function InventoryService.RemoveInventory(player: Player)
	inventories[player.UserId] = nil
end

-- Check if player owns an item in a category
local function OwnsItem(inv: any, category: string, itemId: string): boolean
	if category == "bombs" then
		for _, id in ipairs(inv.ownedSkins) do
			if id == itemId then return true end
		end
	elseif category == "emotes" then
		for _, id in ipairs(inv.ownedDances) do
			if id == itemId then return true end
		end
	elseif category == "titles" then
		for _, id in ipairs(inv.ownedTitles) do
			if id == itemId then return true end
		end
	elseif category == "explosions" then
		for _, id in ipairs(inv.ownedExplosions) do
			if id == itemId then return true end
		end
	end
	return false
end

-- Equip an item (validate ownership first)
function InventoryService.EquipItem(player: Player, category: string, itemId: string): boolean
	local inv = inventories[player.UserId]
	if not inv then return false end

	if not OwnsItem(inv, category, itemId) then
		return false
	end

	if category == "bombs" then
		inv.equippedSkin = itemId
	elseif category == "emotes" then
		inv.equippedDance = itemId
	elseif category == "titles" then
		inv.equippedTitle = itemId
		-- Update the EquippedTitle StringValue so nameplates can read it
		local pStats = player:FindFirstChild("PersistentStats")
		if pStats then
			local titleVal = pStats:FindFirstChild("EquippedTitle")
			if titleVal then
				titleVal.Value = itemId
			end
		end
	elseif category == "explosions" then
		inv.equippedExplosion = itemId
	end

	return true
end

-- Unequip (reset to default)
function InventoryService.UnequipItem(player: Player, category: string): boolean
	local inv = inventories[player.UserId]
	if not inv then return false end

	if category == "bombs" then
		inv.equippedSkin = "default_bomb"
	elseif category == "emotes" then
		inv.equippedDance = "billy_bounce"
	elseif category == "titles" then
		inv.equippedTitle = ""
		local pStats = player:FindFirstChild("PersistentStats")
		if pStats then
			local titleVal = pStats:FindFirstChild("EquippedTitle")
			if titleVal then
				titleVal.Value = ""
			end
		end
	elseif category == "explosions" then
		inv.equippedExplosion = "default_red_explosion"
	end

	return true
end

-- Add a capsule to player's inventory (used by spin wheel rewards)
function InventoryService.AddCapsule(player: Player, rarity: string)
	local inv = inventories[player.UserId]
	if not inv then return end
	table.insert(inv.ownedCapsules, { rarity = rarity })
end

-- Open a capsule by index in ownedCapsules
-- Returns a single reward of the capsule's exact rarity
function InventoryService.OpenCapsule(player: Player, capsuleIndex: number): any?
	local inv = inventories[player.UserId]
	if not inv then return nil end

	if capsuleIndex < 1 or capsuleIndex > #inv.ownedCapsules then
		return nil
	end

	local capsule = inv.ownedCapsules[capsuleIndex]
	local rarity = capsule.rarity

	-- 2x Luck boost: 30% chance to upgrade rarity by one tier (doubled from base 15%)
	local expiry = GameState.luckBoostExpiry[player.UserId]
	local hasLuck = expiry and os.time() < expiry
	local upgradeChance = if hasLuck then 0.30 else 0.15
	local upgrade = RARITY_UPGRADE[rarity]
	if upgrade and math.random() < upgradeChance then
		rarity = upgrade
	end

	-- Remove capsule from inventory
	table.remove(inv.ownedCapsules, capsuleIndex)

	-- Collect all items of the capsule's exact rarity, preferring unowned items
	local categoryMap = { skin = "bombs", dance = "emotes", title = "titles", explosion = "explosions" }
	local allPossible: {any} = {}
	local unowned: {any} = {}

	for _, skin in ipairs(BombSkins.Skins) do
		if skin.rarity == rarity then
			local entry = { type = "skin", item = skin }
			table.insert(allPossible, entry)
			if not OwnsItem(inv, "bombs", skin.id) then
				table.insert(unowned, entry)
			end
		end
	end
	for _, dance in ipairs(WinDances.Dances) do
		if dance.rarity == rarity then
			local entry = { type = "dance", item = dance }
			table.insert(allPossible, entry)
			if not OwnsItem(inv, "emotes", dance.id) then
				table.insert(unowned, entry)
			end
		end
	end
	for _, title in ipairs(Titles.List) do
		if title.rarity == rarity then
			local entry = { type = "title", item = title }
			table.insert(allPossible, entry)
			if not OwnsItem(inv, "titles", title.id) then
				table.insert(unowned, entry)
			end
		end
	end
	for _, explosion in ipairs(ExplosionSkins.Skins) do
		if explosion.rarity == rarity and explosion.chance > 0 then
			local entry = { type = "explosion", item = explosion }
			table.insert(allPossible, entry)
			if not OwnsItem(inv, "explosions", explosion.id) then
				table.insert(unowned, entry)
			end
		end
	end

	if #allPossible == 0 then return nil end

	-- Prefer unowned items; fall back to all items if player owns everything of this rarity
	local pool = if #unowned > 0 then unowned else allPossible
	local idx = math.random(1, #pool)
	local reward = pool[idx]

	-- Add to owned if not already owned
	local itemId = reward.item.id
	if reward.type == "skin" then
		if not OwnsItem(inv, "bombs", itemId) then
			table.insert(inv.ownedSkins, itemId)
		end
	elseif reward.type == "dance" then
		if not OwnsItem(inv, "emotes", itemId) then
			table.insert(inv.ownedDances, itemId)
		end
	elseif reward.type == "title" then
		if not OwnsItem(inv, "titles", itemId) then
			table.insert(inv.ownedTitles, itemId)
		end
	elseif reward.type == "explosion" then
		if not OwnsItem(inv, "explosions", itemId) then
			table.insert(inv.ownedExplosions, itemId)
		end
	end

	local category = categoryMap[reward.type]

	-- Return full reward data
	return {
		type = reward.type,
		category = category,
		itemId = itemId,
		itemName = reward.item.name,
		imageId = reward.item.imageId or "",
		rarity = rarity,
	}
end

-- Grant a title if not already owned (used by level milestones, VIP, etc.)
function InventoryService.GrantTitle(player: Player, titleId: string): boolean
	local inv = inventories[player.UserId]
	if not inv then return false end
	for _, id in ipairs(inv.ownedTitles) do
		if id == titleId then return false end -- already owned
	end
	table.insert(inv.ownedTitles, titleId)
	return true
end

-- Grant all level milestone titles the player has earned
function InventoryService.GrantMilestoneTitles(player: Player, level: number)
	local earned = Titles.GetMilestoneTitlesForLevel(level)
	for _, titleId in ipairs(earned) do
		InventoryService.GrantTitle(player, titleId)
	end
end

-- Get the equipped bomb skin id for a player
function InventoryService.GetEquippedBombSkinId(player: Player): string
	local inv = inventories[player.UserId]
	if not inv or not inv.equippedSkin or inv.equippedSkin == "" then
		return "default_bomb"
	end
	return inv.equippedSkin
end

-- Get the VFX model name for a player's equipped explosion
function InventoryService.GetEquippedExplosionModel(player: Player): string
	local inv = inventories[player.UserId]
	if not inv or not inv.equippedExplosion or inv.equippedExplosion == "" then
		return "Default Red Explosion"
	end
	local skin = ExplosionSkins.GetById(inv.equippedExplosion)
	if skin then
		return skin.modelName
	end
	return "Default Red Explosion"
end

return InventoryService
