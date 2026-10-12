--!strict
-- Part-building helpers for the generated world. Every part is anchored
-- SmoothPlastic, which wears the stud material. Purely decorative parts can
-- skip touch/query work (`decor`) and small ones can skip shadows, which keeps
-- a part-built island cheap on phones.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Frames = require(ReplicatedStorage.Shared.Util.Frames)

local Build = {}

export type Options = {
	name: string?,
	smooth: boolean?, -- no classic studs (water)
	material: Enum.Material?,
	transparency: number?,
	reflectance: number?,
	collide: boolean?, -- default true
	shadow: boolean?, -- default true
	decor: boolean?, -- no Touched events or raycasts
}

local SMOOTH_MATERIALS = {
	[Enum.Material.Neon] = true,
	[Enum.Material.Glass] = true,
	[Enum.Material.ForceField] = true,
	[Enum.Material.Ice] = true,
}

-- Classic bricks: studs on top, inlets underneath. Surfaces only render on
-- block faces, so round shapes stay smooth. (Square studs come from a
-- material instead, see Shared.Visual.Studs.)
local function surfaces(p: BasePart, options: Options?)
	local studded = Config.STUD_STYLE == "classic"
		and not (options and options.smooth)
		and not SMOOTH_MATERIALS[p.Material]
		and (p:IsA("WedgePart") or (p:IsA("Part") and p.Shape == Enum.PartType.Block))
		and p:FindFirstChildOfClass("SpecialMesh") == nil
	p.TopSurface = if studded then Enum.SurfaceType.Studs else Enum.SurfaceType.Smooth
	p.BottomSurface = if studded then Enum.SurfaceType.Inlet else Enum.SurfaceType.Smooth
end

local function finish(p: BasePart, color: Color3, parent: Instance, options: Options?): ()
	p.Anchored = true
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	if options then
		if options.name then
			p.Name = options.name
		end
		if options.material then
			p.Material = options.material
		end
		if options.transparency then
			p.Transparency = options.transparency
		end
		if options.reflectance then
			p.Reflectance = options.reflectance
		end
		if options.collide == false then
			p.CanCollide = false
		end
		if options.shadow == false then
			p.CastShadow = false
		end
		if options.decor then
			p.CanTouch = false
			p.CanQuery = false
		end
	end
	surfaces(p, options)
	p.Parent = parent
end

function Build.block(
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance,
	options: Options?
): Part
	local p = Instance.new("Part")
	p.Name = "Block"
	p.Size = size
	p.CFrame = cframe
	finish(p, color, parent, options)
	return p
end

-- Wedge: the slope rises toward -Z (front), full height at the back (+Z).
function Build.wedge(
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance,
	options: Options?
): WedgePart
	local p = Instance.new("WedgePart")
	p.Name = "Wedge"
	p.Size = size
	p.CFrame = cframe
	finish(p, color, parent, options)
	return p
end

function Build.ball(
	diameter: number,
	position: Vector3,
	color: Color3,
	parent: Instance,
	options: Options?
): Part
	local p = Instance.new("Part")
	p.Name = "Ball"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(diameter, diameter, diameter)
	p.CFrame = CFrame.new(position)
	finish(p, color, parent, options)
	return p
end

-- Stretched sphere (a sphere mesh fills the part's box).
function Build.ellipsoid(
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance,
	options: Options?
): Part
	local p = Instance.new("Part")
	p.Name = "Ellipsoid"
	p.Size = size
	p.CFrame = cframe
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	finish(p, color, parent, options)
	return p
end

-- Upright cylinder centred on `cframe` (Roblox cylinders run along X, so this
-- turns X onto the frame's Y axis).
function Build.disc(
	diameter: number,
	height: number,
	cframe: CFrame,
	color: Color3,
	parent: Instance,
	options: Options?
): Part
	local p = Instance.new("Part")
	p.Name = "Disc"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, diameter, diameter)
	p.CFrame = cframe * CFrame.Angles(0, 0, math.rad(90))
	finish(p, color, parent, options)
	return p
end

-- Cylinder from point a to point b.
function Build.rod(
	a: Vector3,
	b: Vector3,
	diameter: number,
	color: Color3,
	parent: Instance,
	options: Options?
): Part
	local p = Instance.new("Part")
	p.Name = "Rod"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new((b - a).Magnitude, diameter, diameter)
	p.CFrame = Frames.alongX((a + b) / 2, b - a)
	finish(p, color, parent, options)
	return p
end

-- Flat-topped bar from a to b (its up side stays as close to world-up as it can).
function Build.beam(
	a: Vector3,
	b: Vector3,
	width: number,
	thickness: number,
	color: Color3,
	parent: Instance,
	options: Options?
): Part
	local p = Instance.new("Part")
	p.Name = "Beam"
	p.Size = Vector3.new(width, thickness, (b - a).Magnitude)
	p.CFrame = Frames.alongZ((a + b) / 2, b - a)
	finish(p, color, parent, options)
	return p
end

-- Flat ring of blocks around `center` (an upright frame), e.g. a circular path.
function Build.ring(
	center: CFrame,
	radius: number,
	width: number,
	height: number,
	segments: number,
	color: Color3,
	parent: Instance,
	options: Options?
): { Part }
	local parts = {}
	local step = 2 * math.pi / segments
	-- Segment length covering the outer edge so neighbours meet without gaps.
	local length = 2 * (radius + width / 2) * math.tan(step / 2) + 0.05
	for i = 0, segments - 1 do
		local angle = i * step
		local cf = center * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -radius)
		table.insert(
			parts,
			Build.block(Vector3.new(length, height, width), cf, color, parent, options)
		)
	end
	return parts
end

export type Circle = { center: Vector3, radius: number }

-- Fills the union of flat circles with rows of bricks snapped to the stud
-- grid, so studs line up across every row (round shapes can't show studs).
-- The coast steps by `rowDepth` studs, like a classic brick-built island.
function Build.strips(
	circles: { Circle },
	top: number,
	thickness: number,
	rowDepth: number,
	color: Color3,
	parent: Instance,
	options: Options?
): { Part }
	local minZ, maxZ = math.huge, -math.huge
	for _, circle in circles do
		minZ = math.min(minZ, circle.center.Z - circle.radius)
		maxZ = math.max(maxZ, circle.center.Z + circle.radius)
	end
	local parts = {}
	local z = math.floor(minZ / rowDepth) * rowDepth
	while z < maxZ do
		local mid = z + rowDepth / 2
		local spans: { { number } } = {}
		for _, circle in circles do
			local dz = math.abs(mid - circle.center.Z)
			if dz < circle.radius then
				local half = math.sqrt(circle.radius * circle.radius - dz * dz)
				table.insert(spans, {
					math.floor(circle.center.X - half + 0.5),
					math.floor(circle.center.X + half + 0.5),
				})
			end
		end
		table.sort(spans, function(a, b)
			return a[1] < b[1]
		end)
		local merged: { { number } } = {}
		for _, span in spans do
			local last = merged[#merged]
			if last and span[1] <= last[2] then
				last[2] = math.max(last[2], span[2])
			else
				table.insert(merged, { span[1], span[2] })
			end
		end
		for _, span in merged do
			local width = span[2] - span[1]
			if width >= 1 then
				table.insert(
					parts,
					Build.block(
						Vector3.new(width, thickness, rowDepth),
						CFrame.new((span[1] + span[2]) / 2, top - thickness / 2, mid),
						color,
						parent,
						options
					)
				)
			end
		end
		z += rowDepth
	end
	return parts
end

-- Ground position on a circle (angle 0 points along +Z, matching the plots).
function Build.polar(angle: number, radius: number, y: number?): Vector3
	return Vector3.new(math.sin(angle) * radius, y or 0, math.cos(angle) * radius)
end

function Build.model(name: string, parent: Instance?): Model
	local m = Instance.new("Model")
	m.Name = name
	if parent then
		m.Parent = parent
	end
	return m
end

return Build
