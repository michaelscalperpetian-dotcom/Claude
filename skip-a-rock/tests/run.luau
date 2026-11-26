--!strict
-- Unit tests for the pure game rules. Run from skip-a-rock/: lune run tests/run

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./loader")

Loader.globals.Vector3 = roblox.Vector3

local Config = Loader.load("src/shared/Config")
local RockData = Loader.load("src/shared/Data/RockData")
local IslandData = Loader.load("src/shared/Data/IslandData")
local GoalData = Loader.load("src/shared/Data/GoalData")
local Skip = Loader.load("src/shared/Skip")
local Economy = Loader.load("src/shared/Economy")
local Sea = Loader.load("src/shared/Sea")
local Land = Loader.load("src/shared/Land")
local DayCycle = Loader.load("src/shared/DayCycle")
local Format = Loader.load("src/shared/Util/Format")
local Rng = Loader.load("src/shared/Util/Rng")

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

local function middle(a: number, b: number): number
	return (a + b) / 2
end
local function high(_a: number, b: number): number
	return b
end

local pebble = RockData.get("pebble")
local starstone = RockData.get("starstone")

describe("Format", function()
	it("abbreviates big numbers the simulator way", function()
		eq(Format.short(0), "0")
		eq(Format.short(999), "999")
		eq(Format.short(1000), "1K")
		eq(Format.short(1500), "1.5K")
		eq(Format.short(12345), "12.3K")
		eq(Format.short(999950), "1M", "rounds up into the next suffix")
		eq(Format.short(2.5e9), "2.5B")
		eq(Format.short(7e12), "7T")
		eq(Format.short(3e15), "3Qa")
		eq(Format.short(-4200), "-4.2K")
		eq(Format.short(0 / 0), "0", "NaN never shows")
	end)
	it("writes multipliers with their decimals while they're small", function()
		eq(Format.times(1), "x1")
		eq(Format.times(1.6), "x1.6")
		eq(Format.times(1.576), "x1.58")
		eq(Format.times(12.4), "x12")
		eq(Format.times(3400), "x3.4K")
	end)
	it("writes exact counts with commas", function()
		eq(Format.commas(0), "0")
		eq(Format.commas(1234567), "1,234,567")
		eq(Format.commas(100), "100")
	end)
end)

describe("Skip", function()
	it("the power needle swings up and back down", function()
		near(Skip.power(0), 0, 1e-9)
		near(Skip.power(Skip.PERIOD / 2), 1, 1e-9)
		near(Skip.power(Skip.PERIOD), 0, 1e-9)
		near(Skip.power(Skip.PERIOD / 4), 0.5, 1e-9)
	end)
	it("too soft plops, too hard dives", function()
		eq(Skip.outcome(0.05, pebble, middle).verdict, "plop")
		eq(Skip.outcome(0.99, pebble, middle).verdict, "dive")
		eq(Skip.outcome(0.99, pebble, middle).skips, 0)
	end)
	it("a perfect release skips more than a sloppy one, and one hop per skip", function()
		local perfect = Skip.outcome(Skip.SWEET, pebble, middle)
		local sloppy = Skip.outcome(0.4, pebble, middle)
		ok(perfect.perfect and not sloppy.perfect, "perfect flag")
		ok(perfect.skips > sloppy.skips, "more skips")
		eq(#perfect.hops, perfect.skips)
		local sum = 0
		for _, hop in perfect.hops do
			sum += hop
		end
		near(sum, perfect.distance, 1e-9)
	end)
	it("better rocks skip more", function()
		ok(
			Skip.outcome(Skip.SWEET, starstone, middle).skips
				> Skip.outcome(Skip.SWEET, pebble, middle).skips,
			"starstone"
		)
	end)
	it("the same random numbers give the same throw", function()
		local a = Skip.outcome(0.8, pebble, middle)
		local b = Skip.outcome(0.8, pebble, middle)
		eq(a.skips, b.skips)
		near(a.distance, b.distance, 1e-9)
		ok(
			Skip.outcome(Skip.SWEET, pebble, high).distance > a.distance,
			"luckier numbers fly further"
		)
	end)
end)

describe("Rocks and islands", function()
	it("every rock is stronger and dearer than the one before", function()
		for i = 2, #RockData.LIST do
			local a, b = RockData.LIST[i - 1], RockData.LIST[i]
			ok(b.power > a.power, `{b.id} power`)
			ok(b.price > a.price, `{b.id} price`)
			ok(b.flat >= 0 and b.flat <= 1 and b.weight >= 0 and b.weight <= 1, `{b.id} stats`)
			ok(RockData.rarityInfo(b.rarity), `{b.id} rarity`)
		end
		eq(RockData.LIST[1].id, RockData.STARTER)
		eq(RockData.LIST[1].price, 0)
	end)
	it("locked rocks name real islands", function()
		for _, rock in RockData.LIST do
			if rock.island then
				ok(IslandData.get(rock.island), `{rock.id} needs {rock.island}`)
			end
		end
	end)
	it("islands get further and better", function()
		for i = 2, #IslandData.LIST do
			local a, b = IslandData.LIST[i - 1], IslandData.LIST[i]
			ok(b.distance > a.distance, b.id)
			ok(b.bonus > a.bonus, b.id)
		end
	end)
	it("the next island is the first not reached", function()
		eq(IslandData.next({}).id, "buoy")
		eq(IslandData.next({ buoy = true }).id, "gull")
		local all = {}
		for _, island in IslandData.LIST do
			all[island.id] = true
		end
		eq(IslandData.next(all), nil)
	end)
end)

describe("Economy", function()
	local fresh = { strength = 0, rebirths = 0, equipped = "pebble", islands = {} }
	it("strength throws further and costs more each level", function()
		eq(Economy.strengthPower(0), 1)
		ok(Economy.strengthPower(10) > Economy.strengthPower(9), "stronger")
		ok(Economy.strengthCost(10) > Economy.strengthCost(9), "dearer")
		-- cost grows faster than power, so upgrades slow down
		ok(Economy.STRENGTH_COST_GROWTH > Economy.STRENGTH_STEP, "costs outpace power")
	end)
	it("a first throw pays a few coins, and the first upgrade is cheap", function()
		local o = Skip.outcome(0.8, pebble, middle)
		local coins = Economy.coinsFor(
			o.distance * Economy.distanceMultiplier(fresh, false),
			o.skips,
			false,
			fresh
		)
		ok(coins >= 5 and coins <= 60, `first throw pays {coins}`)
		ok(Economy.strengthCost(0) <= coins * 3, "first upgrade within a few throws")
	end)
	it("rebirths, islands and night stones all multiply", function()
		local reborn = {
			strength = 0,
			rebirths = 2,
			equipped = "pebble",
			islands = { buoy = true, gull = true },
		}
		near(Economy.coinMultiplier(reborn), (1 + 2 * Economy.REBIRTH_COINS) * 1.15, 1e-9)
		ok(
			Economy.distanceMultiplier(reborn, false) > Economy.distanceMultiplier(fresh, false),
			"rebirth distance"
		)
		local moon = { strength = 0, rebirths = 0, equipped = "moonstone", islands = {} }
		near(
			Economy.distanceMultiplier(moon, true) / Economy.distanceMultiplier(moon, false),
			1.5,
			1e-9
		)
		eq(
			Economy.distanceMultiplier(fresh, true),
			Economy.distanceMultiplier(fresh, false),
			"pebble ignores night"
		)
	end)
	it("a perfect release pays a bonus", function()
		ok(
			Economy.coinsFor(100, 10, true, fresh) > Economy.coinsFor(100, 10, false, fresh),
			"bonus"
		)
	end)
	it("rocks behind islands stay locked until you reach them", function()
		local basalt = RockData.get("basalt")
		eq(Economy.rockUnlocked(basalt, {}), false)
		eq(Economy.rockUnlocked(basalt, { gull = true }), true)
		eq(Economy.rockUnlocked(pebble, {}), true)
	end)
	it("an unknown equipped rock falls back to the Pebble", function()
		eq(
			Economy.rockOf({ strength = 0, rebirths = 0, equipped = "nope", islands = {} }).id,
			"pebble"
		)
	end)
	it("pacing: a decent player rebirths in about a quarter hour, and the game lasts", function()
		-- a greedy player who lets go anywhere from just below the gold to
		-- almost too hard, buying the best rock, then strength, rebirthing asap
		local gen = Rng.new(7)
		local function rand(a: number, b: number): number
			return a + (b - a) * gen.next()
		end
		local stats = {
			strength = 0,
			rebirths = 0,
			equipped = "pebble",
			islands = {} :: { [string]: boolean },
		}
		local owned: { [string]: boolean } = { pebble = true }
		local coins = 0
		local firstRebirth, moonstoneAt = nil :: number?, nil :: number?
		for t = 1, 30000 do
			local rock = Economy.rockOf(stats)
			local o = Skip.outcome(rand(0.72, 0.95), rock, rand)
			local d = o.distance * Economy.distanceMultiplier(stats, false)
			coins += Economy.coinsFor(d, o.skips, o.perfect, stats)
			for _, island in IslandData.LIST do
				if d >= island.distance then
					stats.islands[island.id] = true
				end
			end
			if coins >= Economy.rebirthCost(stats.rebirths) then
				stats.rebirths += 1
				stats.strength = 0
				coins = 0
				firstRebirth = firstRebirth or t
			end
			for _, r in RockData.LIST do
				if
					not owned[r.id]
					and Economy.rockUnlocked(r, stats.islands)
					and coins >= r.price
					and r.power > rock.power
				then
					coins -= r.price
					owned[r.id] = true
					stats.equipped = r.id
					rock = r
					if r.id == "moonstone" then
						moonstoneAt = moonstoneAt or t
					end
				end
			end
			while coins >= Economy.strengthCost(stats.strength) do
				coins -= Economy.strengthCost(stats.strength)
				stats.strength += 1
			end
		end
		ok(
			firstRebirth and firstRebirth > 250 and firstRebirth < 900,
			`first rebirth after {firstRebirth} throws`
		)
		ok(
			moonstoneAt and moonstoneAt > 8000,
			`moonstone after {moonstoneAt} throws (should take many hours)`
		)
		ok(not owned.comet, "the best rock is a long-term goal")
		ok(stats.rebirths >= 6, `rebirths keep coming ({stats.rebirths})`)
	end)
end)

describe("Sea", function()
	it("distances are true to life near the shore, squeezed far out", function()
		eq(Sea.toWorld(0), 0)
		eq(Sea.toWorld(500), 500)
		eq(Sea.toWorld(Sea.LINEAR), Sea.LINEAR)
		ok(Sea.toWorld(1e6) < 1e6 and Sea.toWorld(1e6) > Sea.LINEAR, "squeezed")
		ok(Sea.toWorld(1e15) < 60000, `even 1Qa fits on the map ({Sea.toWorld(1e15)})`)
		local last = -1
		for _, d in { 0, 10, 1499, 1500, 1501, 1e4, 1e6, 1e9, 1e12, 1e15, 1e18 } do
			local w = Sea.toWorld(d)
			ok(w > last, `keeps increasing at {d}`)
			last = w
		end
	end)
	it("fromWorld undoes toWorld", function()
		for _, d in { 0, 100, 1500, 4000, 1e5, 1e8 } do
			near(Sea.fromWorld(Sea.toWorld(d)), d, d * 1e-9 + 1e-6, `distance {d}`)
		end
	end)
	it("broken numbers never break the map", function()
		local w = Sea.toWorld(0 / 0)
		ok(w == w and w < 1e6, "NaN")
		ok(Sea.toWorld(math.huge) < 1e6, "infinity")
		eq(Sea.toWorld(-50), 0, "negative")
	end)
	it("you can throw from the beach and the piers, not from the plaza", function()
		ok(Sea.canThrowFrom(Vector3.new(0, 3, -10)), "beach")
		ok(Sea.canThrowFrom(Vector3.new(60, 4.8, 50)), "end of a pier")
		ok(not Sea.canThrowFrom(Vector3.new(0, 4, -60)), "plaza")
		ok(not Sea.canThrowFrom(Vector3.new(400, 3, -10)), "far along the cliffs")
		ok(not Sea.canThrowFrom(Vector3.new(0, Config.MAX_THROW_HEIGHT + 5, -10)), "too high")
	end)
	it("a rock lands straight out in front, clear of the piers", function()
		local entry = Sea.entry(Vector3.new(30, 3, -10))
		eq(entry.X, 30)
		eq(entry.Y, 0)
		eq(entry.Z, Sea.FIRST_WATER, "never on the sand")
		local behindPier = Sea.entry(Vector3.new(60, 3, -10))
		ok(behindPier.Z > Sea.PIER_END, "sails over the pier")
		local onPierEnd = Sea.entry(Vector3.new(0, 4.8, Sea.PIER_END - 1))
		ok(onPierEnd.Z > Sea.PIER_END and onPierEnd.Z < Sea.PIER_END + 10, "just past the end")
		eq(Sea.along(entry, 100).Z, entry.Z + 100)
	end)
end)

describe("Land", function()
	it("every rock's first touch is on water deep enough for terrain", function()
		-- terrain voxels are 4 studs: the one from -4 to 0 must be mostly water
		for x = -Config.THROW_ZONE_HALF_WIDTH, Config.THROW_ZONE_HALF_WIDTH, 10 do
			for _, z in { Sea.FIRST_WATER, Sea.FIRST_WATER + 4, Sea.PIER_END + 3, 120 } do
				local h = Land.height(x, z)
				ok(h < -2, `ground at ({x}, {z}) is {h}`)
			end
		end
	end)
	it("the beach is dry and slopes gently down to the water", function()
		local last = math.huge
		for z = Land.BEACH_BACK, -2, 1 do
			local h = Land.height(0, z)
			ok(h > 0.4, `beach at {z} is {h}`)
			ok(h <= last + 1e-9, "only slopes down toward the sea")
			last = h
		end
	end)
	it("the plaza is flat for the boardwalk", function()
		for x = -180, 180, 20 do
			for z = Land.PLAZA_BACK + 5, Land.BEACH_BACK, 10 do
				near(Land.height(x, z), Land.PLAZA_HEIGHT, 0.05, `plaza at ({x}, {z})`)
			end
		end
	end)
	it("headlands rise as cliffs either side of the bay", function()
		for _, x in { -520, 520 } do
			ok(Land.height(x, 50) > 15, `headland at {x}`)
			ok(Land.height(x, -60) > 15, `cliff behind the beach at {x}`)
		end
		ok(Land.height(0, 50) < 0, "the middle of the bay is sea")
	end)
	it("hills rise behind the plaza", function()
		ok(Land.height(0, -330) > 25, "wooded ridge")
	end)
	it("materials: sand by the sea, grass inland, rock on cliffs", function()
		eq(Land.material(0, -10, Land.height(0, -10), 0), "Sand")
		local inland = Land.material(0, -200, 30, 0.2)
		ok(inland == "Grass" or inland == "LeafyGrass", inland)
		eq(Land.material(500, 0, 30, 1), "Rock")
	end)
end)

describe("GoalData", function()
	it("goals have unique ids and the collection goal needs every rock", function()
		local seen = {}
		for _, goal in GoalData.GOALS do
			ok(not seen[goal.id], "duplicate " .. goal.id)
			seen[goal.id] = true
		end
		eq(GoalData.get("rocks12").value, #RockData.LIST)
	end)
	it("titles grow with your longest throw", function()
		eq(GoalData.title(10), nil)
		eq(GoalData.title(1000), "Skimmer")
		eq(GoalData.title(5e6), "Sea Legend")
		eq(GoalData.title(1e13), "Starfall Skipper")
	end)
	it("measures progress", function()
		local stats = {
			bestSkips = 12,
			bestDistance = 2000,
			perfects = 1,
			rocks = 3,
			rebirths = 0,
			throws = 50,
			totalCoins = 10,
		}
		ok(GoalData.isDone(GoalData.get("skip10"), stats), "10 skips")
		ok(not GoalData.isDone(GoalData.get("skip20"), stats), "not 20")
		ok(GoalData.isDone(GoalData.get("far1000"), stats), "1K")
		ok(GoalData.isDone(GoalData.get("rocks3"), stats), "rocks")
		eq(GoalData.progress(GoalData.get("throws100"), stats), 50)
	end)
end)

describe("DayCycle", function()
	it("runs 6:00 -> 19:00 by day, then through the night back to 6:00", function()
		near(DayCycle.clockTime(0), 6, 1e-9)
		near(DayCycle.clockTime(Config.DAY_LENGTH * DayCycle.DAY_SHARE), 19, 1e-6)
	end)
	it("phaseFor undoes clockTime", function()
		for _, clock in { 0, 3.5, 6, 12.25, 19, 23.99 } do
			near(
				DayCycle.clockTime(DayCycle.phaseFor(clock) * Config.DAY_LENGTH),
				clock,
				1e-6,
				`clock {clock}`
			)
		end
	end)
	it("darkness eases from day to night", function()
		eq(DayCycle.darkness(12), 0)
		eq(DayCycle.darkness(23), 1)
	end)
end)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
