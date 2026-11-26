--!nocheck
-- Builds the real client UI in the Lune client environment and writes each
-- screen state to JSON for the repo's tools/preview/render_ui.py.
--
-- Usage (from still-lake/): lune run tools/export_ui [outDir]

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
local BEACH = Vector3.new(0, 3, 115)
env.makeCharacter(BEACH)
env.lookAt(BEACH + Vector3.new(0, 4, 8), Vector3.new(0, 0, 0))

-- a newcomer by the water: meter, hint
env.pushState({ bestSkips = 0, bestDistance = 0, title = nil, throws = 1 })
env.frame()
capture(env, "hud")

-- winding up, the needle in the gold
env.pushState()
C.ThrowInput.press()
env.frame(0.62)
capture(env, "charging")
C.ThrowInput.letGo()

-- a finished throw
local Lake = require("../tests/loader").load("src/shared/Lake")
env.listeners.Throw({
	userId = env.localPlayer.UserId,
	stone = "slate",
	origin = BEACH + Vector3.new(0, 1.2, -0.8),
	entry = Vector3.new(0, 0, Lake.EDGE),
	direction = Vector3.new(0, 0, -1),
	hops = { 14, 12, 10, 8.5, 7, 6, 5, 4, 3.4, 2.8, 2.3, 1.9, 1.6, 1.3 },
	skips = 14,
	distance = 80.2,
	verdict = "skips",
	perfect = true,
	power = 0.86,
	night = false,
	newBestSkips = true,
	newBestDistance = true,
})
local landed = false
C.ClientState.landed:connect(function()
	landed = true
end)
for _ = 1, 300 do
	if landed then
		break
	end
	env.frame(1 / 30)
end
env.frame(0.3)
env.listeners.Notify("🌊 Goal complete: 10 skips in one throw", "good")
env.listeners.Notify("✦ New title: Splash Artist ✦", "rare")
capture(env, "result")

-- the journal
env.advance(6)
env.pushState({
	stones = { pebble = 1, river = 3, slate = 2, seaglass = 1, jade = 1, moonstone = 1 },
	equipped = "slate",
})
C.Journal.open("Stones")
capture(env, "journal_stones")
C.Journal.open("Goals")
capture(env, "journal_goals", "desktop")
C.Journal.open("Records")
capture(env, "journal_records", "desktop")
C.Journal.close()

-- picking up a stone, and the test panel open
env.listeners.Found("moonstone", true, 1)
local panel = env.playerGui.DevPanel.Canvas.Panel
panel.Visible = true
env.listeners.Notify("✨ Bob found a Starstone!", "rare")
capture(env, "found")

process.exit(0)
