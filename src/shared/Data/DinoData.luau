--!strict
-- Every dinosaur species in the game. Adding a dino = one entry here (plus a
-- line in an egg's odds table). Colors and sizes are plain numbers so the Lune
-- unit tests can load this file without Roblox datatypes.

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Secret"

export type Feature =
	"plates"
	| "frill"
	| "horns"
	| "club"
	| "sail"
	| "crest"
	| "dome"
	| "doubleCrest"
	| "wings"
	| "flippers"
	| "teeth"
	| "stripes"
	| "spikes"
	| "beakCrest"
	| "tailFin"

export type BodyKind = "biped" | "quad" | "flyer" | "swimmer"

export type BodyPlan = {
	kind: BodyKind,
	body: { number }, -- width, height, length (studs at scale 1)
	legHeight: number,
	legThickness: number,
	head: { number }, -- width, height, length
	neckLength: number,
	neckAngle: number, -- degrees above horizontal
	neckThickness: number,
	tailLength: number,
	tailThickness: number,
	arms: boolean,
	features: { Feature },
}

export type Rgb = { number }

export type Species = {
	id: string,
	name: string,
	rarity: Rarity,
	income: number, -- coins per second at Adult stage with no mutation
	growth: { number }, -- age (seconds) to become Juvenile, Adult, Giant
	layHatchSeconds: number, -- hatch time for eggs this dino lays
	scale: number, -- adult size multiplier
	colors: { main: Rgb, belly: Rgb, accent: Rgb },
	plan: BodyPlan,
	blurb: string,
}

export type RarityInfo = {
	order: number,
	color: Rgb,
	growth: { number },
	layHatchSeconds: number,
}

local RARITIES: { [Rarity]: RarityInfo } = {
	Common = {
		order = 1,
		color = { 190, 190, 190 },
		growth = { 300, 1800, 14400 },
		layHatchSeconds = 60,
	},
	Uncommon = {
		order = 2,
		color = { 110, 200, 110 },
		growth = { 480, 2700, 21600 },
		layHatchSeconds = 120,
	},
	Rare = {
		order = 3,
		color = { 80, 150, 255 },
		growth = { 600, 3600, 28800 },
		layHatchSeconds = 240,
	},
	Epic = {
		order = 4,
		color = { 180, 90, 255 },
		growth = { 900, 5400, 43200 },
		layHatchSeconds = 480,
	},
	Legendary = {
		order = 5,
		color = { 255, 185, 40 },
		growth = { 1200, 7200, 57600 },
		layHatchSeconds = 900,
	},
	Secret = {
		order = 6,
		color = { 255, 70, 120 },
		growth = { 1800, 10800, 86400 },
		layHatchSeconds = 1800,
	},
}

type SpeciesInput = {
	id: string,
	name: string,
	rarity: Rarity,
	income: number,
	scale: number,
	colors: { main: Rgb, belly: Rgb, accent: Rgb },
	plan: BodyPlan,
	blurb: string,
}

local function species(input: SpeciesInput): Species
	local rarity = RARITIES[input.rarity]
	return {
		id = input.id,
		name = input.name,
		rarity = input.rarity,
		income = input.income,
		growth = rarity.growth,
		layHatchSeconds = rarity.layHatchSeconds,
		scale = input.scale,
		colors = input.colors,
		plan = input.plan,
		blurb = input.blurb,
	}
end

local LIST: { Species } = {
	species({
		id = "Raptor",
		name = "Raptor",
		rarity = "Common",
		income = 2,
		scale = 1,
		colors = { main = { 120, 170, 90 }, belly = { 230, 220, 170 }, accent = { 70, 110, 60 } },
		plan = {
			kind = "biped",
			body = { 1.4, 1.4, 2.6 },
			legHeight = 1.4,
			legThickness = 0.45,
			head = { 0.9, 0.8, 1.3 },
			neckLength = 0.6,
			neckAngle = 35,
			neckThickness = 0.6,
			tailLength = 3,
			tailThickness = 0.7,
			arms = true,
			features = { "stripes" },
		},
		blurb = "Fast, clever and always hungry.",
	}),
	species({
		id = "Gallimimus",
		name = "Gallimimus",
		rarity = "Common",
		income = 3,
		scale = 1,
		colors = { main = { 220, 180, 110 }, belly = { 245, 230, 200 }, accent = { 170, 120, 70 } },
		plan = {
			kind = "biped",
			body = { 1.3, 1.3, 2.3 },
			legHeight = 2,
			legThickness = 0.4,
			head = { 0.6, 0.6, 0.9 },
			neckLength = 1.4,
			neckAngle = 55,
			neckThickness = 0.45,
			tailLength = 2.6,
			tailThickness = 0.6,
			arms = true,
			features = {},
		},
		blurb = "The speediest runner on the island.",
	}),
	species({
		id = "Pachy",
		name = "Pachycephalosaurus",
		rarity = "Common",
		income = 4,
		scale = 1.05,
		colors = { main = { 160, 120, 200 }, belly = { 230, 210, 240 }, accent = { 240, 200, 90 } },
		plan = {
			kind = "biped",
			body = { 1.6, 1.5, 2.4 },
			legHeight = 1.3,
			legThickness = 0.55,
			head = { 1, 1, 1.1 },
			neckLength = 0.5,
			neckAngle = 30,
			neckThickness = 0.7,
			tailLength = 2.4,
			tailThickness = 0.8,
			arms = true,
			features = { "dome" },
		},
		blurb = "Has a super hard head. Do not play bonk with it.",
	}),
	species({
		id = "Parasaur",
		name = "Parasaurolophus",
		rarity = "Uncommon",
		income = 10,
		scale = 1.3,
		colors = { main = { 230, 140, 90 }, belly = { 250, 220, 180 }, accent = { 200, 70, 60 } },
		plan = {
			kind = "biped",
			body = { 1.8, 1.7, 3 },
			legHeight = 1.6,
			legThickness = 0.6,
			head = { 0.9, 0.9, 1.4 },
			neckLength = 1,
			neckAngle = 45,
			neckThickness = 0.7,
			tailLength = 3,
			tailThickness = 0.9,
			arms = true,
			features = { "crest" },
		},
		blurb = "Toots through its crest like a trumpet.",
	}),
	species({
		id = "Dilophosaurus",
		name = "Dilophosaurus",
		rarity = "Uncommon",
		income = 12,
		scale = 1.15,
		colors = { main = { 90, 170, 190 }, belly = { 220, 240, 230 }, accent = { 230, 90, 110 } },
		plan = {
			kind = "biped",
			body = { 1.5, 1.4, 2.7 },
			legHeight = 1.5,
			legThickness = 0.5,
			head = { 0.85, 0.8, 1.3 },
			neckLength = 0.8,
			neckAngle = 40,
			neckThickness = 0.6,
			tailLength = 3,
			tailThickness = 0.75,
			arms = true,
			features = { "doubleCrest", "stripes" },
		},
		blurb = "Two fancy crests and a big attitude.",
	}),
	species({
		id = "Stegosaurus",
		name = "Stegosaurus",
		rarity = "Uncommon",
		income = 15,
		scale = 1.4,
		colors = { main = { 120, 160, 120 }, belly = { 220, 220, 180 }, accent = { 220, 120, 80 } },
		plan = {
			kind = "quad",
			body = { 2, 1.9, 3.4 },
			legHeight = 1.2,
			legThickness = 0.7,
			head = { 0.7, 0.6, 1 },
			neckLength = 0.7,
			neckAngle = 5,
			neckThickness = 0.7,
			tailLength = 2.8,
			tailThickness = 1,
			arms = false,
			features = { "plates", "spikes" },
		},
		blurb = "Plates on its back, spikes on its tail.",
	}),
	species({
		id = "Triceratops",
		name = "Triceratops",
		rarity = "Rare",
		income = 45,
		scale = 1.6,
		colors = { main = { 110, 140, 200 }, belly = { 220, 225, 240 }, accent = { 240, 190, 90 } },
		plan = {
			kind = "quad",
			body = { 2.4, 2, 3.4 },
			legHeight = 1.2,
			legThickness = 0.85,
			head = { 1.3, 1.2, 1.6 },
			neckLength = 0.4,
			neckAngle = 10,
			neckThickness = 1,
			tailLength = 2.2,
			tailThickness = 1,
			arms = false,
			features = { "frill", "horns" },
		},
		blurb = "Three horns, one giant frill, zero fear.",
	}),
	species({
		id = "Ankylosaurus",
		name = "Ankylosaurus",
		rarity = "Rare",
		income = 55,
		scale = 1.5,
		colors = { main = { 170, 140, 100 }, belly = { 230, 215, 190 }, accent = { 110, 90, 70 } },
		plan = {
			kind = "quad",
			body = { 2.6, 1.5, 3.2 },
			legHeight = 0.9,
			legThickness = 0.8,
			head = { 1, 0.8, 1 },
			neckLength = 0.3,
			neckAngle = 5,
			neckThickness = 0.9,
			tailLength = 2.6,
			tailThickness = 0.7,
			arms = false,
			features = { "club", "spikes" },
		},
		blurb = "A walking tank with a club for a tail.",
	}),
	species({
		id = "Pteranodon",
		name = "Pteranodon",
		rarity = "Rare",
		income = 65,
		scale = 1.4,
		colors = { main = { 200, 110, 140 }, belly = { 250, 225, 230 }, accent = { 120, 80, 150 } },
		plan = {
			kind = "flyer",
			body = { 1, 1, 1.8 },
			legHeight = 0.8,
			legThickness = 0.25,
			head = { 0.6, 0.6, 1.6 },
			neckLength = 0.6,
			neckAngle = 30,
			neckThickness = 0.4,
			tailLength = 0.4,
			tailThickness = 0.3,
			arms = false,
			features = { "wings", "beakCrest" },
		},
		blurb = "Rules the skies above the island.",
	}),
	species({
		id = "Brachiosaurus",
		name = "Brachiosaurus",
		rarity = "Epic",
		income = 220,
		scale = 1.8,
		colors = { main = { 130, 180, 210 }, belly = { 230, 240, 245 }, accent = { 80, 130, 170 } },
		plan = {
			kind = "quad",
			body = { 2.8, 2.6, 4.2 },
			legHeight = 2.4,
			legThickness = 0.9,
			head = { 0.9, 0.8, 1.2 },
			neckLength = 4.5,
			neckAngle = 65,
			neckThickness = 0.9,
			tailLength = 4,
			tailThickness = 1,
			arms = false,
			features = {},
		},
		blurb = "So tall it eats clouds for breakfast.",
	}),
	species({
		id = "Spinosaurus",
		name = "Spinosaurus",
		rarity = "Epic",
		income = 260,
		scale = 1.9,
		colors = { main = { 90, 120, 170 }, belly = { 210, 220, 230 }, accent = { 230, 100, 80 } },
		plan = {
			kind = "biped",
			body = { 2, 2, 4 },
			legHeight = 2,
			legThickness = 0.8,
			head = { 0.9, 0.9, 2 },
			neckLength = 1,
			neckAngle = 30,
			neckThickness = 0.9,
			tailLength = 4.2,
			tailThickness = 1,
			arms = true,
			features = { "sail", "teeth" },
		},
		blurb = "A giant sail on its back and a love of fish.",
	}),
	species({
		id = "TRex",
		name = "T-Rex",
		rarity = "Legendary",
		income = 1200,
		scale = 2.2,
		colors = { main = { 200, 70, 60 }, belly = { 245, 215, 180 }, accent = { 120, 40, 40 } },
		plan = {
			kind = "biped",
			body = { 2.4, 2.4, 4 },
			legHeight = 2.4,
			legThickness = 1,
			head = { 1.8, 1.6, 2.4 },
			neckLength = 0.8,
			neckAngle = 25,
			neckThickness = 1.3,
			tailLength = 4.5,
			tailThickness = 1.3,
			arms = true,
			features = { "teeth", "stripes" },
		},
		blurb = "The king of the dinosaurs. Tiny arms, giant roar.",
	}),
	species({
		id = "Mosasaurus",
		name = "Mosasaurus",
		rarity = "Secret",
		income = 6000,
		scale = 2,
		colors = { main = { 50, 90, 160 }, belly = { 220, 235, 245 }, accent = { 90, 200, 220 } },
		plan = {
			kind = "swimmer",
			body = { 2, 1.6, 5 },
			legHeight = 0.4,
			legThickness = 0,
			head = { 1.2, 1, 2.2 },
			neckLength = 0.4,
			neckAngle = 0,
			neckThickness = 1.2,
			tailLength = 4.5,
			tailThickness = 1,
			arms = false,
			features = { "flippers", "tailFin", "teeth" },
		},
		blurb = "A secret sea monster. How did it get in an egg?!",
	}),
}

local BY_ID: { [string]: Species } = {}
for _, s in LIST do
	BY_ID[s.id] = s
end

local DinoData = {
	LIST = LIST,
	BY_ID = BY_ID,
	RARITIES = RARITIES,
	RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Secret" } :: { Rarity },
}

function DinoData.get(id: string): Species?
	return BY_ID[id]
end

function DinoData.rarityInfo(rarity: Rarity): RarityInfo
	return RARITIES[rarity]
end

function DinoData.rarityOrder(id: string): number
	local s = BY_ID[id]
	if not s then
		return 0
	end
	return RARITIES[s.rarity].order
end

return DinoData
