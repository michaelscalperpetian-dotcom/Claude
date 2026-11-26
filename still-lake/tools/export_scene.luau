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

-- (not the whole workspace: Terrain counts as a part, and is drawn separately)
local parts = {}
for _, child in env.workspace:GetChildren() do
	if not child:IsA("Terrain") then
		if child:IsA("BasePart") then
			table.insert(parts, Export.part(child))
		else
			for _, part in Export.parts(child) do
				table.insert(parts, part)
			end
		end
	end
end
local scene = { parts = parts }
fs.writeFile(outDir .. "/scene.json", serde.encode("json", scene))
print(`scene: {#scene.parts} parts`)

-- The terrain as a height and material grid (for tools/render_terrain.py).
local Land = require("../tests/loader").load("src/shared/Land")
local Ground = require("../tests/loader").load("src/server/Lib/Ground")
local Palette = require("../tests/loader").load("src/shared/Palette")
local step = 4
local heights, materials = {}, {}
for z = -Land.SIZE, Land.SIZE, step do
	local hrow, mrow = {}, {}
	for x = -Land.SIZE, Land.SIZE, step do
		local h = Land.height(x, z)
		table.insert(hrow, math.floor(h * 100 + 0.5) / 100)
		table.insert(mrow, Land.material(x, z, h, Land.slope(x, z)))
	end
	table.insert(heights, hrow)
	table.insert(materials, mrow)
end
local colors = {}
for _, tint in Ground.COLORS do
	colors[tostring(tint.material.Name)] = { tint.color.R, tint.color.G, tint.color.B }
end
local water = Palette.lakeDay
fs.writeFile(
	outDir .. "/terrain.json",
	serde.encode("json", {
		origin = -Land.SIZE,
		step = step,
		heights = heights,
		materials = materials,
		colors = colors,
		water = { water.R, water.G, water.B },
	})
)
print(`terrain: {#heights} x {#heights[1]}`)
process.exit(0)
