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

local env = ClientEnv.new({ start = true })
local Panels = env.Panels
local C = env.C

local VIEWPORTS = {
	desktop = { 1280, 720, false },
	phone = { 844, 390, true },
	tablet = { 1024, 768, true },
}

local function capture(name: string)
	local function check(value, path)
		if type(value) == "userdata" then
			error(`userdata at {path}: {typeof(value)} {tostring(value)}`)
		elseif type(value) == "table" then
			for k, v in value do
				check(v, path .. "." .. tostring(k))
			end
		end
	end
	for viewportName, vp in VIEWPORTS do
		env.setViewport(vp[1], vp[2])
		taskLib.wait(0.03)
		local data = {
			viewport = { vp[1], vp[2] },
			touch = vp[3],
			screens = Export.screens(env.playerGui),
		}
		check(data, name)
		fs.writeFile(`{outDir}/ui_{name}_{viewportName}.json`, serde.encode("json", data))
	end
	print("captured " .. name)
end

-- Scenes (a mid-game player with a quest ready to claim)
local QuestData = require("../../tests/loader").load("src/shared/Data/QuestData")
local day = env.snapshot().quests.day
local first = QuestData.forDay(day)[1]
local base = {
	tutorial = 99,
	quests = {
		day = day,
		progress = { [first.id] = first.goal },
		claimed = {},
		bonusClaimed = false,
	},
}
env.pushState(base)
taskLib.wait(0.1)
capture("hud")

env.pushState({ tutorial = 2 })
taskLib.wait(0.1)
capture("tutorial")
env.pushState(base)
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

-- a named Golden dino
local dinos = env.snapshot().dinos
for _, dino in dinos do
	if dino.id == "3" then
		dino.golden = true
		dino.name = "Sparkles"
	end
end
env.pushState({ tutorial = 99, quests = base.quests, dinos = dinos })
taskLib.wait(0.05)
C.DinoPanel.open("3")
taskLib.wait(0.05)
capture("dino")
env.pushState(base)

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

-- Hatch reveal, captured once the dino has popped out.
C.Effects.reveal("TRex", "Cosmic", true)
taskLib.wait(1.9)
capture("reveal")
taskLib.wait(4.5)
print("done")
process.exit(0)
