--!strict
-- Builds spotted eggs from simple parts. Same model-space rules as DinoModel:
-- origin on the ground, root part named "Root".

local DinoData = require(script.Parent.Parent.Data.DinoData)
local EggData = require(script.Parent.Parent.Data.EggData)
local Frames = require(script.Parent.Parent.Util.Frames)

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

	-- Egg silhouette: a squashed base under a taller, slightly narrower cap.
	-- The two ellipsoids are tangent (solved numerically), so the shell reads
	-- as one smooth egg that is widest a little below the middle.
	local a, b = size * 0.38, size * 0.5 -- radii (width, height)
	local shells = {
		make("Shell", look.main, Vector3.new(a * 2, b * 1.68, a * 2), Vector3.new(0, b * 0.84, 0)),
		make(
			"ShellTop",
			look.main,
			Vector3.new(a * 1.986, b * 2.18, a * 1.986),
			Vector3.new(0, b * 0.91, 0)
		),
	}
	if look.material == Enum.Material.Glass then
		for _, shell in shells do
			shell.Transparency = 0.25
		end
		local core = make("Core", look.spots, Vector3.new(a, b, a), Vector3.new(0, b, 0))
		core.Material = Enum.Material.Neon
	end

	-- Shell radius at a height (the larger of the two shapes there).
	local function radiusAt(y: number): number
		local function r(cy: number, ry: number, rx: number): number
			local t = (y - cy) / ry
			return if math.abs(t) >= 1 then 0 else rx * math.sqrt(1 - t * t)
		end
		return math.max(r(b * 0.84, b * 0.84, a), r(b * 0.91, b * 1.09, a * 0.993))
	end

	-- Painted spots at fixed spots on the shell (deterministic look).
	local spots = {
		{ 0.4, 0.62, 0.22 },
		{ 1.9, 0.75, 0.16 },
		{ 3.1, 0.45, 0.24 },
		{ 4.3, 0.68, 0.15 },
		{ 5.4, 0.36, 0.2 },
		{ 2.6, 0.24, 0.17 },
		{ 0.9, 0.22, 0.14 },
		{ 5.0, 0.86, 0.12 },
	}
	for _, spot in spots do
		local theta, height, spotSize = spot[1], spot[2] * b * 2, spot[3] * size
		local r = radiusAt(height)
		local outward = Vector3.new(math.cos(theta), 0, math.sin(theta))
		local slope = (radiusAt(height - 0.05) - radiusAt(height + 0.05)) / 0.1
		local normal = (outward + Vector3.new(0, slope, 0)).Unit
		local position = outward * r + Vector3.new(0, height, 0)
		local p =
			make("Spot", look.spots, Vector3.new(spotSize, spotSize, spotSize * 0.22), position)
		p.CFrame = Frames.alongZ(position - normal * spotSize * 0.04, normal)
		if look.glow then
			p.Material = Enum.Material.Neon
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
