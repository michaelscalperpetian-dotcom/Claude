--!strict
-- Unit tests for the pure game logic. Run with: lune run tests/run

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Loader = require("./loader")

local Config = Loader.load("src/shared/Config")
local DinoData = Loader.load("src/shared/Data/DinoData")
local EggData = Loader.load("src/shared/Data/EggData")
local MutationData = Loader.load("src/shared/Data/MutationData")
local Odds = Loader.load("src/shared/Util/Odds")
local Growth = Loader.load("src/shared/Util/Growth")
local Economy = Loader.load("src/shared/Util/Economy")
local Cycle = Loader.load("src/shared/Util/Cycle")
local Rng = Loader.load("src/shared/Util/Rng")
local Streak = Loader.load("src/shared/Util/Streak")
local Format = Loader.load("src/shared/Util/Format")
local EggOdds = Loader.load("src/shared/Util/EggOdds")

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

local function ok(condition: any, label: string)
	if not condition then
		error(label, 2)
	end
end

local function rarityOf(id: string): number
	return DinoData.rarityOrder(id)
end

local RARE = DinoData.RARITIES.Rare.order

describe("DinoData", function()
	it("every species has 3 growth thresholds in increasing order", function()
		for _, s in DinoData.LIST do
			eq(#s.growth, 3, s.id .. " thresholds")
			ok(s.growth[1] < s.growth[2] and s.growth[2] < s.growth[3], s.id .. " increasing")
		end
	end)
	it("has 19 dinos plus 2 secrets", function()
		local secrets = 0
		for _, s in DinoData.LIST do
			if s.rarity == "Secret" then
				secrets += 1
			end
		end
		eq(#DinoData.LIST, 21, "species count")
		eq(secrets, 2, "secret count")
	end)
end)

describe("EggData odds", function()
	it("every egg's weights sum to exactly 100%", function()
		for _, egg in EggData.LIST do
			local sum = 0
			for _, e in egg.odds do
				sum += e.weight
				ok(DinoData.get(e.species) ~= nil, `{egg.id} lists unknown species {e.species}`)
			end
			eq(sum, 10000, egg.id .. " sum")
		end
	end)

	it("normalized chances match raw weights when there is no luck", function()
		for _, egg in EggData.LIST do
			local chances = Odds.chances(egg.odds, rarityOf, 1, RARE)
			for i, c in chances do
				eq(c.bp, egg.odds[i].weight, egg.id .. " " .. c.species)
			end
		end
	end)

	it("luck keeps the total at exactly 100% and raises rare odds", function()
		for _, egg in EggData.LIST do
			local base = Odds.chances(egg.odds, rarityOf, 1, RARE)
			local lucky = Odds.chances(egg.odds, rarityOf, Config.LUCK_MULTIPLIER, RARE)
			local total = 0
			for i, c in lucky do
				total += c.bp
				if rarityOf(c.species) >= RARE and base[i].bp < 10000 then
					ok(c.bp >= base[i].bp, `{egg.id} {c.species} should not drop with luck`)
				end
			end
			eq(total, 10000, egg.id .. " lucky total")
		end
	end)

	it("roll() lands on each species exactly as often as its displayed odds", function()
		for _, egg in EggData.LIST do
			for _, luck in { 1, Config.LUCK_MULTIPLIER } do
				local chances = Odds.chances(egg.odds, rarityOf, luck, RARE)
				local counts: { [string]: number } = {}
				for k = 0, 9999 do
					local species = Odds.roll(chances, k / 10000)
					counts[species] = (counts[species] or 0) + 1
				end
				for _, c in chances do
					eq(counts[c.species] or 0, c.bp, `{egg.id} luck {luck} {c.species}`)
				end
			end
		end
	end)

	it("formats percentages for the odds panel", function()
		eq(Odds.format(4500), "45%")
		eq(Odds.format(380), "3.8%")
		eq(Odds.format(10), "0.1%")
		eq(Odds.format(1), "0.01%")
		eq(Odds.format(1250), "12.5%")
		eq(Odds.format(10000), "100%")
	end)
end)

describe("EggOdds (shared by server rolls and the Odds panel)", function()
	it("matches the raw egg tables without luck", function()
		for _, egg in EggData.LIST do
			local chances = EggOdds.species(egg.id, false)
			eq(#chances, #egg.odds, egg.id .. " entries")
			for i, c in chances do
				eq(c.bp, egg.odds[i].weight, egg.id .. " " .. c.species)
			end
		end
	end)
	it("sums to 100% with luck", function()
		for _, egg in EggData.LIST do
			local total = 0
			for _, c in EggOdds.species(egg.id, true) do
				total += c.bp
			end
			eq(total, 10000, egg.id)
		end
	end)
	it("mutation chances follow storms", function()
		local calm = EggOdds.mutations(Config.STORM_INTERVAL * 900001 + Config.STORM_DURATION + 5)
		eq(#calm, 1, "only Glossy when calm")
		local stormy = EggOdds.mutations(Config.STORM_INTERVAL * 900001 + 5)
		ok(#stormy >= 2, "storm adds a mutation")
	end)
end)

describe("MutationData", function()
	it("hatch chances never exceed 100%", function()
		for _, kind in { "Lava", "Frost", "Cosmic" } do
			for _, mega in { false, true } do
				local total = 0
				for _, c in MutationData.hatchChances(kind, mega) do
					total += c.bp
				end
				ok(total <= 10000, "total too high")
			end
		end
	end)
	it("pick returns nil (no mutation) above the listed chances", function()
		local chances = MutationData.hatchChances(nil, false)
		eq(Odds.pick(chances, 0), "Glossy")
		eq(Odds.pick(chances, 0.0199), "Glossy")
		eq(Odds.pick(chances, 0.02), nil)
		eq(Odds.pick(chances, 0.999), nil)
	end)
	it("mega storm gives Rainbow and triples the nest mutation chance", function()
		eq(MutationData.stormGives(nil, true), "Rainbow")
		eq(MutationData.stormGives("Frost", false), "Frost")
		eq(MutationData.stormTickBp(true), MutationData.stormTickBp(false) * 3)
	end)
end)

describe("Growth", function()
	local t = { 300, 1800, 14400 }
	it("computes stages at the boundaries", function()
		eq(Growth.stageIndex(0, t), 1)
		eq(Growth.stageIndex(299, t), 1)
		eq(Growth.stageIndex(300, t), 2)
		eq(Growth.stageIndex(1800, t), 3)
		eq(Growth.stageIndex(14400, t), 4)
		eq(Growth.stageIndex(10 ^ 9, t), 4)
	end)
	it("reports progress toward the next stage", function()
		local stage, fraction, left = Growth.progress(150, t)
		eq(stage, 1)
		eq(fraction, 0.5)
		eq(left, 150)
		local giant, full, none = Growth.progress(20000, t)
		eq(giant, 4)
		eq(full, 1)
		eq(none, 0)
	end)
	it("bornAtForStage makes a dino exactly that stage", function()
		for stage = 1, 4 do
			local bornAt = Growth.bornAtForStage(1000000, stage, t)
			eq(Growth.stageIndex(1000000 - bornAt, t), stage, "stage " .. stage)
		end
	end)
	it("babies and juveniles don't lay eggs", function()
		local laid = Growth.laysDue(0, 0, t, 1000, 600, 400, 6)
		eq(laid, 0)
	end)
	it("adults lay one egg per interval after becoming adult", function()
		local laid, last = Growth.laysDue(0, 0, t, 1800 + 600, 600, 400, 6)
		eq(laid, 1)
		eq(last, 2400)
		local again = Growth.laysDue(0, last, t, 2400 + 599, 600, 400, 6)
		eq(again, 0)
	end)
	it("offline catch-up lays several eggs but respects tray room", function()
		local laid, last = Growth.laysDue(0, 0, t, 1800 + 600 * 5, 600, 400, 3)
		eq(laid, 3)
		eq(last, 1800 + 600 * 5) -- backlog dropped
		local laid2, last2 = Growth.laysDue(0, 0, t, 1800 + 600 * 2, 600, 400, 6)
		eq(laid2, 2)
		eq(last2, 1800 + 600 * 2)
	end)
	it("a full tray lays nothing and drops the backlog", function()
		local laid, last = Growth.laysDue(0, 0, t, 5000, 600, 400, 0)
		eq(laid, 0)
		eq(last, 5000)
	end)
	it("income scales with stage and mutation", function()
		eq(Growth.income(10, 1, 1), 2.5)
		eq(Growth.income(10, 4, 3), 60)
	end)
end)

describe("Economy", function()
	local base = { doubleCoins = false, vip = false, club = false, adBoost = false, friends = 0 }
	it("multiplier is 1 with nothing active", function()
		eq(Economy.coinMultiplier(base), 1)
	end)
	it("friend boost caps at +40%", function()
		local m = Economy.coinMultiplier({
			doubleCoins = false,
			vip = false,
			club = false,
			adBoost = false,
			friends = 9,
		})
		ok(math.abs(m - 1.4) < 1e-9, "expected 1.4, got " .. m)
	end)
	it("stacks double coins and VIP", function()
		local m = Economy.coinMultiplier({
			doubleCoins = true,
			vip = true,
			club = false,
			adBoost = false,
			friends = 0,
		})
		ok(math.abs(m - 2.4) < 1e-9, "expected 2.4, got " .. m)
	end)
	it("income rewards respect the minimum", function()
		eq(Economy.incomeReward(0, 10, 250), 250)
		eq(Economy.incomeReward(10, 10, 250), 6000)
	end)
	it("offline earnings are capped and halved", function()
		eq(Economy.offlineCoins(10, 100), 500)
		eq(
			Economy.offlineCoins(1, 10 ^ 9),
			Config.OFFLINE_EARNINGS_CAP_SECONDS * Config.OFFLINE_EARNINGS_RATE
		)
		eq(Economy.offlineCoins(1, -50), 0)
	end)
	it("upgrade costs run out at max level", function()
		eq(Economy.nextUpgradeCost({ 10, 20 }, 0), 10)
		eq(Economy.nextUpgradeCost({ 10, 20 }, 1), 20)
		eq(Economy.nextUpgradeCost({ 10, 20 }, 2), nil)
	end)
	it("bigger stages and mutations sell for more", function()
		ok(Economy.dinoValue(10, 4, 1) > Economy.dinoValue(10, 1, 1), "giant > baby")
		ok(Economy.dinoValue(10, 3, 5) > Economy.dinoValue(10, 3, 1), "mutated > plain")
	end)
end)

describe("Rng", function()
	it("is deterministic and in [0, 1)", function()
		local a = Rng.new(12345)
		local b = Rng.new(12345)
		local sum = 0
		for _ = 1, 10000 do
			local x = a.next()
			eq(x, b.next(), "same sequence")
			ok(x >= 0 and x < 1, "range")
			sum += x
		end
		local mean = sum / 10000
		ok(mean > 0.48 and mean < 0.52, "mean looks uniform: " .. mean)
	end)
	it("int() stays inside its bounds", function()
		local g = Rng.new(99)
		for _ = 1, 1000 do
			local v = g.int(3, 6)
			ok(v >= 3 and v <= 6 and v == math.floor(v), "bad int " .. v)
		end
	end)
	it("hash spreads nearby inputs", function()
		ok(Rng.hash(1, 2) ~= Rng.hash(2, 1), "order matters")
		ok(Rng.hash(100, 0) ~= Rng.hash(101, 0), "neighbours differ")
	end)
end)

describe("Cycle", function()
	it("day then night with continuous countdowns", function()
		local length = Config.DAY_SECONDS + Config.NIGHT_SECONDS
		local start = length * 1000
		local d = Cycle.dayNight(start)
		eq(d.isNight, false)
		eq(d.secondsLeft, Config.DAY_SECONDS)
		local n = Cycle.dayNight(start + Config.DAY_SECONDS)
		eq(n.isNight, true)
		eq(n.secondsLeft, Config.NIGHT_SECONDS)
		local nextDay = Cycle.dayNight(start + length)
		eq(nextDay.isNight, false)
	end)

	it("storms are active for STORM_DURATION each interval and deterministic", function()
		local slotStart = Config.STORM_INTERVAL * 900001
		-- make sure we are not inside a mega storm for this check
		local megaActive = Cycle.megaStorm(slotStart)
		if megaActive then
			slotStart += Config.STORM_INTERVAL * 7
		end
		local s1 = Cycle.storm(slotStart + 1)
		eq(s1.active, true)
		ok(s1.kind ~= nil, "regular storm has a kind")
		eq(Cycle.storm(slotStart + 1).kind, s1.kind, "deterministic")
		local after = Cycle.storm(slotStart + Config.STORM_DURATION)
		eq(after.active, false)
		eq(after.secondsLeft, Config.STORM_INTERVAL - Config.STORM_DURATION)
	end)

	it("all storm kinds show up over time", function()
		local seen: { [string]: boolean } = {}
		for slot = 1, 300 do
			local s = Cycle.storm(slot * Config.STORM_INTERVAL + 1)
			if s.kind then
				seen[s.kind] = true
			end
		end
		ok(seen.Lava and seen.Frost and seen.Cosmic, "expected Lava, Frost and Cosmic")
	end)

	it("mega storm runs Saturday at the configured UTC hour", function()
		-- find a Saturday at MEGA_STORM_HOUR_UTC:00:00 UTC
		local t = 1790000000
		t -= t % 86400
		while (os.date("!*t", t) :: any).wday ~= 7 do
			t += 86400
		end
		t += Config.MEGA_STORM_HOUR_UTC * 3600
		eq((Cycle.megaStorm(t - 1)), false, "one second before")
		eq((Cycle.megaStorm(t)), true, "at start")
		eq((Cycle.megaStorm(t + Config.MEGA_STORM_DURATION - 1)), true, "just before end")
		eq((Cycle.megaStorm(t + Config.MEGA_STORM_DURATION)), false, "after end")
		local s = Cycle.storm(t + 5)
		eq(s.mega, true)
		eq(s.active, true)
		local _, untilNext = Cycle.megaStorm(t + Config.MEGA_STORM_DURATION)
		eq(untilNext, 7 * 86400 - Config.MEGA_STORM_DURATION, "next mega storm in a week")
	end)

	it("restock is deterministic and within each egg's range", function()
		local inStock: { [string]: number } = {}
		for i = 0, 499 do
			local now = i * Config.RESTOCK_SECONDS + 3
			local r = Cycle.restock(now)
			local again = Cycle.restock(now + 10)
			eq(r.index, again.index)
			ok(r.secondsLeft > 0 and r.secondsLeft <= Config.RESTOCK_SECONDS, "secondsLeft")
			for _, egg in EggData.LIST do
				local count = r.stock[egg.id]
				eq(count, again.stock[egg.id], "same restock same stock")
				ok(
					count == 0 or (count >= egg.stock.min and count <= egg.stock.max),
					"range " .. egg.id
				)
				if count > 0 then
					inStock[egg.id] = (inStock[egg.id] or 0) + 1
				end
			end
		end
		eq(inStock.Jungle, 500, "jungle always in stock")
		ok(
			(inStock.Crystal or 0) > 30 and (inStock.Crystal or 0) < 120,
			"crystal ~15%: " .. tostring(inStock.Crystal)
		)
	end)
end)

describe("Streak", function()
	it("first claim is day 1", function()
		local can, day = Streak.status({ count = 0, lastDay = 0 }, 20000)
		eq(can, true)
		eq(day, 1)
	end)
	it("consecutive days advance and wrap after 7", function()
		local _, day = Streak.status({ count = 3, lastDay = 19999 }, 20000)
		eq(day, 4)
		local _, wrapped = Streak.status({ count = 7, lastDay = 19999 }, 20000)
		eq(wrapped, 1)
	end)
	it("can't claim twice in a day", function()
		local can = Streak.status({ count = 2, lastDay = 20000 }, 20000)
		eq(can, false)
	end)
	it("missing a day resets to day 1", function()
		local _, day = Streak.status({ count = 5, lastDay = 19990 }, 20000)
		eq(day, 1)
	end)
end)

describe("Frames (robust orientation)", function()
	local roblox = require("@lune/roblox")
	local Common = require("./support/Common")
	Loader.globals.Vector3 = roblox.Vector3
	Loader.globals.CFrame = Common.CFrame
	local Frames = Loader.load("src/shared/Util/Frames")
	local V = roblox.Vector3
	local function close(a, b)
		return (a - b).Magnitude < 1e-6
	end
	it("points X along any direction, including straight down", function()
		for _, dir in { V.new(0, -1, 0), V.new(0, 1, 0), V.new(1, 0, 0), V.new(0.3, -0.8, 0.2) } do
			local cf = Frames.alongX(V.new(1, 2, 3), dir)
			ok(close(cf.RightVector, dir.Unit), "x axis follows direction")
			for _, v in { cf:GetComponents() } do
				ok(v == v, "no NaN")
			end
		end
	end)
	it("faces a target on the ground plane like Roblox's lookAt", function()
		for _, target in { V.new(0, 0, -5), V.new(0, 3, 5), V.new(4, -2, 9), V.new(-7, 0, 1) } do
			local cf = Frames.facing(V.new(0, 0, 0), target)
			local flat = V.new(target.X, 0, target.Z).Unit
			ok(close(cf.LookVector, flat), "looks at the target")
			ok(close(cf.UpVector, V.new(0, 1, 0)), "stays upright")
		end
	end)
	it("test CFrame.lookAt matches Roblox (Lune's mirrors Z)", function()
		local cf = Common.CFrame.lookAt(V.new(1, 2, 3), V.new(4, 0, 9))
		ok(close(cf.LookVector, (V.new(4, 0, 9) - V.new(1, 2, 3)).Unit), "look vector")
		ok(math.abs(cf.RightVector.Y) < 1e-6, "right vector is horizontal")
		ok(close(cf.Position, V.new(1, 2, 3)), "position")
	end)
	it("points Z along any direction, including straight up", function()
		for _, dir in { V.new(0, 1, 0), V.new(0, -1, 0), V.new(0, 0, 1), V.new(-0.5, 0.5, 0.1) } do
			local cf = Frames.alongZ(V.new(0, 0, 0), dir)
			ok(close(-cf.LookVector, dir.Unit), "z axis follows direction")
		end
	end)
end)

describe("QuestData (daily quests)", function()
	local QuestData = Loader.load("src/shared/Data/QuestData")
	it("picks three different quests, the same for everyone on a day", function()
		for day = 20000, 20030 do
			local a = QuestData.forDay(day)
			local b = QuestData.forDay(day)
			eq(#a, 3)
			local seen = {}
			for i, quest in a do
				eq(quest.id, b[i].id)
				ok(not seen[quest.id], "no repeats")
				seen[quest.id] = true
				ok(quest.goal >= 1, "goal")
				ok(quest.reward and quest.reward.kind, "reward")
			end
		end
	end)
	it("changes from day to day", function()
		local different = false
		local first = QuestData.forDay(20000)
		for day = 20001, 20010 do
			for i, quest in QuestData.forDay(day) do
				if quest.id ~= first[i].id then
					different = true
				end
			end
		end
		ok(different, "quests vary")
	end)
end)

describe("DexRewards", function()
	local DexRewards = Loader.load("src/shared/Data/DexRewards")
	local DinoData = Loader.load("src/shared/Data/DinoData")
	it("counts known species and ends with the full Dex", function()
		eq(
			DexRewards.discovered({
				Raptor = { Normal = true },
				TRex = {},
				Fake = { Normal = true },
			}),
			2
		)
		local last = DexRewards.MILESTONES[#DexRewards.MILESTONES]
		eq(last.count, #DinoData.LIST)
		for i = 2, #DexRewards.MILESTONES do
			ok(DexRewards.MILESTONES[i].count > DexRewards.MILESTONES[i - 1].count, "increasing")
		end
	end)
end)

describe("Square studs", function()
	it("STUD_STYLE is a known style", function()
		local style = Config.STUD_STYLE
		ok(style == "square" or style == "classic" or style == "none", `unknown style {style}`)
	end)
	it("the place makes SquareStuds the SmoothPlastic override", function()
		local project = serde.decode("json", fs.readFile("default.project.json"))
		local service = project.tree.MaterialService
		ok(service, "MaterialService in the project")
		eq(service["$properties"].SmoothPlasticName, "SquareStuds", "override")
		local variant = service.SquareStuds
		ok(variant, "SquareStuds variant")
		eq(variant["$className"], "MaterialVariant", "class")
		eq(variant["$properties"].BaseMaterial, "SmoothPlastic", "base material")
		eq(variant["$properties"].StudsPerTile, 4, "4 studs per 1024px tile")
	end)
	it("ships the 1024 x 1024 stud maps", function()
		for _, name in { "Color", "Normal", "Roughness" } do
			local png = fs.readFile(`assets/textures/SquareStuds_{name}.png`)
			eq(string.sub(png, 2, 4), "PNG", name)
			eq(string.unpack(">I4", png, 17), 1024, `{name} width`)
			eq(string.unpack(">I4", png, 21), 1024, `{name} height`)
		end
	end)
end)

describe("Selling babies", function()
	it("never pays more than the egg cost on average, even in a Mega Storm", function()
		for _, egg in EggData.LIST do
			local average = 0
			for _, entry in egg.odds do
				local species = DinoData.get(entry.species)
				average += Economy.dinoValue(species.income, 1, 1) * entry.weight / 10000
			end
			-- a Mega Storm makes about 15% of hatches Rainbow (8x) and some Cosmic/Glossy
			ok(average * 2.3 < egg.price, `{egg.id}: babies sell for {average} on average`)
		end
	end)
end)

describe("Rebirth", function()
	it("costs more each time and boosts coins for good", function()
		eq(Economy.rebirthCost(0), Config.REBIRTH_BASE_COST)
		eq(Economy.rebirthCost(2), Config.REBIRTH_BASE_COST * Config.REBIRTH_COST_GROWTH ^ 2)
		eq(Economy.rebirthMultiplier(0), 1)
		eq(Economy.rebirthMultiplier(2), 1 + 2 * Config.REBIRTH_BONUS)
		local base = {
			doubleCoins = true,
			vip = false,
			club = false,
			adBoost = false,
			friends = 0,
		}
		local without = Economy.coinMultiplier(base)
		base.rebirths = 3
		eq(Economy.coinMultiplier(base), without * Economy.rebirthMultiplier(3), "stacks on top")
	end)
end)

describe("Golden dinos", function()
	it("earn GOLDEN_MULTIPLIER x and cost a few minutes of income to make", function()
		eq(Economy.goldenMultiplier(true), Config.GOLDEN_MULTIPLIER)
		eq(Economy.goldenMultiplier(nil), 1)
		eq(Economy.goldenFee(2), 2 * Config.GOLDEN_FEE_SECONDS)
		eq(Economy.goldenFee(0.01), 100, "minimum fee")
	end)
end)

describe("Format", function()
	it("abbreviates big numbers", function()
		eq(Format.number(950), "950")
		eq(Format.number(12345), "12.3K")
		eq(Format.number(4500000), "4.5M")
		eq(Format.number(1000), "1K")
		eq(Format.number(2.5), "2.5")
		eq(Format.number(999999), "999K")
	end)
	it("formats times", function()
		eq(Format.time(75), "1:15")
		eq(Format.time(3725), "1:02:05")
		eq(Format.duration(45), "45s")
		eq(Format.duration(300), "5m")
		eq(Format.duration(5400), "1h 30m")
	end)
end)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
