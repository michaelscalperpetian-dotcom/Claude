--!nocheck
-- Runs the real server systems in a fake Roblox server and plays the game:
-- joining, throwing (and every way a throw can be refused), finding stones,
-- equipping them, night time, records, goals, titles, leaderboards, the
-- test panel and leaving. Run from still-lake/: lune run tests/integration

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local ServerEnv = require("./support/ServerEnv")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local env = ServerEnv.new()
local S = env.S
local Config = env.Config
local Loader = require("./loader")
local Lake = Loader.load("src/shared/Lake")
local Skip = Loader.load("src/shared/Skip")
local StoneData = Loader.load("src/shared/Data/StoneData")
local GoalData = Loader.load("src/shared/Data/GoalData")
local Tags = Loader.load("src/shared/Tags")
local Scenery = Loader.load("src/server/Lib/Scenery")

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
local R = Config.LAKE_RADIUS

local function inside(part, point, slack)
	local p = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2 + Vector3.new(slack, slack, slack)
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

local function fences()
	local list = {}
	for _, part in env.workspace.StillLake.Fences:GetChildren() do
		table.insert(list, part)
	end
	return list
end

local function walled(point, slack)
	for _, part in fences() do
		if inside(part, point, slack or 0) then
			return true
		end
	end
	return false
end

-- Throws for `player` from where they stand: wind up, wait, let go.
local function throw(player, direction, hold, claimedHold)
	env.send(player, "BeginCharge")
	env.advance(hold)
	local before = #env.messages(player, "Throw")
	env.send(player, "Release", direction, claimedHold or hold)
	local after = env.messages(player, "Throw")
	if #after > before then
		return after[#after].args[1]
	end
	return nil
end

local function lastNotify(player)
	local message = env.lastMessage(player, "Notify")
	return message and message.args[1]
end

local function onShore(angle, extra)
	return Vector3.new(math.sin(angle) * (R + extra), 3, math.cos(angle) * (R + extra))
end

local function towardCentre(position)
	return Vector3.new(-position.X, 0, -position.Z).Unit
end

-- ===== The world =====

describe("World", function()
	it("builds the lake and removes nothing it shouldn't", function()
		local root = env.workspace:FindFirstChild("StillLake")
		ok(root, "StillLake folder")
		for _, name in
			{
				"Land",
				"Fences",
				"Horizon",
				"Docks",
				"Cabin",
				"Campfire",
				"Shore",
				"Forest",
				"WelcomeSign",
				"Leaderboards",
				"Spawn",
			}
		do
			ok(root:FindFirstChild(name), "has " .. name)
		end
		eq(#root.Docks:GetChildren(), 3, "docks")
		ok(env.workspace:FindFirstChild("Glints"), "glint folder")
	end)
	it("stays within a sensible part budget", function()
		local parts = 0
		for _, d in env.workspace.StillLake:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		ok(parts > 1500 and parts < 7000, `part count {parts}`)
	end)
	it("tags lanterns and fireflies for the night", function()
		ok(#(env.tags[Tags.NIGHT_LIGHT] or {}) >= 10, "lantern lights")
		eq(#(env.tags[Tags.FIREFLIES] or {}), 12, "firefly swarms")
		ok(#(env.tags[Tags.WINDOW] or {}) >= 2, "cabin windows")
		for _, light in env.tags[Tags.NIGHT_LIGHT] do
			eq(light.Enabled, false, "lights start off")
		end
	end)
	it("both leaderboards have ten rows to fill", function()
		local boards = S.World.get().boards
		for _, key in { "Skips", "Distance" } do
			local gui = boards[key]
			ok(gui, key)
			for row = 1, 10 do
				local frame = gui:FindFirstChild("Row" .. row)
				ok(
					frame and frame:FindFirstChild("Player") and frame:FindFirstChild("Score"),
					`{key} row {row}`
				)
			end
		end
	end)
	it("the spawn is on the grass, facing the lake, outside the fence", function()
		local spawn = S.World.get().spawn
		local p = spawn.CFrame.Position
		local r = Vector3.new(p.X, 0, p.Z).Magnitude
		ok(r > R + Config.SHORE_WIDTH and r < R + Config.SHORE_WIDTH + 30, `spawn radius {r}`)
		local look = spawn.CFrame.LookVector
		ok(look:Dot(towardCentre(p)) > 0.99, "faces the lake")
	end)
	it("the water's edge is walled all the way round, except onto the docks", function()
		local gaps = {}
		local steps = 1440
		for i = 0, steps - 1 do
			local angle = i / steps * 2 * math.pi
			local point = Vector3.new(math.sin(angle) * (R + 1), 3, math.cos(angle) * (R + 1))
			if not walled(point, 0.3) and not Lake.underDock(point, 0) then
				table.insert(gaps, string.format("%.1f°", math.deg(angle)))
			end
		end
		ok(#gaps == 0, "gaps at " .. table.concat(gaps, ", "))
	end)
	it("every dock is walled along both sides and across its end", function()
		local half = Lake.DOCK_WIDTH / 2
		for _, angle in Lake.DOCK_ANGLES do
			local along = Vector3.new(math.sin(angle), 0, math.cos(angle))
			local across = Vector3.new(math.cos(angle), 0, -math.sin(angle))
			for d = Lake.DOCK_INNER, R + 2, 0.5 do
				for _, side in { -1, 1 } do
					local point = along * d + across * side * (half + 0.25) + Vector3.new(0, 3, 0)
					ok(walled(point, 0.05), `side wall at {d} ({math.deg(angle)}°)`)
				end
			end
			for x = -half, half, 0.5 do
				local point = along * (Lake.DOCK_INNER - 0.25) + across * x + Vector3.new(0, 3, 0)
				ok(walled(point, 0.05), `end wall ({math.deg(angle)}°)`)
			end
		end
	end)
	it("walls are invisible, solid, and taller than a jump", function()
		for _, part in fences() do
			eq(part.Transparency, 1, "invisible")
			eq(part.CanCollide, true, "solid")
			eq(part.CanQuery, false, "the camera ignores them")
			ok(part.CFrame.Position.Y + part.Size.Y / 2 > 9, "tall")
		end
	end)
	it("no tree or prop grows in the water or on the path", function()
		for _, model in env.workspace.StillLake.Forest:GetChildren() do
			local p = model:GetBoundingBox().Position
			local r = Vector3.new(p.X, 0, p.Z).Magnitude
			ok(r > Scenery.PATH_RADIUS + 3, `{model.Name} at radius {r}`)
		end
	end)
end)

-- ===== Joining =====

local alice = env.makePlayer("Alice")
env.join(alice)
env.send(alice, "Ready")

describe("Joining", function()
	it("starts with a Pebble in hand", function()
		local profile = env.profileOf(alice)
		eq(profile.stones.pebble, 1, "pebble")
		eq(profile.equipped, "pebble")
		local held = alice.Character:FindFirstChild("HeldStone")
		ok(held, "held stone")
		eq(held:GetAttribute("Stone"), "pebble")
		eq(held.Anchored, false, "welded, not anchored")
		ok(held:FindFirstChildOfClass("WeldConstraint"), "weld")
	end)
	it("shows Best Skips on the player list", function()
		local stats = alice:FindFirstChild("leaderstats")
		ok(stats and stats:FindFirstChild("Best Skips"), "leaderstat")
	end)
	it("gets a full snapshot once the client is ready", function()
		local message = env.lastMessage(alice, "State")
		ok(message, "state sent")
		local snapshot = message.args[1]
		eq(snapshot.equipped, "pebble")
		eq(snapshot.bestSkips, 0)
		eq(snapshot.isDev, true, "Studio shows the test panel")
		eq(snapshot.title, nil, "no title yet")
	end)
end)

-- ===== Throwing =====

describe("Throwing", function()
	local spot = onShore(0, 5) -- on the beach due "north", facing the middle
	it("a perfect release from the beach skips and is recorded", function()
		env.moveTo(alice, spot)
		env.clearOutbox()
		local event = throw(alice, towardCentre(spot), SWEET_HOLD)
		ok(event, "throw happened")
		eq(event.perfect, true, "perfect")
		ok(event.skips >= 4, `skips {event.skips}`)
		eq(#event.hops, event.skips, "one hop per skip")
		eq(event.userId, alice.UserId)
		eq(event.stone, "pebble")
		eq(event.entry.Y, 0, "touches the surface")
		ok(Lake.distanceFromCentre(event.entry) <= Lake.EDGE + 1e-6, "first touch on the water")
		ok(
			(event.entry - Vector3.new(spot.X, 0, spot.Z)).Magnitude <= Config.THROW_REACH,
			"within reach"
		)
		local profile = env.profileOf(alice)
		eq(profile.bestSkips, event.skips, "best skips")
		eq(profile.perfects, 1, "perfects")
		eq(profile.throws, 1, "throws")
		eq(profile.totalSkips, event.skips, "total skips")
		eq(event.newBestSkips, true, "a record")
		ok(profile.goals.skip1 and profile.goals.perfect1, "goals done")
		eq(alice.leaderstats["Best Skips"].Value, event.skips, "player list")
	end)
	it("everyone is told about the throw", function()
		eq(env.lastMessage(alice, "Throw").player, "all", "broadcast")
	end)
	it("the held stone hides while the thrown one flies, then comes back", function()
		local held = alice.Character.HeldStone
		eq(held.Transparency, 1, "hidden")
		env.advance(Config.THROW_COOLDOWN + 0.1)
		eq(held.Transparency, held:GetAttribute("BaseTransparency"), "back")
	end)
	it("can't throw again straight away", function()
		local event = throw(alice, towardCentre(spot), SWEET_HOLD)
		ok(event, "after the cooldown it works")
		eq(throw(alice, towardCentre(spot), 0.3), nil, "too soon")
		env.advance(Config.THROW_COOLDOWN)
	end)
	it("letting go almost at once plops; at full power it dives", function()
		env.advance(Config.THROW_COOLDOWN)
		local plop = throw(alice, towardCentre(spot), Skip.PERIOD - 0.05) -- the needle swung back down
		ok(plop, "throw happened")
		eq(plop.verdict, "plop")
		eq(plop.skips, 0)
		env.advance(Config.THROW_COOLDOWN)
		local dive = throw(alice, towardCentre(spot), Skip.PERIOD / 2)
		eq(dive.verdict, "dive")
		env.advance(Config.THROW_COOLDOWN)
	end)
	it("plops and dives don't count as skipped stones", function()
		eq(env.profileOf(alice).throws, 2, "only the two real skips")
	end)
	it("refuses throws facing away from the lake", function()
		env.advance(Config.THROW_COOLDOWN)
		eq(throw(alice, -towardCentre(spot), SWEET_HOLD), nil)
		eq(lastNotify(alice), "Face the lake to throw")
	end)
	it("refuses throws from too far up the beach", function()
		env.moveTo(alice, onShore(0, Config.SHORE_WIDTH + Config.THROW_REACH + 4))
		eq(throw(alice, Vector3.new(0, 0, -1), SWEET_HOLD), nil)
		eq(lastNotify(alice), "Walk a little closer to the water")
		env.moveTo(alice, spot)
	end)
	it("refuses throws from up high", function()
		env.moveTo(alice, spot + Vector3.new(0, Config.MAX_THROW_HEIGHT + 2, 0))
		eq(throw(alice, towardCentre(spot), SWEET_HOLD), nil)
		eq(lastNotify(alice), "Climb down to throw")
		env.moveTo(alice, spot)
	end)
	it("ignores broken directions, taps, overlong holds and releases without a wind-up", function()
		local dir = towardCentre(spot)
		eq(throw(alice, "north", SWEET_HOLD), nil, "not a vector")
		eq(throw(alice, Vector3.new(0, 1, 0), SWEET_HOLD), nil, "straight up")
		eq(throw(alice, Vector3.new(0 / 0, 0, 1), SWEET_HOLD), nil, "NaN")
		eq(throw(alice, Vector3.new(math.huge, 0, 1), SWEET_HOLD), nil, "infinite")
		eq(throw(alice, dir, 0.02), nil, "a tap")
		eq(throw(alice, dir, Config.MAX_CHARGE_SECONDS + 1), nil, "held too long")
		local before = #env.messages(alice, "Throw")
		env.send(alice, "Release", dir, SWEET_HOLD)
		eq(#env.messages(alice, "Throw"), before, "no wind-up")
		env.send(alice, "BeginCharge")
		env.send(alice, "CancelCharge")
		env.advance(SWEET_HOLD)
		env.send(alice, "Release", dir, SWEET_HOLD)
		eq(#env.messages(alice, "Throw"), before, "cancelled")
	end)
	it("a hold time the server never saw can't buy a perfect", function()
		env.advance(Config.THROW_COOLDOWN)
		local event = throw(alice, towardCentre(spot), 1.2, SWEET_HOLD)
		ok(event, "throws")
		eq(event.perfect, false, "the claim was pulled back toward the real hold")
		env.advance(Config.THROW_COOLDOWN)
	end)
	it("from the end of a dock the stone lands clear of the planks", function()
		for _, angle in Lake.DOCK_ANGLES do
			local stand = Vector3.new(
				math.sin(angle) * (Lake.DOCK_INNER + 1),
				3,
				math.cos(angle) * (Lake.DOCK_INNER + 1)
			)
			env.moveTo(alice, stand)
			local forward = throw(alice, towardCentre(stand), SWEET_HOLD)
			ok(forward, "forward throw")
			ok(not Lake.underDock(forward.entry, 0), "clear ahead")
			env.advance(Config.THROW_COOLDOWN)
			local side = Vector3.new(math.cos(angle), 0, -math.sin(angle))
			local sideways = throw(alice, side, SWEET_HOLD)
			ok(sideways, "sideways throw")
			ok(not Lake.underDock(sideways.entry, 0), "clear to the side")
			env.advance(Config.THROW_COOLDOWN)
			eq(throw(alice, -towardCentre(stand), SWEET_HOLD), nil, "not back along the dock")
			env.advance(Config.THROW_COOLDOWN)
		end
		env.moveTo(alice, spot)
	end)
	it("every hop stays on the water and the stone stops before the far shore", function()
		for _ = 1, 20 do
			local event = throw(alice, towardCentre(spot), SWEET_HOLD)
			local last = Lake.along(event.entry, event.direction, event.distance)
			ok(Lake.distanceFromCentre(last) <= Lake.EDGE + 1e-6, "ends on the lake")
			env.advance(Config.THROW_COOLDOWN)
		end
	end)
end)

-- ===== Finding stones =====

describe("Glints", function()
	it("a full set washes up on the beach, clear of the docks and each other", function()
		local list = S.Stones.list()
		eq(#list, Config.GLINT_COUNT, "glints")
		for i, glint in list do
			local r = Lake.distanceFromCentre(glint.CFrame.Position)
			ok(r >= S.Stones.INNER and r <= S.Stones.OUTER, `radius {r}`)
			ok(not Lake.underDock(glint.CFrame.Position, 2), "not under a dock")
			ok(glint:FindFirstChildOfClass("ProximityPrompt"), "can be picked up")
			for j = i + 1, #list do
				ok(
					(glint.CFrame.Position - list[j].CFrame.Position).Magnitude
						>= S.Stones.SPACING - 1e-6,
					"spaced out"
				)
			end
		end
	end)
	it("can't be picked up from across the beach", function()
		local glint = S.Stones.list()[1]
		env.moveTo(alice, glint.CFrame.Position + Vector3.new(0, 3, S.Stones.PICKUP_RANGE + 5))
		S.Stones.collectFor(alice, glint)
		eq(S.Stones.glintCount(), Config.GLINT_COUNT, "still there")
	end)
	it("picking one up reveals a stone and adds it to the journal", function()
		local glint = S.Stones.list()[1]
		env.moveTo(alice, glint.CFrame.Position + Vector3.new(0, 3, 1))
		local before = 0
		for _, count in env.profileOf(alice).stones do
			before += count
		end
		env.signal(glint:FindFirstChildOfClass("ProximityPrompt"), "Triggered"):Fire(alice)
		eq(S.Stones.glintCount(), Config.GLINT_COUNT - 1, "taken")
		local found = env.lastMessage(alice, "Found")
		ok(found, "found message")
		local id, isNew, count = found.args[1], found.args[2], found.args[3]
		ok(StoneData.get(id), "a real stone")
		ok(id ~= StoneData.STARTER, "never a Pebble")
		eq(isNew, true, "new")
		eq(count, 1)
		local after = 0
		for _, n in env.profileOf(alice).stones do
			after += n
		end
		eq(after, before + 1, "one more stone")
	end)
	it("the same glint can't be taken twice", function()
		local glint = S.Stones.list()[1]
		env.moveTo(alice, glint.CFrame.Position + Vector3.new(0, 3, 1))
		local triggered = env.signal(glint:FindFirstChildOfClass("ProximityPrompt"), "Triggered")
		triggered:Fire(alice)
		triggered:Fire(alice)
		eq(S.Stones.glintCount(), Config.GLINT_COUNT - 2, "only one more taken")
	end)
	it("new glints wash up after a while", function()
		env.advance(Config.GLINT_RESPAWN_MAX + 1)
		eq(S.Stones.glintCount(), Config.GLINT_COUNT, "back to a full set")
	end)
end)

-- ===== Choosing a stone =====

describe("Equipping", function()
	it("only stones you own", function()
		local profile = env.profileOf(alice)
		profile.stones.starstone = nil
		env.send(alice, "Equip", "starstone")
		eq(profile.equipped, "pebble", "not owned")
		env.send(alice, "Equip", "notastone")
		env.send(alice, "Equip", 42)
		eq(profile.equipped, "pebble", "junk ignored")
	end)
	it("switches the stone in your hand", function()
		local profile = env.profileOf(alice)
		profile.stones.slate = 2
		env.send(alice, "Equip", "slate")
		eq(profile.equipped, "slate")
		eq(alice.Character.HeldStone:GetAttribute("Stone"), "slate", "in hand")
		local holding = 0
		for _, child in alice.Character:GetChildren() do
			if child.Name == "HeldStone" then
				holding += 1
			end
		end
		eq(holding, 1, "only one stone in hand")
	end)
	it("the stone you hold is the one you throw", function()
		local spot = onShore(math.rad(60), 4)
		env.moveTo(alice, spot)
		env.advance(Config.THROW_COOLDOWN)
		local event = throw(alice, towardCentre(spot), SWEET_HOLD)
		eq(event.stone, "slate")
		env.advance(Config.THROW_COOLDOWN)
	end)
end)

-- ===== Night, titles, records =====

describe("Night", function()
	it("the test panel can bring the night, and the sky follows", function()
		ok(S.Cheats.run(alice, "night"), "ran")
		eq(S.DayNight.isNight(), true, "night")
		ok(math.abs(env.lighting.ClockTime - 22) < 0.05, `clock {env.lighting.ClockTime}`)
		ok(env.lighting.Brightness < 1.5, "dimmer")
	end)
	it("a Moonstone at night counts toward the night goal", function()
		local profile = env.profileOf(alice)
		profile.stones.moonstone = 1
		env.send(alice, "Equip", "moonstone")
		local spot = onShore(math.rad(60), 4)
		env.moveTo(alice, spot)
		local event = throw(alice, towardCentre(spot), SWEET_HOLD)
		eq(event.night, true, "thrown at night")
		eq(profile.nightSkips, event.skips, "night record")
		ok(profile.goals.night10, "10 skips at night with a Moonstone")
		env.advance(Config.THROW_COOLDOWN)
	end)
	it("and morning comes back", function()
		S.Cheats.run(alice, "day")
		eq(S.DayNight.isNight(), false)
		ok(math.abs(env.lighting.ClockTime - 9) < 0.05, "nine o'clock")
	end)
end)

describe("Titles and records", function()
	it("a good best throw earns a floating title", function()
		local gui = alice.Character.Head:FindFirstChild("SkipperTitle")
		ok(gui, "title over the head")
		local title = GoalData.title(env.profileOf(alice).bestSkips)
		ok(title, "has a title")
		eq(gui.Text.Text, `✦ {title} ✦`)
	end)
	it("the leaderboards show this server's skippers (no DataStores here)", function()
		local bob = env.makePlayer("Bob")
		env.join(bob)
		S.Leaderboards.refresh()
		local board = S.World.get().boards.Skips
		eq(board.Row1.Player.Text, "Alice", "first")
		eq(board.Row1.Score.Text, `{env.profileOf(alice).bestSkips} skips`)
		eq(board.Row2.Player.Text, "Bob", "second")
		eq(board.Row3.Player.Text, "", "empty")
		local distance = S.World.get().boards.Distance
		ok(string.find(distance.Row1.Score.Text, "studs", 1, true), distance.Row1.Score.Text)
		env.leave(bob)
	end)
end)

-- ===== Test panel =====

describe("Test panel", function()
	it("gives every stone", function()
		S.Cheats.run(alice, "stones")
		for _, stone in StoneData.LIST do
			ok((env.profileOf(alice).stones[stone.id] or 0) >= 1, stone.id)
		end
		ok(env.profileOf(alice).goals.stones12, "the collection goal")
	end)
	it("is closed to ordinary players in live games", function()
		local studio = env.services.RunService.IsStudio
		env.services.RunService.IsStudio = function()
			return false
		end
		eq(S.Cheats.run(alice, "stones"), false, "refused")
		env.services.RunService.IsStudio = studio
	end)
	it("ignores unknown actions", function()
		eq(S.Cheats.run(alice, "coins"), false)
		eq(S.Cheats.run(alice, 7), false)
	end)
	it("can wipe the journal", function()
		S.Cheats.run(alice, "reset")
		local profile = env.profileOf(alice)
		eq(profile.bestSkips, 0)
		eq(profile.equipped, "pebble")
		eq(alice.Character.HeldStone:GetAttribute("Stone"), "pebble", "pebble back in hand")
		eq(alice.leaderstats["Best Skips"].Value, 0, "player list")
		eq(alice.Character.Head:FindFirstChild("SkipperTitle"), nil, "title gone")
	end)
end)

-- ===== Safety nets and leaving =====

describe("Safety nets", function()
	it("anyone who ends up in the lake is put back by the spawn", function()
		env.moveTo(alice, Vector3.new(0, -6, 0))
		eq(S.World.rescue(alice), true, "rescued")
		local p = alice.Character.HumanoidRootPart.CFrame.Position
		ok((p - S.World.get().spawn.CFrame.Position).Magnitude < 6, "by the spawn")
		eq(S.World.rescue(alice), false, "only when needed")
	end)
	it("the stone moves to the new hand when the avatar finishes loading", function()
		local character = alice.Character
		character.RightHand:Destroy()
		local hand = roblox.Instance.new("Part")
		hand.Name = "RightHand"
		hand.Parent = character
		env.signal(alice, "CharacterAppearanceLoaded"):Fire(character)
		local held = character:FindFirstChild("HeldStone")
		ok(held, "still holding a stone")
		eq(held:FindFirstChildOfClass("WeldConstraint").Part0, hand, "welded to the new hand")
	end)
	it("a character that respawns gets its stone back", function()
		alice.Character:Destroy()
		local character = env.makeCharacter(alice)
		env.signal(alice, "CharacterAdded"):Fire(character)
		ok(character:FindFirstChild("HeldStone"), "stone in the new hand")
	end)
end)

describe("Leaving", function()
	it("saves, forgets the player and ignores their late messages", function()
		env.leave(alice)
		eq(S.Data.get(alice), nil, "released")
		eq(S.Sessions.get(alice), nil, "no session")
		env.send(alice, "BeginCharge")
		env.send(alice, "Release", Vector3.new(0, 0, -1), SWEET_HOLD)
		env.send(alice, "Equip", "pebble")
	end)
end)

print(`{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
