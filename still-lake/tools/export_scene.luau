--!nocheck
-- Builds Still Lake with the real server code, puts a couple of skippers on
-- the beach and a dock, and writes every visible part to JSON for the repo's
-- tools/preview/render3d.py.
--
-- Usage (from still-lake/): lune run tools/export_scene [outDir]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local ServerEnv = require("../tests/support/ServerEnv")
local Export = require("../../tools/preview/Export")

local outDir = process.args[1] or "tools/out"
fs.writeDir(outDir)

local env = ServerEnv.new()
local Lake = require("../tests/loader").load("src/shared/Lake")

local function stand(name, position, lookAt)
	local player = env.makePlayer(name)
	env.join(player)
	local character = player.Character
	character.HumanoidRootPart.CFrame = roblox.CFrame.lookAt(position, lookAt)
	return player
end

local angle = Lake.DOCK_ANGLES[1]
stand(
	"Alice",
	roblox.Vector3.new(math.sin(0.5) * 114, 3, math.cos(0.5) * 114),
	roblox.Vector3.new(0, 3, 0)
)
stand(
	"Bob",
	roblox.Vector3.new(
		math.sin(angle) * (Lake.DOCK_INNER + 2),
		4.2,
		math.cos(angle) * (Lake.DOCK_INNER + 2)
	),
	roblox.Vector3.new(0, 4.2, 0)
)

local scene = { parts = Export.parts(env.workspace) }
fs.writeFile(outDir .. "/scene.json", serde.encode("json", scene))
print(`scene: {#scene.parts} parts`)
process.exit(0)
