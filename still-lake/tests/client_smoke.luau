--!nocheck
-- Loads every client controller in a fake client and plays through the
-- screens: the HUD and power meter, winding up and throwing, a stone's flight
-- and the result, the journal's tabs, toasts and found-stone cards, night
-- ambience and the test panel. Run from still-lake/: lune run tests/client_smoke

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local ClientEnv = require("./support/ClientEnv")

local Vector3 = roblox.Vector3
local Instance = roblox.Instance

local env = ClientEnv.new()
local C = env.C
local Loader = require("./loader")
local Skip = Loader.load("src/shared/Skip")
local Lake = Loader.load("src/shared/Lake")
local Tags = Loader.load("src/shared/Tags")
local GoalData = Loader.load("src/shared/Data/GoalData")
local StoneData = Loader.load("src/shared/Data/StoneData")

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

local function gui(name)
	return env.playerGui:FindFirstChild(name)
end

local function find(root, name)
	return root:FindFirstChild(name, true)
end

local R = Lake.EDGE + 1
local BEACH = Vector3.new(0, 3, R + 5) -- on the beach, the lake to the -Z side
local SWEET_HOLD = Skip.SWEET * Skip.PERIOD / 2

local function faceLake()
	env.lookAt(BEACH + Vector3.new(0, 4, 8), Vector3.new(0, 0, 0))
end

local function throwEvent(overrides)
	local entry = Vector3.new(0, 0, Lake.EDGE)
	local event = {
		userId = env.localPlayer.UserId,
		stone = "pebble",
		origin = BEACH + Vector3.new(0, 1.2, -0.8),
		entry = entry,
		direction = Vector3.new(0, 0, -1),
		hops = { 10, 8, 6.5, 5, 4 },
		skips = 5,
		distance = 33.5,
		verdict = "skips",
		perfect = false,
		power = 0.8,
		night = false,
		newBestSkips = false,
		newBestDistance = false,
	}
	for k, v in overrides or {} do
		event[k] = v
	end
	return event
end

-- Runs frames until every stone in the air has landed (or gives up).
local function settle()
	for _ = 1, 600 do
		env.frame(1 / 30)
	end
end

env.makeCharacter(BEACH)
faceLake()
env.pushState()

describe("Loading", function()
	it("every controller loads and sets up", function()
		for _, name in
			{
				"Ambience",
				"Audio",
				"ClientState",
				"DevPanel",
				"Hud",
				"Journal",
				"StoneFx",
				"ThrowInput",
				"Toasts",
			}
		do
			ok(C[name], name)
		end
		for _, name in { "Hud", "Journal", "Toasts", "DevPanel" } do
			ok(gui(name), name .. " screen")
		end
	end)
	it("asks the server for its state once started", function()
		C.ClientState.start()
		ok(env.lastSent("Ready"), "Ready sent")
	end)
	it("the screen canvas fills phones and desktops", function()
		for _, size in { { 1280, 720 }, { 844, 390 }, { 1920, 1080 }, { 1024, 768 } } do
			env.setViewport(size[1], size[2])
			local canvas = gui("Hud").Canvas
			local scale = canvas:FindFirstChildOfClass("UIScale").Scale
			local w = canvas.Size.X.Offset * scale
			local h = canvas.Size.Y.Offset * scale
			-- (offsets are whole pixels, so it may overhang by a fraction)
			ok(w >= size[1] - 1e-6 and w < size[1] + 2, `width {w} for {size[1]}`)
			ok(h >= size[2] - 58 - 1e-6 and h < size[2] - 58 + 2, `height {h} for {size[2]}`)
			ok(canvas.Size.X.Offset >= 700, `room for the journal at {size[1]}x{size[2]}`)
		end
		env.setViewport(1280, 720)
	end)
end)

describe("HUD", function()
	it("shows the stone in hand and the best throw", function()
		local hud = gui("Hud")
		eq(find(hud, "StoneName").Text, "Pebble")
		eq(find(hud, "Rarity").Text, "Common")
		local best = hud.Canvas.Best.Text.Text
		ok(string.find(best, "×12", 1, true) and string.find(best, "Splash Artist", 1, true), best)
	end)
	it("a newcomer is told to skip a first stone", function()
		env.pushState({ bestSkips = 0, bestDistance = 0, title = nil, throws = 0 })
		eq(gui("Hud").Canvas.Best.Text.Text, "Skip your first stone")
	end)
	it("the meter and how-to hint appear by the water", function()
		env.frame()
		eq(C.ThrowInput.state.status, "ok", "can throw here")
		eq(gui("Hud").Canvas.PowerMeter.Visible, true, "meter")
		ok(
			string.find(gui("Hud").Canvas.Hint.Text, "Hold click", 1, true),
			gui("Hud").Canvas.Hint.Text
		)
	end)
	it("the meter's zones match the skip rules", function()
		local bands = find(gui("Hud"), "Bands")
		local gold = bands.Gold
		ok(math.abs(gold.Position.Y.Scale - (1 - Skip.GOLD_LOW)) < 1e-6, "gold starts")
		ok(math.abs(gold.Size.Y.Scale - (Skip.DIVE - Skip.GOLD_LOW)) < 1e-6, "gold height")
		local perfect = bands.Perfect
		ok(math.abs(perfect.Size.Y.Scale - 2 * Skip.PERFECT) < 1e-6, "perfect band")
		ok(
			math.abs(perfect.Position.Y.Scale - (1 - (Skip.SWEET - Skip.PERFECT))) < 1e-6,
			"perfect position"
		)
	end)
	it("facing away shows what's wrong; far from the water hides the meter", function()
		env.lookAt(BEACH, BEACH + Vector3.new(0, 0, 10))
		env.frame()
		eq(C.ThrowInput.state.status, "away")
		ok(string.find(gui("Hud").Canvas.Hint.Text, "Face the open water", 1, true), "hint")
		env.moveTo(Vector3.new(0, 3, 200))
		env.frame()
		eq(C.ThrowInput.state.status, "far")
		eq(gui("Hud").Canvas.PowerMeter.Visible, false, "meter hidden")
		env.moveTo(BEACH)
		faceLake()
		env.frame()
	end)
	it("an old hand doesn't need the how-to hint", function()
		env.pushState({ throws = 40 })
		env.frame()
		eq(gui("Hud").Canvas.Hint.Text, "")
	end)
end)

describe("Throwing", function()
	local function press()
		env.inputBegan:Fire({
			UserInputType = roblox.Enum.UserInputType.MouseButton1,
			KeyCode = roblox.Enum.KeyCode.Unknown,
		}, false)
	end
	local function release()
		env.inputEnded:Fire({
			UserInputType = roblox.Enum.UserInputType.MouseButton1,
			KeyCode = roblox.Enum.KeyCode.Unknown,
		})
	end
	it("holding winds up the needle and plants your feet", function()
		table.clear(env.sent)
		press()
		ok(env.lastSent("BeginCharge"), "told the server")
		eq(C.ThrowInput.state.charging, true)
		eq(env.localPlayer.Character.Humanoid.WalkSpeed, C.ThrowInput.CHARGE_WALKSPEED, "slowed")
		env.frame(SWEET_HOLD)
		ok(math.abs(C.ThrowInput.power() - Skip.SWEET) < 1e-6, "needle at the sweet spot")
		local needle = find(gui("Hud"), "Needle")
		eq(needle.Visible, true, "needle shows")
		ok(math.abs(needle.Position.Y.Scale - (1 - Skip.SWEET)) < 1e-6, "needle position")
	end)
	it("letting go sends the throw toward the lake and says Perfect", function()
		release()
		local message = env.lastSent("Release")
		ok(message, "release sent")
		local direction, held = message.args[1], message.args[2]
		ok(direction.Z < -0.9, "toward the lake")
		ok(math.abs(held - SWEET_HOLD) < 1e-6, `held {held}`)
		eq(C.ThrowInput.state.charging, false)
		eq(env.localPlayer.Character.Humanoid.WalkSpeed, 16, "walking again")
		eq(find(gui("Hud"), "Flash").Text, "Perfect!")
	end)
	it("can't wind up again during the cooldown", function()
		table.clear(env.sent)
		press()
		eq(env.lastSent("BeginCharge"), nil)
		release()
		env.frame(1.5)
	end)
	it("a quick tap is cancelled, not thrown", function()
		table.clear(env.sent)
		press()
		env.frame(0.03)
		release()
		ok(env.lastSent("CancelCharge"), "cancelled")
		eq(env.lastSent("Release"), nil, "no throw")
	end)
	it("held far too long, the wind-up gives up by itself", function()
		table.clear(env.sent)
		press()
		env.frame(9)
		eq(C.ThrowInput.state.charging, false)
		ok(env.lastSent("CancelCharge"), "cancelled")
		release()
		eq(env.lastSent("Release"), nil, "nothing thrown")
	end)
	it("clicks on the UI don't throw", function()
		table.clear(env.sent)
		env.inputBegan:Fire({
			UserInputType = roblox.Enum.UserInputType.MouseButton1,
			KeyCode = roblox.Enum.KeyCode.Unknown,
		}, true)
		eq(env.lastSent("BeginCharge"), nil)
	end)
	it("a finger that slides off the Throw button still throws when lifted", function()
		env.frame(1.5)
		table.clear(env.sent)
		local finger = {
			UserInputType = roblox.Enum.UserInputType.Touch,
			KeyCode = roblox.Enum.KeyCode.Unknown,
		}
		C.ThrowInput.press(finger)
		env.frame(SWEET_HOLD)
		-- some other finger (the camera) lifting doesn't count
		env.inputEnded:Fire({
			UserInputType = roblox.Enum.UserInputType.Touch,
			KeyCode = roblox.Enum.KeyCode.Unknown,
		})
		eq(C.ThrowInput.state.charging, true, "still winding up")
		env.inputEnded:Fire(finger)
		ok(env.lastSent("Release"), "thrown")
		env.frame(1.5)
	end)
	it("pressing while facing away flashes the reason", function()
		env.lookAt(BEACH, BEACH + Vector3.new(0, 0, 10))
		press()
		eq(C.ThrowInput.state.charging, false)
		ok(string.find(find(gui("Hud"), "Flash").Text, "Face the open water", 1, true), "flash")
		release()
		faceLake()
	end)
end)

describe("Stones in flight", function()
	it("plans one segment per hop after the flight to the water", function()
		local event = throwEvent()
		local segments = C.StoneFx.plan(event)
		eq(#segments, #event.hops + 1)
		eq(segments[1].from, event.origin, "from the hand")
		eq(segments[1].to, event.entry, "to the water")
		for i = 2, #segments do
			eq(segments[i].from, segments[i - 1].to, "joined up")
			eq(segments[i].touch, true, "a skip")
			ok(
				math.abs((segments[i].to - segments[i].from).Magnitude - event.hops[i - 1]) < 1e-6,
				"hop length"
			)
			ok(segments[i].duration <= segments[i - 1].duration or i == 2, "hops get quicker")
		end
		local last = segments[#segments].to
		ok(
			math.abs(Lake.distanceFromCentre(last) - (Lake.EDGE - 33.5)) < 1e-6,
			"ends where the server said"
		)
	end)
	it("a stone that crosses the lake ends up on the far beach", function()
		local event = throwEvent({
			verdict = "shore",
			hops = { 60, 50, 40, 40.0 + 28 },
			skips = 4,
			distance = 2 * Lake.EDGE,
		})
		local segments = C.StoneFx.plan(event)
		eq(#segments, #event.hops + 2, "an extra slide")
		local rest = segments[#segments].to
		ok(Lake.distanceFromCentre(rest) > Lake.EDGE, "past the water")
		ok(rest.Y > 0, "on the sand")
	end)
	it("the arc starts and ends on the segment's points", function()
		local segment = C.StoneFx.plan(throwEvent())[2]
		eq(C.StoneFx.positionOn(segment, 0), segment.from)
		ok((C.StoneFx.positionOn(segment, 1) - segment.to).Magnitude < 1e-9, "lands")
		ok(C.StoneFx.positionOn(segment, 0.5).Y > 0, "in the air between")
	end)
	it("a throw flies, ripples, lands and shows the result", function()
		local landed = nil
		C.ClientState.landed:connect(function(event)
			landed = event
		end)
		env.listeners.Throw(throwEvent({ skips = 5, newBestSkips = true }))
		local fx = env.workspace.LakeFx
		ok(fx:FindFirstChild("Stone"), "a stone in the air")
		settle()
		ok(landed, "landed")
		eq(fx:FindFirstChild("Stone"), nil, "sank")
		local result = find(gui("Hud"), "Result")
		eq(result.Title.Text, "5 skips!")
		ok(string.find(result.Line.Text, "New best!", 1, true), result.Line.Text)
		local ripplesUsed = 0
		for _, part in fx:GetChildren() do
			if part.Name == "Ripple" and part.Size.X > 0.6 then
				ripplesUsed += 1
			end
		end
		ok(ripplesUsed >= 6, `ripples {ripplesUsed}`)
	end)
	it("someone else's throw doesn't pop up a result for you", function()
		local result = find(gui("Hud"), "Result")
		env.advance(5)
		result.Title.Text = ""
		env.listeners.Throw(throwEvent({ userId = 99 }))
		settle()
		eq(result.Title.Text, "", "no popup")
	end)
	it("many throws at once never pile up", function()
		for i = 1, 20 do
			env.listeners.Throw(throwEvent({ userId = 100 + i }))
		end
		local flying = 0
		for _, child in env.workspace.LakeFx:GetChildren() do
			if child.Name == "Stone" and child.Transparency < 1 then
				flying += 1
			end
		end
		ok(flying <= C.StoneFx.MAX_FLIGHTS, `{flying} in the air`)
		settle()
	end)
	it("describes every kind of throw", function()
		local title, line = C.Hud.describe(throwEvent({ verdict = "plop", skips = 0, hops = {} }))
		eq(title, "Plop.")
		ok(string.find(line, "gentle", 1, true), line)
		title = C.Hud.describe(throwEvent({ verdict = "dive", skips = 0, hops = {} }))
		eq(title, "Sploosh!")
		title, line = C.Hud.describe(throwEvent({ verdict = "shore", perfect = true }))
		eq(title, "5 skips!")
		ok(
			string.find(line, "All the way across", 1, true)
				and string.find(line, "Perfect", 1, true),
			line
		)
		title = C.Hud.describe(throwEvent({ skips = 1, hops = { 5 } }))
		eq(title, "1 skip")
	end)
end)

describe("Journal", function()
	it("opens on the stones: found ones named, others a mystery", function()
		env.pushState()
		C.Journal.open("Stones")
		local grid = find(gui("Journal"), "Grid")
		local cards = 0
		for _, card in grid:GetChildren() do
			if card:IsA("TextButton") then
				cards += 1
			end
		end
		eq(cards, #StoneData.LIST, "a card per stone")
		eq(grid.slate.Title.Text, "Slate", "found")
		eq(grid.starstone.Title.Text, "Not found yet", "unfound")
		eq(grid.pebble.Status.Text, "In hand")
		ok(string.find(grid.slate.Rarity.Text, "×2", 1, true), "count")
	end)
	it("tapping a found stone picks it", function()
		table.clear(env.sent)
		local grid = find(gui("Journal"), "Grid")
		env.signal(grid.slate, "Activated"):Fire()
		local message = env.lastSent("Equip")
		ok(message and message.args[1] == "slate", "equip slate")
		table.clear(env.sent)
		env.signal(grid.starstone, "Activated"):Fire()
		eq(env.lastSent("Equip"), nil, "can't pick an unfound stone")
	end)
	it("the goals tab lists every goal with progress", function()
		C.Journal.open("Goals")
		local list = find(gui("Journal"), "List")
		for _, goal in GoalData.GOALS do
			ok(list:FindFirstChild(goal.id), goal.id)
		end
		eq(list.skip10.Bar.Fill.Size.X.Scale, 1, "done goal full")
		ok(math.abs(list.skip15.Bar.Fill.Size.X.Scale - 12 / 15) < 1e-6, "12 of 15")
	end)
	it("the records tab shows the numbers and the next title", function()
		C.Journal.open("Records")
		local journal = gui("Journal")
		eq(find(journal, "Rows").Row1.Value.Text, "12")
		local title = find(journal, "Title").Text
		ok(string.find(title, "Skimmer at 15", 1, true), title)
	end)
	it("updates while open and closes", function()
		env.pushState({ bestSkips = 31, title = "Legend of Still Lake" })
		local title = find(gui("Journal"), "Title").Text
		ok(string.find(title, "highest there is", 1, true), title)
		C.Journal.close()
		eq(C.Journal.isOpen(), false)
		eq(find(gui("Journal"), "Panel").Visible, false)
	end)
	it("J opens and closes it", function()
		env.inputBegan:Fire(
			{ UserInputType = roblox.Enum.UserInputType.Keyboard, KeyCode = roblox.Enum.KeyCode.J },
			false
		)
		eq(C.Journal.isOpen(), true)
		env.inputBegan:Fire(
			{ UserInputType = roblox.Enum.UserInputType.Keyboard, KeyCode = roblox.Enum.KeyCode.J },
			false
		)
		eq(C.Journal.isOpen(), false)
	end)
	it("goal progress dots read sensibly", function()
		eq(C.Journal.dots(0), "●○○○○")
		eq(C.Journal.dots(0.5), "●●●○○")
		eq(C.Journal.dots(1), "●●●●●")
	end)
end)

describe("Messages", function()
	it("server messages become toasts, at most a few at once", function()
		for i = 1, 6 do
			env.listeners.Notify(`message {i}`, "good")
		end
		local count = 0
		for _, child in find(gui("Toasts"), "Stack"):GetChildren() do
			if child:IsA("Frame") then
				count += 1
			end
		end
		ok(count <= C.Toasts.MAX and count > 0, `{count} toasts`)
		env.advance(5)
	end)
	it("finding a stone shows a card", function()
		env.listeners.Found("slate", true, 1)
		local card = C.Toasts.latest()
		eq(card.Name, "Found")
		eq(card.Title.Text, "New stone: Slate!")
		env.listeners.Found("slate", false, 3)
		local again = C.Toasts.latest()
		eq(again.Title.Text, "Another Slate")
		ok(string.find(again.Line.Text, "3", 1, true), again.Line.Text)
		env.advance(6)
		eq(C.Toasts.latest(), nil, "they go away")
	end)
end)

describe("Night", function()
	local light = Instance.new("PointLight")
	local glass = Instance.new("Part")
	light.Parent = glass
	light.Enabled = false
	local flies = Instance.new("ParticleEmitter")
	flies.Enabled = false
	local window = Instance.new("Part")
	env.services.CollectionService:AddTag(light, Tags.NIGHT_LIGHT)
	env.services.CollectionService:AddTag(flies, Tags.FIREFLIES)
	env.services.CollectionService:AddTag(window, Tags.WINDOW)
	it("lanterns, windows and fireflies come on after dusk", function()
		env.lighting.ClockTime = 22
		C.Ambience.update()
		eq(light.Enabled, true, "lantern")
		eq(flies.Enabled, true, "fireflies")
		eq(window.Material, roblox.Enum.Material.Neon, "window glows")
	end)
	it("and go off in the morning", function()
		env.lighting.ClockTime = 9
		C.Ambience.update()
		eq(light.Enabled, false)
		eq(flies.Enabled, false)
		eq(window.Material, roblox.Enum.Material.Glass, "glass by day")
	end)
end)

describe("Test panel", function()
	it("shows for testers and sends actions", function()
		env.pushState({ isDev = true })
		local toggle = find(gui("DevPanel"), "Toggle")
		eq(toggle.Visible, true)
		table.clear(env.sent)
		env.signal(find(gui("DevPanel"), "night"), "Activated"):Fire()
		local message = env.lastSent("Dev")
		ok(message and message.args[1] == "night", "night sent")
	end)
	it("stays hidden from everyone else", function()
		env.pushState({ isDev = false })
		eq(find(gui("DevPanel"), "Toggle").Visible, false)
	end)
end)

print(`{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
process.exit(0)
