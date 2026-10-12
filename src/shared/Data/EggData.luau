--!strict
-- Shop eggs. Odds are stored as integer basis points (1 bp = 0.01%) that sum to
-- exactly 10000 for every egg. The odds shown to players and the odds used when
-- hatching both come from these tables, so they can never disagree.
-- (Roblox paid random item policy: show every outcome with real % odds.)

export type OddsEntry = { species: string, weight: number }

export type EggType = {
	id: string,
	name: string,
	order: number,
	price: number,
	hatchSeconds: number,
	colors: { main: { number }, spots: { number } },
	material: "SmoothPlastic" | "Neon" | "Glass",
	odds: { OddsEntry },
	stock: { chance: number, min: number, max: number },
}

local LIST: { EggType } = {
	{
		id = "Jungle",
		name = "Jungle Egg",
		order = 1,
		price = 50,
		hatchSeconds = 30,
		colors = { main = { 140, 200, 100 }, spots = { 60, 120, 50 } },
		material = "SmoothPlastic",
		odds = {
			{ species = "Raptor", weight = 4000 },
			{ species = "Gallimimus", weight = 2700 },
			{ species = "Pachy", weight = 1800 },
			{ species = "Compy", weight = 1000 },
			{ species = "Parasaur", weight = 380 },
			{ species = "Dilophosaurus", weight = 120 },
		},
		stock = { chance = 1, min = 3, max = 6 },
	},
	{
		id = "Swamp",
		name = "Swamp Egg",
		order = 2,
		price = 600,
		hatchSeconds = 90,
		colors = { main = { 90, 150, 140 }, spots = { 120, 90, 60 } },
		material = "SmoothPlastic",
		odds = {
			{ species = "Gallimimus", weight = 1500 },
			{ species = "Pachy", weight = 1500 },
			{ species = "Parasaur", weight = 2400 },
			{ species = "Dilophosaurus", weight = 2000 },
			{ species = "Stegosaurus", weight = 1300 },
			{ species = "Iguanodon", weight = 700 },
			{ species = "Triceratops", weight = 450 },
			{ species = "Ankylosaurus", weight = 150 },
		},
		stock = { chance = 0.85, min = 1, max = 4 },
	},
	{
		id = "Volcano",
		name = "Volcano Egg",
		order = 3,
		price = 7500,
		hatchSeconds = 300,
		colors = { main = { 90, 30, 30 }, spots = { 255, 120, 30 } },
		material = "SmoothPlastic",
		odds = {
			{ species = "Stegosaurus", weight = 1700 },
			{ species = "Iguanodon", weight = 800 },
			{ species = "Triceratops", weight = 2200 },
			{ species = "Ankylosaurus", weight = 2000 },
			{ species = "Pteranodon", weight = 1800 },
			{ species = "Carnotaurus", weight = 300 },
			{ species = "Brachiosaurus", weight = 800 },
			{ species = "Spinosaurus", weight = 350 },
			{ species = "TRex", weight = 50 },
		},
		stock = { chance = 0.5, min = 1, max = 2 },
	},
	{
		id = "Crystal",
		name = "Crystal Egg",
		order = 4,
		price = 90000,
		hatchSeconds = 900,
		colors = { main = { 160, 220, 255 }, spots = { 255, 255, 255 } },
		material = "Glass",
		odds = {
			{ species = "Triceratops", weight = 1000 },
			{ species = "Ankylosaurus", weight = 1500 },
			{ species = "Pteranodon", weight = 2500 },
			{ species = "Brachiosaurus", weight = 2500 },
			{ species = "Spinosaurus", weight = 1800 },
			{ species = "TRex", weight = 690 },
			{ species = "Mosasaurus", weight = 10 },
		},
		stock = { chance = 0.15, min = 1, max = 1 },
	},
	{
		id = "Glacier",
		name = "Glacier Egg",
		order = 5,
		price = 600000,
		hatchSeconds = 1800,
		colors = { main = { 200, 235, 255 }, spots = { 90, 160, 230 } },
		material = "SmoothPlastic",
		odds = {
			{ species = "Carnotaurus", weight = 2400 },
			{ species = "Therizinosaurus", weight = 2200 },
			{ species = "Quetzalcoatlus", weight = 1800 },
			{ species = "Brachiosaurus", weight = 1600 },
			{ species = "Spinosaurus", weight = 1300 },
			{ species = "Giganotosaurus", weight = 500 },
			{ species = "TRex", weight = 190 },
			{ species = "Cryolophosaurus", weight = 10 },
		},
		stock = { chance = 0.1, min = 1, max = 1 },
	},
	{
		id = "Abyss",
		name = "Abyss Egg",
		order = 6,
		price = 5000000,
		hatchSeconds = 2700,
		colors = { main = { 30, 50, 110 }, spots = { 80, 230, 220 } },
		material = "SmoothPlastic",
		odds = {
			{ species = "Quetzalcoatlus", weight = 2500 },
			{ species = "Therizinosaurus", weight = 2000 },
			{ species = "Spinosaurus", weight = 1800 },
			{ species = "Plesiosaurus", weight = 1900 },
			{ species = "Giganotosaurus", weight = 1200 },
			{ species = "TRex", weight = 500 },
			{ species = "Mosasaurus", weight = 80 },
			{ species = "Cryolophosaurus", weight = 20 },
		},
		stock = { chance = 0.06, min = 1, max = 1 },
	},
}

local BY_ID: { [string]: EggType } = {}
for _, egg in LIST do
	BY_ID[egg.id] = egg
end

local EggData = {
	LIST = LIST,
	BY_ID = BY_ID,
	TOTAL_BP = 10000,
}

function EggData.get(id: string): EggType?
	return BY_ID[id]
end

return EggData
