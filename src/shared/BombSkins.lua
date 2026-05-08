--!strict
-- BombSkins.lua
-- Skin & pack registry for the bomb skin shop

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type BombSkin = {
	id: string,
	name: string,
	modelName: string,
	imageId: string,
	pack: string,
	rarity: string,
	chance: number,
}

export type Pack = {
	id: string,
	name: string,
	robuxPrice: number,
	coinPrice: number,
	skins: {string},
}

local BombSkins = {}

-- Common UI images
BombSkins.Images = {
	BombIcon = "rbxassetid://125079663060203",    -- Cartoonish bomb for kill feed, eliminations, overhead UI
	DefaultBombThumb = "rbxassetid://113616012361408", -- Thumbnail of default bomb for inventory/skin selection
	Capsule = "rbxassetid://104738757916164",
	Coin = "rbxassetid://118687282770235",
}

-- Rarity definitions
BombSkins.Rarities = {
	COMMON = "Common",
	RARE = "Rare",
	EPIC = "Epic",
	LEGENDARY = "Legendary",
}

-- UI colors per rarity
BombSkins.RarityColors = {
	Common = Color3.fromRGB(180, 180, 180),
	Uncommon = Color3.fromRGB(80, 200, 120),
	Rare = Color3.fromRGB(80, 140, 255),
	Epic = Color3.fromRGB(170, 80, 255),
	Legendary = Color3.fromRGB(255, 215, 0),
}

-- All skins
BombSkins.Skins = {
	-- Base bomb (everyone has this, shown in inventory)
	{ id = "default_bomb", name = "Default Bomb", modelName = "Default Bomb", imageId = "rbxassetid://108571249340540", pack = "none", rarity = "Common", chance = 0 },

	-- Default pack (classic round bomb in different colors)
	{ id = "default_red", name = "Default Red", modelName = "Default Bomb", imageId = "rbxassetid://73772908020879", pack = "default", rarity = "Common", chance = 50 },
	{ id = "default_purple", name = "Default Purple", modelName = "Default Bomb", imageId = "rbxassetid://115989089688005", pack = "default", rarity = "Common", chance = 50 },
	{ id = "default_green", name = "Default Green", modelName = "Default Bomb", imageId = "rbxassetid://133680974830526", pack = "default", rarity = "Common", chance = 50 },

	-- Pastel pack
	{ id = "pastel_blue", name = "Pastel Blue", modelName = "Default Bomb", imageId = "rbxassetid://86460687705734", pack = "pastel", rarity = "Common", chance = 40 },
	{ id = "pastel_yellow", name = "Pastel Yellow", modelName = "Default Bomb", imageId = "rbxassetid://96252430041488", pack = "pastel", rarity = "Common", chance = 40 },
	{ id = "pastel_peach", name = "Pastel Peach", modelName = "Default Bomb", imageId = "rbxassetid://107341116516713", pack = "pastel", rarity = "Uncommon", chance = 30 },
	{ id = "pastel_pink", name = "Pastel Pink", modelName = "Default Bomb", imageId = "rbxassetid://122361381774471", pack = "pastel", rarity = "Uncommon", chance = 30 },

	-- Neon pack
	{ id = "neon_red", name = "Neon Red", modelName = "Default Bomb", imageId = "rbxassetid://121422424999836", pack = "neon", rarity = "Rare", chance = 20 },
	{ id = "neon_yellow", name = "Neon Yellow", modelName = "Default Bomb", imageId = "rbxassetid://89506413707450", pack = "neon", rarity = "Rare", chance = 20 },
	{ id = "neon_blue", name = "Neon Blue", modelName = "Default Bomb", imageId = "rbxassetid://73779214608960", pack = "neon", rarity = "Rare", chance = 20 },
	{ id = "neon_green", name = "Neon Green", modelName = "Default Bomb", imageId = "rbxassetid://100876649852837", pack = "neon", rarity = "Rare", chance = 20 },

	-- Dynamite pack
	{ id = "dynamite_orange", name = "Dynamite Orange", modelName = "Dynamite Bomb", imageId = "rbxassetid://121930721090278", pack = "dynamite", rarity = "Epic", chance = 10 },
	{ id = "dynamite_green", name = "Dynamite Green", modelName = "Dynamite Bomb", imageId = "rbxassetid://91099634645499", pack = "dynamite", rarity = "Epic", chance = 10 },
	{ id = "dynamite_blue", name = "Dynamite Blue", modelName = "Dynamite Bomb", imageId = "rbxassetid://80034204252028", pack = "dynamite", rarity = "Epic", chance = 10 },
	{ id = "dynamite_red", name = "Dynamite Red", modelName = "Dynamite Bomb", imageId = "rbxassetid://123869718481420", pack = "dynamite", rarity = "Epic", chance = 10 },

	-- Food Bombs pack
	{ id = "food_cupcake", name = "Cupcake", modelName = "Cupcake", imageId = "rbxassetid://119682761726732", pack = "food", rarity = "Legendary", chance = 5 },
	{ id = "food_donut", name = "Donut", modelName = "Donut", imageId = "rbxassetid://102314277311839", pack = "food", rarity = "Uncommon", chance = 30 },
	{ id = "food_cookie", name = "Cookie", modelName = "Cookie", imageId = "rbxassetid://135489965700224", pack = "food", rarity = "Rare", chance = 20 },

	-- Pet Bombs pack
	{ id = "pet_dog", name = "Dog", modelName = "Dog", imageId = "rbxassetid://90825861882795", pack = "pets", rarity = "Rare", chance = 20 },
	{ id = "pet_bee", name = "Bee", modelName = "Bee", imageId = "rbxassetid://117704920081015", pack = "pets", rarity = "Legendary", chance = 5 },
	{ id = "pet_eagle", name = "Eagle", modelName = "Eagle", imageId = "rbxassetid://112126888800545", pack = "pets", rarity = "Legendary", chance = 5 },
	{ id = "pet_penguin", name = "Penguin", modelName = "Penguin", imageId = "rbxassetid://123730082955988", pack = "pets", rarity = "Rare", chance = 20 },

	-- Sports Bombs pack
	{ id = "sports_basketball", name = "Basketball", modelName = "Basketball", imageId = "rbxassetid://133954962743497", pack = "sports", rarity = "Uncommon", chance = 30 },
	{ id = "sports_soccer", name = "Soccer Ball", modelName = "Soccer", imageId = "rbxassetid://130373537985403", pack = "sports", rarity = "Uncommon", chance = 30 },
	{ id = "sports_tennis", name = "Tennis Ball", modelName = "TennisBall", imageId = "rbxassetid://111750552551302", pack = "sports", rarity = "Uncommon", chance = 30 },
	{ id = "sports_volleyball", name = "Volleyball", modelName = "Volleyball", imageId = "rbxassetid://94534150470213", pack = "sports", rarity = "Uncommon", chance = 30 },

	-- Misc Bombs pack (common/uncommon filler for spins, capsules, daily rewards)
	{ id = "misc_brain", name = "Brain", modelName = "Brain", imageId = "rbxassetid://82485346781969", pack = "misc", rarity = "Common", chance = 50 },
	{ id = "misc_soda", name = "Soda", modelName = "Soda", imageId = "rbxassetid://108471525535182", pack = "misc", rarity = "Common", chance = 50 },
	{ id = "misc_car", name = "Car", modelName = "White Car", imageId = "rbxassetid://136787681284972", pack = "misc", rarity = "Uncommon", chance = 30 },

	-- Free skin (promotional)
	{ id = "pet_squirrel", name = "Squirrel", modelName = "Squirrel", imageId = "rbxassetid://98481503531058", pack = "pets", rarity = "Epic", chance = 0 },
} :: {BombSkin}

-- All packs
BombSkins.Packs = {
	{ id = "default", name = "Default Bombs", robuxPrice = 75, coinPrice = 500, skins = { "default_red", "default_purple", "default_green" } },
	{ id = "pastel", name = "Pastel Bombs", robuxPrice = 75, coinPrice = 500, skins = { "pastel_blue", "pastel_yellow", "pastel_peach", "pastel_pink" } },
	{ id = "neon", name = "Neon Bombs", robuxPrice = 99, coinPrice = 750, skins = { "neon_red", "neon_yellow", "neon_blue", "neon_green" } },
	{ id = "dynamite", name = "Dynamite Bombs", robuxPrice = 149, coinPrice = 1000, skins = { "dynamite_orange", "dynamite_green", "dynamite_blue", "dynamite_red" } },
	{ id = "food", name = "Food Bombs", robuxPrice = 99, coinPrice = 750, skins = { "food_cupcake", "food_donut", "food_cookie" } },
	{ id = "pets", name = "Pet Bombs", robuxPrice = 149, coinPrice = 1000, skins = { "pet_dog", "pet_bee", "pet_eagle", "pet_penguin" } },
	{ id = "sports", name = "Sports Bombs", robuxPrice = 75, coinPrice = 500, skins = { "sports_basketball", "sports_soccer", "sports_tennis", "sports_volleyball" } },
} :: {Pack}

-- Lookup a skin by id
function BombSkins.GetSkinById(id: string): BombSkin?
	for _, skin in ipairs(BombSkins.Skins) do
		if skin.id == id then
			return skin
		end
	end
	return nil
end

-- Get all skins belonging to a pack
function BombSkins.GetSkinsForPack(packId: string): {BombSkin}
	local result = {}
	for _, skin in ipairs(BombSkins.Skins) do
		if skin.pack == packId then
			table.insert(result, skin)
		end
	end
	return result
end

-- Find the bomb model in Assets/Bombs
function BombSkins.GetSkinModel(skin: BombSkin): Model?
	local Assets = ReplicatedStorage:FindFirstChild("Assets")
	if not Assets then return nil end
	local Bombs = Assets:FindFirstChild("Bombs")
	if not Bombs then return nil end

	-- Direct child model
	local model = Bombs:FindFirstChild(skin.modelName)
	if model and model:IsA("Model") then
		return model
	end

	-- Search inside sub-folders (e.g. Emoji Bombs/Happy Bomb)
	for _, folder in ipairs(Bombs:GetChildren()) do
		if folder:IsA("Folder") or folder:IsA("Model") then
			local child = folder:FindFirstChild(skin.modelName)
			if child and child:IsA("Model") then
				return child
			end
		end
	end

	return nil
end

return BombSkins
