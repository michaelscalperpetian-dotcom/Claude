--!strict
-- Soft, chunky props built from parts: rounded shapes, 2-3 shades per
-- material. Each builder takes a ground position, a size multiplier and a
-- random generator (so layouts are repeatable).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Frames = require(ReplicatedStorage.Shared.Util.Frames)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Rng = require(ReplicatedStorage.Shared.Util.Rng)
local Build = require(script.Parent.Build)

local Props = {}

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

-- Leafy round tree: a short trunk under a cluster of soft blobs.
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

-- Tiered pine tree.
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

-- A little patch of flowers.
function Props.flowers(base: Vector3, s: number, gen: Gen, parent: Instance): Model
	local m = Build.model("Flowers", parent)
	Build.ellipsoid(Vector3.new(4.4, 0.7, 4.4) * s, CFrame.new(base), Palette.grassDark, m, SMALL)
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

-- A mossy boulder.
function Props.rock(base: Vector3, s: number, gen: Gen, parent: Instance): Model
	local m = Build.model("Rock", parent)
	local yaw = CFrame.Angles(0, gen.next() * math.pi * 2, 0)
	Build.ellipsoid(
		Vector3.new(4.4, 2.8, 3.6) * s,
		CFrame.new(base + Vector3.new(0, 0.7 * s, 0)) * yaw,
		Palette.rock,
		m,
		{ decor = true }
	)
	Build.ellipsoid(
		Vector3.new(2.6, 2, 2.4) * s,
		CFrame.new(base + yaw:VectorToWorldSpace(Vector3.new(2, 0.4, 0.9) * s)) * yaw,
		Palette.rockDark,
		m,
		{ decor = true, collide = false }
	)
	Build.ellipsoid(
		Vector3.new(2.6, 1, 2.2) * s,
		CFrame.new(base + Vector3.new(-0.3, 1.8, -0.2) * s) * yaw,
		Palette.rockLight,
		m,
		SMALL
	)
	return m
end

-- A soft cloud.
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

return Props
