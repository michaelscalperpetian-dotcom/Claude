--!strict
-- Builds the island scenery: layered coastline (grass, beach, foam, shallows),
-- paths, the central plaza with the egg-shop tent, the volcano, scattered
-- cartoon props, palms, clouds and little islands on the horizon.
-- Nests (plots) are built by World; this module only needs to know where they
-- are so props stay out of them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EggData = require(ReplicatedStorage.Shared.Data.EggData)
local EggModel = require(ReplicatedStorage.Shared.Visual.EggModel)
local DinoModel = require(ReplicatedStorage.Shared.Visual.DinoModel)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Rng = require(ReplicatedStorage.Shared.Util.Rng)
local Build = require(script.Parent.Build)
local Props = require(script.Parent.Props)

local Island = {}

local TAU = 2 * math.pi
local PLOT_ANGLE = TAU / Config.PLOT_COUNT
local HALF = Config.PLOT_SIZE / 2

Island.LAND_RADIUS = 184
Island.PLAZA_RADIUS = 40
Island.RING_PATH_RADIUS = 86
Island.GATE_RADIUS = Config.PLOT_RING_RADIUS - HALF
Island.VOLCANO_ANGLE = PLOT_ANGLE / 2
Island.VOLCANO_POSITION = Build.polar(PLOT_ANGLE / 2, 205)
Island.VOLCANO_RADIUS = 46
Island.SHOP_RADIUS = 15

local GROUND = { decor = true }
local FLAT = { decor = true, shadow = false }

type Land = { center: Vector3, radius: number }

-- ===== Coastline =====

local function lands(): { Land }
	local list: { Land } = { { center = Vector3.zero, radius = Island.LAND_RADIUS } }
	local gen = Rng.new(7)
	-- Uneven bumps (a few big peninsulas, some small coves) keep the coast
	-- from looking like a stamped flower.
	local bumps = 13
	for i = 0, bumps - 1 do
		local angle = i * (TAU / bumps) + (gen.next() - 0.5) * 0.32
		local big = gen.next() < 0.3
		local radius = if big then 44 + gen.next() * 16 else 20 + gen.next() * 18
		local distance = Island.LAND_RADIUS - radius * 0.3 + (gen.next() - 0.3) * 16
		table.insert(list, { center = Build.polar(angle, distance), radius = radius })
	end
	-- the volcano needs solid ground under it
	table.insert(list, { center = Island.VOLCANO_POSITION, radius = Island.VOLCANO_RADIUS + 12 })
	return list
end

-- Layers from the water up; each land disc is drawn in every layer so the
-- coastline keeps its bumps. Higher layers always win, so overlaps never fight.
local LAYERS = {
	{ name = "DeepShallows", grow = 70, top = -1.98, thick = 0.2, color = Palette.water },
	{ name = "Shallows", grow = 30, top = -1.9, thick = 0.2, color = Palette.shallows },
	{ name = "Foam", grow = 13, top = -1.8, thick = 0.2, color = Palette.foam },
	{ name = "Beach", grow = 10, top = -0.9, thick = 2, color = Palette.sand },
	{ name = "GrassLip", grow = 1.6, top = -0.3, thick = 6, color = Palette.grassDark },
	{ name = "Grass", grow = 0, top = 0, thick = 6, color = Palette.grass },
}

local function buildCoast(map: Instance, landList: { Land }, extraGrow: number?)
	local folder = Instance.new("Folder")
	folder.Name = "Coast"
	for _, layer in LAYERS do
		for _, land in landList do
			local diameter = 2 * (land.radius + layer.grow + (extraGrow or 0))
			Build.disc(
				diameter,
				layer.thick,
				CFrame.new(land.center.X, layer.top - layer.thick / 2, land.center.Z),
				layer.color,
				folder,
				{ name = layer.name, decor = true, shadow = layer.thick > 1 }
			)
		end
	end
	folder.Parent = map
end

local function buildOcean(map: Instance)
	Build.block(
		Vector3.new(4000, 2, 4000),
		CFrame.new(0, -3.05, 0),
		Palette.waterDeep,
		map,
		{ name = "Ocean", decor = true, shadow = false, reflectance = 0.06 }
	)
end

-- ===== Paths =====

local function buildPaths(map: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Paths"
	local inner = Island.PLAZA_RADIUS - 4
	local outer = Island.GATE_RADIUS + 1
	for i = 0, Config.PLOT_COUNT - 1 do
		local angle = i * PLOT_ANGLE
		local a = Build.polar(angle, inner)
		local b = Build.polar(angle, outer)
		Build.beam(
			a + Vector3.new(0, -0.09, 0),
			b + Vector3.new(0, -0.09, 0),
			12.5,
			0.3,
			Palette.pathEdge,
			folder,
			FLAT
		)
		Build.beam(
			a + Vector3.new(0, -0.03, 0),
			b + Vector3.new(0, -0.03, 0),
			10,
			0.3,
			Palette.path,
			folder,
			FLAT
		)
	end
	local center = CFrame.new(0, -0.09, 0)
	Build.ring(center, Island.RING_PATH_RADIUS, 11, 0.3, 64, Palette.pathEdge, folder, FLAT)
	Build.ring(
		center + Vector3.new(0, 0.06, 0),
		Island.RING_PATH_RADIUS,
		8.5,
		0.3,
		64,
		Palette.path,
		folder,
		FLAT
	)
	folder.Parent = map
end

-- A trail of dino footprints from the plaza toward the volcano.
local function buildFootprints(map: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Footprints"
	local angle = Island.VOLCANO_ANGLE
	local outward = Build.polar(angle, 1)
	local side = Vector3.new(outward.Z, 0, -outward.X)
	local facing = angle + math.pi
	local step = 0
	for r = Island.PLAZA_RADIUS + 6, 150, 5.5 do
		if math.abs(r - Island.RING_PATH_RADIUS) > 8 then
			local offset = if step % 2 == 0 then 1.4 else -1.4
			local p = Build.polar(angle, r, 0.06) + side * offset
			Props.footprint(p, facing, 1, Palette.grassDeep, folder)
		end
		step += 1
	end
	folder.Parent = map
end

-- ===== Plaza + egg shop =====

local function stripedPillar(a: Vector3, b: Vector3, parent: Instance)
	local stripes = 6
	for i = 0, stripes - 1 do
		local p0 = a:Lerp(b, i / stripes)
		local p1 = a:Lerp(b, (i + 1) / stripes)
		Build.rod(p0, p1, 1.3, if i % 2 == 0 then Palette.red else Palette.white, parent)
	end
end

-- Candy-striped tent roof: a cone of alternating wedges with a scalloped rim.
local function tent(center: Vector3, radius: number, height: number, parent: Instance)
	local segments = 16
	local width = 2 * radius * math.sin(math.pi / segments) + 0.4
	for i = 0, segments - 1 do
		local angle = i * (TAU / segments)
		local cf = CFrame.new(center)
			* CFrame.Angles(0, angle, 0)
			* CFrame.new(0, height / 2, -radius / 2)
		Build.wedge(
			Vector3.new(width, height, radius),
			cf,
			if i % 2 == 0 then Palette.red else Palette.white,
			parent,
			{ name = "Roof" }
		)
		local rim = Build.polar(angle + math.pi, radius - 0.3, center.Y - 0.2)
		Build.ball(2.3, rim, if i % 2 == 0 then Palette.white else Palette.red, parent, FLAT)
	end
end

local function buildHub(map: Instance)
	local hub = Build.model("Hub", map)
	local plazaTop = 0.3
	Build.disc(
		Island.PLAZA_RADIUS * 2,
		1,
		CFrame.new(0, plazaTop - 0.5, 0),
		Palette.plaza,
		hub,
		{ name = "Plaza" }
	)
	Build.ring(CFrame.new(0, plazaTop - 0.02, 0), 26, 2.2, 0.1, 48, Palette.plazaDark, hub, FLAT)
	Build.ring(CFrame.new(0, plazaTop - 0.02, 0), 18.5, 1.4, 0.1, 40, Palette.plazaDark, hub, FLAT)
	Build.ring(
		CFrame.new(0, plazaTop + 0.1, 0),
		Island.PLAZA_RADIUS,
		1.4,
		0.8,
		64,
		Palette.stone,
		hub,
		FLAT
	)

	-- planters and lamps between the paths
	local gen = Rng.new(11)
	for i = 0, Config.PLOT_COUNT - 1 do
		local angle = (i + 0.5) * PLOT_ANGLE
		local planter = Build.polar(angle, 31, plazaTop)
		Build.disc(
			7.5,
			1.6,
			CFrame.new(planter + Vector3.new(0, 0.8, 0)),
			Palette.stone,
			hub,
			GROUND
		)
		Build.disc(
			6.4,
			0.3,
			CFrame.new(planter + Vector3.new(0, 1.55, 0)),
			Palette.dirtDark,
			hub,
			FLAT
		)
		Props.flowers(planter + Vector3.new(0, 1.6, 0), 1.15, gen, hub)
		Props.lamp(Build.polar(angle, 37.5, plazaTop), 1, hub)
	end

	-- the shop: stone base, round counter, striped pillars, candy tent
	local baseTop = plazaTop + 1
	Build.disc(
		25,
		1,
		CFrame.new(0, baseTop - 0.5, 0),
		Palette.stoneLight,
		hub,
		{ name = "ShopBase" }
	)
	local counterTop = baseTop + 3.6
	Build.disc(18, 3, CFrame.new(0, baseTop + 1.5, 0), Palette.wood, hub, { name = "Counter" })
	Build.disc(18.4, 0.8, CFrame.new(0, baseTop + 1.7, 0), Palette.red, hub, FLAT)
	Build.disc(
		19.6,
		0.6,
		CFrame.new(0, counterTop - 0.3, 0),
		Palette.woodLight,
		hub,
		{ name = "CounterTop" }
	)
	for i, egg in EggData.LIST do
		local angle = math.rad(45) + (i - 1) * (TAU / #EggData.LIST)
		local model = EggModel.build(EggModel.lookForShopEgg(egg.id), 2.8, true)
		model.Name = egg.id .. "Display"
		model:PivotTo(CFrame.new(Build.polar(angle, 6.6, counterTop)))
		model.Parent = hub
	end
	local rimY = counterTop + 9.5
	for i = 0, 3 do
		local angle = i * (TAU / 4)
		local foot = Build.polar(angle, 8.6, counterTop)
		stripedPillar(foot, foot + Vector3.new(0, rimY + 3 - counterTop, 0), hub)
	end
	tent(Vector3.new(0, rimY, 0), Island.SHOP_RADIUS, 9, hub)
	-- a giant spotted egg crowns the tent, with a baby dino on top
	Build.disc(6.4, 1.4, CFrame.new(0, rimY + 8.2, 0), Palette.yellow, hub, { decor = true })
	local eggCenter = Vector3.new(0, rimY + 9 + 3.2, 0)
	Build.ellipsoid(
		Vector3.new(6.4, 8, 6.4),
		CFrame.new(eggCenter),
		Palette.cream,
		hub,
		{ name = "BigEgg" }
	)
	for i = 1, 6 do
		local a = i * 1.05
		local e = math.rad(if i % 2 == 0 then 10 else -25)
		local p = eggCenter
			+ Vector3.new(
				math.cos(e) * math.sin(a) * 3.15,
				math.sin(e) * 4,
				math.cos(e) * math.cos(a) * 3.15
			)
		Build.ball(
			1.3,
			p,
			if i % 3 == 0 then Palette.purple elseif i % 3 == 1 then Palette.mint else Palette.orange,
			hub,
			FLAT
		)
	end
	local baby = DinoModel.build("Raptor", 3, nil, "Static")
	baby.Name = "ShopMascot"
	baby:PivotTo(CFrame.new(eggCenter + Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, math.pi, 0))
	baby.Parent = hub

	-- invisible prompt target in the middle of the counter
	local promptPart =
		Build.block(Vector3.new(4, 4, 4), CFrame.new(0, counterTop - 1.5, 0), Palette.white, hub, {
			name = "ShopPrompt",
			transparency = 1,
			collide = false,
		})
	return hub, promptPart
end

-- ===== Volcano =====

-- Low-poly volcano: three frustum bands of wedge facets (gentle foot, steep
-- cone, steeper top) give a concave cartoon profile. Facets alternate between
-- two shades, lava runs straight down facet centre lines.
local VOLCANO_BANDS = {
	{
		r0 = 46,
		r1 = 31,
		y0 = 0,
		y1 = 11,
		light = Color3.fromRGB(150, 118, 104),
		dark = Color3.fromRGB(136, 106, 96),
	},
	{
		r0 = 31,
		r1 = 18,
		y0 = 11,
		y1 = 34,
		light = Color3.fromRGB(132, 102, 98),
		dark = Color3.fromRGB(118, 92, 90),
	},
	{
		r0 = 18,
		r1 = 13,
		y0 = 34,
		y1 = 46,
		light = Color3.fromRGB(112, 86, 88),
		dark = Color3.fromRGB(98, 76, 80),
	},
}
local VOLCANO_FACETS = 24

local function volcanoRadiusAt(y: number): number
	for _, band in VOLCANO_BANDS do
		if y <= band.y1 then
			local t = math.clamp((y - band.y0) / (band.y1 - band.y0), 0, 1)
			return band.r0 + (band.r1 - band.r0) * t
		end
	end
	return VOLCANO_BANDS[#VOLCANO_BANDS].r1
end

local function buildVolcano(map: Instance)
	local volcano = Build.model("Volcano", map)
	local base = Island.VOLCANO_POSITION
	local bottom = -1.2
	local step = TAU / VOLCANO_FACETS
	for b, band in VOLCANO_BANDS do
		local h = band.y1 - band.y0
		local depth = band.r0 - band.r1
		local width = 2 * band.r0 * math.sin(step / 2) + 0.35
		for i = 0, VOLCANO_FACETS - 1 do
			-- offset odd bands by half a facet so seams don't line up
			local angle = (i + (b % 2) * 0.5) * step
			local cf = CFrame.new(base.X, bottom + band.y0, base.Z)
				* CFrame.Angles(0, angle, 0)
				* CFrame.new(0, h / 2, -(band.r1 + depth / 2))
			Build.wedge(
				Vector3.new(width, h, depth),
				cf,
				if i % 2 == 0 then band.light else band.dark,
				volcano,
				{
					name = "Rock",
					decor = true,
				}
			)
		end
		Build.disc(
			band.r1 * 2 + 0.6,
			h,
			CFrame.new(base.X, bottom + band.y0 + h / 2, base.Z),
			band.dark,
			volcano,
			{
				name = "Core",
				decor = true,
				shadow = false,
			}
		)
	end
	local top = bottom + VOLCANO_BANDS[#VOLCANO_BANDS].y1
	local rim = VOLCANO_BANDS[#VOLCANO_BANDS].r1
	for i = 0, 13 do
		local angle = i * (TAU / 14)
		Build.ellipsoid(
			Vector3.new(6, 3.2, 4.6),
			CFrame.new(base + Build.polar(angle, rim - 0.6, top + 0.4)) * CFrame.Angles(0, angle, 0),
			Color3.fromRGB(84, 64, 70),
			volcano,
			GROUND
		)
	end
	local pool =
		Build.disc(rim * 2 - 3, 0.6, CFrame.new(base.X, top + 0.1, base.Z), Palette.lava, volcano, {
			name = "Lava",
			material = Enum.Material.Neon,
			decor = true,
			shadow = false,
		})
	Build.disc(rim, 0.6, CFrame.new(base.X, top + 0.25, base.Z), Palette.lavaHot, volcano, {
		material = Enum.Material.Neon,
		decor = true,
		shadow = false,
	})
	local glow = Instance.new("PointLight")
	glow.Color = Palette.lava
	glow.Range = 60
	glow.Brightness = 2
	glow.Parent = pool
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(120, 112, 120))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 5),
		NumberSequenceKeypoint.new(1, 14),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(5, 8)
	smoke.Speed = NumberRange.new(5, 8)
	smoke.Rate = 5
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-20, 20)
	smoke.SpreadAngle = Vector2.new(12, 12)
	smoke.Parent = pool

	-- lava flows down the island-facing side (facets sit within 1% of the
	-- band radius, so a small lift keeps the flows on the surface)
	local lavaOptions =
		{ material = Enum.Material.Neon, decor = true, shadow = false, collide = false }
	local inward = math.atan2(-base.X, -base.Z)
	local facing = math.floor(inward / step + 0.5)
	for _, k in { -2, 1, 3 } do
		local angle = (facing + k + 0.5) * step
		local stopAt = if k == 1 then 0 else 9
		local points: { Vector3 } = {}
		for y = VOLCANO_BANDS[#VOLCANO_BANDS].y1 - 0.5, stopAt, -3.5 do
			table.insert(points, base + Build.polar(angle, volcanoRadiusAt(y) + 0.6, bottom + y))
		end
		for i = 1, #points - 1 do
			local t = i / #points
			Build.beam(
				points[i],
				points[i + 1],
				2.2 + t * 2.4,
				0.8,
				Palette.lava,
				volcano,
				lavaOptions
			)
		end
		local last = points[#points]
		Build.ellipsoid(
			Vector3.new(8, 1.2, 8),
			CFrame.new(last),
			Palette.lava,
			volcano,
			lavaOptions
		)
		Build.ellipsoid(
			Vector3.new(4, 1.4, 4),
			CFrame.new(last + Vector3.new(0, 0.1, 0)),
			Palette.lavaHot,
			volcano,
			lavaOptions
		)
	end
	local gen = Rng.new(5)
	for i = 0, 11 do
		local angle = i * (TAU / 12) + gen.next() * 0.3
		Props.rock(
			base + Build.polar(angle, Island.VOLCANO_RADIUS + 1.5, 0),
			1.7 + gen.next() * 1.2,
			gen,
			volcano
		)
	end
end

-- ===== Scattered props =====

local function insidePlot(position: Vector3, margin: number): boolean
	for i = 0, Config.PLOT_COUNT - 1 do
		local angle = i * PLOT_ANGLE
		local center = Build.polar(angle, Config.PLOT_RING_RADIUS)
		local offset = position - center
		-- plot axes: local Z points away from the hub
		local z = offset.X * math.sin(angle) + offset.Z * math.cos(angle)
		local x = offset.X * math.cos(angle) - offset.Z * math.sin(angle)
		if math.abs(x) < HALF + margin and math.abs(z) < HALF + margin then
			return true
		end
	end
	return false
end

local function nearPath(position: Vector3, margin: number): boolean
	local r = position.Magnitude
	if r < Island.PLAZA_RADIUS + margin then
		return true
	end
	if math.abs(r - Island.RING_PATH_RADIUS) < 6.5 + margin then
		return true
	end
	if r < Island.GATE_RADIUS + 14 then
		local angle = math.atan2(position.X, position.Z)
		for i = 0, Config.PLOT_COUNT - 1 do
			local diff = (angle - i * PLOT_ANGLE + math.pi) % TAU - math.pi
			if math.abs(math.sin(diff) * r) < 7.5 + margin and math.cos(diff) > 0 then
				return true
			end
		end
	end
	return false
end

local function onLand(position: Vector3, landList: { Land }, inset: number): boolean
	for _, land in landList do
		local flat = Vector3.new(position.X - land.center.X, 0, position.Z - land.center.Z)
		if flat.Magnitude < land.radius - inset then
			return true
		end
	end
	return false
end

type Spot = { position: Vector3, radius: number }

local function scatter(map: Instance, landList: { Land })
	local folder = Instance.new("Folder")
	folder.Name = "Decorations"
	local gen = Rng.new(2024)
	local taken: { Spot } = {}
	local function free(position: Vector3, radius: number): boolean
		if not onLand(position, landList, radius + 3) then
			return false
		end
		if insidePlot(position, radius + 4) or nearPath(position, radius) then
			return false
		end
		local volcano = Vector3.new(
			position.X - Island.VOLCANO_POSITION.X,
			0,
			position.Z - Island.VOLCANO_POSITION.Z
		)
		if volcano.Magnitude < Island.VOLCANO_RADIUS + radius + 6 then
			return false
		end
		for _, spot in taken do
			if (spot.position - position).Magnitude < spot.radius + radius then
				return false
			end
		end
		return true
	end
	local function place(
		count: number,
		radius: number,
		minR: number,
		maxR: number,
		build: (Vector3) -> ()
	)
		local placed = 0
		local tries = 0
		while placed < count and tries < count * 60 do
			tries += 1
			local angle = gen.next() * TAU
			local r = minR + (maxR - minR) * math.sqrt(gen.next())
			local p = Build.polar(angle, r)
			if free(p, radius) then
				table.insert(taken, { position = p, radius = radius })
				build(p)
				placed += 1
			end
		end
	end

	-- landmarks first: decorative egg nests and ponds in open meadows
	for _, spot in { Build.polar(PLOT_ANGLE * 4.5, 62), Build.polar(PLOT_ANGLE * 6.5, 150) } do
		if free(spot, 6) then
			table.insert(taken, { position = spot, radius = 6 })
			Props.eggNest(spot, 1.2, gen, folder)
		end
	end
	place(2, 10, 60, 175, function(p)
		Props.pond(p, 1 + gen.next() * 0.3, gen, folder)
	end)
	local reach = Island.LAND_RADIUS + 45 -- peninsulas reach past the main disc
	place(40, 5, 50, reach, function(p)
		Props.tree(p, 0.9 + gen.next() * 0.45, gen, folder)
	end)
	place(22, 4, 115, reach, function(p)
		Props.pine(p, 0.9 + gen.next() * 0.4, gen, folder)
	end)
	place(30, 3, 45, reach, function(p)
		Props.fern(p, 0.9 + gen.next() * 0.5, gen, folder)
	end)
	place(36, 3, 45, reach, function(p)
		Props.bush(p, 0.8 + gen.next() * 0.5, gen, folder)
	end)
	place(24, 2.5, 45, reach, function(p)
		Props.flowers(p, 1 + gen.next() * 0.3, gen, folder)
	end)
	place(18, 3, 60, reach, function(p)
		Props.rock(p, 0.8 + gen.next() * 0.8, gen, folder)
	end)
	place(14, 2.5, 50, reach, function(p)
		Props.mushroom(p, 0.9 + gen.next() * 0.9, gen, folder)
	end)

	-- palms ring the beach
	for i, land in landList do
		if i > 1 and i < #landList then
			local outward = Vector3.new(land.center.X, 0, land.center.Z).Unit
			local p = land.center + outward * (land.radius - 3)
			p = Vector3.new(p.X, 0, p.Z)
			if free(p, 3) then
				table.insert(taken, { position = p, radius = 3 })
				Props.palm(p, 1 + gen.next() * 0.3, gen, folder)
			end
		end
	end
	place(14, 3, 170, reach, function(p)
		Props.palm(p, 0.95 + gen.next() * 0.3, gen, folder)
	end)

	-- path lamps where the ring path meets each spoke
	for i = 0, Config.PLOT_COUNT - 1 do
		local angle = i * PLOT_ANGLE
		local center = Build.polar(angle, Island.RING_PATH_RADIUS)
		local outward = Build.polar(angle, 1)
		local side = Vector3.new(outward.Z, 0, -outward.X)
		Props.lamp(center + side * 9.5 + outward * 7, 0.9, folder)
	end
	folder.Parent = map
end

-- ===== Sky and horizon =====

local function buildSky(map: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Sky"
	local gen = Rng.new(99)
	for i = 0, 13 do
		local angle = i * (TAU / 14) + gen.next() * 0.3
		local r = 150 + gen.next() * 300
		Props.cloud(
			Build.polar(angle, r, 100 + gen.next() * 45),
			0.8 + gen.next() * 0.7,
			gen,
			folder
		)
	end
	folder.Parent = map
end

local function buildIslets(map: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Islets"
	local gen = Rng.new(31)
	local spots = { { 0.6, 470 }, { 1.9, 560 }, { 3.0, 430 }, { 4.2, 600 }, { 5.3, 500 } }
	for _, spot in spots do
		local center = Build.polar(spot[1], spot[2])
		local radius = 16 + gen.next() * 14
		local land = { { center = center, radius = radius } }
		buildCoast(folder, land)
		Props.palm(center + Vector3.new(radius * 0.2, 0, -radius * 0.1), 1.2, gen, folder)
		Props.palm(center + Vector3.new(-radius * 0.35, 0, radius * 0.25), 1, gen, folder)
		Props.bush(center + Vector3.new(radius * 0.3, 0, radius * 0.35), 1, gen, folder)
	end
	folder.Parent = map
end

-- Builds everything and returns the shop's prompt part.
function Island.build(map: Instance): BasePart
	local landList = lands()
	buildOcean(map)
	buildCoast(map, landList)
	buildPaths(map)
	buildFootprints(map)
	local _, shopPrompt = buildHub(map)
	buildVolcano(map)
	scatter(map, landList)
	buildSky(map)
	buildIslets(map)
	return shopPrompt
end

return Island
