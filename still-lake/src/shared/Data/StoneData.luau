--!strict
-- Every kind of skipping stone. Flatter stones skip more times; heavier ones
-- fly further on each hop. Everyone starts with a Pebble; the rest wash up on
-- the beach as glinting stones. Colours are plain numbers so the Lune tests
-- can load this file.

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"

export type Stone = {
	id: string,
	name: string,
	rarity: Rarity,
	flat: number, -- 0..1: more skips
	weight: number, -- 0..1: longer hops
	color: { number },
	size: { number }, -- model size in studs (width, thickness, length)
	material: "SmoothPlastic" | "Glass" | "Neon",
	sparkle: boolean?, -- glitters in flight
	nightBonus: number?, -- extra skips at night (0.2 = +20%)
	findWeight: number, -- how often it washes up (0 = never; you start with it)
	blurb: string,
}

export type RarityInfo = { order: number, color: { number } }

local RARITIES: { [Rarity]: RarityInfo } = {
	Common = { order = 1, color = { 176, 170, 160 } },
	Uncommon = { order = 2, color = { 112, 196, 120 } },
	Rare = { order = 3, color = { 92, 156, 238 } },
	Epic = { order = 4, color = { 176, 110, 236 } },
	Legendary = { order = 5, color = { 255, 190, 60 } },
}

local LIST: { Stone } = {
	{
		id = "pebble",
		name = "Pebble",
		rarity = "Common",
		flat = 0.3,
		weight = 0.3,
		color = { 150, 146, 140 },
		size = { 0.85, 0.42, 0.75 },
		material = "SmoothPlastic",
		findWeight = 0,
		blurb = "Round, grey and trusty. Every skipper starts here.",
	},
	{
		id = "river",
		name = "River Stone",
		rarity = "Common",
		flat = 0.42,
		weight = 0.38,
		color = { 124, 112, 100 },
		size = { 0.95, 0.36, 0.8 },
		material = "SmoothPlastic",
		findWeight = 30,
		blurb = "Smoothed by years of running water.",
	},
	{
		id = "sandstone",
		name = "Sandstone",
		rarity = "Common",
		flat = 0.38,
		weight = 0.5,
		color = { 214, 172, 120 },
		size = { 1, 0.4, 0.85 },
		material = "SmoothPlastic",
		findWeight = 30,
		blurb = "Warm and a little heavy. Flies far, skips less.",
	},
	{
		id = "slate",
		name = "Slate",
		rarity = "Uncommon",
		flat = 0.68,
		weight = 0.42,
		color = { 88, 98, 112 },
		size = { 1.15, 0.22, 0.85 },
		material = "SmoothPlastic",
		findWeight = 18,
		blurb = "Thin as a cracker. The classic skipping stone.",
	},
	{
		id = "seaglass",
		name = "Sea Glass",
		rarity = "Uncommon",
		flat = 0.56,
		weight = 0.32,
		color = { 132, 214, 196 },
		size = { 0.85, 0.28, 0.7 },
		material = "Glass",
		findWeight = 16,
		blurb = "A frosted green jewel, worn soft by the waves.",
	},
	{
		id = "basalt",
		name = "Basalt",
		rarity = "Uncommon",
		flat = 0.5,
		weight = 0.72,
		color = { 54, 52, 58 },
		size = { 1.05, 0.34, 0.9 },
		material = "SmoothPlastic",
		findWeight = 16,
		blurb = "Dark volcanic rock. Throw it hard and it really goes.",
	},
	{
		id = "jade",
		name = "Jade",
		rarity = "Rare",
		flat = 0.7,
		weight = 0.58,
		color = { 86, 178, 120 },
		size = { 1.05, 0.24, 0.85 },
		material = "SmoothPlastic",
		findWeight = 6,
		blurb = "Cool, green and said to bring good luck.",
	},
	{
		id = "rosequartz",
		name = "Rose Quartz",
		rarity = "Rare",
		flat = 0.66,
		weight = 0.52,
		color = { 244, 170, 196 },
		size = { 1, 0.26, 0.8 },
		material = "Glass",
		sparkle = true,
		findWeight = 6,
		blurb = "Pale pink and glowing softly in the sun.",
	},
	{
		id = "obsidian",
		name = "Obsidian",
		rarity = "Rare",
		flat = 0.8,
		weight = 0.62,
		color = { 34, 26, 44 },
		size = { 1.15, 0.2, 0.9 },
		material = "Glass",
		findWeight = 5,
		blurb = "Volcanic glass with an edge like a knife. Skims beautifully.",
	},
	{
		id = "moonstone",
		name = "Moonstone",
		rarity = "Epic",
		flat = 0.84,
		weight = 0.6,
		color = { 200, 222, 255 },
		size = { 1.05, 0.22, 0.85 },
		material = "Glass",
		sparkle = true,
		nightBonus = 0.25,
		findWeight = 2,
		blurb = "It shimmers like moonlight, and skips even better at night.",
	},
	{
		id = "amber",
		name = "Amber",
		rarity = "Epic",
		flat = 0.8,
		weight = 0.76,
		color = { 238, 150, 40 },
		size = { 1.1, 0.24, 0.9 },
		material = "Glass",
		sparkle = true,
		findWeight = 2,
		blurb = "Old tree sap turned to stone, with a tiny bug frozen inside.",
	},
	{
		id = "starstone",
		name = "Starstone",
		rarity = "Legendary",
		flat = 0.95,
		weight = 0.85,
		color = { 46, 60, 140 },
		size = { 1.1, 0.2, 0.9 },
		material = "SmoothPlastic",
		sparkle = true,
		findWeight = 0.8,
		blurb = "A piece of a falling star. Nobody knows how it got here.",
	},
}

local BY_ID: { [string]: Stone } = {}
local FINDABLE: { Stone } = {}
local TOTAL_WEIGHT = 0
for _, stone in LIST do
	BY_ID[stone.id] = stone
	if stone.findWeight > 0 then
		table.insert(FINDABLE, stone)
		TOTAL_WEIGHT += stone.findWeight
	end
end

local StoneData = {
	LIST = LIST,
	RARITIES = RARITIES,
	STARTER = "pebble",
}

function StoneData.get(id: string): Stone?
	return BY_ID[id]
end

function StoneData.rarityInfo(rarity: Rarity): RarityInfo
	return RARITIES[rarity]
end

-- Which stone a glint turns out to be, for r in [0, 1).
function StoneData.roll(r: number): string
	local target = math.clamp(r, 0, 0.999999) * TOTAL_WEIGHT
	local sum = 0
	for _, stone in FINDABLE do
		sum += stone.findWeight
		if target < sum then
			return stone.id
		end
	end
	return FINDABLE[#FINDABLE].id
end

-- Chance (0..1) that a glint is this stone.
function StoneData.findChance(id: string): number
	local stone = BY_ID[id]
	if not stone then
		return 0
	end
	return stone.findWeight / TOTAL_WEIGHT
end

return StoneData
