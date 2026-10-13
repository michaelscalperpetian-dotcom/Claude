--!strict
-- Cartoon props built from parts: chunky rounded shapes, 2-3 shades per
-- material and a few pointy accents. Each builder takes a ground position, a
-- size multiplier and a random generator (so layouts are repeatable).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Frames = require(ReplicatedStorage.Shared.Util.Frames)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Rng = require(ReplicatedStorage.Shared.Util.Rng)
local Tags = require(ReplicatedStorage.Shared.Tags)
local Build = require(script.Parent.Build)

local Props = {}

-- Lights tagged with this are switched on at night by the client.
Props.NIGHT_LIGHT_TAG = Tags.NIGHT_LIGHT

type Gen = Rng.Generator

local LEAF = { decor = true, collide = false }
local SMALL = { decor = true, collide = false, shadow = false }

local function between(gen: Gen, a: number, b: number): number
	return a + (b - a) * gen.next()
end

local function pick<T>(gen: Gen, list: { T }): T
	return list[gen.int(1, #list)]
end

local function horizontal(angle: number): Vector3
	return Vector3.new(math.sin(angle), 0, math.cos(angle))
end

-- Leafy round tree: a short tapered trunk under a cluster of soft blobs.
function Props.tree(base: Vector3, s: number, gen: Gen, parent: Instance): Model
	local m = Build.model("Tree", parent)
	local h = between(gen, 7.5, 9.5) * s
	local lean = horizontal(gen.next() * math.pi * 2) * between(gen, 0.3, 1.2) * s
	local mid = base + Vector3.new(0, h * 0.5, 0) + lean * 0.3
	local top = base + Vector3.new(0, h, 0) + lean
	Build.ellipsoid(Vector3.new(3.4, 1.4, 3.4) * s, CFrame.new(base), Palette.woodDark, m, LEAF)
	Build.rod(base - Vector3.new(0, 0.5, 0), mid, 2.1 * s, Palette.wood, m, { name = "Trunk" })
	Build.rod(mid, top, 1.6 * s, Palette.wood, m, { name = "Trunk" })

	local yaw = CFrame.Angles(0, gen.next() * math.pi * 2, 0)
	local c = top + Vector3.new(0, 1.6 * s, 0)
	local function blob(size: Vector3, offset: Vector3, color: Color3)
		Build.ellipsoid(
			size * s,
			CFrame.new(c + yaw:VectorToWorldSpace(offset * s)),
			color,
			m,
			LEAF
		)
	end
	blob(Vector3.new(10.5, 8.5, 10.5), Vector3.zero, Palette.leaf)
	blob(Vector3.new(7, 6, 7), Vector3.new(4.2, -1.4, 1.2), Palette.leafDark)
	blob(Vector3.new(6.5, 5.5, 6.5), Vector3.new(-3.8, -1, -2), Palette.leafDark)
	blob(Vector3.new(6.5, 5.2, 6.5), Vector3.new(0.8, 3.3, -0.6), Palette.leafLight)
	if gen.next() < 0.3 then
		-- a few fruits
		for i = 1, 3 do
			local a = i * 2.1 + gen.next()
			local p = c
				+ Vector3.new(math.sin(a) * 4.6, between(gen, -2.2, 0.5), math.cos(a) * 4.6) * s
			Build.ball(
				0.9 * s,
				p,
				if gen.next() < 0.5 then Palette.red else Palette.orange,
				m,
				SMALL
			)
		end
	end
	return m
end

-- Fluffy cartoon pine: stacked blobs that shrink toward the top.
function Props.pine(base: Vector3, s: number, gen: Gen, parent: Instance): Model
	local m = Build.model("Pine", parent)
	Build.rod(
		base - Vector3.new(0, 0.5, 0),
		base + Vector3.new(0, 4 * s, 0),
		1.5 * s,
		Palette.woodDark,
		m
	)
	local tiers = { { 9, 5, 4.6 }, { 7.2, 4.6, 7.6 }, { 5.4, 4.2, 10.3 }, { 3.2, 3.4, 12.6 } }
	-- each tier drifts a little so no two pines look stamped
	local drift = horizontal(gen.next() * math.pi * 2) * 0.35 * s
	for i, t in tiers do
		local color = if i % 2 == 1 then Palette.pine else Palette.pineDark
		if i == #tiers then
			color = Palette.leaf
		end
		Build.ellipsoid(
			Vector3.new(t[1], t[2], t[1]) * s,
			CFrame.new(base + Vector3.new(0, t[3] * s, 0) + drift * (i - 1)),
			color,
			m,
			LEAF
		)
	end
	return m
end

-- Palm with a curved, banded trunk and drooping fronds.
function Props.palm(base: Vector3, s: number, gen: Gen, parent: Instance): Model
	local m = Build.model("Palm", parent)
	local lean = horizontal(gen.next() * math.pi * 2)
	local bend = between(gen, 3, 6.5) * s
	local segments = 6
	local length = between(gen, 2.4, 2.9) * s
	local previous = base - Vector3.new(0, 0.6, 0)
	for i = 1, segments do
		local t = i / segments
		local point = base + Vector3.new(0, i * length, 0) + lean * bend * t * t
		local color = if i % 2 == 0 then Palette.woodLight else Palette.wood
		Build.rod(previous, point, (1.9 - 0.5 * t) * s, color, m, { name = "Trunk" })
		previous = point
	end
	local crown = previous
	Build.ball(1.9 * s, crown, Palette.leafDark, m, LEAF)
	local fronds = 7
	local spin = gen.next() * math.pi * 2
	for i = 1, fronds do
		local a = spin + i * (2 * math.pi / fronds)
		local droop = math.rad(between(gen, 14, 30))
		local dir = horizontal(a) * math.cos(droop) - Vector3.new(0, math.sin(droop), 0)
		local center = crown + dir * 3.8 * s + Vector3.new(0, 0.3 * s, 0)
		Build.ellipsoid(
			Vector3.new(2.6, 0.35, 8.4) * s,
			Frames.alongZ(center, dir),
			if i % 2 == 0 then Palette.leaf else Palette.leafLight,
			m,
			LEAF
		)
	end
	for i = 1, 3 do
		local a = spin + i * 2.1
		Build.ball(
			1.15 * s,
			crown + Vector3.new(math.sin(a) * 0.9, -1.1, math.cos(a) * 0.9) * s,
			Palette.woodDark,
			m,
			SMALL
		)
	end
	return m
end

-- Prehistoric fern: a fountain of long leaves.
function Props.fern(base: Vector3, s: number, gen: Gen, parent: Instance): Model
	local m = Build.model("Fern", parent)
	local leaves = 7
	local spin = gen.next() * math.pi * 2
	for i = 1, leaves do
		local a = spin + i * (2 * math.pi / leaves)
		local rise = math.rad(between(gen, 30, 48))
		local dir = horizontal(a) * math.cos(rise) + Vector3.new(0, math.sin(rise), 0)
		Build.ellipsoid(
			Vector3.new(1.5, 0.3, 6) * s,
			Frames.alongZ(base + dir * 2.7 * s + Vector3.new(0, 0.2, 0), dir),
			if i % 2 == 0 then Palette.leafDark else Palette.leaf,
			m,
			SMALL
		)
	end
	Build.ball(1.4 * s, base + Vector3.new(0, 0.4 * s, 0), Palette.leafDark, m, SMALL)
	return m
end

-- A round tree heavy with red apples, plus invisible "FruitSpot" markers on
-- the ground around it where the Fruit system drops pickable fruit.
function Props.fruitTree(base: Vector3, s: number, gen: Gen, parent: Instance): Model
	local m = Props.tree(base, s, gen, parent)
	m.Name = "FruitTree"
	local canopy = base + Vector3.new(0, 9.5 * s, 0)
	for i = 1, 7 do
		local a = i * (math.pi * 2 / 7) + gen.next() * 0.4
		local p = canopy
			+ Vector3.new(math.sin(a) * 4.8, between(gen, -2.6, 1.2), math.cos(a) * 4.8) * s
		Build.ball(0.95 * s, p, Palette.red, m, { decor = true, collide = false, shadow = false })
	end
	for i = 1, 3 do
		local a = i * (math.pi * 2 / 3) + gen.next() * 0.6
		local spot = Instance.new("Part")
		spot.Name = "FruitSpot"
		spot.Anchored = true
		spot.CanCollide = false
		spot.CanTouch = false
		spot.CanQuery = false
		spot.Transparency = 1
		spot.Size = Vector3.new(1, 1, 1)
		spot.CFrame =
			CFrame.new(base + Vector3.new(math.sin(a) * 4.6 * s, 0.9, math.cos(a) * 4.6 * s))
		spot.Parent = m
	end
	return m
end

function Props.bush(base: Vector3, s: number, gen: Gen, parent: Instance): Model
	local m = Build.model("Bush", parent)
	local yaw = CFrame.Angles(0, gen.next() * math.pi * 2, 0)
	local function blob(size: Vector3, offset: Vector3, color: Color3)
		Build.ellipsoid(
			size * s,
			CFrame.new(base + yaw:VectorToWorldSpace(offset * s)),
			color,
			m,
			LEAF
		)
	end
	blob(Vector3.new(5, 4, 5), Vector3.new(0, 1.5, 0), Palette.leaf)
	blob(Vector3.new(3.6, 3, 3.6), Vector3.new(2.3, 1, 0.8), Palette.leafDark)
	blob(Vector3.new(3.4, 2.8, 3.4), Vector3.new(-2.1, 0.9, -0.9), Palette.leafDark)
	blob(Vector3.new(3, 2.6, 3), Vector3.new(0.4, 2.8, -0.3), Palette.leafLight)
	if gen.next() < 0.45 then
		local berry = if gen.next() < 0.5 then Palette.pink else Palette.red
		for i = 1, 4 do
			local a = i * 1.7 + gen.next()
			local p = base
				+ yaw:VectorToWorldSpace(
					Vector3.new(math.sin(a) * 2.4, 1.6 + math.cos(a * 3) * 0.8, math.cos(a) * 2.4)
						* s
				)
			Build.ball(0.6 * s, p, berry, m, SMALL)
		end
	end
	return m
end

function Props.flowers(base: Vector3, s: number, gen: Gen, parent: Instance): Model
	local m = Build.model("Flowers", parent)
	Build.ellipsoid(Vector3.new(4.4, 0.7, 4.4) * s, CFrame.new(base), Palette.grassDeep, m, SMALL)
	local color = pick(gen, Palette.FLOWERS)
	for i = 1, 5 do
		local a = i * 1.26 + gen.next() * 0.5
		local r = between(gen, 0.4, 1.7) * s
		local foot = base + Vector3.new(math.sin(a) * r, 0, math.cos(a) * r)
		local height = between(gen, 0.9, 1.5) * s
		local head = foot + Vector3.new(0, height, 0)
		Build.rod(foot, head, 0.18 * s, Palette.grassDeep, m, SMALL)
		local petals = if gen.next() < 0.75 then color else pick(gen, Palette.FLOWERS)
		Build.ellipsoid(Vector3.new(1.2, 0.45, 1.2) * s, CFrame.new(head), petals, m, SMALL)
		local middle = if petals == Palette.yellow then Palette.orange else Palette.yellow
		Build.ball(0.45 * s, head + Vector3.new(0, 0.18 * s, 0), middle, m, SMALL)
	end
	return m
end

function Props.rock(base: Vector3, s: number, gen: Gen, parent: Instance): Model
	local m = Build.model("Rock", parent)
	local yaw = CFrame.Angles(0, gen.next() * math.pi * 2, 0)
	Build.ellipsoid(
		Vector3.new(4.4, 2.8, 3.6) * s,
		CFrame.new(base + Vector3.new(0, 0.7 * s, 0)) * yaw,
		Palette.stone,
		m,
		{ decor = true }
	)
	Build.ellipsoid(
		Vector3.new(2.6, 2, 2.4) * s,
		CFrame.new(base + yaw:VectorToWorldSpace(Vector3.new(2, 0.4, 0.9) * s)) * yaw,
		Palette.stoneDark,
		m,
		{ decor = true, collide = false }
	)
	Build.ellipsoid(
		Vector3.new(2.6, 1, 2.2) * s,
		CFrame.new(base + Vector3.new(-0.3, 1.8, -0.2) * s) * yaw,
		Palette.stoneLight,
		m,
		SMALL
	)
	return m
end

local CAP_COLORS = { Palette.red, Palette.purple, Palette.orange, Palette.pink }

function Props.mushroom(base: Vector3, s: number, gen: Gen, parent: Instance): Model
	local m = Build.model("Mushroom", parent)
	local height = between(gen, 2, 2.8) * s
	local top = base + Vector3.new(0, height, 0)
	Build.rod(base - Vector3.new(0, 0.3, 0), top, 1.1 * s, Palette.cream, m, { decor = true })
	local cap = Vector3.new(3.6, 2, 3.6) * s
	local center = top + Vector3.new(0, 0.2 * s, 0)
	Build.ellipsoid(cap, CFrame.new(center), pick(gen, CAP_COLORS), m, { decor = true })
	local spin = gen.next() * math.pi * 2
	for i = 1, 4 do
		local a = spin + i * (math.pi / 2)
		local e = math.rad(if i % 2 == 0 then 35 else 60)
		local p = center
			+ Vector3.new(
				math.cos(e) * math.sin(a) * cap.X / 2,
				math.sin(e) * cap.Y / 2,
				math.cos(e) * math.cos(a) * cap.Z / 2
			)
		Build.ellipsoid(Vector3.new(0.9, 0.35, 0.9) * s, CFrame.new(p), Palette.white, m, SMALL)
	end
	return m
end

-- Street lamp; its light switches on at night (see NIGHT_LIGHT_TAG).
function Props.lamp(base: Vector3, s: number, parent: Instance, glow: Color3?): Model
	local m = Build.model("Lamp", parent)
	local dark = Color3.fromRGB(88, 76, 104)
	Build.disc(1.8 * s, 0.8 * s, CFrame.new(base + Vector3.new(0, 0.4 * s, 0)), dark, m)
	local top = base + Vector3.new(0, 8.5 * s, 0)
	Build.rod(base, top, 0.55 * s, dark, m)
	local bulb =
		Build.ball(1.7 * s, top + Vector3.new(0, 0.9 * s, 0), glow or Palette.lampGlow, m, {
			name = "Bulb",
			material = Enum.Material.Neon,
			decor = true,
			shadow = false,
		})
	Build.disc(
		2.6 * s,
		0.5 * s,
		CFrame.new(top + Vector3.new(0, 2 * s, 0)),
		dark,
		m,
		{ decor = true }
	)
	Build.ball(0.7 * s, top + Vector3.new(0, 2.5 * s, 0), dark, m, SMALL)
	local light = Instance.new("PointLight")
	light.Color = glow or Palette.lampGlow
	light.Range = 22 * s
	light.Brightness = 1.6
	light.Shadows = false
	light.Enabled = false
	light.Parent = bulb
	CollectionService:AddTag(light, Props.NIGHT_LIGHT_TAG)
	return m
end

function Props.cloud(center: Vector3, s: number, gen: Gen, parent: Instance): Model
	local m = Build.model("Cloud", parent)
	local options = { decor = true, collide = false, shadow = false }
	local yaw = CFrame.Angles(0, gen.next() * math.pi * 2, 0)
	local puffs = {
		{ Vector3.new(26, 13, 18), Vector3.new(0, 0, 0) },
		{ Vector3.new(18, 12, 15), Vector3.new(-12, -1.5, 2) },
		{ Vector3.new(17, 11, 14), Vector3.new(12, -2, -1) },
		{ Vector3.new(15, 12, 13), Vector3.new(3, 4.5, 1) },
		{ Vector3.new(30, 6, 20), Vector3.new(0, -4, 0) },
	}
	for _, puff in puffs do
		Build.ellipsoid(
			puff[1] * s,
			CFrame.new(center + yaw:VectorToWorldSpace(puff[2] * s)) * yaw,
			Palette.white,
			m,
			options
		)
	end
	return m
end

-- Little pond with a stone rim, lily pads and reeds.
function Props.pond(base: Vector3, s: number, gen: Gen, parent: Instance): Model
	local m = Build.model("Pond", parent)
	local radius = 6.5 * s
	Build.disc(
		radius * 2 + 0.6,
		0.4,
		CFrame.new(base + Vector3.new(0, -0.05, 0)),
		Palette.sandDark,
		m,
		{
			decor = true,
			shadow = false,
		}
	)
	Build.disc(
		radius * 2 - 0.6,
		0.4,
		CFrame.new(base + Vector3.new(0, 0.02, 0)),
		Palette.water,
		m,
		{
			name = "Water",
			decor = true,
			shadow = false,
		}
	)
	Build.disc(
		radius * 1.2,
		0.4,
		CFrame.new(base + Vector3.new(0, 0.05, 0)),
		Palette.waterDeep,
		m,
		{
			decor = true,
			shadow = false,
		}
	)
	local stones = 14
	for i = 0, stones - 1 do
		local a = i * (2 * math.pi / stones) + gen.next() * 0.2
		local size = Vector3.new(
			between(gen, 1.8, 2.6),
			between(gen, 0.9, 1.4),
			between(gen, 1.4, 2)
		) * s
		Build.ellipsoid(
			size,
			CFrame.new(base + Vector3.new(math.sin(a) * radius, 0.25 * s, math.cos(a) * radius))
				* CFrame.Angles(0, a, 0),
			if i % 3 == 0 then Palette.stoneDark else Palette.stone,
			m,
			SMALL
		)
	end
	for i = 1, 3 do
		local a = i * 2.2 + gen.next()
		local r = between(gen, 1.5, radius - 2.2)
		local pad = base + Vector3.new(math.sin(a) * r, 0.3, math.cos(a) * r)
		Build.disc(1.9 * s, 0.12, CFrame.new(pad), Palette.leaf, m, SMALL)
		if i == 1 then
			Build.ball(0.7 * s, pad + Vector3.new(0, 0.3, 0), Palette.pink, m, SMALL)
		end
	end
	local reedAngle = gen.next() * math.pi * 2
	for i = 0, 3 do
		local a = reedAngle + i * 0.22
		local foot = base
			+ Vector3.new(math.sin(a) * (radius - 0.8), 0, math.cos(a) * (radius - 0.8))
		local height = between(gen, 2.6, 3.6) * s
		Build.rod(foot, foot + Vector3.new(0, height, 0), 0.22 * s, Palette.leafDark, m, SMALL)
		Build.ellipsoid(
			Vector3.new(0.5, 1.3, 0.5) * s,
			CFrame.new(foot + Vector3.new(0, height, 0)),
			Palette.woodDark,
			m,
			SMALL
		)
	end
	return m
end

-- Three-toed dino footprint pressed into a path.
function Props.footprint(
	position: Vector3,
	facing: number,
	s: number,
	color: Color3,
	parent: Instance
)
	local frame = CFrame.new(position) * CFrame.Angles(0, facing, 0)
	local options = { decor = true, collide = false, shadow = false }
	Build.ellipsoid(Vector3.new(1.7, 0.1, 2) * s, frame, color, parent, options)
	for i = -1, 1 do
		local toe = frame * CFrame.Angles(0, -i * math.rad(28), 0) * CFrame.new(0, 0, -1.9 * s)
		Build.ellipsoid(Vector3.new(0.6, 0.1, 1.6) * s, toe, color, parent, options)
	end
end

-- A twig nest holding big spotted eggs (landmark decoration).
function Props.eggNest(base: Vector3, s: number, gen: Gen, parent: Instance): Model
	local m = Build.model("EggNest", parent)
	for i = 0, 9 do
		local a = i * (2 * math.pi / 10)
		local cf = CFrame.new(base + Vector3.new(math.sin(a) * 4.4, 0.8, math.cos(a) * 4.4) * s)
			* CFrame.Angles(0, a + math.pi / 2, 0)
		Build.ellipsoid(
			Vector3.new(1.6, 1.6, 3.6) * s,
			cf,
			if i % 2 == 0 then Palette.woodDark else Palette.wood,
			m,
			{
				decor = true,
			}
		)
	end
	Build.disc(
		8.6 * s,
		0.6 * s,
		CFrame.new(base + Vector3.new(0, 0.3 * s, 0)),
		Palette.sandDark,
		m,
		SMALL
	)
	local eggs = {
		{ offset = Vector3.new(-1.4, 0, -0.6), shell = Palette.mint, spots = Palette.teal },
		{ offset = Vector3.new(1.5, 0, -0.9), shell = Palette.cream, spots = Palette.orange },
		{ offset = Vector3.new(0, 0, 1.6), shell = Palette.purple, spots = Palette.pink },
	}
	for _, egg in eggs do
		local size = Vector3.new(2.6, 3.4, 2.6) * s
		local center = base + egg.offset * s + Vector3.new(0, size.Y / 2 + 0.2 * s, 0)
		Build.ellipsoid(
			size,
			CFrame.new(center)
				* CFrame.Angles(math.rad(between(gen, -12, 12)), 0, math.rad(between(gen, -12, 12))),
			egg.shell,
			m,
			{
				decor = true,
			}
		)
		for k = 1, 3 do
			local a = k * 2.2 + gen.next()
			local p = center
				+ Vector3.new(
					math.sin(a) * size.X * 0.47,
					between(gen, -0.6, 0.9) * s,
					math.cos(a) * size.Z * 0.47
				)
			Build.ellipsoid(Vector3.new(0.8, 0.8, 0.8) * s, CFrame.new(p), egg.spots, m, SMALL)
		end
	end
	return m
end

return Props
