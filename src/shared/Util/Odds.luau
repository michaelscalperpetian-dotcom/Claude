--!strict
-- Egg odds math. The same function produces both the odds shown in the
-- "Odds" panel and the table the server rolls against, so displayed odds are
-- always the real odds (Roblox paid random item policy). Pure: runs under Lune.

local Odds = {}

export type Entry = { species: string, weight: number }
export type Chance = { species: string, bp: number }

Odds.TOTAL_BP = 10000

-- Scale weights to integers that sum to exactly TOTAL_BP using the largest
-- remainder method, so the percentages always add up to exactly 100%.
local function normalize(species: { string }, weights: { number }): { Chance }
	local sum = 0
	for _, w in weights do
		sum += w
	end
	local result: { Chance } = {}
	if sum <= 0 then
		return result
	end

	local floors: { number } = {}
	local remainders: { { index: number, frac: number } } = {}
	local assigned = 0
	for i, w in weights do
		local exact = w * Odds.TOTAL_BP / sum
		local f = math.floor(exact)
		floors[i] = f
		assigned += f
		table.insert(remainders, { index = i, frac = exact - f })
	end

	table.sort(remainders, function(a, b)
		if a.frac == b.frac then
			return a.index < b.index
		end
		return a.frac > b.frac
	end)

	local leftover = Odds.TOTAL_BP - assigned
	for i = 1, leftover do
		local r = remainders[((i - 1) % #remainders) + 1]
		floors[r.index] += 1
	end

	for i, name in species do
		table.insert(result, { species = name, bp = floors[i] })
	end
	return result
end

-- luckMultiplier multiplies the weight of every species whose rarity order is
-- >= luckMinRarity. Pass 1 for no luck.
function Odds.chances(
	entries: { Entry },
	rarityOf: (string) -> number,
	luckMultiplier: number,
	luckMinRarity: number
): { Chance }
	local names: { string } = {}
	local weights: { number } = {}
	for i, e in entries do
		names[i] = e.species
		local w = e.weight
		if luckMultiplier ~= 1 and rarityOf(e.species) >= luckMinRarity then
			w *= luckMultiplier
		end
		weights[i] = w
	end
	return normalize(names, weights)
end

-- r must be in [0, 1). Returns the species whose bp range contains r.
function Odds.roll(chances: { Chance }, r: number): string
	-- (the tiny nudge stops 0.1415 * 10000 = 1414.9999... landing one bp early)
	local target =
		math.min(math.floor(math.clamp(r, 0, 1) * Odds.TOTAL_BP + 1e-6), Odds.TOTAL_BP - 1)
	local cumulative = 0
	for _, c in chances do
		cumulative += c.bp
		if target < cumulative then
			return c.species
		end
	end
	return chances[#chances].species
end

-- Generic weighted pick over keys with bp values (used for mutations).
-- `none` is returned when r lands outside every listed bp range.
function Odds.pick<T>(entries: { { key: T, bp: number } }, r: number): T?
	-- (the tiny nudge stops 0.1415 * 10000 = 1414.9999... landing one bp early)
	local target =
		math.min(math.floor(math.clamp(r, 0, 1) * Odds.TOTAL_BP + 1e-6), Odds.TOTAL_BP - 1)
	local cumulative = 0
	for _, e in entries do
		cumulative += e.bp
		if target < cumulative then
			return e.key
		end
	end
	return nil
end

-- "12.5%", "0.1%", "45%"
function Odds.format(bp: number): string
	local percent = bp / 100
	if percent == math.floor(percent) then
		return string.format("%d%%", percent)
	end
	local s = string.format("%.2f", percent)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s .. "%"
end

return Odds
