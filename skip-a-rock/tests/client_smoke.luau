--!nocheck
-- Loads every client controller in a fake client and plays through the
-- screens: coins and buttons, the power meter, winding up and throwing, a
-- rock's flight out to sea and the chase camera, the menu's tabs (buying,
-- upgrading, rebirthing), island banners, night ambience and the test panel.
-- Run from skip-a-rock/: lune run tests/client_smoke

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local ClientEnv = require("./support/ClientEnv")

local Vector3 = roblox.Vector3
local Instance = roblox.Instance

local env = ClientEnv.new()
local C = env.C
local Loader = require("./loader")
local Skip = Loader.load("src/shared/Skip")
local Sea = Loader.load("src/shared/Sea")
local Tags = Loader.load("src/shared/Tags")
local RockData = Loader.load("src/shared/Data/RockData")
local IslandData = Loader.load("src/shared/Data/IslandData")
local GoalData = Loader.load("src/shared/Data/GoalData")

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

local BEACH = Vector3.new(30, 3, -10)
local SWEET_HOLD = Skip.SWEET * Skip.PERIOD / 2

local function mouse(down: boolean, processed: boolean?)
	local input = {
		UserInputType = roblox.Enum.UserInputType.MouseButton1,
		KeyCode = roblox.Enum.KeyCode.Unknown,
	}
	if down then
		env.inputBegan:Fire(input, processed == true)
	else
		env.inputEnded:Fire(input)
	end
end

local function throwEvent(overrides)
	local event = {
		userId = env.localPlayer.UserId,
		rock = "river",
		origin = BEACH + Vector3.new(0, 1.2, 0.8),
		entry = Vector3.new(BEACH.X, 0, Sea.FIRST_WATER),
		hops = { 120, 100, 80, 60, 40 },
		skips = 5,
		distance = 400,
		coins = 1234,
		verdict = "skips",
		perfect = false,
		power = 0.8,
		night = false,
		newBest = false,
	}
	for k, v in overrides or {} do
		event[k] = v
	end
	return event
end

local function settle()
	for _ = 1, 600 do
		env.frame(1 / 30)
	end
end

env.makeCharacter(BEACH)
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
				"Menu",
				"RockFx",
				"ThrowInput",
				"Toasts",
			}
		do
			ok(C[name], name)
		end
		for _, name in { "Hud", "Menu", "Toasts", "DevPanel" } do
			ok(gui(name), name .. " screen")
		end
	end)
	it("asks the server for its state once started", function()
		C.ClientState.start()
		ok(env.lastSent("Ready"), "Ready sent")
	end)
	it("the screen canvas fills phones and desktops", function()
		for _, size in { { 1280, 720 }, { 844, 390 }, { 1920, 1080 } } do
			env.setViewport(size[1], size[2])
			local canvas = gui("Hud").Canvas
			local scale = canvas:FindFirstChildOfClass("UIScale").Scale
			local w = canvas.Size.X.Offset * scale
			ok(w >= size[1] - 1e-6 and w < size[1] + 2, `width {w} for {size[1]}`)
			ok(canvas.Size.X.Offset >= 820, `room for the menu at {size[1]}x{size[2]}`)
		end
		env.setViewport(1280, 720)
	end)
end)

describe("HUD", function()
	it("counts coins up to the real number and shows the multiplier", function()
		env.frame(1)
		local hud = gui("Hud")
		eq(find(hud, "Coins").Text, "🪙 2.5K")
		local details = find(hud, "Details").Text
		ok(
			string.find(details, "x1.05", 1, true) and string.find(details, "1.23K studs", 1, true),
			details
		)
	end)
	it("the upgrade button shows its price and lights up when affordable", function()
		local hud = gui("Hud")
		eq(find(hud, "Upgrade").Cost.Text, "🪙 109")
		env.pushState({ coins = 10, strengthCost = 109 })
		ok(find(hud, "Upgrade").BackgroundTransparency > 0.2, "dim when you can't afford it")
		env.pushState()
		ok(find(hud, "Upgrade").BackgroundTransparency < 0.2, "lit when you can")
	end)
	it("one tap on Upgrade buys a level", function()
		table.clear(env.sent)
		env.signal(find(gui("Hud"), "Upgrade"), "Activated"):Fire()
		local message = env.lastSent("Upgrade")
		ok(message and message.args[1] == 1, "upgrade 1")
	end)
	it("the meter shows on the beach, not on the boardwalk", function()
		env.frame()
		eq(C.ThrowInput.state.status, "ok")
		eq(gui("Hud").Canvas.PowerMeter.Visible, true)
		env.moveTo(Vector3.new(0, 4.3, -80))
		env.frame()
		eq(C.ThrowInput.state.status, "far")
		eq(gui("Hud").Canvas.PowerMeter.Visible, false)
		env.moveTo(BEACH)
		env.frame()
	end)
	it("a newcomer on the boardwalk is told to walk down to the beach", function()
		env.pushState({ throws = 0 })
		env.moveTo(Vector3.new(0, 4.3, -80))
		env.frame()
		ok(string.find(gui("Hud").Canvas.Hint.Text, "beach", 1, true), gui("Hud").Canvas.Hint.Text)
		env.moveTo(BEACH)
		env.frame()
		ok(string.find(gui("Hud").Canvas.Hint.Text, "Hold click", 1, true), "how to throw")
		env.pushState()
		env.frame()
	end)
end)

describe("Throwing", function()
	it("holding winds up the needle; letting go sends the hold time and faces the sea", function()
		table.clear(env.sent)
		mouse(true)
		ok(env.lastSent("BeginCharge"), "wind-up")
		env.frame(SWEET_HOLD)
		ok(math.abs(C.ThrowInput.power() - Skip.SWEET) < 1e-6, "needle at the sweet spot")
		mouse(false)
		local message = env.lastSent("Release")
		ok(message, "release sent")
		ok(math.abs(message.args[1] - SWEET_HOLD) < 1e-6, "hold time")
		eq(find(gui("Hud"), "Flash").Text, "Perfect!")
		local look = env.localPlayer.Character.HumanoidRootPart.CFrame.LookVector
		ok(look.Z > 0.99, "facing the sea")
		env.frame(1.5)
	end)
	it("taps cancel, UI clicks don't throw, overlong holds give up", function()
		table.clear(env.sent)
		mouse(true)
		env.frame(0.03)
		mouse(false)
		ok(env.lastSent("CancelCharge") and not env.lastSent("Release"), "tap")
		table.clear(env.sent)
		mouse(true, true)
		eq(env.lastSent("BeginCharge"), nil, "click on the UI")
		mouse(true)
		env.frame(9)
		eq(C.ThrowInput.state.charging, false, "gave up")
		mouse(false)
		eq(env.lastSent("Release"), nil)
	end)
	it("can't wind up on the boardwalk", function()
		env.moveTo(Vector3.new(0, 4.3, -80))
		table.clear(env.sent)
		mouse(true)
		mouse(false)
		eq(env.lastSent("BeginCharge"), nil)
		env.moveTo(BEACH)
	end)
end)

describe("Rocks in flight", function()
	it("plans hops out to sea on the squeezed scale", function()
		local event = throwEvent({ hops = { 1000, 800, 600, 400, 200 }, distance = 3000 })
		local segments = C.RockFx.plan(event)
		eq(#segments, #event.hops + 1)
		eq(segments[1].to, event.entry)
		local last = segments[#segments].to
		ok(
			math.abs(last.Z - (event.entry.Z + Sea.toWorld(3000))) < 1e-3,
			"lands where the scale says"
		)
		eq(last.X, event.entry.X, "straight out")
	end)
	it("huge throws are sped up to finish in a few seconds", function()
		local hops = {}
		for i = 1, 40 do
			hops[i] = 1e9 / i
		end
		local segments = C.RockFx.plan(throwEvent({ hops = hops, skips = 40, distance = 4e9 }))
		ok(
			C.RockFx.duration(segments) <= C.RockFx.MAX_FLIGHT_SECONDS + 1,
			`flight {C.RockFx.duration(segments)}s`
		)
	end)
	it("a throw flies, ripples, sinks and shows coins and distance", function()
		local landed
		C.ClientState.landed:connect(function(event)
			landed = event
		end)
		env.listeners.Throw(throwEvent({ newBest = true }))
		ok(env.workspace.SeaFx:FindFirstChild("Rock"), "a rock in the air")
		settle()
		ok(landed, "landed")
		local result = find(gui("Hud"), "Result")
		eq(result.Title.Text, "+1.23K 🪙")
		ok(
			string.find(result.Line.Text, "New record!", 1, true)
				and string.find(result.Line.Text, "400 studs", 1, true),
			result.Line.Text
		)
	end)
	it("the camera chases your own long throw, then comes back", function()
		env.listeners.Throw(throwEvent({ hops = { 300, 250, 200 }, skips = 3, distance = 750 }))
		env.frame(0.3)
		eq(C.RockFx.isChasing(), true, "chasing")
		eq(env.camera.CameraType, roblox.Enum.CameraType.Scriptable)
		settle()
		eq(C.RockFx.isChasing(), false, "done")
		eq(env.camera.CameraType, roblox.Enum.CameraType.Custom, "camera back")
	end)
	it("pressing throw skips the chase; the 🎥 button turns it off", function()
		env.listeners.Throw(throwEvent({ hops = { 300, 250, 200 }, skips = 3, distance = 750 }))
		env.frame(0.2)
		mouse(true)
		eq(C.RockFx.isChasing(), false, "skipped")
		mouse(false)
		settle()
		env.signal(find(gui("Hud"), "Camera"), "Activated"):Fire()
		eq(C.RockFx.chaseEnabled, false)
		env.listeners.Throw(throwEvent({ hops = { 300, 250, 200 }, skips = 3, distance = 750 }))
		env.frame(0.2)
		eq(C.RockFx.isChasing(), false, "off")
		settle()
		env.signal(find(gui("Hud"), "Camera"), "Activated"):Fire()
		eq(C.RockFx.chaseEnabled, true)
	end)
	it("other people's throws don't move your camera or pop up results", function()
		local result = find(gui("Hud"), "Result")
		env.advance(5)
		result.Title.Text = ""
		env.listeners.Throw(throwEvent({ userId = 99 }))
		env.frame(0.3)
		eq(C.RockFx.isChasing(), false)
		settle()
		eq(result.Title.Text, "")
	end)
	it("describes plops and dives", function()
		eq(
			C.Hud.describe(throwEvent({ verdict = "plop", skips = 0, hops = {}, coins = 0 })),
			"Plop."
		)
		eq(
			C.Hud.describe(throwEvent({ verdict = "dive", skips = 0, hops = {}, coins = 0 })),
			"Sploosh!"
		)
	end)
end)

describe("Menu", function()
	it("rocks: owned ones equip, affordable ones buy, locked ones say where to go", function()
		env.pushState()
		C.Menu.open("Rocks")
		local grid = find(gui("Menu"), "Grid")
		local cards = 0
		for _, card in grid:GetChildren() do
			if card:IsA("Frame") then
				cards += 1
			end
		end
		eq(cards, #RockData.LIST)
		eq(grid.river.Action.Label.Text, "In hand")
		eq(grid.pebble.Action.Label.Text, "Equip")
		eq(grid.slate.Action.Label.Text, "🪙 1.5K", "affordable")
		ok(string.find(grid.basalt.Action.Label.Text, "Gull Rock", 1, true), "locked")
		table.clear(env.sent)
		env.signal(grid.slate.Action, "Activated"):Fire()
		ok(env.lastSent("BuyRock") and env.lastSent("BuyRock").args[1] == "slate", "buy")
		env.signal(grid.pebble.Action, "Activated"):Fire()
		ok(env.lastSent("Equip") and env.lastSent("Equip").args[1] == "pebble", "equip")
		table.clear(env.sent)
		env.signal(grid.basalt.Action, "Activated"):Fire()
		eq(env.lastSent("BuyRock"), nil, "locked rocks can't be bought")
	end)
	it("upgrades: +1, +10 and max", function()
		C.Menu.open("Upgrades")
		local menu = gui("Menu")
		ok(string.find(find(menu, "Level").Text, "Level 6", 1, true), find(menu, "Level").Text)
		table.clear(env.sent)
		env.signal(find(menu, "Option2").Buy, "Activated"):Fire()
		eq(env.lastSent("Upgrade").args[1], 10)
		env.signal(find(menu, "Option3").Buy, "Activated"):Fire()
		eq(env.lastSent("Upgrade").args[1], 100)
	end)
	it("rebirth: shows what you get, and needs two taps", function()
		env.pushState({ coins = 50000 })
		C.Menu.open("Rebirth")
		local menu = gui("Menu")
		ok(
			string.find(find(menu, "Progress").Text, "50K / 40K", 1, true),
			find(menu, "Progress").Text
		)
		table.clear(env.sent)
		env.signal(find(menu, "RebirthButton"), "Activated"):Fire()
		eq(env.lastSent("Rebirth"), nil, "first tap only arms it")
		env.advance(0.6)
		env.signal(find(gui("Menu"), "RebirthButton"), "Activated"):Fire()
		ok(env.lastSent("Rebirth"), "second tap rebirths")
		env.pushState({ coins = 100 })
		eq(find(gui("Menu"), "RebirthButton").Label.Text, "Not enough coins yet")
	end)
	it("islands list every island with its bonus", function()
		C.Menu.open("Islands")
		local list = find(gui("Menu"), "List")
		for _, island in IslandData.LIST do
			ok(list:FindFirstChild(island.id), island.id)
		end
	end)
	it("goals list every goal", function()
		C.Menu.open("Goals")
		local list = find(gui("Menu"), "List")
		for _, goal in GoalData.GOALS do
			ok(list:FindFirstChild(goal.id), goal.id)
		end
	end)
	it("M toggles it, and walking up to a shop opens its tab", function()
		C.Menu.close()
		env.inputBegan:Fire(
			{ UserInputType = roblox.Enum.UserInputType.Keyboard, KeyCode = roblox.Enum.KeyCode.M },
			false
		)
		eq(C.Menu.isOpen(), true)
		env.inputBegan:Fire(
			{ UserInputType = roblox.Enum.UserInputType.Keyboard, KeyCode = roblox.Enum.KeyCode.M },
			false
		)
		eq(C.Menu.isOpen(), false)
		local prompt = Instance.new("ProximityPrompt")
		prompt:SetAttribute("Menu", "Upgrades")
		env.services.ProximityPromptService.PromptTriggered:Fire(prompt)
		eq(C.Menu.isOpen(), true)
		eq(C.Menu.current(), "Upgrades")
		C.Menu.close()
	end)
	it("the side buttons open their tabs", function()
		env.signal(find(gui("Hud"), "Rocks"), "Activated"):Fire()
		eq(C.Menu.current(), "Rocks")
		env.signal(find(gui("Hud"), "Rebirth"), "Activated"):Fire()
		eq(C.Menu.current(), "Rebirth")
		C.Menu.close()
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
		env.advance(6)
	end)
	it("reaching an island shows a banner", function()
		env.listeners.Island("gull")
		local card = C.Toasts.latest()
		eq(card.Name, "Island")
		ok(string.find(card.Title.Text, "Gull Rock", 1, true), card.Title.Text)
		env.advance(6)
		eq(C.Toasts.latest(), nil, "goes away")
	end)
end)

describe("Night", function()
	local light = Instance.new("PointLight")
	local glass = Instance.new("Part")
	light.Parent = glass
	light.Enabled = false
	local flies = Instance.new("ParticleEmitter")
	flies.Enabled = false
	env.services.CollectionService:AddTag(light, Tags.NIGHT_LIGHT)
	env.services.CollectionService:AddTag(flies, Tags.FIREFLIES)
	it("lanterns and fireflies come on after dusk, and the sea darkens", function()
		env.lighting.ClockTime = 22
		C.Ambience.update()
		eq(light.Enabled, true)
		eq(flies.Enabled, true)
		local night = env.workspace.Terrain.WaterColor
		env.lighting.ClockTime = 10
		C.Ambience.update()
		eq(light.Enabled, false)
		ok(env.workspace.Terrain.WaterColor.B > night.B, "brighter by day")
	end)
end)

describe("Test panel", function()
	it("shows for testers and sends actions", function()
		env.pushState({ isDev = true })
		eq(find(gui("DevPanel"), "Toggle").Visible, true)
		table.clear(env.sent)
		env.signal(find(gui("DevPanel"), "coins"), "Activated"):Fire()
		ok(env.lastSent("Dev") and env.lastSent("Dev").args[1] == "coins", "coins sent")
	end)
	it("stays hidden from everyone else", function()
		env.pushState({ isDev = false })
		eq(find(gui("DevPanel"), "Toggle").Visible, false)
	end)
end)

print(`{passed} passed, {failed} failed`)
process.exit(if failed > 0 then 1 else 0)
