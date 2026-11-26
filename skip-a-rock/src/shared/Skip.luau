--!strict
-- How a skipping rock behaves. Pure maths, shared by the server (which
-- decides every throw) and the client (which draws the power meter).
--
-- Holding the throw button winds up a power needle that swings 0 -> 1 -> 0
-- every PERIOD seconds. Letting go in the gold zone (just under full power)
-- gives the most skips; the very top of the swing is too hard and the rock
-- dives straight in. The rock's flatness adds skips; its weight makes each
-- hop longer. This gives the throw's shape in "base" studs; the economy then
-- scales it up by your strength, rock and rebirths (see Economy).

local Skip = {}

Skip.PERIOD = 1.5 -- seconds for one full swing of the power needle (0 -> 1 -> 0)
Skip.SWEET = 0.86 -- the best power
Skip.SWEET_WIDTH = 0.6 -- quality falls to 0 this far from SWEET
Skip.PERFECT = 0.035 -- within this of SWEET counts as a perfect release
Skip.DIVE = 0.975 -- at or above this the rock is thrown too hard and dives in
Skip.PLOP = 0.12 -- below this it just plops in
Skip.GOLD_LOW = 0.74 -- the gold zone on the meter runs from here up to DIVE
Skip.PERFECT_BONUS = 3 -- extra skips for a perfect release
Skip.MIN_HOP = 0.9 -- hops never get shorter than this (base studs)

export type Verdict = "plop" | "dive" | "skips"

export type Outcome = {
	power: number,
	skips: number, -- times it bounced off the water
	hops: { number }, -- length of each hop between touches, in base studs
	distance: number, -- base studs from the first touch to where it sank
	perfect: boolean,
	verdict: Verdict,
}

export type RockStats = { flat: number, weight: number }

-- Where the power needle is after holding for `elapsed` seconds.
function Skip.power(elapsed: number): number
	local phase = (math.max(elapsed, 0) % Skip.PERIOD) / Skip.PERIOD
	return if phase < 0.5 then phase * 2 else 2 - phase * 2
end

-- 0..1: how good a release at this power is.
function Skip.quality(power: number): number
	return math.clamp(1 - math.abs(power - Skip.SWEET) / Skip.SWEET_WIDTH, 0, 1)
end

function Skip.isPerfect(power: number): boolean
	return math.abs(power - Skip.SWEET) <= Skip.PERFECT
end

-- The whole throw. `rand(a, b)` returns a random number in [a, b]; pass a
-- seeded one to get the same throw again.
function Skip.outcome(power: number, rock: RockStats, rand: (number, number) -> number): Outcome
	power = math.clamp(power, 0, 1)
	if power < Skip.PLOP then
		return {
			power = power,
			skips = 0,
			hops = {},
			distance = 0,
			perfect = false,
			verdict = "plop",
		}
	end
	if power >= Skip.DIVE then
		return {
			power = power,
			skips = 0,
			hops = {},
			distance = 0,
			perfect = false,
			verdict = "dive",
		}
	end
	local perfect = Skip.isPerfect(power)
	local quality = Skip.quality(power)
	local multiplier = 0.45 + 0.65 * rock.flat
	local skips = math.floor((1 + 22 * quality ^ 1.6) * multiplier * rand(0.9, 1.1) + 0.5)
	if perfect then
		skips += Skip.PERFECT_BONUS
	end
	skips = math.max(skips, 1)

	local first = (5 + 14 * power) * (0.8 + 0.4 * rock.weight)
	local decay = 0.8 + 0.1 * rock.flat
	local hops: { number } = {}
	local distance = 0
	for i = 1, skips do
		local hop = math.max(first * decay ^ (i - 1) * rand(0.94, 1.06), Skip.MIN_HOP)
		table.insert(hops, hop)
		distance += hop
	end
	return {
		power = power,
		skips = skips,
		hops = hops,
		distance = distance,
		perfect = perfect,
		verdict = "skips",
	}
end

return Skip
