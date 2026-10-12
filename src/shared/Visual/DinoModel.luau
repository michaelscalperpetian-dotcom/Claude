--!strict
-- Builds a chunky, cartoon dinosaur out of simple parts from the species' body
-- plan. No uploaded meshes needed, so the game works out of the box; swap in
-- real models later by replacing build().
--
-- Model space: origin on the ground under the body, facing -Z (LookVector).

local CollectionService = game:GetService("CollectionService")

local DinoData = require(script.Parent.Parent.Data.DinoData)
local MutationData = require(script.Parent.Parent.Data.MutationData)
local Frames = require(script.Parent.Parent.Util.Frames)
local Growth = require(script.Parent.Parent.Util.Growth)

local DinoModel = {}

export type Mode = "Static" | "World" | "Mount"

DinoModel.BASE_UNIT = 1.4
DinoModel.RAINBOW_TAG = "RainbowPart"
DinoModel.TAG = "Dino"

local IVORY = Color3.fromRGB(240, 235, 215)
local EYE_WHITE = Color3.fromRGB(255, 255, 255)
local PUPIL = Color3.fromRGB(28, 24, 40)
local MOUTH = Color3.fromRGB(70, 35, 45)
local CHEEK = Color3.fromRGB(255, 150, 175)

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

type Role = "main" | "belly" | "accent" | "detail"

type Builder = {
	model: Model,
	root: BasePart,
	scale: number,
	colors: { main: Color3, belly: Color3, accent: Color3 },
	parts: { { part: BasePart, role: Role } },
}

local function newPart(b: Builder, name: string, role: Role, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Anchored = true
	p.CastShadow = role ~= "detail"
	p.Parent = b.model
	table.insert(b.parts, { part = p :: BasePart, role = role })
	return p
end

-- Ellipsoid of `size` (unit space) at `cf` (unit space).
local function ellipsoid(
	b: Builder,
	name: string,
	role: Role,
	color: Color3,
	size: Vector3,
	cf: CFrame
): Part
	local p = newPart(b, name, role, color)
	p.Size = size * b.scale
	p.CFrame = cf.Rotation + cf.Position * b.scale
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Cylinder from `a` to `b` (unit space).
local function cylinder(
	bld: Builder,
	name: string,
	role: Role,
	color: Color3,
	a: Vector3,
	z: Vector3,
	thickness: number
): Part
	local p = newPart(bld, name, role, color)
	p.Shape = Enum.PartType.Cylinder
	local length = (z - a).Magnitude
	p.Size = Vector3.new(length, thickness, thickness) * bld.scale
	local mid = (a + z) / 2
	local cf = Frames.alongX(mid, z - a)
	p.CFrame = cf.Rotation + cf.Position * bld.scale
	return p
end

local function along(center: Vector3, direction: Vector3): CFrame
	return Frames.alongZ(center, direction)
end

local function addParticles(target: BasePart, color: Color3, scale: number, rate: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35 * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Parent = target
end

-- Signature details per mutation so each one reads at a glance, not just as
-- a recolour: glowing cracks (Lava), ice crystals (Frost), stars (Cosmic).
local DETAIL_SPOTS = {
	{ 0.35, -0.22 },
	{ -0.5, -0.05 },
	{ 0.15, 0.15 },
	{ -0.2, 0.3 },
	{ 0.9, 0.05 },
	{ -1, -0.25 },
	{ 0.6, 0.32 },
}

local function addMutationDetails(b: Builder, body: BasePart, mutation: string)
	local center = body.CFrame.Position / b.scale
	local size = body.Size / b.scale
	for i, spot in DETAIL_SPOTS do
		local a, bb, c = size.X / 2, size.Y / 2, size.Z / 2
		local ring = math.sqrt(math.max(0, 1 - (2 * spot[2]) ^ 2))
		local p = Vector3.new(
			math.sin(spot[1]) * a * ring,
			math.cos(spot[1]) * bb * ring,
			spot[2] * size.Z
		)
		local normal = Vector3.new(p.X / (a * a), p.Y / (bb * bb), p.Z / (c * c)).Unit
		local at = center + p
		if mutation == "Lava" and i <= 5 then
			local crack = ellipsoid(
				b,
				"LavaCrack",
				"detail",
				Color3.fromRGB(255, 150, 40),
				Vector3.new(size.X * 0.06, size.X * 0.32, size.Y * 0.06),
				along(at, normal) * CFrame.Angles(0, 0, i * 0.9)
			)
			crack.Material = Enum.Material.Neon
		elseif mutation == "Frost" and i <= 5 then
			local up = (normal + Vector3.new(0, 1.2, 0)).Unit
			local crystal = ellipsoid(
				b,
				"IceCrystal",
				"detail",
				Color3.fromRGB(200, 240, 255),
				Vector3.new(size.Y * 0.12, size.Y * 0.12, size.Y * 0.5),
				along(at + up * size.Y * 0.12, up)
			)
			crystal.Material = Enum.Material.Ice
		elseif mutation == "Cosmic" then
			local star = ellipsoid(
				b,
				"Star",
				"detail",
				Color3.fromRGB(255, 250, 220),
				Vector3.new(size.Y * 0.09, size.Y * 0.09, size.Y * 0.09),
				CFrame.new(at + normal * size.Y * 0.02)
			)
			star.Material = Enum.Material.Neon
		end
	end
end

local function applyMutation(b: Builder, mutation: string?)
	if mutation == nil then
		return
	end
	local body = b.model:FindFirstChild("Body")
	for _, entry in b.parts do
		local p = entry.part
		if entry.role == "detail" then
			continue
		end
		if mutation == "Glossy" then
			p.Reflectance = 0.3
			p.Color = p.Color:Lerp(Color3.new(1, 1, 1), 0.15)
		elseif mutation == "Lava" then
			if entry.role == "main" then
				p.Color = Color3.fromRGB(60, 22, 18)
			elseif entry.role == "belly" and p.Name ~= "Belly" then
				-- only the belly glows; a glowing chin reads as a duck bill
				p.Color = Color3.fromRGB(150, 52, 24)
			elseif entry.role == "belly" then
				p.Color = Color3.fromRGB(255, 120, 30)
				p.Material = Enum.Material.Neon
			else
				p.Color = Color3.fromRGB(255, 80, 20)
				p.Material = Enum.Material.Neon
			end
		elseif mutation == "Frost" then
			if entry.role == "main" then
				p.Color = Color3.fromRGB(170, 220, 255)
				p.Material = Enum.Material.Ice
			elseif entry.role == "belly" then
				p.Color = Color3.fromRGB(240, 250, 255)
			else
				p.Color = Color3.fromRGB(110, 180, 255)
				p.Material = Enum.Material.Glass
			end
		elseif mutation == "Cosmic" then
			if entry.role == "main" then
				p.Color = Color3.fromRGB(55, 30, 110)
			elseif entry.role == "belly" and p.Name ~= "Belly" then
				p.Color = Color3.fromRGB(110, 70, 190)
			elseif entry.role == "belly" then
				p.Color = Color3.fromRGB(150, 90, 255)
				p.Material = Enum.Material.Neon
			else
				p.Color = Color3.fromRGB(255, 255, 255)
				p.Material = Enum.Material.Neon
			end
		elseif mutation == "Rainbow" then
			p.Reflectance = 0.1
			if entry.role == "main" or entry.role == "accent" then
				CollectionService:AddTag(p, DinoModel.RAINBOW_TAG)
			end
		end
	end
	if body and body:IsA("BasePart") then
		addMutationDetails(b, body, mutation)
		local m = MutationData.get(mutation)
		if m and mutation ~= "Glossy" then
			addParticles(body, rgb(m.color), b.scale, 6)
		elseif mutation == "Glossy" then
			addParticles(body, Color3.fromRGB(255, 255, 220), b.scale, 2)
		end
	end
end

local function ball(
	b: Builder,
	name: string,
	role: Role,
	color: Color3,
	diameter: number,
	position: Vector3
): Part
	return ellipsoid(
		b,
		name,
		role,
		color,
		Vector3.new(diameter, diameter, diameter),
		CFrame.new(position)
	)
end

local function darker(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount)
end

local function lighter(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount)
end

-- Point on an axis-aligned ellipsoid's surface (`around` = angle from the top
-- toward +X, `k` = -0.5..0.5 along the length) plus the outward normal there.
local function onSurface(
	center: Vector3,
	size: Vector3,
	around: number,
	k: number
): (Vector3, Vector3)
	local a, bb, c = size.X / 2, size.Y / 2, size.Z / 2
	local ring = math.sqrt(math.max(0, 1 - (2 * k) ^ 2))
	local p = Vector3.new(math.sin(around) * a * ring, math.cos(around) * bb * ring, k * size.Z)
	local normal = Vector3.new(p.X / (a * a), p.Y / (bb * bb), p.Z / (c * c))
	if normal.Magnitude < 1e-6 then
		normal = Vector3.new(0, 1, 0)
	end
	return center + p, normal.Unit
end

type Head = { center: Vector3, size: Vector3, muzzle: Vector3, muzzleSize: Vector3 }

local function buildHead(b: Builder, stage: number, center: Vector3, size: Vector3): Head
	local c = b.colors
	local hw, hh, hl = size.X, size.Y, size.Z
	local baby = stage == Growth.BABY
	ellipsoid(b, "Head", "main", c.main, size, CFrame.new(center))

	-- rounded muzzle in the body colour, lighter chin underneath, smile line between
	local muzzleSize = Vector3.new(hw * 0.84, hh * 0.64, hl * 0.62)
	local muzzle = center + Vector3.new(0, -hh * 0.14, -hl * 0.36)
	ellipsoid(b, "Muzzle", "main", c.main, muzzleSize, CFrame.new(muzzle))
	ellipsoid(
		b,
		"Chin",
		"belly",
		c.belly,
		Vector3.new(hw * 0.74, hh * 0.42, hl * 0.6),
		CFrame.new(muzzle + Vector3.new(0, -hh * 0.15, hl * 0.02))
	)
	ellipsoid(
		b,
		"Mouth",
		"detail",
		MOUTH,
		Vector3.new(hw * 0.86, hh * 0.05, hl * 0.64),
		CFrame.new(muzzle + Vector3.new(0, -hh * 0.08, -hl * 0.01))
	)
	for _, side in { -1, 1 } do
		ball(
			b,
			"Nostril",
			"detail",
			darker(c.main, 0.45),
			hh * 0.08,
			muzzle + Vector3.new(side * hw * 0.15, hh * 0.24, -hl * 0.27)
		)
	end

	-- big shiny eyes and blush cheeks
	local e = hh * (if baby then 0.5 else 0.42)
	for _, side in { -1, 1 } do
		local eye = center + Vector3.new(side * hw * 0.33, hh * 0.2, -hl * 0.2)
		ellipsoid(
			b,
			"Eye",
			"detail",
			EYE_WHITE,
			Vector3.new(e * 0.85, e, e * 0.85),
			CFrame.new(eye)
		)
		ellipsoid(
			b,
			"Pupil",
			"detail",
			PUPIL,
			Vector3.new(e * 0.6, e * 0.72, e * 0.6),
			CFrame.new(eye + Vector3.new(side * e * 0.2, -e * 0.02, -e * 0.2))
		)
		ball(
			b,
			"Shine",
			"detail",
			EYE_WHITE,
			e * 0.22,
			eye + Vector3.new(side * e * 0.33, e * 0.2, -e * 0.32)
		)
		ellipsoid(
			b,
			"Cheek",
			"detail",
			CHEEK,
			Vector3.new(e * 0.75, e * 0.38, e * 0.62),
			CFrame.new(center + Vector3.new(side * hw * 0.36, -hh * 0.1, -hl * 0.34))
		)
	end
	return { center = center, size = size, muzzle = muzzle, muzzleSize = muzzleSize }
end

local function buildBody(b: Builder, species: DinoData.Species, stage: number)
	local plan = species.plan
	local c = b.colors
	local bw, bh, bl = plan.body[1], plan.body[2], plan.body[3]
	local legH = plan.legHeight
	local lt = plan.legThickness
	local tailLength = plan.tailLength
	local tt = plan.tailThickness
	local neckLength = plan.neckLength
	local feet = darker(c.main, 0.22)

	-- Cartoon proportions: rounder heads for everyone, and young dinos get
	-- bigger heads and eyes with shorter legs and tails.
	local headScale = 1.15
	local headLength = 1
	if stage == Growth.BABY then
		headScale, headLength = 1.55, 1.3
		legH *= 0.8
		tailLength *= 0.75
		neckLength *= 0.8
	elseif stage == Growth.JUVENILE then
		headScale, headLength = 1.3, 1.12
		legH *= 0.92
		tailLength *= 0.9
	end
	local headSize =
		Vector3.new(plan.head[1] * headScale, plan.head[2] * headScale, plan.head[3] * headLength)
	local hw, hh, hl = headSize.X, headSize.Y, headSize.Z

	local bodyCenter = Vector3.new(0, legH + bh * 0.42, 0)
	local bodySize = Vector3.new(bw, bh, bl)
	ellipsoid(b, "Body", "main", c.main, bodySize, CFrame.new(bodyCenter))
	ellipsoid(
		b,
		"Belly",
		"belly",
		c.belly,
		Vector3.new(bw * 0.84, bh * 0.72, bl * 0.82),
		CFrame.new(bodyCenter + Vector3.new(0, -bh * 0.17, -bl * 0.05))
	)

	-- Legs: round feet with ivory claws
	if plan.kind == "biped" or plan.kind == "flyer" then
		for _, side in { -1, 1 } do
			local x = side * bw * 0.3
			local z = bl * 0.1
			if plan.kind == "biped" then
				ellipsoid(
					b,
					"Thigh",
					"main",
					c.main,
					Vector3.new(lt * 1.5, legH * 0.78, lt * 1.9),
					CFrame.new(x, legH * 0.74, z - lt * 0.05)
				)
			end
			cylinder(
				b,
				"Shin",
				"main",
				c.main,
				Vector3.new(x, legH * 0.58, z + lt * 0.05),
				Vector3.new(x, lt * 0.35, z),
				lt * 0.95
			)
			ellipsoid(
				b,
				"Foot",
				"main",
				feet,
				Vector3.new(lt * 1.45, lt * 0.62, lt * 2.1),
				CFrame.new(x, lt * 0.31, z - lt * 0.5)
			)
			for i = -1, 1 do
				ball(
					b,
					"Claw",
					"detail",
					IVORY,
					lt * 0.36,
					Vector3.new(x + i * lt * 0.42, lt * 0.2, z - lt * 1.45)
				)
			end
		end
	elseif plan.kind == "quad" then
		for _, side in { -1, 1 } do
			for _, front in { -1, 1 } do
				local x = side * bw * 0.32
				local z = front * bl * 0.27
				ellipsoid(
					b,
					"Leg",
					"main",
					c.main,
					Vector3.new(lt * 1.35, legH * 0.8 + bh * 0.3, lt * 1.4),
					CFrame.new(x, legH * 0.75 + bh * 0.1, z)
				)
				cylinder(
					b,
					"Shin",
					"main",
					c.main,
					Vector3.new(x, legH * 0.62, z),
					Vector3.new(x, lt * 0.3, z),
					lt * 1.05
				)
				ellipsoid(
					b,
					"Foot",
					"main",
					feet,
					Vector3.new(lt * 1.38, lt * 0.56, lt * 1.45),
					CFrame.new(x, lt * 0.28, z - lt * 0.06)
				)
				for i = -1, 1 do
					ball(
						b,
						"Nail",
						"detail",
						IVORY,
						lt * 0.3,
						Vector3.new(x + i * lt * 0.38, lt * 0.18, z - lt * 0.66)
					)
				end
			end
		end
	end

	-- Little arms with round hands
	if plan.arms then
		local ta = math.max(lt * 0.48, 0.18)
		for _, side in { -1, 1 } do
			local shoulder = bodyCenter + Vector3.new(side * bw * 0.36, -bh * 0.02, -bl * 0.3)
			local hand = shoulder + Vector3.new(side * 0.06, -bh * 0.3, -bl * 0.1)
			ellipsoid(
				b,
				"Arm",
				"main",
				c.main,
				Vector3.new(ta, ta, (hand - shoulder).Magnitude + ta),
				along((shoulder + hand) / 2, hand - shoulder)
			)
			ball(b, "Hand", "main", c.main, ta * 1.25, hand)
		end
	end

	-- Neck + head
	local headCenter: Vector3
	if neckLength > 0.05 then
		local angle = math.rad(plan.neckAngle)
		local dir = Vector3.new(0, math.sin(angle), -math.cos(angle))
		local neckStart = bodyCenter + Vector3.new(0, bh * 0.2, -bl * 0.36)
		local neckEnd = neckStart + dir * neckLength
		ellipsoid(
			b,
			"Neck",
			"main",
			c.main,
			Vector3.new(plan.neckThickness, plan.neckThickness, neckLength + plan.neckThickness),
			along((neckStart + neckEnd) / 2, dir)
		)
		headCenter = neckEnd + Vector3.new(0, hh * 0.12, -hl * 0.28)
	else
		headCenter = bodyCenter + Vector3.new(0, bh * 0.2, -(bl * 0.48 + hl * 0.3))
	end
	local head = buildHead(b, stage, headCenter, headSize)

	-- Tail: three tapering segments curling up a little at the tip
	local segments = {
		{ length = 0.42, thick = 1, dir = Vector3.new(0, -0.12, 1) },
		{ length = 0.34, thick = 0.68, dir = Vector3.new(0, 0.02, 1) },
		{ length = 0.3, thick = 0.42, dir = Vector3.new(0, 0.2, 1) },
	}
	local cursor = bodyCenter + Vector3.new(0, bh * 0.04, bl * 0.36)
	local lastDir = Vector3.new(0, 0, 1)
	local lastLength = 0
	for i, seg in segments do
		local dir = seg.dir.Unit
		local length = tailLength * seg.length
		local thick = tt * seg.thick
		ellipsoid(
			b,
			if i == 1 then "Tail" else "TailTip",
			"main",
			c.main,
			Vector3.new(thick, thick * 0.9, length * 1.2),
			along(cursor + dir * length * 0.5, dir)
		)
		cursor += dir * length * 0.85
		lastDir = dir
		lastLength = length
	end
	local tailEnd = cursor

	-- Species features
	local accentLight = lighter(c.accent, 0.35)
	for _, feature in plan.features do
		if feature == "stripes" then
			-- bands across the back only (not wrapped round the belly)
			for _, k in { -0.24, -0.02, 0.2 } do
				local ring = math.sqrt(math.max(0, 1 - (2 * k) ^ 2))
				ellipsoid(
					b,
					"Stripe",
					"accent",
					c.accent,
					Vector3.new(bw * 0.86 * ring, bh * 0.26, bl * 0.11),
					CFrame.new(bodyCenter + Vector3.new(0, bh * 0.42 * ring - bh * 0.06, k * bl))
				)
			end
		elseif feature == "spots" then
			local spots = {
				{ 0.5, -0.15 },
				{ -0.6, 0.05 },
				{ 0.15, 0.22 },
				{ -0.25, -0.28 },
				{ 0.85, 0.15 },
				{ -0.9, -0.12 },
			}
			for _, spot in spots do
				local p, normal = onSurface(bodyCenter, bodySize, spot[1], spot[2])
				ellipsoid(
					b,
					"Spot",
					"accent",
					c.accent,
					Vector3.new(bw * 0.22, bw * 0.2, bh * 0.08),
					along(p, normal)
				)
			end
		elseif feature == "plates" then
			for i = 1, 6 do
				local k = -0.3 + (i - 1) * 0.12
				local ring = math.sqrt(math.max(0, 1 - (2 * k) ^ 2))
				local height = bh * 0.62 * (1 - math.abs(k + 0.02) * 1.3)
				local x = if i % 2 == 0 then bw * 0.05 else -bw * 0.05
				ellipsoid(
					b,
					"Plate",
					"accent",
					c.accent,
					Vector3.new(bw * 0.09, height, height * 0.8),
					CFrame.new(
						bodyCenter + Vector3.new(x, bh * 0.44 * ring + height * 0.28, k * bl)
					)
				)
			end
		elseif feature == "spikes" then
			for _, side in { -1, 1 } do
				for _, back in { 0.15, 0.55 } do
					local base = tailEnd - lastDir * lastLength * back
					local dir = Vector3.new(side * 1, 0.7, 0.25).Unit
					ellipsoid(
						b,
						"Spike",
						"detail",
						IVORY,
						Vector3.new(tt * 0.22, tt * 0.22, tt * 1.1),
						along(base + dir * tt * 0.4, dir)
					)
				end
			end
		elseif feature == "club" then
			ellipsoid(
				b,
				"Club",
				"accent",
				c.accent,
				Vector3.new(tt * 1.9, tt * 1.3, tt * 1.6),
				CFrame.new(tailEnd)
			)
			for _, side in { -1, 1 } do
				ball(
					b,
					"Knob",
					"accent",
					accentLight,
					tt * 0.7,
					tailEnd + Vector3.new(side * tt * 0.85, tt * 0.1, 0)
				)
			end
		elseif feature == "armor" then
			for row = -1, 1 do
				for i = 0, 3 do
					local k = -0.27 + i * 0.18
					local around = row * 0.55
					local p, normal = onSurface(bodyCenter, bodySize, around, k)
					ellipsoid(
						b,
						"Scute",
						"accent",
						c.accent,
						Vector3.new(bw * 0.17, bw * 0.17, bh * 0.16),
						along(p, normal)
					)
				end
			end
			for _, side in { -1, 1 } do
				for i = 0, 2 do
					local k = -0.22 + i * 0.22
					local p = onSurface(bodyCenter, bodySize, side * 1.45, k)
					local dir = Vector3.new(side, 0.15, 0).Unit
					ellipsoid(
						b,
						"Spike",
						"detail",
						IVORY,
						Vector3.new(bh * 0.14, bh * 0.14, bh * 0.42),
						along(p + dir * bh * 0.12, dir)
					)
				end
			end
		elseif feature == "frill" then
			-- fan behind the head: body-coloured rim, accent centre, knobbly edge
			local frillSize = Vector3.new(hw * 1.95, hh * 1.65, hh * 0.18)
			local frill = CFrame.new(headCenter + Vector3.new(0, hh * 0.5, hl * 0.36))
				* CFrame.Angles(math.rad(40), 0, 0)
			ellipsoid(b, "Frill", "main", darker(c.main, 0.08), frillSize, frill)
			ellipsoid(
				b,
				"FrillInner",
				"accent",
				c.accent,
				Vector3.new(frillSize.X * 0.66, frillSize.Y * 0.6, frillSize.Z * 1.08),
				frill * CFrame.new(0, -frillSize.Y * 0.06, 0)
			)
			for i = 0, 6 do
				local phi = math.rad(15 + i * 25)
				local p = frill
					* Vector3.new(
						math.cos(phi) * frillSize.X * 0.47,
						math.sin(phi) * frillSize.Y * 0.47,
						0
					)
				ball(b, "FrillKnob", "accent", accentLight, hh * 0.26, p)
			end
		elseif feature == "horns" then
			for _, side in { -1, 1 } do
				local base = headCenter + Vector3.new(side * hw * 0.24, hh * 0.38, -hl * 0.04)
				local dir = Vector3.new(side * 0.12, 0.6, -0.8).Unit
				local length = hh * 1.15
				ellipsoid(
					b,
					"Horn",
					"detail",
					IVORY,
					Vector3.new(hh * 0.22, hh * 0.22, length),
					along(base + dir * length * 0.42, dir)
				)
			end
			local nose = head.muzzle
				+ Vector3.new(0, head.muzzleSize.Y * 0.42, -head.muzzleSize.Z * 0.22)
			local dir = Vector3.new(0, 0.85, -0.5).Unit
			ellipsoid(
				b,
				"Horn",
				"detail",
				IVORY,
				Vector3.new(hh * 0.2, hh * 0.2, hh * 0.55),
				along(nose + dir * hh * 0.18, dir)
			)
		elseif feature == "crest" then
			local dir = Vector3.new(0, 0.5, 1).Unit
			ellipsoid(
				b,
				"Crest",
				"accent",
				c.accent,
				Vector3.new(hw * 0.32, hw * 0.32, hl * 1.5),
				along(headCenter + Vector3.new(0, hh * 0.55, hl * 0.45), dir)
			)
		elseif feature == "dome" then
			local dome = headCenter + Vector3.new(0, hh * 0.36, hl * 0.06)
			ellipsoid(
				b,
				"Dome",
				"accent",
				c.accent,
				Vector3.new(hw * 1.08, hh * 0.82, hl * 0.84),
				CFrame.new(dome)
			)
			for i = 0, 6 do
				local a = math.rad(-90 + i * 30)
				ball(
					b,
					"Knob",
					"accent",
					darker(c.accent, 0.15),
					hh * 0.16,
					dome + Vector3.new(math.sin(a) * hw * 0.5, -hh * 0.18, math.cos(a) * hl * 0.4)
				)
			end
		elseif feature == "doubleCrest" then
			for _, side in { -1, 1 } do
				ellipsoid(
					b,
					"Crest",
					"accent",
					c.accent,
					Vector3.new(hw * 0.1, hh * 0.8, hl * 0.95),
					CFrame.new(headCenter + Vector3.new(side * hw * 0.18, hh * 0.55, -hl * 0.02))
						* CFrame.Angles(0, 0, math.rad(side * -8))
				)
			end
		elseif feature == "wings" then
			-- half-raised wings with a bony leading edge
			for _, side in { -1, 1 } do
				local shoulder = bodyCenter + Vector3.new(side * bw * 0.4, bh * 0.22, -bl * 0.05)
				local inner = shoulder + Vector3.new(side * bl * 0.55, bl * 0.22, bl * 0.05)
				ellipsoid(
					b,
					"Wing",
					"accent",
					c.accent,
					Vector3.new(bl * 1.2, 0.12, bl * 1.0),
					CFrame.new(inner) * CFrame.Angles(0, 0, math.rad(side * 22))
				)
				local outer = shoulder + Vector3.new(side * bl * 1.35, bl * 0.62, -bl * 0.06)
				ellipsoid(
					b,
					"Wing",
					"accent",
					c.accent,
					Vector3.new(bl * 0.95, 0.1, bl * 0.58),
					CFrame.new(outer) * CFrame.Angles(0, math.rad(side * 14), math.rad(side * 32))
				)
				local tip = shoulder + Vector3.new(side * bl * 1.8, bl * 0.9, -bl * 0.28)
				cylinder(
					b,
					"WingBone",
					"main",
					c.main,
					shoulder + Vector3.new(0, 0.05, -bl * 0.2),
					tip,
					0.16
				)
			end
		elseif feature == "beakCrest" then
			ellipsoid(
				b,
				"BeakCrest",
				"accent",
				c.accent,
				Vector3.new(hw * 0.25, hh * 0.8, hl * 0.9),
				along(headCenter + Vector3.new(0, hh * 0.35, hl * 0.6), Vector3.new(0, 0.5, 1))
			)
		elseif feature == "flippers" then
			for _, side in { -1, 1 } do
				for _, front in { -1, 1 } do
					ellipsoid(
						b,
						"Flipper",
						"accent",
						c.accent,
						Vector3.new(bw * 0.9, 0.15, bw * 0.45),
						CFrame.new(
							bodyCenter + Vector3.new(side * bw * 0.6, -bh * 0.3, front * bl * 0.28)
						)
							* CFrame.Angles(0, math.rad(front * side * 20), math.rad(side * -10))
					)
				end
			end
		elseif feature == "tailFin" then
			-- crescent fin: a tall upper lobe and a short, shallow lower one
			-- (kept above the ground since swimmers lie low)
			local lobes = {
				{ dir = Vector3.new(0, 0.75, 0.65).Unit, length = tt * 1.9, offset = tt * 0.75 },
				{ dir = Vector3.new(0, -0.4, 0.9).Unit, length = tt * 1.3, offset = tt * 0.6 },
			}
			for _, lobe in lobes do
				ellipsoid(
					b,
					"TailFin",
					"accent",
					c.accent,
					Vector3.new(0.14, tt * 0.7, lobe.length),
					along(tailEnd + lobe.dir * lobe.offset, lobe.dir)
				)
			end
		elseif feature == "teeth" then
			for _, side in { -1, 1 } do
				for _, step in { 0.18, 0.32 } do
					ellipsoid(
						b,
						"Tooth",
						"detail",
						IVORY,
						Vector3.new(hw * 0.08, hh * 0.15, hw * 0.08),
						CFrame.new(
							head.muzzle
								+ Vector3.new(
									side * hw * step,
									-hh * 0.18,
									-hl * (0.22 - step * 0.3)
								)
						)
					)
				end
			end
		elseif feature == "sail" then
			local heights = { 0.7, 1.15, 1.4, 1.2, 0.8 }
			for i, height in heights do
				local k = -0.24 + (i - 1) * 0.12
				local h = bh * height
				ellipsoid(
					b,
					"Sail",
					"accent",
					if i % 2 == 0 then c.accent else darker(c.accent, 0.1),
					Vector3.new(0.14, h, bl * 0.2),
					CFrame.new(bodyCenter + Vector3.new(0, bh * 0.36 + h * 0.36, k * bl))
				)
			end
		end
	end
end

-- Studs per body-plan unit. Species sizes are softened (big species stay
-- big without a giant T-Rex swallowing the whole nest).
function DinoModel.scaleFor(species: DinoData.Species, stage: number): number
	return species.scale ^ 0.75 * Growth.SIZE[math.clamp(stage, 1, 4)] * DinoModel.BASE_UNIT
end

-- Builds a dino model. `stage` is 1-4 (Baby..Giant).
--   Static: every part anchored (UI previews)
--   World: root anchored, everything else welded to it (move the root to move the dino)
--   Mount: nothing anchored, welded to the root; caller welds the root to a character
function DinoModel.build(speciesId: string, stage: number, mutation: string?, mode: Mode): Model
	local species = DinoData.get(speciesId)
	assert(species, `unknown species {speciesId}`)
	stage = math.clamp(stage, 1, 4)
	local scale = DinoModel.scaleFor(species, stage)

	local model = Instance.new("Model")
	model.Name = species.name

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Size = Vector3.new(species.plan.body[1], 0.2, species.plan.body[3]) * scale
	root.CFrame = CFrame.new(0, 0.1, 0)
	root.Parent = model
	model.PrimaryPart = root

	local b: Builder = {
		model = model,
		root = root,
		scale = scale,
		colors = {
			main = rgb(species.colors.main),
			belly = rgb(species.colors.belly),
			accent = rgb(species.colors.accent),
		},
		parts = {},
	}

	buildBody(b, species, stage)
	applyMutation(b, mutation)

	-- Prompt anchor at chest height
	local top = 0
	for _, entry in b.parts do
		local p = entry.part
		top = math.max(top, p.CFrame.Position.Y + p.Size.Y / 2)
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "PromptAttachment"
	attachment.CFrame = CFrame.new(0, top * 0.55, 0)
	attachment.Parent = root
	local labelAttachment = Instance.new("Attachment")
	labelAttachment.Name = "LabelAttachment"
	labelAttachment.CFrame = CFrame.new(0, top + 1, 0)
	labelAttachment.Parent = root
	model:SetAttribute("Height", top)

	if mode ~= "Static" then
		for _, entry in b.parts do
			local p = entry.part
			p.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = p
			weld.Parent = p
			p.Anchored = false
		end
		root.Anchored = mode == "World"
		root.Massless = mode == "Mount"
	end

	return model
end

return DinoModel
