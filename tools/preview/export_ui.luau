--!nocheck
-- Builds the real client UI in the Lune client environment and writes the GUI
-- tree of each screen state to JSON for tools/preview/render_ui.py.
--
-- Usage: lune run tools/preview/export_ui [outDir]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local taskLib = require("@lune/task")
local ClientEnv = require("../../tests/support/ClientEnv")
local Export = require("./Export")

local outDir = process.args[1] or "tools/preview/out"
fs.writeDir(outDir)

local env = ClientEnv.new()
local Panels = env.Panels
local C = env.C

local VIEWPORTS = {
	desktop = { 1280, 720, false },
	phone = { 844, 390, true },
	tablet = { 1024, 768, true },
}

local function capture(name: string)
	for viewportName, vp in VIEWPORTS do
		env.setViewport(vp[1], vp[2])
		taskLib.wait(0.03)
		local data = {
			viewport = { vp[1], vp[2] },
			touch = vp[3],
			screens = Export.screens(env.playerGui),
		}
		fs.writeFile(`{outDir}/ui_{name}_{viewportName}.json`, serde.encode("json", data))
	end
	print("captured " .. name)
end

-- Scenes
env.pushState({ tutorial = 99 })
taskLib.wait(0.1)
capture("hud")

env.pushState({ tutorial = 1 })
taskLib.wait(0.1)
capture("tutorial")
env.pushState({ tutorial = 99 })
taskLib.wait(0.05)

Panels.open("Shop")
taskLib.wait(0.05)
capture("shop")

C.ShopUI.showOdds("Volcano")
taskLib.wait(0.05)
capture("odds")

Panels.open("Store")
taskLib.wait(0.2)
capture("store")

Panels.open("Dex")
taskLib.wait(0.05)
capture("dex")

Panels.open("Rewards")
taskLib.wait(0.05)
capture("rewards")

C.DinoPanel.open("3")
taskLib.wait(0.05)
capture("dino")

for _, extra in { "Quests", "Codes", "Settings" } do
	if Panels.has and Panels.has(extra) then
		Panels.open(extra)
		taskLib.wait(0.05)
		capture(string.lower(extra))
	end
end
Panels.close()

C.Toasts.show("🥚 Jungle Egg is warming in your nest!", "good")
C.Toasts.show("🌋 A Lava Storm is here! Dinos can turn Lava!", "event")
C.Toasts.show("Not enough coins yet!", "bad")
taskLib.wait(0.05)
capture("toasts")

-- Hatch reveal, captured mid-reveal.
task = taskLib
taskLib.spawn(function()
	env.listeners.Effect("Hatch", { species = "TRex", mutation = "Cosmic" })
end)
taskLib.wait(1.3)
capture("reveal")
taskLib.wait(4)
print("done")
