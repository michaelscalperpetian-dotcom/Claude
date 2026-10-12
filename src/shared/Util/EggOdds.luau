--!strict
-- The single source for "what are the odds for this egg right now". The server
-- rolls with these tables and the client's Odds panel displays these tables,
-- so the shown odds are always the real odds.

local Config = require(script.Parent.Parent.Config)
local DinoData = require(script.Parent.Parent.Data.DinoData)
local EggData = require(script.Parent.Parent.Data.EggData)
local MutationData = require(script.Parent.Parent.Data.MutationData)
local Cycle = require(script.Parent.Cycle)
local Odds = require(script.Parent.Odds)

local EggOdds = {}

local RARE_ORDER = DinoData.rarityInfo("Rare").order

-- Species chances (basis points, summing to exactly 10000) for an egg type.
function EggOdds.species(eggId: string, luckActive: boolean): { Odds.Chance }
	local egg = EggData.get(eggId)
	if not egg then
		return {}
	end
	local multiplier = if luckActive then Config.LUCK_MULTIPLIER else 1
	return Odds.chances(egg.odds, DinoData.rarityOrder, multiplier, RARE_ORDER)
end

-- Mutation chances for a hatch at `cycleTime` (storms change them).
function EggOdds.mutations(cycleTime: number): { MutationData.MutationChance }
	local storm = Cycle.storm(cycleTime)
	local kind: MutationData.StormKind? = if storm.active then storm.kind else nil
	return MutationData.hatchChances(kind, storm.active and storm.mega)
end

return EggOdds
