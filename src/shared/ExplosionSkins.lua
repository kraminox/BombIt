--!strict
-- ExplosionSkins.lua
-- Explosion VFX registry for the cosmetic system

export type ExplosionSkin = {
	id: string,
	name: string,
	modelName: string,
	imageId: string,
	rarity: string,
	chance: number,
}

local ExplosionSkins = {}

-- All explosion VFX
-- modelName matches the instance name under ReplicatedStorage.VFX
ExplosionSkins.Skins = {
	-- Common (starter) — every player owns this
	{ id = "default_red_explosion", name = "Red Explosion", modelName = "Default Red Explosion", imageId = "rbxassetid://86278696833855", rarity = "Common", chance = 0 },

	-- Uncommon
	{ id = "default_blue_explosion", name = "Blue Explosion", modelName = "Default Blue Explosion", imageId = "rbxassetid://91696095928502", rarity = "Uncommon", chance = 30 },
	{ id = "default_green_explosion", name = "Green Explosion", modelName = "Default Green Explosion", imageId = "rbxassetid://116487761542346", rarity = "Uncommon", chance = 30 },

	-- Rare
	{ id = "lightning_explosion", name = "Lightning", modelName = "Lightning Explosion", imageId = "rbxassetid://113022396372768", rarity = "Rare", chance = 20 },
	{ id = "fireworks_explosion", name = "Fireworks", modelName = "Firework Explosion", imageId = "rbxassetid://84517223346143", rarity = "Rare", chance = 20 },
	{ id = "confetti_explosion", name = "Confetti", modelName = "Confetti", imageId = "rbxassetid://88976904255248", rarity = "Rare", chance = 20 },
	{ id = "water_explosion", name = "Water", modelName = "Water Explosion", imageId = "rbxassetid://135369264988888", rarity = "Rare", chance = 20 },

	-- Epic
	{ id = "default_candy_explosion", name = "Candy Explosion", modelName = "Default Candy Explosion", imageId = "rbxassetid://113617756239056", rarity = "Epic", chance = 10 },
	{ id = "red_lightning_explosion", name = "Red Lightning", modelName = "Red Lightning Explosion", imageId = "rbxassetid://118317511324317", rarity = "Epic", chance = 10 },
	{ id = "earth_explosion", name = "Earth", modelName = "Earth Explosion", imageId = "rbxassetid://103823902887977", rarity = "Epic", chance = 10 },

	-- Legendary
	{ id = "default_black_explosion", name = "Black Explosion", modelName = "Default Black Explosion", imageId = "rbxassetid://97169547428777", rarity = "Legendary", chance = 5 },
	{ id = "default_gold_explosion", name = "Gold Explosion", modelName = "Default Gold Explosion", imageId = "rbxassetid://130152535290985", rarity = "Legendary", chance = 5 },
} :: {ExplosionSkin}

-- Lookup by id
function ExplosionSkins.GetById(id: string): ExplosionSkin?
	for _, skin in ipairs(ExplosionSkins.Skins) do
		if skin.id == id then
			return skin
		end
	end
	return nil
end

-- Get all skins of a given rarity
function ExplosionSkins.GetByRarity(rarity: string): {ExplosionSkin}
	local result = {}
	for _, skin in ipairs(ExplosionSkins.Skins) do
		if skin.rarity == rarity then
			table.insert(result, skin)
		end
	end
	return result
end

return ExplosionSkins
