--!strict
-- Every rock you can skip. You start with a Pebble and buy the rest with
-- coins; each one throws further (power) and skips more times (flat). The
-- best ones only appear in the shop once you've skipped a rock past a
-- certain island. Colours are plain numbers so the Lune tests can load this.

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type Rock = {
	id: string,
	name: string,
	rarity: Rarity,
	price: number, -- coins (0 = you start with it)
	power: number, -- distance multiplier
	flat: number, -- 0..1: more skips
	weight: number, -- 0..1: longer hops
	color: { number },
	size: { number }, -- model size in studs (width, thickness, length)
	material: "SmoothPlastic" | "Glass" | "Neon" | "Slate" | "Marble",
	sparkle: boolean?, -- glitters in flight
	nightBonus: number?, -- extra distance at night (0.5 = +50%)
	island: string?, -- must have reached this island to buy it
	blurb: string,
}

export type RarityInfo = { order: number, color: { number } }

local RARITIES: { [Rarity]: RarityInfo } = {
	Common = { order = 1, color = { 176, 170, 160 } },
	Uncommon = { order = 2, color = { 112, 196, 120 } },
	Rare = { order = 3, color = { 92, 156, 238 } },
	Epic = { order = 4, color = { 176, 110, 236 } },
	Legendary = { order = 5, color = { 246, 184, 64 } },
	Mythic = { order = 6, color = { 255, 102, 150 } },
}

local function rock(r: Rock): Rock
	return r
end

local LIST: { Rock } = {
	rock({
		id = "pebble",
		name = "Pebble",
		rarity = "Common",
		price = 0,
		power = 1,
		flat = 0.3,
		weight = 0.3,
		color = { 150, 146, 140 },
		size = { 0.9, 0.45, 0.8 },
		material = "SmoothPlastic",
		blurb = "Round, grey and trusty. Every skipper starts here.",
	}),
	rock({
		id = "river",
		name = "River Stone",
		rarity = "Common",
		price = 120,
		power = 1.6,
		flat = 0.42,
		weight = 0.38,
		color = { 120, 108, 96 },
		size = { 1, 0.4, 0.85 },
		material = "SmoothPlastic",
		blurb = "Smoothed by years of running water.",
	}),
	rock({
		id = "slate",
		name = "Slate",
		rarity = "Uncommon",
		price = 1500,
		power = 2.6,
		flat = 0.68,
		weight = 0.42,
		color = { 86, 94, 106 },
		size = { 1.2, 0.22, 0.95 },
		material = "Slate",
		blurb = "Thin as a cracker. The classic skipping stone.",
	}),
	rock({
		id = "seaglass",
		name = "Sea Glass",
		rarity = "Uncommon",
		price = 15000,
		power = 4.2,
		flat = 0.6,
		weight = 0.36,
		color = { 128, 214, 190 },
		size = { 0.95, 0.3, 0.75 },
		material = "Glass",
		sparkle = true,
		blurb = "A frosted green jewel, worn soft by the waves.",
	}),
	rock({
		id = "basalt",
		name = "Basalt",
		rarity = "Rare",
		price = 150000,
		power = 7,
		flat = 0.56,
		weight = 0.72,
		color = { 54, 54, 60 },
		size = { 1.15, 0.38, 1 },
		material = "SmoothPlastic",
		island = "gull",
		blurb = "Dark volcanic rock. Throw it hard and it really goes.",
	}),
	rock({
		id = "jade",
		name = "Jade",
		rarity = "Rare",
		price = 2e6,
		power = 12,
		flat = 0.7,
		weight = 0.58,
		color = { 72, 168, 112 },
		size = { 1.1, 0.26, 0.9 },
		material = "Marble",
		island = "gull",
		blurb = "Cool, green and said to bring good luck.",
	}),
	rock({
		id = "rosequartz",
		name = "Rose Quartz",
		rarity = "Epic",
		price = 30e6,
		power = 21,
		flat = 0.72,
		weight = 0.52,
		color = { 244, 168, 190 },
		size = { 1.05, 0.28, 0.85 },
		material = "Glass",
		sparkle = true,
		island = "palm",
		blurb = "Pale pink and glowing softly in the sun.",
	}),
	rock({
		id = "obsidian",
		name = "Obsidian",
		rarity = "Epic",
		price = 400e6,
		power = 37,
		flat = 0.8,
		weight = 0.62,
		color = { 34, 26, 44 },
		size = { 1.2, 0.2, 1 },
		material = "Glass",
		island = "palm",
		blurb = "Volcanic glass with an edge like a knife. Skims beautifully.",
	}),
	rock({
		id = "moonstone",
		name = "Moonstone",
		rarity = "Legendary",
		price = 6e9,
		power = 64,
		flat = 0.84,
		weight = 0.6,
		color = { 206, 222, 255 },
		size = { 1.05, 0.24, 0.9 },
		material = "Glass",
		sparkle = true,
		nightBonus = 0.5,
		island = "turtle",
		blurb = "It shimmers like moonlight, and flies half as far again at night.",
	}),
	rock({
		id = "amber",
		name = "Amber",
		rarity = "Legendary",
		price = 100e9,
		power = 110,
		flat = 0.82,
		weight = 0.76,
		color = { 236, 150, 40 },
		size = { 1.1, 0.3, 0.9 },
		material = "Glass",
		sparkle = true,
		island = "turtle",
		blurb = "Old tree sap turned to stone, with a tiny bug frozen inside.",
	}),
	rock({
		id = "starstone",
		name = "Starstone",
		rarity = "Mythic",
		price = 600e9,
		power = 200,
		flat = 0.95,
		weight = 0.85,
		color = { 255, 236, 150 },
		size = { 1.05, 0.22, 0.95 },
		material = "Neon",
		sparkle = true,
		island = "whale",
		blurb = "A piece of a falling star. Nobody knows how it got here.",
	}),
	rock({
		id = "comet",
		name = "Comet Core",
		rarity = "Mythic",
		price = 10e12,
		power = 380,
		flat = 0.97,
		weight = 0.95,
		color = { 140, 200, 255 },
		size = { 1.15, 0.24, 1 },
		material = "Neon",
		sparkle = true,
		island = "lagoon",
		blurb = "Still cold from space. It barely touches the water.",
	}),
}

local BY_ID: { [string]: Rock } = {}
for _, r in LIST do
	BY_ID[r.id] = r
end

local RockData = {
	LIST = LIST,
	RARITIES = RARITIES,
	STARTER = "pebble",
}

function RockData.get(id: string): Rock?
	return BY_ID[id]
end

function RockData.rarityInfo(rarity: Rarity): RarityInfo
	return RARITIES[rarity]
end

return RockData
