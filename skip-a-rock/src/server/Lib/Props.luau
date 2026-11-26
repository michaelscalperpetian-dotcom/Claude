--!strict
-- Natural props built from parts: trees, bushes, ferns, flowers and rocks.
-- Real materials (bark, leaves, rock) instead of plain plastic, two or three
-- shades each, and a little randomness so nothing looks stamped. Each
-- builder takes a ground position, a size multiplier and a random generator
-- (so layouts are repeatable).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Frames = require(ReplicatedStorage.Shared.Util.Frames)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Rng = require(ReplicatedStorage.Shared.Util.Rng)
local Build = require(script.Parent.Build)

local Props = {}

type Gen = Rng.Generator

local BARK: Build.Options = { name = "Trunk", material = Enum.Material.Wood }
local LEAF: Build.Options = { decor = true, collide = false, material = Enum.Material.LeafyGrass }
local SMALL: Build.Options = { decor = true, collide = false, shadow = false }
local ROCK: Build.Options = { decor = true, material = Enum.Material.Rock }

local function between(gen: Gen, a: number, b: number): number
	return a + (b - a) * gen.next()
end

local function pick<T>(gen: Gen, list: { T }): T
	return list[gen.int(1, #list)]
end

local function horizontal(angle: number): Vector3
	return Vector3.new(math.sin(angle), 0, math.cos(angle))
end

-- A colour nudged a little lighter or darker.
local function vary(gen: Gen, c: Color3, amount: number): Color3
	local t = (gen.next() - 0.5) * 2 * amount
	return if t > 0 then c:Lerp(Color3.new(1, 1, 1), t) else c:Lerp(Color3.new(0, 0, 0), -t)
end

-- Leafy round tree: a short trunk under a cluster of soft blobs.
function Props.tree(base: Vector3, s: number, gen: Gen, parent: Instance): Model
	local m = Build.model("Tree", parent)
	local h = between(gen, 7.5, 9.5) * s
	local lean = horizontal(gen.next() * math.pi * 2) * between(gen, 0.3, 1.2) * s
	local mid = base + Vector3.new(0, h * 0.5, 0) + lean * 0.3
	local top = base + Vector3.new(0, h, 0) + lean
	Build.rod(base - Vector3.new(0, 1, 0), mid, 2 * s, Palette.bark, m, BARK)
	Build.rod(mid, top, 1.5 * s, Palette.bark, m, BARK)

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
	local leaf = vary(gen, Palette.leaf, 0.12)
	blob(Vector3.new(10.5, 8, 10.5), Vector3.zero, leaf)
	blob(Vector3.new(7, 5.6, 7), Vector3.new(4.2, -1.4, 1.2), vary(gen, Palette.leafDark, 0.1))
	blob(Vector3.new(6.5, 5.2, 6.5), Vector3.new(-3.8, -1, -2), vary(gen, Palette.leafDark, 0.1))
	blob(Vector3.new(6.5, 5, 6.5), Vector3.new(0.8, 3.1, -0.6), vary(gen, Palette.leafLight, 0.1))
	return m
end

-- A tall pine: a slim trunk through five drooping tiers of needles,
-- narrowing to a point.
function Props.pine(base: Vector3, s: number, gen: Gen, parent: Instance): Model
	local m = Build.model("Pine", parent)
	local height = 17 * s
	Build.rod(
		base - Vector3.new(0, 1, 0),
		base + Vector3.new(0, height * 0.8, 0),
		1.1 * s,
		Palette.bark,
		m,
		BARK
	)
	local lean = horizontal(gen.next() * math.pi * 2) * 0.25 * s
	local shade = vary(gen, Palette.pine, 0.12)
	local dark = vary(gen, Palette.pineDark, 0.1)
	local tiers = 5
	for i = 1, tiers do
		local t = (i - 1) / (tiers - 1) -- 0 at the bottom tier, 1 at the top
		local width = (8.6 - 6.4 * t) * s
		local tall = (3.6 - 0.9 * t) * s
		local y = (3.2 + t * 11.2) * s
		Build.ellipsoid(
			Vector3.new(width, tall, width * between(gen, 0.9, 1)),
			CFrame.new(base + Vector3.new(0, y, 0) + lean * t)
				* CFrame.Angles(0, gen.next() * math.pi, 0),
			if i % 2 == 1 then shade else dark,
			m,
			LEAF
		)
	end
	-- the pointed tip
	Build.ellipsoid(
		Vector3.new(1.4, 3.2, 1.4) * s,
		CFrame.new(base + Vector3.new(0, 16 * s, 0) + lean),
		shade,
		m,
		LEAF
	)
	return m
end

-- Low fern of drooping leaves.
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

-- Round bush, sometimes with berries.
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
	blob(Vector3.new(5, 3.6, 5), Vector3.new(0, 1.3, 0), vary(gen, Palette.leaf, 0.12))
	blob(Vector3.new(3.6, 2.8, 3.6), Vector3.new(2.3, 0.9, 0.8), Palette.leafDark)
	blob(Vector3.new(3.4, 2.6, 3.4), Vector3.new(-2.1, 0.8, -0.9), Palette.leafDark)
	blob(Vector3.new(3, 2.4, 3), Vector3.new(0.4, 2.4, -0.3), Palette.leafLight)
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

-- A little patch of flowers.
function Props.flowers(base: Vector3, s: number, gen: Gen, parent: Instance): Model
	local m = Build.model("Flowers", parent)
	local color = pick(gen, Palette.FLOWERS)
	for i = 1, 5 do
		local a = i * 1.26 + gen.next() * 0.5
		local r = between(gen, 0.4, 1.7) * s
		local foot = base + Vector3.new(math.sin(a) * r, 0, math.cos(a) * r)
		local height = between(gen, 0.9, 1.5) * s
		local head = foot + Vector3.new(0, height, 0)
		Build.rod(foot, head, 0.18 * s, Palette.grassDark, m, SMALL)
		local petals = if gen.next() < 0.75 then color else pick(gen, Palette.FLOWERS)
		Build.ellipsoid(Vector3.new(1.2, 0.45, 1.2) * s, CFrame.new(head), petals, m, SMALL)
		local middle = if petals == Palette.yellow then Palette.orange else Palette.yellow
		Build.ball(0.45 * s, head + Vector3.new(0, 0.18 * s, 0), middle, m, SMALL)
	end
	return m
end

-- A weathered boulder, half sunk in the ground, sometimes with moss on top.
function Props.rock(base: Vector3, s: number, gen: Gen, parent: Instance): Model
	local m = Build.model("Rock", parent)
	local yaw = CFrame.Angles(gen.next() * 0.3, gen.next() * math.pi * 2, gen.next() * 0.3)
	local stone = vary(gen, Palette.rock, 0.1)
	Build.ellipsoid(
		Vector3.new(5, 3.2, 4) * s,
		CFrame.new(base + Vector3.new(0, 0.5 * s, 0)) * yaw,
		stone,
		m,
		ROCK
	)
	Build.ellipsoid(
		Vector3.new(2.8, 2, 2.6) * s,
		CFrame.new(base + yaw:VectorToWorldSpace(Vector3.new(2.2, 0, 1) * s)) * yaw,
		Palette.rockDark,
		m,
		ROCK
	)
	if gen.next() < 0.5 then
		Build.ellipsoid(
			Vector3.new(3, 0.8, 2.4) * s,
			CFrame.new(base + Vector3.new(-0.2, 1.95, -0.1) * s) * yaw,
			Palette.moss,
			m,
			{ decor = true, collide = false, shadow = false, material = Enum.Material.LeafyGrass }
		)
	end
	return m
end

-- A palm: a gently curving, ringed trunk under a crown of drooping fronds,
-- with a few coconuts.
function Props.palm(base: Vector3, s: number, gen: Gen, parent: Instance): Model
	local m = Build.model("Palm", parent)
	local height = between(gen, 13, 17) * s
	local lean = horizontal(gen.next() * math.pi * 2) * between(gen, 2, 4.5) * s
	local segments = 6
	local last = base - Vector3.new(0, 0.6, 0)
	for i = 1, segments do
		local t = i / segments
		-- the trunk bends more toward the top
		local point = base + Vector3.new(0, height * t, 0) + lean * t * t
		Build.rod(
			last,
			point,
			(1.25 - 0.35 * t) * s,
			if i % 2 == 0 then Palette.palmTrunk else Palette.bark,
			m,
			BARK
		)
		last = point
	end
	local top = last
	local fronds = 8
	local spin = gen.next() * math.pi * 2
	for i = 1, fronds do
		local a = spin + i * (2 * math.pi / fronds)
		local droop = math.rad(between(gen, 10, 35))
		local dir = horizontal(a) * math.cos(droop) - Vector3.new(0, math.sin(droop), 0)
		Build.ellipsoid(
			Vector3.new(1.8, 0.35, 8.5) * s,
			Frames.alongZ(top + dir * 3.8 * s, dir),
			vary(gen, Palette.palmLeaf, 0.12),
			m,
			LEAF
		)
	end
	for i = 1, 3 do
		local a = i * 2.1 + gen.next()
		Build.ball(
			0.9 * s,
			top + Vector3.new(math.sin(a) * 0.7, -0.7, math.cos(a) * 0.7) * s,
			Palette.woodDark,
			m,
			SMALL
		)
	end
	return m
end

return Props
