--!strict
-- Mutations multiply a dino's income and change how it looks. Storms boost the
-- chance of one mutation for everyone in the game at the same time.

export type MutationId = "Glossy" | "Lava" | "Frost" | "Cosmic" | "Rainbow"

export type Mutation = {
	id: MutationId,
	name: string,
	multiplier: number,
	emoji: string,
	color: { number },
}

export type StormKind = "Lava" | "Frost" | "Cosmic"

export type Storm = {
	kind: StormKind,
	name: string,
	emoji: string,
	weight: number,
}

local MUTATIONS: { [string]: Mutation } = {
	Glossy = {
		id = "Glossy",
		name = "Glossy",
		multiplier = 1.5,
		emoji = "✨",
		color = { 255, 250, 210 },
	},
	Lava = { id = "Lava", name = "Lava", multiplier = 3, emoji = "🌋", color = { 255, 110, 30 } },
	Frost = {
		id = "Frost",
		name = "Frost",
		multiplier = 3,
		emoji = "❄️",
		color = { 170, 225, 255 },
	},
	Cosmic = {
		id = "Cosmic",
		name = "Cosmic",
		multiplier = 5,
		emoji = "🌌",
		color = { 150, 90, 255 },
	},
	Rainbow = {
		id = "Rainbow",
		name = "Rainbow",
		multiplier = 8,
		emoji = "🌈",
		color = { 255, 120, 200 },
	},
}

local STORMS: { Storm } = {
	{ kind = "Lava", name = "Lava Storm", emoji = "🌋", weight = 40 },
	{ kind = "Frost", name = "Blizzard", emoji = "❄️", weight = 40 },
	{ kind = "Cosmic", name = "Meteor Shower", emoji = "🌠", weight = 20 },
}

local MutationData = {
	MUTATIONS = MUTATIONS,
	ORDER = { "Glossy", "Lava", "Frost", "Cosmic", "Rainbow" } :: { MutationId },
	STORMS = STORMS,
	MEGA_STORM_NAME = "Rainbow Mega Storm",
	MEGA_STORM_EMOJI = "🌈",

	-- Hatch mutation chances in basis points (1 bp = 0.01%).
	BASE_GLOSSY_BP = 200,
	STORM_MUTATION_BP = 1000,
	MEGA_RAINBOW_BP = 1500,
	MEGA_COSMIC_BP = 500,
	MEGA_GLOSSY_BP = 600,

	-- While a storm is active, each unmutated dino gets this chance per storm tick.
	STORM_DINO_MUTATE_BP = 150,
	MEGA_STORM_MULTIPLIER = 3,
}

export type MutationChance = { key: MutationId, bp: number }

-- Chances for a dino hatching right now. `stormKind` is the active storm (or nil).
function MutationData.hatchChances(stormKind: StormKind?, mega: boolean): { MutationChance }
	if mega then
		return {
			{ key = "Rainbow", bp = MutationData.MEGA_RAINBOW_BP },
			{ key = "Cosmic", bp = MutationData.MEGA_COSMIC_BP },
			{ key = "Glossy", bp = MutationData.MEGA_GLOSSY_BP },
		}
	elseif stormKind then
		return {
			{ key = stormKind :: MutationId, bp = MutationData.STORM_MUTATION_BP },
			{ key = "Glossy", bp = MutationData.BASE_GLOSSY_BP },
		}
	end
	return { { key = "Glossy", bp = MutationData.BASE_GLOSSY_BP } }
end

-- Which mutation a storm gives to dinos already living in nests.
function MutationData.stormGives(stormKind: StormKind?, mega: boolean): MutationId?
	if mega then
		return "Rainbow"
	end
	return stormKind
end

function MutationData.stormTickBp(mega: boolean): number
	return MutationData.STORM_DINO_MUTATE_BP
		* (if mega then MutationData.MEGA_STORM_MULTIPLIER else 1)
end

function MutationData.stormInfo(kind: StormKind): Storm
	for _, s in STORMS do
		if s.kind == kind then
			return s
		end
	end
	return STORMS[1]
end

function MutationData.get(id: string?): Mutation?
	if id == nil then
		return nil
	end
	return MUTATIONS[id]
end

function MutationData.multiplier(id: string?): number
	local m = MutationData.get(id)
	return if m then m.multiplier else 1
end

return MutationData
