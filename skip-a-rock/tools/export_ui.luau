--!nocheck
-- Builds the real client UI in the Lune client environment and writes each
-- screen state to JSON for the repo's tools/preview/render_ui.py.
--
-- Usage (from skip-a-rock/): lune run tools/export_ui [outDir] [touch]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local ClientEnv = require("../tests/support/ClientEnv")
local Export = require("../../tools/preview/Export")

local outDir = process.args[1] or "tools/out"
local touch = process.args[2] == "touch" -- a phone: the Throw button shows
fs.writeDir(outDir)

local Vector3 = roblox.Vector3
local VIEWPORTS = if touch
	then { phone = { 844, 390, true } }
	else { desktop = { 1280, 720, false }, phone = { 844, 390, true } }

local function capture(env, name: string, only: string?)
	for viewportName, vp in VIEWPORTS do
		if only == nil or only == viewportName then
			env.setViewport(vp[1], vp[2])
			local data = {
				viewport = { vp[1], vp[2] },
				touch = vp[3],
				screens = Export.screens(env.playerGui),
			}
			local suffix = if touch then "touch" else viewportName
			fs.writeFile(`{outDir}/ui_{name}_{suffix}.json`, serde.encode("json", data))
		end
	end
	print("captured " .. name)
end

local env = ClientEnv.new({ touch = touch })
local C = env.C
local Sea = require("../tests/loader").load("src/shared/Sea")
local BEACH = Vector3.new(30, 3, -10)
env.makeCharacter(BEACH)

-- on the beach, a newcomer
env.pushState({
	coins = 45,
	strengthCost = 20,
	throws = 1,
	bestDistance = 86,
	coinMultiplier = 1,
	title = nil,
})
env.frame(2)
capture(env, "hud")

-- mid-game: winding up, the needle in the gold
env.pushState({
	coins = 182400,
	strength = 18,
	strengthCost = 3410,
	coinMultiplier = 1.58,
	rebirths = 1,
	rebirthCost = 280000,
})
env.frame(2)
C.ThrowInput.press()
env.frame(0.62)
capture(env, "charging")
C.ThrowInput.letGo()

-- a finished throw
C.RockFx.chaseEnabled = false
local landed = false
C.ClientState.landed:connect(function()
	landed = true
end)
env.listeners.Throw({
	userId = env.localPlayer.UserId,
	rock = "slate",
	origin = BEACH + Vector3.new(0, 1.2, 0.8),
	entry = Vector3.new(BEACH.X, 0, Sea.FIRST_WATER),
	hops = { 900, 700, 500, 300, 200, 120, 80, 50 },
	skips = 8,
	distance = 2850,
	coins = 12700,
	verdict = "skips",
	perfect = true,
	power = 0.86,
	night = false,
	newBest = true,
})
for _ = 1, 400 do
	if landed then
		break
	end
	env.frame(1 / 30)
end
env.frame(0.3)
env.listeners.Notify("🎯 Goal complete: Make a perfect release", "good")
capture(env, "result")

-- the menu
env.advance(6)
env.pushState({
	coins = 182400,
	strength = 18,
	strengthCost = 3410,
	rebirths = 1,
	rebirthCost = 280000,
	coinMultiplier = 1.58,
	rocks = { pebble = true, river = true, slate = true, seaglass = true },
	equipped = "seaglass",
	islands = { buoy = true, gull = true },
	bestDistance = 2850,
})
C.Menu.open("Rocks")
capture(env, "menu_rocks")
C.Menu.open("Upgrades")
capture(env, "menu_upgrades", "desktop")
C.Menu.open("Rebirth")
capture(env, "menu_rebirth", "desktop")
C.Menu.open("Islands")
capture(env, "menu_islands", "desktop")
C.Menu.close()

-- an island reached, and the test panel open
env.listeners.Island("palm")
env.playerGui.DevPanel.Canvas.Panel.Visible = true
capture(env, "island")

process.exit(0)
