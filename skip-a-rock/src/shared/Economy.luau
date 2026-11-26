--!strict
-- The simulator's numbers: how far a throw goes, what it pays, what
-- upgrades and rebirths cost. Pure maths so both sides (and the tests,
-- which check the pacing) agree.
--
--   distance = base throw x strength x rock power x rebirth power (x night, for Moonstone)
--   coins    = (distance / 10 + skips x 2) x coin multiplier (x1.25 for a perfect release)
--   coin multiplier = (1 + rebirths / 2) x (1 + island bonuses)
--
-- Strength gets dearer faster than it gets stronger, so each upgrade takes a
-- little longer than the last, until a rebirth (which resets coins and
-- strength but keeps your rocks and islands) speeds everything up again.

local IslandData = require(script.Parent.Data.IslandData)
local RockData = require(script.Parent.Data.RockData)

local Economy = {}

Economy.STRENGTH_STEP = 1.1 -- each strength level throws this much further
Economy.STRENGTH_BASE_COST = 20
Economy.STRENGTH_COST_GROWTH = 1.33
Economy.REBIRTH_BASE_COST = 40000
Economy.REBIRTH_COST_GROWTH = 7
Economy.REBIRTH_DISTANCE = 0.2 -- each rebirth: +20% distance...
Economy.REBIRTH_COINS = 0.5 -- ...and +50% coins
Economy.PERFECT_COINS = 1.25
Economy.MAX_STRENGTH = 500

-- What these formulas need to know about a player.
export type Stats = {
	strength: number,
	rebirths: number,
	equipped: string,
	islands: { [string]: boolean },
}

-- The parts of a saved profile these formulas read.
function Economy.statsOf(profile: {
	strength: number,
	rebirths: number,
	equipped: string,
	islands: { [string]: boolean },
}): Stats
	return {
		strength = profile.strength,
		rebirths = profile.rebirths,
		equipped = profile.equipped,
		islands = profile.islands,
	}
end

function Economy.strengthPower(level: number): number
	return Economy.STRENGTH_STEP ^ level
end

-- Coins to go from `level` to `level + 1`.
function Economy.strengthCost(level: number): number
	return math.floor(Economy.STRENGTH_BASE_COST * Economy.STRENGTH_COST_GROWTH ^ level)
end

-- Coins needed for the next rebirth.
function Economy.rebirthCost(rebirths: number): number
	return Economy.REBIRTH_BASE_COST * Economy.REBIRTH_COST_GROWTH ^ rebirths
end

function Economy.rebirthPower(rebirths: number): number
	return 1 + Economy.REBIRTH_DISTANCE * rebirths
end

function Economy.islandBonus(islands: { [string]: boolean }): number
	local bonus = 0
	for _, island in IslandData.LIST do
		if islands[island.id] then
			bonus += island.bonus
		end
	end
	return bonus
end

function Economy.coinMultiplier(stats: Stats): number
	return (1 + Economy.REBIRTH_COINS * stats.rebirths) * (1 + Economy.islandBonus(stats.islands))
end

function Economy.rockOf(stats: Stats): RockData.Rock
	return (RockData.get(stats.equipped) or RockData.get(RockData.STARTER)) :: RockData.Rock
end

-- Everything that multiplies a throw's base distance.
function Economy.distanceMultiplier(stats: Stats, night: boolean): number
	local rock = Economy.rockOf(stats)
	local nightBonus = if night and rock.nightBonus then 1 + rock.nightBonus else 1
	return Economy.strengthPower(stats.strength)
		* rock.power
		* Economy.rebirthPower(stats.rebirths)
		* nightBonus
end

function Economy.coinsFor(distance: number, skips: number, perfect: boolean, stats: Stats): number
	local raw = (distance / 10 + skips * 2) * Economy.coinMultiplier(stats)
	if perfect then
		raw *= Economy.PERFECT_COINS
	end
	return math.floor(raw)
end

-- Can this rock be bought with these islands reached (ignoring price)?
function Economy.rockUnlocked(rock: RockData.Rock, islands: { [string]: boolean }): boolean
	return rock.island == nil or islands[rock.island] == true
end

return Economy
