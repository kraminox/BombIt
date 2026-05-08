--!strict
-- Titles.lua
-- Title registry for player inventory system

export type Title = {
	id: string,
	name: string,
	rarity: string,
}

local Titles = {}

Titles.List = {
	-- Common (5)
	{ id = "novice", name = "Novice", rarity = "Common" },
	{ id = "bomber", name = "Bomber", rarity = "Common" },
	{ id = "winner", name = "Winner", rarity = "Common" },
	{ id = "recruit", name = "Recruit", rarity = "Common" },
	{ id = "cadet", name = "Cadet", rarity = "Common" },
	-- Uncommon (10)
	{ id = "veteran", name = "Veteran", rarity = "Uncommon" },
	{ id = "blaster", name = "Blaster", rarity = "Uncommon" },
	{ id = "hotshot", name = "Hotshot", rarity = "Uncommon" },
	{ id = "fair", name = "Fair", rarity = "Uncommon" },
	{ id = "pro", name = "Pro", rarity = "Uncommon" },
	{ id = "nooob", name = "Nooob", rarity = "Uncommon" },
	{ id = "owl", name = "Owl", rarity = "Uncommon" },
	{ id = "kitten", name = "Kitten", rarity = "Uncommon" },
	{ id = "puppy", name = "Puppy", rarity = "Uncommon" },
	{ id = "gg_ez", name = "GG EZ", rarity = "Uncommon" },
	-- Rare (11)
	{ id = "demolisher", name = "Demolisher", rarity = "Rare" },
	{ id = "ace", name = "Ace", rarity = "Rare" },
	{ id = "papa_bear", name = "Papa Bear", rarity = "Rare" },
	{ id = "habibi", name = "Habibi", rarity = "Rare" },
	{ id = "mama", name = "Mama", rarity = "Rare" },
	{ id = "partner", name = "Partner", rarity = "Rare" },
	{ id = "rival", name = "Rival", rarity = "Rare" },
	{ id = "uhh", name = "Uhh", rarity = "Rare" },
	{ id = "booooo", name = "Booooo", rarity = "Rare" },
	{ id = "ghost", name = "Ghost", rarity = "Rare" },
	{ id = "arise", name = "Arise", rarity = "Rare" },
	-- Epic (7)
	{ id = "imperator", name = "Imperator", rarity = "Epic" },
	{ id = "perfect", name = "Perfect", rarity = "Epic" },
	{ id = "untouchable", name = "Untouchable", rarity = "Epic" },
	{ id = "dada", name = "Dada", rarity = "Epic" },
	{ id = "vandal", name = "Vandal", rarity = "Epic" },
	{ id = "sixty_seven", name = "67", rarity = "Epic" },
	{ id = "sixty_nine", name = "69", rarity = "Epic" },
	-- Legendary (7)
	{ id = "invulnerable", name = "Invulnerable", rarity = "Legendary" },
	{ id = "goat", name = "G.O.A.T.", rarity = "Legendary" },
	{ id = "bomb_god", name = "Bomb God", rarity = "Legendary" },
	{ id = "reaper", name = "Reaper", rarity = "Legendary" },
	{ id = "hound", name = "Hound", rarity = "Legendary" },
	{ id = "tung_tung", name = "Tung Tung Sahur", rarity = "Legendary" },
	{ id = "number_one", name = "#1", rarity = "Legendary" },
	-- VIP Gamepass
	{ id = "vip_golden", name = "VIP", rarity = "Legendary" },
	-- Level Milestones
	{ id = "lv1", name = "Level 1", rarity = "Uncommon" },
	{ id = "lv5", name = "Level 5", rarity = "Uncommon" },
	{ id = "lv10", name = "Level 10", rarity = "Uncommon" },
	{ id = "lv15", name = "Level 15", rarity = "Rare" },
	{ id = "lv25", name = "Level 25", rarity = "Rare" },
	{ id = "lv35", name = "Level 35", rarity = "Epic" },
	{ id = "lv50", name = "Level 50", rarity = "Epic" },
	{ id = "lv100", name = "Level 100", rarity = "Legendary" },
	{ id = "lv150", name = "Level 150", rarity = "Legendary" },
	{ id = "lv250", name = "Level 250", rarity = "Legendary" },
} :: {Title}

function Titles.GetById(id: string): Title?
	for _, title in ipairs(Titles.List) do
		if title.id == id then
			return title
		end
	end
	return nil
end

-- Level milestone title IDs, sorted descending so highest is checked first
Titles.LevelMilestones = {
	{ level = 250, titleId = "lv250" },
	{ level = 150, titleId = "lv150" },
	{ level = 100, titleId = "lv100" },
	{ level = 50,  titleId = "lv50" },
	{ level = 35,  titleId = "lv35" },
	{ level = 25,  titleId = "lv25" },
	{ level = 15,  titleId = "lv15" },
	{ level = 10,  titleId = "lv10" },
	{ level = 5,   titleId = "lv5" },
	{ level = 1,   titleId = "lv1" },
}

-- Returns all milestone title IDs the player has earned at a given level
function Titles.GetMilestoneTitlesForLevel(level: number): {string}
	local earned = {}
	for _, milestone in ipairs(Titles.LevelMilestones) do
		if level >= milestone.level then
			table.insert(earned, milestone.titleId)
		end
	end
	return earned
end

function Titles.GetByRarity(rarity: string): {Title}
	local result = {}
	for _, title in ipairs(Titles.List) do
		if title.rarity == rarity then
			table.insert(result, title)
		end
	end
	return result
end

return Titles
