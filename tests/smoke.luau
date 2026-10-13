--!nocheck
-- Smoke test: build the whole island and every dino/egg model with real Roblox
-- classes (Lune's roblox library knows every class and property), so a typo'd
-- property or a crash in the builders shows up here instead of in Studio.
-- Run with: lune run tests/smoke

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./loader")

local Instance = roblox.Instance

-- ===== Minimal engine stand-ins =====

local dataModel = Instance.new("DataModel")
local workspaceService = dataModel:GetService("Workspace")

for _, className in { "Part", "SpawnLocation", "WedgePart", "MeshPart" } do
	roblox.implementProperty(className, "Position", function(part)
		return part.CFrame.Position
	end, function(part, value)
		part.CFrame = part.CFrame - part.CFrame.Position + value
	end)
end

roblox.implementProperty("Attachment", "Position", function(attachment)
	return attachment.CFrame.Position
end, function(attachment, value)
	attachment.CFrame = attachment.CFrame - attachment.CFrame.Position + value
end)

local function pivotOf(model)
	if model.PrimaryPart then
		return model.PrimaryPart.CFrame
	end
	return roblox.CFrame.new()
end

roblox.implementMethod("Model", "GetPivot", function(model)
	return pivotOf(model)
end)

roblox.implementMethod("Model", "PivotTo", function(model, target)
	local delta = target * pivotOf(model):Inverse()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CFrame = delta * descendant.CFrame
		end
	end
end)

roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return os.time()
end)

local tags = {}
local collectionService = {
	AddTag = function(_, _instance, tag)
		tags[tag] = (tags[tag] or 0) + 1
	end,
}

local replicatedAttributes = {}
local replicatedStorage = setmetatable({}, {
	__index = function(_, key)
		if key == "Shared" then
			return Loader.path("src/shared")
		elseif key == "GetAttribute" then
			return function(_, name)
				return replicatedAttributes[name]
			end
		elseif key == "SetAttribute" then
			return function(_, name, value)
				replicatedAttributes[name] = value
			end
		end
		return nil
	end,
})

local game = {
	JobId = "",
	PrivateServerId = "",
	GetService = function(_, name)
		if name == "ReplicatedStorage" then
			return replicatedStorage
		elseif name == "Workspace" then
			return workspaceService
		elseif name == "CollectionService" then
			return collectionService
		end
		return dataModel:GetService(name)
	end,
}

for _, name in
	{
		"Vector3",
		"Vector2",
		"CFrame",
		"Color3",
		"UDim",
		"UDim2",
		"Enum",
		"NumberSequence",
		"NumberSequenceKeypoint",
		"ColorSequence",
		"ColorSequenceKeypoint",
		"NumberRange",
	}
do
	Loader.globals[name] = (roblox :: any)[name]
end
Loader.globals.Instance = Instance
Loader.globals.game = game
Loader.globals.workspace = workspaceService

-- ===== Tests =====

local passed, failed = 0, 0
local function check(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print(`FAIL  {name}\n      {err}`)
	end
end

local Config = Loader.load("src/shared/Config")
local DinoData = Loader.load("src/shared/Data/DinoData")
local EggData = Loader.load("src/shared/Data/EggData")
local MutationData = Loader.load("src/shared/Data/MutationData")
local DinoModel = Loader.load("src/shared/Visual/DinoModel")
local EggModel = Loader.load("src/shared/Visual/EggModel")

check("every dino builds at every stage, mutation and mode", function()
	local mutations = { false }
	for _, id in MutationData.ORDER do
		table.insert(mutations, id)
	end
	for _, species in DinoData.LIST do
		for stage = 1, 4 do
			for _, mutation in mutations do
				for _, mode in { "Static", "World", "Mount" } do
					local model = DinoModel.build(species.id, stage, mutation or nil, mode)
					assert(model.PrimaryPart and model.PrimaryPart.Name == "Root", "root")
					local height = model:GetAttribute("Height")
					assert(
						type(height) == "number" and height > 0.5,
						`{species.id} height {height}`
					)
					local lowest = math.huge
					local count = 0
					for _, d in model:GetDescendants() do
						if d:IsA("BasePart") and d.Name ~= "Root" then
							count += 1
							-- vertical half-extent of a rotated box: |R| * half size
							local _, _, _, _, _, _, r10, r11, r12 = d.CFrame:GetComponents()
							local halfHeight = (
								math.abs(r10) * d.Size.X
								+ math.abs(r11) * d.Size.Y
								+ math.abs(r12) * d.Size.Z
							) / 2
							lowest = math.min(lowest, d.CFrame.Position.Y - halfHeight)
						end
					end
					assert(count >= 10, `{species.id} only has {count} parts`)
					for _, d in model:GetDescendants() do
						if d:IsA("BasePart") then
							for _, v in { d.CFrame:GetComponents() } do
								assert(v == v, `{species.id} part {d.Name} has a NaN CFrame`)
							end
						end
					end
					assert(
						lowest > -1,
						`{species.id} stage {stage} sinks into the ground ({lowest})`
					)
					model:Destroy()
				end
			end
		end
	end
end)

check("adult dinos are a sensible size next to a 5-stud player", function()
	for _, species in DinoData.LIST do
		local model = DinoModel.build(species.id, 3, nil, "Static")
		local height = model:GetAttribute("Height")
		assert(height >= 2 and height <= 30, `{species.id} adult height {height}`)
		model:Destroy()
	end
end)

check("every egg builds", function()
	for _, egg in EggData.LIST do
		EggModel.build(EggModel.lookForShopEgg(egg.id), 3, true):Destroy()
		EggModel.build(EggModel.lookForShopEgg(egg.id), 3, false):Destroy()
	end
	for _, species in DinoData.LIST do
		EggModel.build(EggModel.lookForSpecies(species.id), 2.2):Destroy()
	end
	EggModel.build(EggModel.giftLook(), 3):Destroy()
end)

check("the island and all plots build", function()
	local World = Loader.load("src/server/Systems/World")
	World.init()
	local map = workspaceService:FindFirstChild("Map")
	assert(map, "Map folder")
	assert(map:FindFirstChild("Hub"), "Hub")
	local plots = workspaceService:FindFirstChild("Plots")
	assert(plots and #plots:GetChildren() == Config.PLOT_COUNT, "plot count")
	for index, plot in World.plots do
		assert(#plot.incubators == Config.MAX_INCUBATORS, "incubators")
		assert(#plot.traySpots == Config.TRAY_CAPACITY, "tray spots")
		assert(
			#plot.homeSpots >= Config.BASE_DINO_SLOTS + Config.PASS_EXTRA_SLOTS + 4,
			"enough home spots"
		)
		assert(plot.spawn and plot.pad and plot.signPart, "plot parts")
		-- the plot's own pad and tray are inside its bounds
		assert(World.isInside(index, plot.pad.CFrame.Position), "pad inside plot")
		assert(World.isInside(index, plot.traySpots[1].Position), "tray inside plot")
		assert(not World.isInside(index, World.outsideGate(index).Position), "gate exit is outside")
		for other = 1, Config.PLOT_COUNT do
			if other ~= index then
				assert(not World.isInside(other, plot.pad.CFrame.Position), "plots don't overlap")
			end
		end
	end
	assert((tags.GamePrompt or 0) >= 1, "shop prompt tagged")
end)

-- Square studs come from the SmoothPlastic override, so every part that isn't
-- meant to glow or shine must be SmoothPlastic, without classic surfaces on top.
local Enum = roblox.Enum
-- (by name: Lune's enum items aren't stable table keys)
local SPECIAL = { Neon = true, Glass = true, Ice = true, ForceField = true }

local function checkSurfaces(root, label)
	for _, part in root:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 and not SPECIAL[part.Material.Name] then
			assert(
				part.Material == Enum.Material.SmoothPlastic,
				`{label} {part:GetFullName()} is {part.Material.Name}, not SmoothPlastic`
			)
			if Config.STUD_STYLE == "square" then
				assert(
					part.TopSurface == Enum.SurfaceType.Smooth
						and part.BottomSurface == Enum.SurfaceType.Smooth,
					`{label} {part:GetFullName()} has classic surfaces`
				)
			end
		end
	end
end

check("every world part wears the stud material", function()
	checkSurfaces(workspaceService, "world")
end)

check("every dino and egg part wears the stud material", function()
	local folder = Instance.new("Folder")
	for _, species in DinoData.LIST do
		for stage = 1, 4 do
			DinoModel.build(species.id, stage, nil, "Static").Parent = folder
		end
		for _, mutation in MutationData.ORDER do
			DinoModel.build(species.id, 3, mutation, "Static").Parent = folder
		end
		local golden = DinoModel.build(species.id, 4, nil, "World", true)
		assert(golden:GetAttribute("Golden"), "golden attribute")
		assert(golden:FindFirstChild("Crown", true), `{species.id} golden crown`)
		golden.Parent = folder
	end
	for _, egg in EggData.LIST do
		EggModel.build(EggModel.lookForShopEgg(egg.id), 3, true).Parent = folder
	end
	checkSurfaces(folder, "model")
	folder:Destroy()
end)

check("Studs.apply sets the SmoothPlastic override", function()
	local calls = {}
	roblox.implementMethod("MaterialService", "SetBaseMaterialOverride", function(_, material, name)
		table.insert(calls, { material, name })
	end)
	local variant = Instance.new("MaterialVariant")
	variant.Name = "SquareStuds"
	variant.Parent = dataModel:GetService("MaterialService")
	local Studs = Loader.load("src/shared/Visual/Studs")
	Studs.apply()
	assert(#calls == 1, "one override call")
	assert(calls[1][1] == Enum.Material.SmoothPlastic, "SmoothPlastic")
	local expected = if Config.STUD_STYLE == "square" then "SquareStuds" else ""
	assert(calls[1][2] == expected, `override name {calls[1][2]}`)
end)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
