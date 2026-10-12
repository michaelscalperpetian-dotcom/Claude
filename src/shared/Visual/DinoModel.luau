--!strict
-- Builds a chunky, cartoon dinosaur out of simple parts from the species' body
-- plan. No uploaded meshes needed, so the game works out of the box; swap in
-- real models later by replacing build().
--
-- Model space: origin on the ground under the body, facing -Z (LookVector).

local CollectionService = game:GetService("CollectionService")

local DinoData = require(script.Parent.Parent.Data.DinoData)
local MutationData = require(script.Parent.Parent.Data.MutationData)
local Growth = require(script.Parent.Parent.Util.Growth)

local DinoModel = {}

export type Mode = "Static" | "World" | "Mount"

DinoModel.BASE_UNIT = 1.4
DinoModel.RAINBOW_TAG = "RainbowPart"
DinoModel.TAG = "Dino"

local IVORY = Color3.fromRGB(240, 235, 215)
local EYE_WHITE = Color3.fromRGB(255, 255, 255)
local PUPIL = Color3.fromRGB(25, 25, 30)
local MOUTH = Color3.fromRGB(70, 35, 35)

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

local function block(
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
	local cf = CFrame.lookAt(mid, mid + (z - a).Unit) * CFrame.Angles(0, math.rad(90), 0)
	p.CFrame = cf.Rotation + cf.Position * bld.scale
	return p
end

local function along(center: Vector3, direction: Vector3): CFrame
	return CFrame.lookAt(center, center + direction.Unit)
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
		local m = MutationData.get(mutation)
		if m and mutation ~= "Glossy" then
			addParticles(body, rgb(m.color), b.scale, 6)
		elseif mutation == "Glossy" then
			addParticles(body, Color3.fromRGB(255, 255, 220), b.scale, 2)
		end
	end
end

local function buildBody(b: Builder, species: DinoData.Species, stage: number)
	local plan = species.plan
	local c = b.colors
	local bw, bh, bl = plan.body[1], plan.body[2], plan.body[3]
	local hw, hh, hl = plan.head[1], plan.head[2], plan.head[3]
	local legH = plan.legHeight
	local lt = plan.legThickness
	local tailLength = plan.tailLength
	local tt = plan.tailThickness
	local neckLength = plan.neckLength

	-- Babies: bigger heads, shorter legs and tails = cuter.
	if stage == Growth.BABY then
		hw, hh, hl = hw * 1.35, hh * 1.35, hl * 1.25
		legH *= 0.85
		tailLength *= 0.8
		neckLength *= 0.85
	end

	local bodyCenter = Vector3.new(0, legH + bh * 0.42, 0)

	-- Body + belly
	ellipsoid(b, "Body", "main", c.main, Vector3.new(bw, bh, bl), CFrame.new(bodyCenter))
	ellipsoid(
		b,
		"Belly",
		"belly",
		c.belly,
		Vector3.new(bw * 0.86, bh * 0.72, bl * 0.86),
		CFrame.new(bodyCenter + Vector3.new(0, -bh * 0.16, 0))
	)

	-- Legs
	if plan.kind == "biped" or plan.kind == "flyer" then
		for _, side in { -1, 1 } do
			local x = side * bw * 0.32
			if plan.kind == "biped" then
				ellipsoid(
					b,
					"Thigh",
					"main",
					c.main,
					Vector3.new(lt * 1.3, legH * 0.8, lt * 1.7),
					CFrame.new(x, legH * 0.68, bl * 0.1)
				)
			end
			cylinder(
				b,
				"Shin",
				"main",
				c.main,
				Vector3.new(x, legH * 0.62, bl * 0.16),
				Vector3.new(x, 0.1, bl * 0.18),
				lt
			)
			block(
				b,
				"Foot",
				"accent",
				c.accent,
				Vector3.new(lt * 1.25, math.max(lt * 0.4, 0.15), lt * 1.9),
				CFrame.new(x, math.max(lt * 0.2, 0.08), bl * 0.18 - lt * 0.45)
			)
		end
	elseif plan.kind == "quad" then
		for _, side in { -1, 1 } do
			for _, front in { -1, 1 } do
				local x = side * bw * 0.33
				local z = front * bl * 0.3
				cylinder(
					b,
					"Leg",
					"main",
					c.main,
					Vector3.new(x, legH + bh * 0.25, z),
					Vector3.new(x, 0.1, z),
					lt
				)
				cylinder(
					b,
					"Toe",
					"accent",
					c.accent,
					Vector3.new(x, 0.25, z),
					Vector3.new(x, 0, z),
					lt * 1.15
				)
			end
		end
	end

	-- Little arms
	if plan.arms then
		for _, side in { -1, 1 } do
			local shoulder = bodyCenter + Vector3.new(side * bw * 0.4, -bh * 0.05, -bl * 0.3)
			local hand = shoulder + Vector3.new(side * 0.05, -legH * 0.35, -legH * 0.18)
			cylinder(b, "Arm", "main", c.main, shoulder, hand, math.max(lt * 0.45, 0.15))
		end
	end

	-- Neck + head placement
	local headCenter: Vector3
	if neckLength > 0.05 then
		local angle = math.rad(plan.neckAngle)
		local dir = Vector3.new(0, math.sin(angle), -math.cos(angle))
		local neckStart = bodyCenter + Vector3.new(0, bh * 0.2, -bl * 0.38)
		local neckEnd = neckStart + dir * neckLength
		local mid = (neckStart + neckEnd) / 2
		ellipsoid(
			b,
			"Neck",
			"main",
			c.main,
			Vector3.new(plan.neckThickness, plan.neckThickness, neckLength + plan.neckThickness),
			along(mid, dir)
		)
		headCenter = neckEnd + Vector3.new(0, hh * 0.15, -hl * 0.3)
	else
		headCenter = bodyCenter + Vector3.new(0, bh * 0.2, -(bl * 0.5 + hl * 0.3))
	end

	-- Head
	ellipsoid(b, "Head", "main", c.main, Vector3.new(hw, hh, hl), CFrame.new(headCenter))
	ellipsoid(
		b,
		"Snout",
		"belly",
		c.belly,
		Vector3.new(hw * 0.78, hh * 0.55, hl * 0.6),
		CFrame.new(headCenter + Vector3.new(0, -hh * 0.18, -hl * 0.36))
	)
	block(
		b,
		"Mouth",
		"detail",
		MOUTH,
		Vector3.new(hw * 0.6, 0.05, hl * 0.4),
		CFrame.new(headCenter + Vector3.new(0, -hh * 0.3, -hl * 0.42))
	)
	for _, side in { -1, 1 } do
		local eyeSize = hh * 0.36
		local eye = ellipsoid(
			b,
			"Eye",
			"detail",
			EYE_WHITE,
			Vector3.new(eyeSize, eyeSize, eyeSize),
			CFrame.new(headCenter + Vector3.new(side * hw * 0.36, hh * 0.16, -hl * 0.12))
		)
		eye.Material = Enum.Material.SmoothPlastic
		local pupilSize = hh * 0.2
		ellipsoid(
			b,
			"Pupil",
			"detail",
			PUPIL,
			Vector3.new(pupilSize, pupilSize, pupilSize),
			CFrame.new(headCenter + Vector3.new(side * hw * 0.46, hh * 0.18, -hl * 0.18))
		)
	end

	-- Tail (two tapering segments)
	local tailStart = bodyCenter + Vector3.new(0, 0, bl * 0.38)
	local dir1 = Vector3.new(0, -0.12, 1).Unit
	local len1 = tailLength * 0.55
	ellipsoid(
		b,
		"Tail",
		"main",
		c.main,
		Vector3.new(tt, tt * 0.9, len1),
		along(tailStart + dir1 * len1 * 0.45, dir1)
	)
	local seg2Start = tailStart + dir1 * len1 * 0.85
	local dir2 = Vector3.new(0, 0.05, 1).Unit
	local len2 = tailLength * 0.5
	ellipsoid(
		b,
		"TailTip",
		"main",
		c.main,
		Vector3.new(tt * 0.55, tt * 0.5, len2),
		along(seg2Start + dir2 * len2 * 0.45, dir2)
	)
	local tailEnd = seg2Start + dir2 * len2 * 0.9

	-- Species features
	for _, feature in plan.features do
		if feature == "stripes" then
			for _, k in { -0.18, 0.04, 0.24 } do
				local shrink = math.sqrt(math.max(0, 1 - (2 * k) ^ 2)) * 1.03
				ellipsoid(
					b,
					"Stripe",
					"accent",
					c.accent,
					Vector3.new(bw * shrink, bh * shrink, bl * 0.09),
					CFrame.new(bodyCenter + Vector3.new(0, 0, k * bl))
				)
			end
		elseif feature == "plates" then
			for i = 1, 5 do
				local k = -0.32 + (i - 1) * 0.16
				local top = bh * 0.5 * math.sqrt(math.max(0, 1 - (2 * k) ^ 2))
				local p = bh * 0.5 * (1 - math.abs(k) * 1.1)
				block(
					b,
					"Plate",
					"accent",
					c.accent,
					Vector3.new(0.14, p, p),
					CFrame.new(bodyCenter + Vector3.new(0, top + p * 0.15, k * bl))
						* CFrame.Angles(math.rad(45), 0, 0)
				)
			end
		elseif feature == "spikes" then
			for _, side in { -1, 1 } do
				for _, offset in { 0, 0.35 } do
					local base = tailEnd - dir2 * len2 * offset
					cylinder(
						b,
						"Spike",
						"accent",
						IVORY,
						base,
						base + Vector3.new(side * tt * 1.1, tt * 0.7, 0),
						tt * 0.18
					)
				end
			end
		elseif feature == "club" then
			ellipsoid(
				b,
				"Club",
				"accent",
				c.accent,
				Vector3.new(tt * 1.7, tt * 1.2, tt * 1.5),
				CFrame.new(tailEnd)
			)
		elseif feature == "frill" then
			local frill = block(
				b,
				"Frill",
				"accent",
				c.accent,
				Vector3.new(0.15, hh * 2.3, hh * 2.3),
				CFrame.new(headCenter + Vector3.new(0, hh * 0.45, hl * 0.35))
					* CFrame.Angles(math.rad(-20), math.rad(90), 0)
			)
			frill.Shape = Enum.PartType.Cylinder
		elseif feature == "horns" then
			for _, side in { -1, 1 } do
				local base = headCenter + Vector3.new(side * hw * 0.28, hh * 0.38, -hl * 0.1)
				cylinder(
					b,
					"Horn",
					"detail",
					IVORY,
					base,
					base + Vector3.new(0, 0.55, -0.75) * hh,
					hh * 0.17
				)
			end
			local noseBase = headCenter + Vector3.new(0, hh * 0.15, -hl * 0.5)
			cylinder(
				b,
				"Horn",
				"detail",
				IVORY,
				noseBase,
				noseBase + Vector3.new(0, 0.45, -0.25) * hh,
				hh * 0.14
			)
		elseif feature == "crest" then
			local dir = Vector3.new(0, 0.45, 1)
			ellipsoid(
				b,
				"Crest",
				"accent",
				c.accent,
				Vector3.new(hw * 0.3, hw * 0.3, hl * 1.4),
				along(headCenter + Vector3.new(0, hh * 0.55, hl * 0.5), dir)
			)
		elseif feature == "dome" then
			ellipsoid(
				b,
				"Dome",
				"accent",
				c.accent,
				Vector3.new(hw * 1.05, hh * 0.78, hl * 0.78),
				CFrame.new(headCenter + Vector3.new(0, hh * 0.38, hl * 0.05))
			)
		elseif feature == "doubleCrest" then
			for _, side in { -1, 1 } do
				ellipsoid(
					b,
					"Crest",
					"accent",
					c.accent,
					Vector3.new(0.08, hh * 0.65, hl * 0.85),
					CFrame.new(headCenter + Vector3.new(side * hw * 0.18, hh * 0.5, -hl * 0.05))
				)
			end
		elseif feature == "wings" then
			local span = bl * 2.2
			for _, side in { -1, 1 } do
				ellipsoid(
					b,
					"Wing",
					"accent",
					c.accent,
					Vector3.new(span, 0.12, bl * 0.9),
					CFrame.new(
						bodyCenter + Vector3.new(side * (bw * 0.45 + span * 0.45), bh * 0.15, 0)
					) * CFrame.Angles(0, 0, math.rad(side * 12))
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
			ellipsoid(
				b,
				"TailFin",
				"accent",
				c.accent,
				Vector3.new(0.12, tt * 2.2, tt * 1.6),
				CFrame.new(tailEnd + Vector3.new(0, tt * 0.2, 0))
			)
		elseif feature == "teeth" then
			for i = 1, 5 do
				local x = (-0.3 + (i - 1) * 0.15) * hw
				block(
					b,
					"Tooth",
					"detail",
					IVORY,
					Vector3.new(hw * 0.08, hh * 0.14, hw * 0.08),
					CFrame.new(headCenter + Vector3.new(x, -hh * 0.36, -hl * 0.6))
				)
			end
		elseif feature == "sail" then
			local sailH = bh * 1.4
			ellipsoid(
				b,
				"Sail",
				"accent",
				c.accent,
				Vector3.new(0.12, sailH, bl * 0.75),
				CFrame.new(bodyCenter + Vector3.new(0, bh * 0.45 + sailH * 0.25, 0))
			)
		end
	end
end

-- Builds a dino model. `stage` is 1-4 (Baby..Giant).
--   Static: every part anchored (UI previews)
--   World: root anchored, everything else welded to it (move the root to move the dino)
--   Mount: nothing anchored, welded to the root; caller welds the root to a character
function DinoModel.build(speciesId: string, stage: number, mutation: string?, mode: Mode): Model
	local species = DinoData.get(speciesId)
	assert(species, `unknown species {speciesId}`)
	stage = math.clamp(stage, 1, 4)
	local scale = species.scale * Growth.SIZE[stage] * DinoModel.BASE_UNIT

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
