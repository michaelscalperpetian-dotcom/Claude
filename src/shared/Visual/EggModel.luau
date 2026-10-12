--!strict
-- Builds spotted eggs from simple parts. Same model-space rules as DinoModel:
-- origin on the ground, root part named "Root".

local DinoData = require(script.Parent.Parent.Data.DinoData)
local EggData = require(script.Parent.Parent.Data.EggData)

local EggModel = {}

export type Look = {
	main: Color3,
	spots: Color3,
	material: Enum.Material,
	glow: boolean,
}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local GIFT_LOOK: Look = {
	main = Color3.fromRGB(255, 205, 60),
	spots = Color3.fromRGB(255, 255, 255),
	material = Enum.Material.SmoothPlastic,
	glow = true,
}

function EggModel.lookForShopEgg(eggTypeId: string): Look
	local egg = EggData.get(eggTypeId)
	assert(egg, `unknown egg {eggTypeId}`)
	local material = Enum.Material.SmoothPlastic
	if egg.material == "Glass" then
		material = Enum.Material.Glass
	elseif egg.material == "Neon" then
		material = Enum.Material.Neon
	end
	return {
		main = rgb(egg.colors.main),
		spots = rgb(egg.colors.spots),
		material = material,
		glow = egg.id == "Volcano" or egg.id == "Crystal",
	}
end

function EggModel.lookForSpecies(speciesId: string): Look
	local species = DinoData.get(speciesId)
	assert(species, `unknown species {speciesId}`)
	return {
		main = rgb(species.colors.belly),
		spots = rgb(species.colors.main),
		material = Enum.Material.SmoothPlastic,
		glow = false,
	}
end

function EggModel.giftLook(): Look
	return GIFT_LOOK
end

-- `size` is the egg height in studs. Root is anchored; other parts are welded
-- to it unless `static` is true (then everything is anchored).
function EggModel.build(look: Look, size: number, static: boolean?): Model
	local model = Instance.new("Model")
	model.Name = "Egg"

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Size = Vector3.new(size * 0.6, 0.1, size * 0.6)
	root.CFrame = CFrame.new(0, 0.05, 0)
	root.Parent = model
	model.PrimaryPart = root

	local parts: { BasePart } = {}

	local function make(name: string, color: Color3, partSize: Vector3, position: Vector3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Color = color
		p.Material = look.material
		p.Size = partSize
		p.CFrame = CFrame.new(position)
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		p.Parent = model
		table.insert(parts, p)
		return p
	end

	local a, b = size * 0.38, size * 0.5 -- radii (width, height)
	local center = Vector3.new(0, b, 0)
	local shell = make("Shell", look.main, Vector3.new(a * 2, b * 2, a * 2), center)
	if look.material == Enum.Material.Glass then
		shell.Transparency = 0.25
		local core = make("Core", look.spots, Vector3.new(a, b, a), center)
		core.Material = Enum.Material.Neon
	end

	-- Spots on the shell surface at fixed angles (deterministic look).
	local spotAngles = {
		{ 0.4, 1.0 },
		{ 1.9, 0.7 },
		{ 3.1, 1.3 },
		{ 4.3, 0.9 },
		{ 5.4, 1.6 },
		{ 2.6, 2.1 },
		{ 0.9, 2.3 },
	}
	for _, angles in spotAngles do
		local theta, phi = angles[1], angles[2]
		local position = center
			+ Vector3.new(
				a * math.cos(theta) * math.sin(phi),
				b * math.cos(phi),
				a * math.sin(theta) * math.sin(phi)
			)
		local spotSize = size * 0.16
		local spot = make("Spot", look.spots, Vector3.new(spotSize, spotSize, spotSize), position)
		if look.glow then
			spot.Material = Enum.Material.Neon
		end
	end

	if not static then
		for _, p in parts do
			p.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = p
			weld.Parent = p
			p.Anchored = false
		end
	end

	return model
end

return EggModel
