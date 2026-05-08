--!strict
-- WinDances.lua
-- Dance animations for win celebrations (R15)

export type Dance = {
	id: string,
	name: string,
	animId: string,
	imageId: string,
	rarity: string,
}

local WinDances = {}

WinDances.Rarities = {
	COMMON = "Common",
	RARE = "Rare",
	EPIC = "Epic",
	LEGENDARY = "Legendary",
}

WinDances.Dances = {
	-- Common
	{ id = "billy_bounce", name = "Billy Bounce", animId = "rbxassetid://76505248167736", imageId = "rbxassetid://113774224641271", rarity = "Common" },
	{ id = "rat_dance", name = "Rat Dance", animId = "rbxassetid://103997091692218", imageId = "rbxassetid://89608686618267", rarity = "Common" },
	{ id = "russian_dance", name = "Russian Dance", animId = "rbxassetid://91441530434422", imageId = "rbxassetid://115486668687410", rarity = "Common" },
	{ id = "gangnam_style", name = "Gangnam Style", animId = "rbxassetid://77315999222047", imageId = "rbxassetid://98029597529611", rarity = "Common" },
	{ id = "spongebob", name = "SpongeBob", animId = "rbxassetid://127773853048148", imageId = "rbxassetid://119013339603681", rarity = "Common" },
	{ id = "cat_dance", name = "Cat Dance", animId = "rbxassetid://73353666336561", imageId = "rbxassetid://120883954950427", rarity = "Common" },
	{ id = "i_want_money", name = "I Want Money", animId = "rbxassetid://90817745997792", imageId = "rbxassetid://88971247624499", rarity = "Common" },
	{ id = "orange_justice", name = "Orange Justice", animId = "rbxassetid://105865111435640", imageId = "rbxassetid://103770271019086", rarity = "Common" },

	-- Rare
	{ id = "metro_swing_arm", name = "Metro Swing Arm", animId = "rbxassetid://86385097875945", imageId = "rbxassetid://85904283941353", rarity = "Rare" },
	{ id = "prince_of_egypt", name = "Prince of Egypt", animId = "rbxassetid://79048660665945", imageId = "rbxassetid://70901277428739", rarity = "Rare" },
	{ id = "groovy_hops", name = "Groovy Hops", animId = "rbxassetid://121852496901107", imageId = "rbxassetid://90161134695252", rarity = "Rare" },
	{ id = "louisiana_dance", name = "Louisiana Dance", animId = "rbxassetid://111594316884177", imageId = "rbxassetid://135073178208695", rarity = "Rare" },
	{ id = "jumpstyle_dance", name = "Jumpstyle Dance", animId = "rbxassetid://117076584054935", imageId = "rbxassetid://71210786532431", rarity = "Rare" },

	-- Epic
	{ id = "anime_warmup", name = "Anime Warmup", animId = "rbxassetid://90380920543015", imageId = "rbxassetid://71103865379329", rarity = "Epic" },
	{ id = "trend_boy", name = "Trend Boy, New Jeans", animId = "rbxassetid://127393858659161", imageId = "rbxassetid://137804366540782", rarity = "Epic" },
	{ id = "baby_queen_twirl", name = "Baby Queen Twirl", animId = "rbxassetid://124080085628568", imageId = "rbxassetid://125596519273571", rarity = "Epic" },

	-- Legendary
	{ id = "default_dance", name = "Default Dance", animId = "rbxassetid://111077158786400", imageId = "rbxassetid://97831368846889", rarity = "Legendary" },
	{ id = "headless_dribbles", name = "Headless Dribbles", animId = "rbxassetid://88062344792608", imageId = "rbxassetid://78210068631476", rarity = "Legendary" },
	{ id = "take_the_l", name = "Take the L", animId = "rbxassetid://123033557757914", imageId = "rbxassetid://74529982200382", rarity = "Legendary" },
}

-- Lookup by id
function WinDances.GetById(id: string): Dance?
	for _, dance in ipairs(WinDances.Dances) do
		if dance.id == id then
			return dance
		end
	end
	return nil
end

-- Get all dances of a given rarity
function WinDances.GetByRarity(rarity: string): {Dance}
	local result = {}
	for _, dance in ipairs(WinDances.Dances) do
		if dance.rarity == rarity then
			table.insert(result, dance)
		end
	end
	return result
end

return WinDances
