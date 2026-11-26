--!strict
-- Unit tests for the pure game logic. Run from still-lake/: lune run tests/run

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./loader")

Loader.globals.Vector3 = roblox.Vector3

local Config = Loader.load("src/shared/Config")
local StoneData = Loader.load("src/shared/Data/StoneData")
local GoalData = Loader.load("src/shared/Data/GoalData")
local Skip = Loader.load("src/shared/Skip")
local Lake = Loader.load("src/shared/Lake")
local DayCycle = Loader.load("src/shared/DayCycle")

local Vector3 = roblox.Vector3

local passed, failed = 0, 0
local currentGroup = ""

local function describe(name: string, fn: () -> ())
	currentGroup = name
	fn()
end

local function it(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print(`FAIL  {currentGroup} > {name}\n      {err}`)
	end
end

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(`{label or "value"}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

local function near(actual: number, expected: number, tolerance: number, label: string?)
	if math.abs(actual - expected) > tolerance then
		error(`{label or "value"}: expected ~{expected}, got {actual}`, 2)
	end
end

local function ok(condition: any, label: string)
	if not condition then
		error(label, 2)
	end
end

-- rand(a, b) that always returns the middle, or one end
local function middle(a: number, b: number): number
	return (a + b) / 2
end
local function high(_a: number, b: number): number
	return b
end

describe("StoneData", function()
	it("has 12 stones with unique ids and sensible stats", function()
		eq(#StoneData.LIST, 12, "stone count")
		local seen = {}
		for _, stone in StoneData.LIST do
			ok(not seen[stone.id], "duplicate id " .. stone.id)
			seen[stone.id] = true
			ok(stone.flat > 0 and stone.flat <= 1, stone.id .. " flat")
			ok(stone.weight > 0 and stone.weight <= 1, stone.id .. " weight")
			ok(StoneData.RARITIES[stone.rarity] ~= nil, stone.id .. " rarity")
			eq(#stone.color, 3, stone.id .. " colour")
			eq(#stone.size, 3, stone.id .. " size")
		end
	end)
	it("everyone starts with the Pebble, which never washes up", function()
		local pebble = StoneData.get(StoneData.STARTER)
		ok(pebble, "starter exists")
		eq(pebble.findWeight, 0, "starter not findable")
		eq(StoneData.findChance(StoneData.STARTER), 0)
	end)
	it("rolls every findable stone as often as its find chance", function()
		local counts: { [string]: number } = {}
		local steps = 100000
		for k = 0, steps - 1 do
			local id = StoneData.roll(k / steps)
			counts[id] = (counts[id] or 0) + 1
		end
		local total = 0
		for _, stone in StoneData.LIST do
			local chance = StoneData.findChance(stone.id)
			total += chance
			near((counts[stone.id] or 0) / steps, chance, 0.0005, stone.id)
		end
		near(total, 1, 1e-9, "chances add up to 100%")
		eq(StoneData.roll(0.9999999), StoneData.LIST[#StoneData.LIST].id, "top end")
	end)
	it("rarer stones are better skippers", function()
		local best: { [number]: number } = {}
		for _, stone in StoneData.LIST do
			local order = StoneData.rarityInfo(stone.rarity).order
			best[order] = math.max(best[order] or 0, stone.flat + stone.weight)
		end
		for order = 2, 5 do
			ok(best[order] > best[order - 1], `rarity {order} beats {order - 1}`)
		end
	end)
end)

describe("Skip power needle", function()
	it("swings 0 -> 1 -> 0 every period", function()
		near(Skip.power(0), 0, 1e-9)
		near(Skip.power(Skip.PERIOD / 4), 0.5, 1e-9)
		near(Skip.power(Skip.PERIOD / 2), 1, 1e-9)
		near(Skip.power(Skip.PERIOD * 3 / 4), 0.5, 1e-9)
		near(Skip.power(Skip.PERIOD), 0, 1e-9)
		near(Skip.power(Skip.PERIOD * 2.25), 0.5, 1e-9, "repeats")
		near(Skip.power(-1), 0, 1e-9, "never negative")
	end)
	it("quality peaks at the sweet spot and the gold zone sits under the dive zone", function()
		eq(Skip.quality(Skip.SWEET), 1)
		ok(Skip.quality(0.5) < Skip.quality(0.8), "rises toward the sweet spot")
		ok(Skip.GOLD_LOW < Skip.SWEET - Skip.PERFECT, "perfect band inside gold")
		ok(Skip.SWEET + Skip.PERFECT < Skip.DIVE, "perfect band below the dive zone")
		ok(Skip.isPerfect(Skip.SWEET) and not Skip.isPerfect(Skip.SWEET + 0.05), "perfect band")
	end)
end)

describe("Skip outcome", function()
	local pebble = StoneData.get("pebble")
	local starstone = StoneData.get("starstone")
	local moonstone = StoneData.get("moonstone")

	it("too soft plops in and too hard dives in", function()
		local plop = Skip.outcome(0.05, pebble, middle)
		eq(plop.verdict, "plop")
		eq(plop.skips, 0)
		eq(#plop.hops, 0)
		local dive = Skip.outcome(0.99, pebble, middle)
		eq(dive.verdict, "dive")
		eq(dive.skips, 0)
	end)
	it("hops match the skip count, shrink, and add up to the distance", function()
		local out = Skip.outcome(0.8, pebble, middle)
		eq(out.verdict, "skips")
		eq(#out.hops, out.skips, "one hop per skip")
		local sum = 0
		for i, hop in out.hops do
			ok(hop >= Skip.MIN_HOP, "hop not too short")
			if i > 1 then
				ok(hop <= out.hops[i - 1], "hops shrink")
			end
			sum += hop
		end
		near(out.distance, sum, 1e-6, "distance")
	end)
	it("a perfect release adds bonus skips", function()
		local perfect = Skip.outcome(Skip.SWEET, pebble, middle)
		local almost = Skip.outcome(Skip.SWEET - Skip.PERFECT - 0.002, pebble, middle)
		ok(perfect.perfect and not almost.perfect, "perfect flag")
		ok(perfect.skips >= almost.skips + Skip.PERFECT_BONUS, "bonus skips")
	end)
	it("better stones skip more and further", function()
		local a = Skip.outcome(0.82, pebble, middle)
		local b = Skip.outcome(0.82, starstone, middle)
		ok(b.skips > a.skips, "more skips")
		ok(b.distance > a.distance, "further")
	end)
	it("Moonstone skips more at night", function()
		local day = Skip.outcome(0.82, moonstone, middle, { night = false })
		local night = Skip.outcome(0.82, moonstone, middle, { night = true })
		ok(night.skips > day.skips, "night bonus")
		local pebbleNight = Skip.outcome(0.82, pebble, middle, { night = true })
		eq(pebbleNight.skips, Skip.outcome(0.82, pebble, middle).skips, "others unchanged")
	end)
	it("a stone that runs out of lake lands on the far shore", function()
		local free = Skip.outcome(Skip.SWEET, starstone, high)
		ok(free.distance > 60, "a long throw")
		local out = Skip.outcome(Skip.SWEET, starstone, high, { available = 60 })
		eq(out.verdict, "shore")
		near(out.distance, 60, 1e-6, "stops at the shore")
		local sum = 0
		for _, hop in out.hops do
			sum += hop
		end
		near(sum, 60, 1e-6, "last hop reaches the shore")
		eq(#out.hops, out.skips, "hops match skips")
		ok(out.skips < free.skips, "fewer skips than on open water")
	end)
	it("is repeatable with the same random numbers", function()
		local seq1 = { 0.95, 1.0, 0.97, 1.02, 0.99, 1.05, 0.96 }
		local function seeded()
			local i = 0
			return function(a: number, b: number): number
				i += 1
				local t = (seq1[(i - 1) % #seq1 + 1] - 0.94) / 0.12
				return a + (b - a) * math.clamp(t, 0, 1)
			end
		end
		local x = Skip.outcome(0.78, pebble, seeded())
		local y = Skip.outcome(0.78, pebble, seeded())
		eq(x.skips, y.skips)
		near(x.distance, y.distance, 1e-9)
	end)
	it("titles are reachable but the top one needs the best stones", function()
		local pebbleBest = Skip.outcome(Skip.SWEET, pebble, high)
		ok(pebbleBest.skips >= 15 and pebbleBest.skips < 25, `pebble best {pebbleBest.skips}`)
		local starBest = Skip.outcome(Skip.SWEET, starstone, high)
		ok(starBest.skips >= 30, `starstone best {starBest.skips}`)
		local moonNight = Skip.outcome(Skip.SWEET, moonstone, high, { night = true })
		ok(moonNight.skips >= 30, `moonstone at night {moonNight.skips}`)
	end)
	it("long throws can cross the lake, but only the best ones", function()
		local across = 2 * Lake.EDGE - 30 -- from the end of a dock
		local star = Skip.outcome(Skip.SWEET, starstone, high)
		ok(star.distance >= across * 0.75, `starstone reaches {star.distance}`)
		local pebbleBest = Skip.outcome(Skip.SWEET, pebble, high)
		ok(pebbleBest.distance < across, `pebble stays on the lake ({pebbleBest.distance})`)
	end)
end)

describe("Lake", function()
	it("finds where a throw from the shore first touches the water", function()
		local origin = Vector3.new(0, 3, -(Config.LAKE_RADIUS + 6))
		local entry, reach = Lake.entry(origin, Vector3.new(0, 0, 1))
		ok(entry, "entry")
		near(reach, Config.LAKE_RADIUS + 6 - Lake.EDGE, 1e-6, "reach")
		near(entry.Z, -Lake.EDGE, 1e-6, "on the edge")
		eq(entry.Y, 0, "on the surface")
		near(Lake.openWater(entry, Vector3.new(0, 0, 1)), 2 * Lake.EDGE, 1e-6, "across the middle")
	end)
	it("throwing away from the lake never reaches it", function()
		local origin = Vector3.new(0, 3, -(Config.LAKE_RADIUS + 6))
		local entry = Lake.entry(origin, Vector3.new(0, 0, -1))
		eq(entry, nil)
	end)
	it("from a dock the stone lands just in front", function()
		local origin = Vector3.new(0, 3, -90)
		local entry, reach = Lake.entry(origin, Vector3.new(0, 0, 1))
		ok(entry, "entry")
		eq(reach, 0, "already over the water")
		near(entry.Z, -90 + Lake.DOCK_LEAD, 1e-6)
		-- facing back toward the beach leaves little open water
		ok(Lake.openWater(entry, Vector3.new(0, 0, -1)) < 25, "short way back")
	end)
	it("knows where the docks are", function()
		for _, angle in Lake.DOCK_ANGLES do
			local along = Vector3.new(math.sin(angle), 0, math.cos(angle))
			local across = Vector3.new(math.cos(angle), 0, -math.sin(angle))
			ok(Lake.underDock(along * (Lake.DOCK_INNER + 1)), "the lake end")
			ok(Lake.underDock(along * (Lake.DOCK_OUTER - 1)), "the land end")
			ok(Lake.underDock(along * 100 + across * (Lake.DOCK_WIDTH / 2 - 0.1)), "the edge")
			ok(not Lake.underDock(along * 100 + across * (Lake.DOCK_WIDTH / 2 + 0.5)), "beside it")
			ok(not Lake.underDock(along * (Lake.DOCK_INNER - 1)), "past the end")
			ok(not Lake.underDock(-along * 100), "the far side of the lake")
		end
	end)
	it("from a dock the stone lands clear of the planks, whichever way you face", function()
		local angle = Lake.DOCK_ANGLES[1]
		local along = Vector3.new(math.sin(angle), 0, math.cos(angle))
		local across = Vector3.new(math.cos(angle), 0, -math.sin(angle))
		local stand = along * 100 + Vector3.new(0, 3, 0)
		local sideways = Lake.entry(stand, across)
		ok(
			sideways and (sideways - Vector3.new(stand.X, 0, stand.Z)).Magnitude < 6,
			"sideways is close"
		)
		for _, direction in { -along, across, -across, (across - along).Unit } do
			local entry, reach = Lake.entry(stand, direction)
			ok(entry, "lands")
			ok(not Lake.underDock(entry), "clear of the dock")
			eq(reach, 0, "standing over the water")
			-- sideways it clears the planks at once; forward it flies past the end
			local flight = (entry - Vector3.new(stand.X, 0, stand.Z)).Magnitude
			ok(flight <= 100 - Lake.DOCK_INNER + 1, `close in front ({flight})`)
		end
		-- from the land end of a dock, along it: the stone sails past the planks
		local landEnd = along * (Lake.DOCK_OUTER - 6) + Vector3.new(0, 3, 0)
		local entry, reach = Lake.entry(landEnd, -along)
		ok(entry and not Lake.underDock(entry), "clear of the dock")
		near(reach, Lake.DOCK_OUTER - 6 - Lake.EDGE, 1e-4, "reach is to the water")
		-- beside a dock on the beach, throwing across it: clear too
		local beside = along * (Lake.EDGE + 4) + across * 8 + Vector3.new(0, 3, 0)
		local across1 = Lake.entry(beside, (-across * 2 - along).Unit)
		ok(across1 == nil or not Lake.underDock(across1), "never under the planks")
		local back = Lake.entry(along * (Lake.DOCK_INNER + 2) + Vector3.new(0, 3, 0), along)
		ok(
			back == nil or Lake.openWater(back, along) < Lake.MIN_OPEN_WATER,
			"not back along the dock"
		)
	end)
	it("flattens directions and rejects straight up or broken ones", function()
		local flat = Lake.flatten(Vector3.new(3, 5, 4))
		ok(flat, "flat")
		near(flat.Magnitude, 1, 1e-9)
		eq(flat.Y, 0)
		eq(Lake.flatten(Vector3.new(0, 1, 0)), nil, "straight up")
		eq(Lake.flatten(Vector3.new(0 / 0, 0, 1)), nil, "NaN")
		eq(Lake.flatten(Vector3.new(math.huge, 0, 1)), nil, "infinite")
		eq(Lake.flatten(Vector3.new(-math.huge, 0, math.huge)), nil, "both infinite")
	end)
end)

describe("GoalData", function()
	it("goals have unique ids and the collection goal needs every stone", function()
		local seen = {}
		for _, goal in GoalData.GOALS do
			ok(not seen[goal.id], "duplicate " .. goal.id)
			seen[goal.id] = true
		end
		eq(GoalData.get("stones12").value, #StoneData.LIST, "every stone")
	end)
	it("titles follow your best throw", function()
		eq(GoalData.title(0), nil)
		eq(GoalData.title(4), nil)
		eq(GoalData.title(5), "Ripple Rookie")
		eq(GoalData.title(19), "Skimmer")
		eq(GoalData.title(30), "Legend of Still Lake")
		eq(GoalData.title(99), "Legend of Still Lake")
	end)
	it("measures progress", function()
		local stats = {
			bestSkips = 12,
			bestDistance = 70,
			perfects = 3,
			stones = 5,
			shore = false,
			nightSkips = 0,
			throws = 40,
		}
		ok(GoalData.isDone(GoalData.get("skip10"), stats), "10 skips done")
		ok(not GoalData.isDone(GoalData.get("skip15"), stats), "15 not yet")
		ok(GoalData.isDone(GoalData.get("far50"), stats), "50 studs")
		ok(not GoalData.isDone(GoalData.get("shore"), stats), "not across yet")
		stats.shore = true
		ok(GoalData.isDone(GoalData.get("shore"), stats), "across")
		eq(GoalData.progress(GoalData.get("throws100"), stats), 40)
	end)
end)

describe("DayCycle", function()
	it("runs 6:00 -> 19:00 by day, then through the night back to 6:00", function()
		near(DayCycle.clockTime(0), 6, 1e-9)
		near(DayCycle.clockTime(Config.DAY_LENGTH * DayCycle.DAY_SHARE), 19, 1e-6)
		near(DayCycle.clockTime(Config.DAY_LENGTH * 0.999), 5.96, 0.05)
		local night = 0
		for k = 0, 999 do
			local t = DayCycle.clockTime(k / 1000 * Config.DAY_LENGTH)
			ok(t >= 0 and t < 24, "valid clock time")
			if DayCycle.isNightAt(t) then
				night += 1
			end
		end
		ok(night > 150 and night < 300, `night share {night / 10}%`)
	end)
	it("phaseFor undoes clockTime", function()
		for _, clock in { 0, 3.5, 5.99, 6, 9, 12.25, 18.9, 19, 21, 23.99 } do
			local phase = DayCycle.phaseFor(clock)
			ok(phase >= 0 and phase < 1, `phase {phase}`)
			near(DayCycle.clockTime(phase * Config.DAY_LENGTH), clock, 1e-6, `clock {clock}`)
		end
	end)
	it("darkness eases from day to night and back", function()
		eq(DayCycle.darkness(12), 0, "noon")
		eq(DayCycle.darkness(23), 1, "late night")
		eq(DayCycle.darkness(2), 1, "small hours")
		local dusk = DayCycle.darkness(18.75)
		ok(dusk > 0.2 and dusk < 0.8, `dusk {dusk}`)
		local last = 0
		for clock = 17.5, 20, 0.1 do
			local d = DayCycle.darkness(clock)
			ok(d >= last - 1e-9, "only gets darker through dusk")
			last = d
		end
		near(DayCycle.darkness(6.5), 0, 1e-9, "full day by 6:30")
	end)
end)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
