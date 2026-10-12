--!nocheck
-- Builds the island with a few populated nests using the real server code, and
-- writes every visible part to JSON for tools/preview/render3d.py.
-- Also writes a "lineup" of every dino (all stages, all mutations) and egg.
--
-- Usage: lune run tools/preview/export_scene [outDir]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local ServerEnv = require("../../tests/support/ServerEnv")
local Export = require("./Export")

local outDir = process.args[1] or "tools/preview/out"
fs.writeDir(outDir)

local env = ServerEnv.new()
local S = env.S

-- ===== Populated island =====
local function populate(player, dinos, lock)
	env.join(player)
	local profile = env.profileOf(player)
	profile.tutorial = 99
	profile.coins = 10 ^ 9
	for slot in profile.incubators do
		profile.incubators[slot] = nil
	end
	for _, d in dinos do
		S.Nest.addDino(player, d[1], d[2], d[3])
	end
	env.handlers.BuyEgg(player, "Jungle")
	env.handlers.BuyEgg(player, "Volcano")
	for _ = 1, 4 do
		local dino = profile.dinos[1]
		if dino then
			S.Nest.addTrayEgg(player, dino.species)
		end
	end
	if lock then
		env.handlers.LockGate(player)
	end
	S.Plots.renderAll(player)
end

local a = env.makePlayer("Alice")
populate(a, {
	{ "Raptor", nil, 1 },
	{ "Gallimimus", nil, 2 },
	{ "Parasaur", "Glossy", 3 },
	{ "Stegosaurus", nil, 3 },
	{ "Triceratops", "Frost", 3 },
	{ "TRex", "Lava", 4 },
	{ "Brachiosaurus", nil, 3 },
	{ "Pteranodon", "Cosmic", 2 },
}, false)
local b = env.makePlayer("Bob")
populate(b, {
	{ "Spinosaurus", nil, 3 },
	{ "Ankylosaurus", "Rainbow", 3 },
	{ "Dilophosaurus", nil, 2 },
	{ "Pachy", nil, 1 },
}, true)
local c = env.makePlayer("Cara")
populate(c, { { "Raptor", nil, 2 }, { "Mosasaurus", "Cosmic", 3 } }, false)

local characters = {}
for _, p in env.players do
	table.insert(characters, p.Character)
end

local function plotInfo(index)
	local plot = S.World.getPlot(index)
	return { cf = { plot.cframe:GetComponents() }, index = index }
end

local Config = require("../../tests/loader").load("src/shared/Config")

local scene = {
	parts = Export.parts(env.workspace, characters),
	plots = { plotInfo(1), plotInfo(2), plotInfo(3) },
	studStyle = Config.STUD_STYLE,
}
fs.writeFile(outDir .. "/scene.json", serde.encode("json", scene))
print(`scene: {#scene.parts} parts`)

-- ===== Lineup of every dino and egg =====
local Loader = require("../../tests/loader")
local DinoData = Loader.load("src/shared/Data/DinoData")
local DinoModel = Loader.load("src/shared/Visual/DinoModel")
local EggModel = Loader.load("src/shared/Visual/EggModel")
local EggData = Loader.load("src/shared/Data/EggData")
local MutationData = Loader.load("src/shared/Data/MutationData")

local lineupRoot = roblox.Instance.new("Folder")
local x = 0
local rows = {}
-- Row per stage (normal), then a row of adults per mutation.
for stage = 1, 4 do
	table.insert(rows, { stage = stage, mutation = nil })
end
for _, m in MutationData.ORDER do
	table.insert(rows, { stage = 3, mutation = m })
end
local z = 0
for _, row in rows do
	x = 0
	local rowDepth = 0
	for _, species in DinoData.LIST do
		local model = DinoModel.build(species.id, row.stage, row.mutation, "Static")
		local _, size = model:GetBoundingBox()
		model:PivotTo(
			roblox.CFrame.new(x + size.X / 2, 0, z) * roblox.CFrame.Angles(0, math.rad(-30), 0)
		)
		model.Parent = lineupRoot
		x += math.max(size.X, size.Z) + 3
		rowDepth = math.max(rowDepth, size.Z, size.X)
	end
	z += rowDepth + 6
end
x = 0
for _, egg in EggData.LIST do
	local model = EggModel.build(EggModel.lookForShopEgg(egg.id), 3.4, true)
	model:PivotTo(roblox.CFrame.new(x, 0, z))
	model.Parent = lineupRoot
	x += 5
end
local lineup = { parts = Export.parts(lineupRoot) }
fs.writeFile(outDir .. "/lineup.json", serde.encode("json", lineup))
print(`lineup: {#lineup.parts} parts`)
