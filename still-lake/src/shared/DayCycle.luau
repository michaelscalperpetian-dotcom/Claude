--!strict
-- The lake's day: a long golden day, then dusk, a starry night and dawn, every
-- Config.DAY_LENGTH seconds. Everyone sees the same time because it comes
-- from the server clock.

local Config = require(script.Parent.Config)

local DayCycle = {}

DayCycle.DAY_SHARE = 0.7 -- share of the cycle that is daytime (6:00 to 19:00)
DayCycle.NIGHT_FROM = 19.5 -- clock hours that count as night (for Moonstone, lanterns, fireflies)
DayCycle.NIGHT_UNTIL = 5.5

-- Lighting.ClockTime (0..24) at server time `now`.
function DayCycle.clockTime(now: number): number
	local phase = (now % Config.DAY_LENGTH) / Config.DAY_LENGTH
	if phase < DayCycle.DAY_SHARE then
		return 6 + phase / DayCycle.DAY_SHARE * 13
	end
	local nightPhase = (phase - DayCycle.DAY_SHARE) / (1 - DayCycle.DAY_SHARE)
	return (19 + nightPhase * 11) % 24
end

-- The inverse of clockTime: where in the cycle (0..1) the clock reads `clock`.
function DayCycle.phaseFor(clock: number): number
	local c = clock % 24
	if c >= 6 and c < 19 then
		return (c - 6) / 13 * DayCycle.DAY_SHARE
	end
	local sinceDusk = (c - 19) % 24 -- 0..11 hours into the night
	return DayCycle.DAY_SHARE + sinceDusk / 11 * (1 - DayCycle.DAY_SHARE)
end

-- How dark it is, 0 (day) .. 1 (deep night), easing through dusk and dawn.
function DayCycle.darkness(clock: number): number
	local c = clock % 24
	local function smooth(t: number): number
		local x = math.clamp(t, 0, 1)
		return x * x * (3 - 2 * x)
	end
	if c >= 17.5 then
		return smooth((c - 17.5) / 2.5) -- dusk: 17:30 -> 20:00
	elseif c < 4.5 then
		return 1
	elseif c < 6.5 then
		return 1 - smooth((c - 4.5) / 2) -- dawn: 4:30 -> 6:30
	end
	return 0
end

function DayCycle.isNightAt(clockTime: number): boolean
	return clockTime >= DayCycle.NIGHT_FROM or clockTime < DayCycle.NIGHT_UNTIL
end

function DayCycle.isNight(now: number): boolean
	return DayCycle.isNightAt(DayCycle.clockTime(now))
end

return DayCycle
