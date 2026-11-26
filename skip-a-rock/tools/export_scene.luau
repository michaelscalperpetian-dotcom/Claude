--!nocheck
-- Builds Skip a Rock with the real server code, puts a few skippers on the
-- beach, a pier and the boardwalk, and writes every visible part (and the
-- terrain as a height grid) to JSON for tools/render_terrain.py.
--
-- Usage (from skip-a-rock/): lune run tools/export_scene [outDir]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local ServerEnv = require("../tests/support/ServerEnv")
local Export = require("../../tools/preview/Export")

local outDir = process.args[1] or "tools/out"
fs.writeDir(outDir)

local env = ServerEnv.new()

local function stand(name, position, lookAt)
	local player = env.makePlayer(name)
	env.join(player)
	local character = player.Character
	character.HumanoidRootPart.CFrame = roblox.CFrame.lookAt(position, lookAt)
	return player
end

stand("Alice", roblox.Vector3.new(30, 3, -10), roblox.Vector3.new(30, 3, 100))
stand("Bob", roblox.Vector3.new(60, 4.8, 52), roblox.Vector3.new(60, 4.8, 200))
stand("Cara", roblox.Vector3.new(-40, 4.3, -80), roblox.Vector3.new(-40, 4.3, 100))

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
for z = Land.SOUTH, Land.NORTH, step do
	local hrow, mrow = {}, {}
	for x = Land.WEST, Land.EAST, step do
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
local water = Palette.seaDay
fs.writeFile(
	outDir .. "/terrain.json",
	serde.encode("json", {
		originX = Land.WEST,
		originZ = Land.SOUTH,
		step = step,
		heights = heights,
		materials = materials,
		colors = colors,
		water = { water.R, water.G, water.B },
	})
)
print(`terrain: {#heights} x {#heights[1]}`)
process.exit(0)
