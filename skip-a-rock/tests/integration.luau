--!nocheck
-- Runs the real server systems in a fake Roblox server and plays the game:
-- the coast and lobby, joining, throwing for coins (and every way a throw
-- can be refused), buying rocks, strength, rebirths, islands, treasure,
-- leaderboards, the test panel and leaving. Run from skip-a-rock/:
-- lune run tests/integration

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local ServerEnv = require("./support/ServerEnv")

local Vector3 = roblox.Vector3
local Enum = roblox.Enum

local env = ServerEnv.new()
local S = env.S
local Config = env.Config
local Loader = require("./loader")
local Sea = Loader.load("src/shared/Sea")
local Land = Loader.load("src/shared/Land")
local Skip = Loader.load("src/shared/Skip")
local Economy = Loader.load("src/shared/Economy")
local RockData = Loader.load("src/shared/Data/RockData")
local IslandData = Loader.load("src/shared/Data/IslandData")
local GoalData = Loader.load("src/shared/Data/GoalData")
local Tags = Loader.load("src/shared/Tags")
local Scenery = Loader.load("src/server/Lib/Scenery")
local Ground = Loader.load("src/server/Lib/Ground")
local BoardData = Loader.load("src/server/Lib/BoardData")

local passed, failed = 0, 0
local group = ""

local function describe(name: string, fn: () -> ())
	group = name
	fn()
end

local function it(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print(`FAIL  {group} > {name}\n      {err}`)
	end
end

local function eq(actual, expected, label)
	if actual ~= expected then
		error(`{label or "value"}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

local function ok(condition, label)
	if not condition then
		error(label, 2)
	end
end

-- Hold time that puts the power needle exactly on the sweet spot.
local SWEET_HOLD = Skip.SWEET * Skip.PERIOD / 2
local BEACH = Vector3.new(30, 3, -10)

local function inside(part, point, slack)
	local p = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2 + Vector3.new(slack, slack, slack)
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

local function walled(point, slack)
	for _, part in env.workspace.SkipARock.Fences:GetChildren() do
		if inside(part, point, slack or 0) then
			return true
		end
	end
	return false
end

-- Throws for `player` from where they stand: wind up, wait, let go.
local function throw(player, hold, claimedHold)
	env.send(player, "BeginCharge")
	env.advance(hold)
	local before = #env.messages(player, "Throw")
	env.send(player, "Release", claimedHold or hold)
	local after = env.messages(player, "Throw")
	env.advance(Config.THROW_COOLDOWN)
	if #after > before then
		return after[#after].args[1]
	end
	return nil
end

local function lastNotify(player)
	local message = env.lastMessage(player, "Notify")
	return message and message.args[1]
end

-- ===== The world =====

describe("World", function()
	it("builds the lobby and everything out at sea", function()
		local root = env.workspace:FindFirstChild("SkipARock")
		ok(root, "SkipARock folder")
		for _, name in { "Fences", "Piers", "Beach", "Boardwalk", "Lighthouse", "Forest", "DistanceMarkers", "Islands", "Spawn" } do
			ok(root:FindFirstChild(name), "has " .. name)
		end
		eq(#root.Piers:GetChildren(), #Sea.PIER_XS, "piers")
		for _, name in { "RockShop", "StrengthGym", "RebirthShrine", "WelcomeArch", "Leaderboards" } do
			ok(root.Boardwalk:FindFirstChild(name), "boardwalk has " .. name)
		end
		ok(env.workspace:FindFirstChild("Treasure"), "treasure folder")
	end)
	it("stays within a sensible part budget", function()
		local parts = 0
		for _, d in env.workspace.SkipARock:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		ok(parts > 2000 and parts < 8000, `part count {parts}`)
	end)
	it("shapes the coast out of terrain and fills the ocean to the horizon", function()
		eq(#env.terrainWrites, #Ground.chunks(), "one write per chunk")
		for _, write in env.terrainWrites do
			local size = write.region.Size / 4
			eq(#write.materials, size.X, "x columns")
			eq(#write.materials[1], size.Y, "layers")
			eq(#write.materials[1][1], size.Z, "z columns")
		end
		local blocks = Ground.oceanBlocks()
		eq(#env.terrainFills, #blocks, "ocean blocks")
		local farthest = 0
		for _, fill in env.terrainFills do
			eq(fill.material, Enum.Material.Water, "water")
			eq(fill.cframe.Position.Y + fill.size.Y / 2, 0, "surface at sea level")
			farthest = math.max(farthest, fill.cframe.Position.Z + fill.size.Z / 2)
		end
		ok(farthest >= Ground.OCEAN_END, "out to the horizon")
		ok(env.workspace.Terrain:FindFirstChildOfClass("Clouds"), "clouds")
	end)
	it("every rock's first touch is on terrain water, across the whole beach", function()
		for x = -Config.THROW_ZONE_HALF_WIDTH, Config.THROW_ZONE_HALF_WIDTH, 25 do
			local entry = Sea.entry(Vector3.new(x, 3, -10))
			local found = false
			for _, write in env.terrainWrites do
				local min = write.region.CFrame.Position - write.region.Size / 2
				local i = math.floor((entry.X - min.X) / 4) + 1
				local k = math.floor((entry.Z - min.Z) / 4) + 1
				local j = math.floor((-2 - min.Y) / 4) + 1
				if i >= 1 and k >= 1 and i <= #write.materials and k <= #write.materials[1][1] then
					eq(write.materials[i][j][k], Enum.Material.Water, `water in front of x={x}`)
					found = true
				end
			end
			ok(found, "voxel found")
		end
	end)
	it("tags lanterns, the lighthouse and fireflies for the night", function()
		ok(#(env.tags[Tags.NIGHT_LIGHT] or {}) >= 15, "lights")
		ok(#(env.tags[Tags.FIREFLIES] or {}) >= 8, "fireflies")
		for _, light in env.tags[Tags.NIGHT_LIGHT] do
			eq(light.Enabled, false, "lights start off")
		end
	end)
	it("three leaderboards with ten rows each", function()
		local boards = S.World.get().boards
		for _, board in BoardData.BOARDS do
			local gui = boards[board.key]
			ok(gui, board.key)
			for row = 1, 10 do
				ok(gui:FindFirstChild("Row" .. row), `{board.key} row {row}`)
			end
		end
	end)
	it("the shops open the menu when you walk up to them", function()
		local menus = {}
		for _, d in env.workspace.SkipARock:GetDescendants() do
			if d:IsA("ProximityPrompt") and d:GetAttribute("Menu") then
				menus[d:GetAttribute("Menu")] = true
			end
		end
		ok(menus.Rocks and menus.Upgrades and menus.Rebirth, "rock shop, gym and shrine")
	end)
	it("the spawn is on the boardwalk, facing the sea", function()
		local spawn = S.World.get().spawn
		local p = spawn.CFrame.Position
		ok(p.Z < Scenery.DECK_FRONT and p.Z > Scenery.DECK_BACK, "on the boardwalk")
		ok(spawn.CFrame.LookVector.Z > 0.99, "faces the sea")
		ok(not Sea.canThrowFrom(p + Vector3.new(0, 3, 0)), "you walk down to the beach to throw")
	end)
	it("the water's edge is walled all the way along, except onto the piers", function()
		for x = -Scenery.PLAY_HALF_WIDTH + 1, Scenery.PLAY_HALF_WIDTH - 1, 0.5 do
			local point = Vector3.new(x, 3, Scenery.SHORE_WALL)
			ok(walled(point, 0.3) or Sea.pierAt(point, 0), `gap at x={x}`)
		end
		for _, px in Sea.PIER_XS do
			for z = Scenery.SHORE_WALL, Sea.PIER_END, 1 do
				for _, side in { -1, 1 } do
					ok(walled(Vector3.new(px + side * (Sea.PIER_WIDTH / 2 + 0.25), 3, z), 0.05), `pier side at {px}, {z}`)
				end
			end
			ok(walled(Vector3.new(px, 3, Sea.PIER_END + 0.25), 0.05), `pier end at {px}`)
		end
	end)
	it("buoys mark the distances out at sea on the same scale rocks fly", function()
		local markers = env.workspace.SkipARock.DistanceMarkers
		eq(#markers:GetChildren(), #Scenery.MARKERS, "a line per marker")
		local line = markers:FindFirstChild("1K")
		ok(line, "1K line")
		local sign = line:FindFirstChild("Sign")
		ok(math.abs(sign.CFrame.Position.Z - (Sea.FIRST_WATER + Sea.toWorld(1000))) < 1e-3, "at 1K")
	end)
end)

-- ===== Joining =====

local alice = env.makePlayer("Alice")
env.join(alice)
env.send(alice, "Ready")

describe("Joining", function()
	it("starts with a Pebble in hand and no coins", function()
		local profile = env.profileOf(alice)
		eq(profile.coins, 0)
		eq(profile.rocks.pebble, true)
		eq(profile.equipped, "pebble")
		local held = alice.Character:FindFirstChild("HeldRock")
		ok(held, "held rock")
		eq(held:GetAttribute("Rock"), "pebble")
		ok(held:FindFirstChildOfClass("WeldConstraint"), "welded")
	end)
	it("spawns on the boardwalk", function()
		local p = alice.Character.HumanoidRootPart.CFrame.Position
		ok(p.Z < Scenery.DECK_FRONT, "on the boardwalk")
	end)
	it("shows coins, longest throw and rebirths on the player list", function()
		local stats = alice:FindFirstChild("leaderstats")
		ok(stats and stats:FindFirstChild("Coins") and stats:FindFirstChild("Longest") and stats:FindFirstChild("Rebirths"), "stats")
		eq(stats.Coins.Value, "0")
	end)
	it("gets a full snapshot once the client is ready", function()
		local snapshot = env.lastMessage(alice, "State").args[1]
		eq(snapshot.coins, 0)
		eq(snapshot.strengthCost, Economy.strengthCost(0))
		eq(snapshot.rebirthCost, Economy.rebirthCost(0))
		eq(snapshot.coinMultiplier, 1)
		eq(snapshot.isDev, true)
	end)
end)

-- ===== Throwing =====

describe("Throwing", function()
	it("can't throw from the boardwalk", function()
		eq(throw(alice, SWEET_HOLD), nil)
		eq(lastNotify(alice), "Walk down to the beach or onto a pier to throw")
	end)
	it("a perfect release from the beach skips out to sea and pays coins", function()
		env.moveTo(alice, BEACH)
		env.clearOutbox()
		local event = throw(alice, SWEET_HOLD)
		ok(event, "throw happened")
		eq(event.perfect, true)
		ok(event.skips >= 4, `skips {event.skips}`)
		eq(#event.hops, event.skips, "one hop per skip")
		ok(event.coins > 0, "paid")
		eq(event.rock, "pebble")
		eq(event.entry.X, BEACH.X, "straight out")
		ok(event.entry.Z >= Sea.FIRST_WATER, "on the water")
		local sum = 0
		for _, hop in event.hops do
			sum += hop
		end
		ok(math.abs(sum - event.distance) < 1e-6, "hops add up to the distance")
		local profile = env.profileOf(alice)
		eq(profile.coins, event.coins, "coins")
		eq(profile.totalCoins, event.coins, "lifetime coins")
		eq(profile.bestDistance, event.distance, "longest throw")
		eq(profile.perfects, 1)
		eq(event.newBest, true)
		ok(profile.goals.skip1 and profile.goals.perfect1, "goals")
		eq(env.lastMessage(alice, "Throw").player, "all", "everyone sees it")
	end)
	it("the held rock hides while the thrown one flies", function()
		env.send(alice, "BeginCharge")
		env.advance(SWEET_HOLD)
		env.send(alice, "Release", SWEET_HOLD)
		eq(alice.Character.HeldRock.Transparency, 1, "hidden")
		env.advance(Config.THROW_COOLDOWN + 0.1)
		eq(alice.Character.HeldRock.Transparency, alice.Character.HeldRock:GetAttribute("BaseTransparency"), "back")
	end)
	it("can't throw again straight away", function()
		env.send(alice, "BeginCharge")
		env.advance(SWEET_HOLD)
		env.send(alice, "Release", SWEET_HOLD)
		local before = #env.messages(alice, "Throw")
		env.send(alice, "BeginCharge")
		env.advance(0.3)
		env.send(alice, "Release", 0.3)
		eq(#env.messages(alice, "Throw"), before, "too soon")
		env.advance(Config.THROW_COOLDOWN)
	end)
	it("too soft plops, too hard dives, and neither pays much", function()
		local plop = throw(alice, Skip.PERIOD - 0.05)
		eq(plop.verdict, "plop")
		eq(plop.coins, 0)
		local dive = throw(alice, Skip.PERIOD / 2)
		eq(dive.verdict, "dive")
	end)
	it("works from the end of a pier, sailing past it", function()
		env.moveTo(alice, Vector3.new(60, Sea.PIER_TOP + 3, Sea.PIER_END - 2))
		local event = throw(alice, SWEET_HOLD)
		ok(event, "threw")
		ok(event.entry.Z > Sea.PIER_END, "past the pier")
		env.moveTo(alice, BEACH)
	end)
	it("ignores taps, overlong holds, releases without a wind-up and junk", function()
		eq(throw(alice, 0.02), nil, "tap")
		eq(throw(alice, Config.MAX_CHARGE_SECONDS + 1), nil, "too long")
		local before = #env.messages(alice, "Throw")
		env.send(alice, "Release", SWEET_HOLD)
		eq(#env.messages(alice, "Throw"), before, "no wind-up")
		env.send(alice, "BeginCharge")
		env.send(alice, "CancelCharge")
		env.advance(SWEET_HOLD)
		env.send(alice, "Release", SWEET_HOLD)
		eq(#env.messages(alice, "Throw"), before, "cancelled")
		ok(throw(alice, SWEET_HOLD, "nonsense"), "a junk hold time falls back to the server's own")
	end)
	it("a hold time the server never saw can't buy a perfect", function()
		local event = throw(alice, 1.2, SWEET_HOLD)
		eq(event.perfect, false)
	end)
	it("better rocks and more strength throw further", function()
		local profile = env.profileOf(alice)
		local base = Economy.distanceMultiplier(Economy.statsOf(profile), false)
		profile.strength = 10
		profile.rocks.slate = true
		profile.equipped = "slate"
		local stronger = Economy.distanceMultiplier(Economy.statsOf(profile), false)
		ok(stronger > base * 5, "much further")
		local event = throw(alice, SWEET_HOLD)
		eq(event.rock, "slate")
		profile.strength = 0
		profile.rocks.slate = nil
		profile.equipped = "pebble"
	end)
end)

-- ===== Spending =====

describe("Shop", function()
	it("strength costs coins and you can't buy it broke", function()
		local profile = env.profileOf(alice)
		profile.coins = 0
		local bought = S.Shop.upgrade(alice, 1)
		eq(bought, 0)
		profile.coins = Economy.strengthCost(0) + Economy.strengthCost(1) + 5
		env.send(alice, "Upgrade", 5)
		eq(profile.strength, 2, "as many as affordable")
		eq(profile.coins, 5, "paid for both")
		env.send(alice, "Upgrade", "lots")
		eq(profile.strength, 2, "junk is one level, and that's too dear")
	end)
	it("rocks: must be affordable, unlocked and not owned already", function()
		local profile = env.profileOf(alice)
		profile.coins = 100
		eq(S.Shop.buyRock(alice, "river"), "poor")
		profile.coins = 10000
		eq(S.Shop.buyRock(alice, "river"), nil)
		eq(profile.rocks.river, true)
		eq(profile.equipped, "river", "a better rock goes straight into your hand")
		eq(alice.Character.HeldRock:GetAttribute("Rock"), "river", "in hand")
		eq(profile.coins, 10000 - RockData.get("river").price)
		eq(S.Shop.buyRock(alice, "river"), "owned")
		profile.coins = 1e12
		eq(S.Shop.buyRock(alice, "basalt"), "locked", "needs Gull Rock")
		eq(S.Shop.buyRock(alice, "diamond"), "unknown")
		eq(S.Shop.buyRock(alice, 7), "unknown")
		profile.coins = 0
	end)
	it("equip only what you own", function()
		local profile = env.profileOf(alice)
		eq(S.Shop.equip(alice, "starstone"), "notOwned")
		eq(S.Shop.equip(alice, "pebble"), nil)
		eq(profile.equipped, "pebble")
		env.send(alice, "Equip", "river")
		eq(profile.equipped, "river")
	end)
	it("rebirth: costs coins, resets coins and strength, keeps rocks", function()
		local profile = env.profileOf(alice)
		profile.coins = Economy.rebirthCost(0) - 1
		eq(S.Shop.rebirth(alice), "poor")
		profile.coins = Economy.rebirthCost(0) + 500
		profile.strength = 12
		env.send(alice, "Rebirth")
		eq(profile.rebirths, 1)
		eq(profile.coins, 0)
		eq(profile.strength, 0)
		eq(profile.rocks.river, true, "rocks kept")
		eq(alice.leaderstats.Rebirths.Value, 1, "player list")
		ok(profile.goals.rebirth1, "goal")
		local snapshot = S.State.snapshot(alice)
		eq(snapshot.rebirthCost, Economy.rebirthCost(1), "next one dearer")
		ok(snapshot.coinMultiplier > 1, "coins multiplied")
	end)
end)

-- ===== Islands and treasure =====

describe("Islands", function()
	it("throwing past an island unlocks it, its bonus and its rocks", function()
		local profile = env.profileOf(alice)
		profile.bestDistance = 1600
		S.Progress.check(alice)
		eq(profile.islands.buoy, true)
		eq(profile.islands.gull, true)
		eq(profile.islands.palm, nil)
		local island = env.lastMessage(alice, "Island")
		ok(island and island.args[1] == "gull", "told the client")
		profile.coins = RockData.get("basalt").price
		eq(S.Shop.buyRock(alice, "basalt"), nil, "basalt unlocked")
		local stats = Economy.statsOf(profile)
		ok(math.abs(Economy.islandBonus(stats.islands) - 0.15) < 1e-9, "bonuses add up")
	end)
	it("a title floats overhead once you throw far", function()
		local gui = alice.Character.Head:FindFirstChild("SkipperTitle")
		ok(gui, "title")
		eq(gui.Text.Text, `✦ {GoalData.title(env.profileOf(alice).bestDistance)} ✦`)
	end)
end)

describe("Treasure", function()
	it("a full set washes up on the beach, clear of the piers", function()
		local list = S.Treasure.list()
		eq(#list, Config.TREASURE_COUNT)
		for _, piece in list do
			local p = piece.CFrame.Position
			ok(p.Z <= S.Treasure.FRONT and p.Z >= S.Treasure.BACK, `on the beach ({p.Z})`)
			ok(not Sea.pierAt(p, 2), "not under a pier")
			ok(piece:FindFirstChildOfClass("ProximityPrompt"), "can be picked up")
		end
	end)
	it("picking one up pays coins (more as you progress); taking it twice pays once", function()
		local profile = env.profileOf(alice)
		local piece = S.Treasure.list()[1]
		env.moveTo(alice, piece.CFrame.Position + Vector3.new(0, 3, 1))
		local before = profile.coins
		local triggered = env.signal(piece:FindFirstChildOfClass("ProximityPrompt"), "Triggered")
		triggered:Fire(alice)
		triggered:Fire(alice)
		local reward = S.Treasure.reward(Economy.statsOf(profile))
		eq(profile.coins, before + reward, "paid once")
		eq(S.Treasure.count(), Config.TREASURE_COUNT - 1)
		env.advance(Config.TREASURE_RESPAWN_MAX + 1)
		eq(S.Treasure.count(), Config.TREASURE_COUNT, "more washes up")
		local early = S.Treasure.reward({ strength = 0, rebirths = 0, equipped = "pebble", islands = {} })
		ok(reward > early, "worth more further along")
	end)
	it("can't be picked up from across the beach", function()
		local piece = S.Treasure.list()[1]
		env.moveTo(alice, piece.CFrame.Position + Vector3.new(0, 3, S.Treasure.PICKUP_RANGE + 5))
		env.signal(piece:FindFirstChildOfClass("ProximityPrompt"), "Triggered"):Fire(alice)
		eq(S.Treasure.count(), Config.TREASURE_COUNT, "still there")
	end)
end)

-- ===== Leaderboards, test panel, safety nets =====

describe("Leaderboards", function()
	it("show this server's skippers (no DataStores here), big numbers included", function()
		local profile = env.profileOf(alice)
		profile.bestDistance = 3.2e12
		profile.totalCoins = 4.5e15
		local bob = env.makePlayer("Bob")
		env.join(bob)
		S.Leaderboards.refresh()
		local boards = S.World.get().boards
		eq(boards.Distance.Row1.Player.Text, "Alice")
		ok(string.find(boards.Distance.Row1.Score.Text, "3.2T", 1, true), boards.Distance.Row1.Score.Text)
		ok(string.find(boards.Coins.Row1.Score.Text, "4.5Qa", 1, true), boards.Coins.Row1.Score.Text)
		eq(boards.Rebirths.Row1.Score.Text, "1")
		eq(boards.Distance.Row2.Player.Text, "Bob")
		eq(boards.Distance.Row3.Player.Text, "")
		env.leave(bob)
	end)
	it("store huge scores safely and read them back", function()
		local board = BoardData.BOARDS[1]
		for _, score in { 0, 1, 1234, 9e15, 1e30 } do
			local stored = BoardData.encode(board, score)
			ok(stored == math.floor(stored) and stored >= 0 and stored < 2 ^ 53, "a whole number in range")
			local back = BoardData.decode(board, stored)
			ok(math.abs(back - score) <= score * 1e-6 + 1e-6, `round trip {score}`)
		end
	end)
end)

describe("Test panel", function()
	it("adds coins, strength and unlocks everything", function()
		local profile = env.profileOf(alice)
		local before = profile.coins
		ok(S.Cheats.run(alice, "coins"), "coins")
		ok(profile.coins > before, "more coins")
		local strength = profile.strength
		S.Cheats.run(alice, "strength")
		eq(profile.strength, strength + 10)
		S.Cheats.run(alice, "everything")
		for _, rock in RockData.LIST do
			eq(profile.rocks[rock.id], true, rock.id)
		end
		for _, island in IslandData.LIST do
			eq(profile.islands[island.id], true, island.id)
		end
	end)
	it("night and day", function()
		S.Cheats.run(alice, "night")
		eq(S.DayNight.isNight(), true)
		S.Cheats.run(alice, "day")
		eq(S.DayNight.isNight(), false)
	end)
	it("is closed to ordinary players in live games, and ignores junk", function()
		local studio = env.services.RunService.IsStudio
		env.services.RunService.IsStudio = function()
			return false
		end
		eq(S.Cheats.run(alice, "coins"), false)
		env.services.RunService.IsStudio = studio
		eq(S.Cheats.run(alice, "fly"), false)
		eq(S.Cheats.run(alice, 3), false)
	end)
	it("can start over", function()
		S.Cheats.run(alice, "reset")
		local profile = env.profileOf(alice)
		eq(profile.coins, 0)
		eq(profile.rebirths, 0)
		eq(profile.equipped, "pebble")
		eq(alice.Character.HeldRock:GetAttribute("Rock"), "pebble")
		eq(alice.leaderstats.Coins.Value, "0")
	end)
end)

describe("Safety nets", function()
	it("anyone who ends up in the sea is put back by the spawn; piers and beach are fine", function()
		env.moveTo(alice, Vector3.new(0, Sea.PIER_TOP + 3, 30))
		eq(S.World.rescue(alice), false, "on a pier")
		env.moveTo(alice, BEACH)
		eq(S.World.rescue(alice), false, "on the beach")
		env.moveTo(alice, Vector3.new(30, 0.5, 40))
		eq(S.World.rescue(alice), true, "swimming")
		local p = alice.Character.HumanoidRootPart.CFrame.Position
		ok((p - S.World.get().spawn.CFrame.Position).Magnitude < 6, "by the spawn")
	end)
	it("a respawned character gets its rock back", function()
		alice.Character:Destroy()
		local character = env.makeCharacter(alice)
		env.signal(alice, "CharacterAdded"):Fire(character)
		ok(character:FindFirstChild("HeldRock"), "rock in hand")
	end)
	it("a corrupt save can't leave anyone with broken numbers", function()
		-- (Data.load sanitises; here the shop just has to cope with odd input)
		local profile = env.profileOf(alice)
		profile.coins = 50
		local bought = S.Shop.upgrade(alice, 0 / 0)
		ok(bought <= 1, "NaN count is one level at most")
	end)
end)

describe("Leaving", function()
	it("saves, forgets the player and ignores their late messages", function()
		env.leave(alice)
		eq(S.Data.get(alice), nil)
		eq(S.Sessions.get(alice), nil)
		env.send(alice, "BeginCharge")
		env.send(alice, "Release", SWEET_HOLD)
		env.send(alice, "BuyRock", "river")
		env.send(alice, "Upgrade", 1)
		env.send(alice, "Rebirth")
	end)
end)

print(`{passed} passed, {failed} failed`)
process.exit(if failed > 0 then 1 else 0)
