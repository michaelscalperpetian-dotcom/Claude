--!nocheck
-- Builds every dino (each stage, each mutation) and every egg with the real
-- model code and writes their parts to models.json for render_models.py.
--
-- Usage: lune run tools/preview/export_models [outDir]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local ServerEnv = require("../../tests/support/ServerEnv")
local Export = require("./Export")

local outDir = process.args[1] or "tools/preview/out"
fs.writeDir(outDir)

ServerEnv.new() -- installs the engine globals the model code needs
local Loader = require("../../tests/loader")
local DinoData = Loader.load("src/shared/Data/DinoData")
local DinoModel = Loader.load("src/shared/Visual/DinoModel")
local EggModel = Loader.load("src/shared/Visual/EggModel")
local EggData = Loader.load("src/shared/Data/EggData")
local MutationData = Loader.load("src/shared/Data/MutationData")

local out = { dinos = {}, eggs = {} }
for _, species in DinoData.LIST do
	local entry = { id = species.id, name = species.name, stages = {}, mutations = {} }
	for stage = 1, 4 do
		local model = DinoModel.build(species.id, stage, nil, "Static")
		entry.stages[stage] = Export.parts(model)
	end
	for _, mutation in MutationData.ORDER do
		local model = DinoModel.build(species.id, 3, mutation, "Static")
		entry.mutations[mutation] = Export.parts(model)
	end
	table.insert(out.dinos, entry)
end
for _, egg in EggData.LIST do
	local model = EggModel.build(EggModel.lookForShopEgg(egg.id), 3.4, true)
	table.insert(out.eggs, { id = egg.id, parts = Export.parts(model) })
end
for _, species in DinoData.LIST do
	local model = EggModel.build(EggModel.lookForSpecies(species.id), 3.4, true)
	table.insert(out.eggs, { id = species.id .. " egg", parts = Export.parts(model) })
end
fs.writeFile(outDir .. "/models.json", serde.encode("json", out))
print(`models: {#out.dinos} species, {#out.eggs} eggs`)
