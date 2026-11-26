--!strict
-- Everything built from parts on top of the terrain (see Ground for the
-- valley itself): three wooden docks, a log cabin with a porch, a campfire
-- with log seats, lanterns along the path, reeds and lily pads, a pine
-- forest climbing toward the mountains, the welcome sign, the leaderboards
-- and the invisible walls that keep everyone out of the lake. Decorations
-- come from fixed random seeds, so every server looks the same.
--
-- Everything stands on Land.height(x, z). Angles: 0 points along +Z.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Lake = require(ReplicatedStorage.Shared.Lake)
local Land = require(ReplicatedStorage.Shared.Land)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Rng = require(ReplicatedStorage.Shared.Util.Rng)
local Tags = require(ReplicatedStorage.Shared.Tags)
local BoardData = require(script.Parent.BoardData)
local Boards = require(script.Parent.Boards)
local Build = require(script.Parent.Build)
local Props = require(script.Parent.Props)

local Scenery = {}

local TAU = 2 * math.pi
local R = Config.LAKE_RADIUS
local BEACH_OUT = R + Config.SHORE_WIDTH

Scenery.WALL_HEIGHT = 12 -- invisible walls: taller than anyone can jump
Scenery.SHORE_WALL = Land.SHORE -- the wall along the water's edge
Scenery.PATH_RADIUS = Land.PATH_RADIUS
Scenery.PLAY_RADIUS = 340 -- an invisible fence keeps everyone this close
Scenery.CABIN_ANGLE = math.rad(200)
Scenery.CABIN_RADIUS = 162
Scenery.CAMPFIRE_ANGLE = math.rad(75)
Scenery.CAMPFIRE_RADIUS = 148
Scenery.SPAWN_ANGLE = math.rad(27)
Scenery.SPAWN_RADIUS = BEACH_OUT + 14
Scenery.BOARD_ANGLES = { math.rad(184), math.rad(216) }
Scenery.BOARD_RADIUS = BEACH_OUT + 16

export type Built = {
	root: Folder,
	spawn: SpawnLocation,
	boards: { [string]: SurfaceGui }, -- "Skips" / "Distance"
}

type Spot = { position: Vector3, radius: number }

local WOOD: Build.Options = { material = Enum.Material.Wood }
local PLANKS: Build.Options = { material = Enum.Material.WoodPlanks }

local function with(options: Build.Options, extra: Build.Options): Build.Options
	local merged: Build.Options = table.clone(options)
	for key, value in extra :: any do
		(merged :: any)[key] = value
	end
	return merged
end

-- A point on the ground at `angle` and `radius` from the lake's centre.
local function ground(angle: number, radius: number, lift: number?): Vector3
	local p = Build.polar(angle, radius)
	return Land.at(p.X, p.Z, lift)
end

-- Faces the centre of the lake from `position` (its -Z looks at the water).
local function facingLake(position: Vector3): CFrame
	return CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
end

local function angleGap(a: number, b: number): number
	local d = (a - b) % TAU
	return math.min(d, TAU - d)
end

local function nearDock(angle: number, radius: number, margin: number): boolean
	for _, dockAngle in Lake.DOCK_ANGLES do
		if angleGap(angle, dockAngle) * radius < Lake.DOCK_WIDTH / 2 + margin then
			return true
		end
	end
	return false
end

-- ===== Invisible walls =====
-- One along the water's edge and around each dock so nobody walks or jumps
-- into the lake, one round the edge of the play area. They ignore raycasts,
-- so the camera never bumps into them.

local FENCE: Build.Options = { name = "Fence", transparency = 1, shadow = false }

local function wall(size: Vector3, cframe: CFrame, parent: Instance)
	local part = Build.block(size, cframe, Palette.white, parent, FENCE)
	part.CanQuery = false
	part.CanTouch = false
end

local function buildFences(root: Instance)
	local fences = Build.model("Fences", root)
	local h = Scenery.WALL_HEIGHT
	local radius = Scenery.SHORE_WALL
	local segments = 180
	local step = TAU / segments
	local length = 2 * radius * math.tan(step / 2) + 0.1
	for i = 0, segments - 1 do
		local angle = i * step
		if not nearDock(angle, radius, length / 2) then
			wall(
				Vector3.new(length, h, 0.5),
				CFrame.lookAt(Build.polar(angle, radius, h / 2 - 1), Vector3.new(0, h / 2 - 1, 0)),
				fences
			)
		end
	end
	-- each dock: walls down both sides (from the beach out) and across the end,
	-- plus short pieces along the shore that close the gap beside it
	local half = Lake.DOCK_WIDTH / 2
	for _, angle in Lake.DOCK_ANGLES do
		local inner, outerEnd = Lake.DOCK_INNER, radius + 2
		local frame =
			CFrame.lookAt(Build.polar(angle, (inner + outerEnd) / 2), Build.polar(angle, inner))
		local dockLength = outerEnd - inner
		for _, side in { -1, 1 } do
			wall(
				Vector3.new(0.5, h, dockLength),
				frame * CFrame.new(side * (half + 0.25), h / 2 - 1, 0),
				fences
			)
			local shore = CFrame.lookAt(Build.polar(angle, radius), Vector3.zero)
			local span = step * radius + 2.5
			wall(
				Vector3.new(span, h, 0.5),
				shore * CFrame.new(side * (half + 0.5 + span / 2), h / 2 - 1, 0),
				fences
			)
		end
		wall(
			Vector3.new(Lake.DOCK_WIDTH + 1, h, 0.5),
			frame * CFrame.new(0, h / 2 - 1, -dockLength / 2 - 0.25),
			fences
		)
	end
	local outer = Build.ring(
		CFrame.new(0, 20, 0),
		Scenery.PLAY_RADIUS,
		1,
		44,
		120,
		Palette.white,
		fences,
		FENCE
	)
	for _, part in outer do
		part.CanQuery = false
		part.CanTouch = false
	end
end

-- ===== Lanterns =====

local function lantern(position: Vector3, parent: Instance, height: number?)
	local h = height or 6
	local m = Build.model("Lantern", parent)
	local dark = Palette.woodDark
	Build.block(
		Vector3.new(0.6, h + 1, 0.6),
		CFrame.new(position + Vector3.new(0, (h - 1) / 2, 0)),
		dark,
		m,
		with(WOOD, { name = "Post" })
	)
	Build.block(
		Vector3.new(1.7, 0.3, 0.5),
		CFrame.new(position + Vector3.new(0.55, h - 0.2, 0)),
		dark,
		m,
		with(WOOD, { decor = true })
	)
	local glass = Build.block(
		Vector3.new(0.8, 1, 0.8),
		CFrame.new(position + Vector3.new(1.1, h - 0.95, 0)),
		Palette.lantern,
		m,
		{
			name = "Glow",
			material = Enum.Material.Neon,
			decor = true,
			collide = false,
			shadow = false,
		}
	)
	for _, y in { h - 0.38, h - 1.52 } do
		Build.block(
			Vector3.new(1.05, 0.18, 1.05),
			CFrame.new(position + Vector3.new(1.1, y, 0)),
			Palette.iron,
			m,
			{ decor = true, collide = false, material = Enum.Material.Metal }
		)
	end
	local light = Instance.new("PointLight")
	light.Color = Palette.lantern
	light.Range = 18
	light.Brightness = 1.6
	light.Shadows = true
	light.Enabled = false
	light.Parent = glass
	CollectionService:AddTag(light, Tags.NIGHT_LIGHT)
end

-- ===== Docks =====

local function buildDock(angle: number, index: number, parent: Instance)
	local dock = Build.model("Dock" .. index, parent)
	local inner, outer = Lake.DOCK_INNER, Lake.DOCK_OUTER
	local length = outer - inner
	local deckY = Lake.DOCK_TOP - 0.25
	-- local -Z points along the dock toward the lake
	local frame = CFrame.lookAt(
		Build.polar(angle, (inner + outer) / 2, deckY),
		Build.polar(angle, inner, deckY)
	)
	local gen = Rng.new(40 + index)
	local planks = math.floor(length / 1.25)
	for i = 0, planks - 1 do
		local z = length / 2 - 0.62 - i * 1.25
		Build.block(
			Vector3.new(Lake.DOCK_WIDTH, 0.5, 1.14),
			frame * CFrame.new(0, (gen.next() - 0.5) * 0.04, z),
			if i % 3 == 0
				then Palette.woodLight
				elseif i % 3 == 1 then Palette.wood
				else Palette.weathered,
			dock,
			with(PLANKS, { name = "Plank", shadow = false })
		)
	end
	for _, side in { -1, 1 } do
		Build.block(
			Vector3.new(0.5, 0.7, length),
			frame * CFrame.new(side * (Lake.DOCK_WIDTH / 2 - 0.25), -0.55, 0),
			Palette.woodDark,
			dock,
			with(WOOD, { decor = true, shadow = false })
		)
		-- posts down into the lake bed (only where the dock is over the water)
		for z = -length / 2 + 1, length / 2, 6 do
			local top = (frame * CFrame.new(side * (Lake.DOCK_WIDTH / 2 - 0.3), 0.55, z)).Position
			local floor = Land.height(top.X, top.Z)
			if floor < 0.3 then
				Build.rod(
					top,
					Vector3.new(top.X, floor - 1.5, top.Z),
					0.9,
					Palette.woodDark,
					dock,
					with(WOOD, {
						decor = true,
						shadow = false,
					})
				)
			end
		end
	end
	-- a lantern on the end, a crate and a coil of rope
	lantern(
		(frame * CFrame.new(Lake.DOCK_WIDTH / 2 - 0.4, 0.25, -length / 2 + 1)).Position,
		dock,
		5.5
	)
	Build.block(
		Vector3.new(1.6, 1.2, 1.6),
		frame
			* CFrame.new(-Lake.DOCK_WIDTH / 2 + 1.1, 0.85, -length / 2 + 4)
			* CFrame.Angles(0, 0.3, 0),
		Palette.woodLight,
		dock,
		with(PLANKS, { name = "Crate", decor = true })
	)
	Build.disc(
		1.5,
		0.35,
		frame * CFrame.new(-Lake.DOCK_WIDTH / 2 + 1.2, 0.42, -length / 2 + 6.2),
		Palette.rope,
		dock,
		{ name = "Rope", decor = true, collide = false, material = Enum.Material.Fabric }
	)
end

-- ===== Cabin and campfire =====

local function window(cf: CFrame, parent: Instance)
	local glass = Build.block(Vector3.new(2.6, 2.2, 0.3), cf, Palette.window, parent, {
		name = "Window",
		material = Enum.Material.Glass,
		transparency = 0.2,
		decor = true,
		shadow = false,
	})
	CollectionService:AddTag(glass, Tags.WINDOW)
	-- frame and sill
	for _, x in { -1.4, 1.4 } do
		Build.block(
			Vector3.new(0.25, 2.5, 0.4),
			cf * CFrame.new(x, 0, 0),
			Palette.cream,
			parent,
			with(WOOD, {
				decor = true,
				shadow = false,
			})
		)
	end
	Build.block(
		Vector3.new(3.2, 0.25, 0.5),
		cf * CFrame.new(0, 1.25, 0),
		Palette.cream,
		parent,
		with(WOOD, {
			decor = true,
			shadow = false,
		})
	)
	Build.block(
		Vector3.new(3.4, 0.3, 0.7),
		cf * CFrame.new(0, -1.3, 0.05),
		Palette.cream,
		parent,
		with(WOOD, {
			decor = true,
			shadow = false,
		})
	)
end

local function buildCabin(root: Instance)
	local cabin = Build.model("Cabin", root)
	local base = ground(Scenery.CABIN_ANGLE, Scenery.CABIN_RADIUS)
	local f = facingLake(base) -- front faces the lake
	local w, d, h = 16, 12, 7
	-- a deep stone footing so the floor never floats on the meadow
	Build.block(
		Vector3.new(w + 6.4, 3, d + 8.4),
		f * CFrame.new(0, -1.15, -2),
		Palette.rock,
		cabin,
		{
			name = "Footing",
			material = Enum.Material.Cobblestone,
		}
	)
	Build.block(
		Vector3.new(w + 6, 0.5, d + 8),
		f * CFrame.new(0, 0.6, -2),
		Palette.wood,
		cabin,
		with(PLANKS, {
			name = "Floor",
		})
	)
	local wallY = h / 2 + 0.85
	-- log walls (the front wall has a door)
	for _, side in { -1, 1 } do
		Build.block(
			Vector3.new(0.9, h, d),
			f * CFrame.new(side * w / 2, wallY, 2),
			Palette.logs,
			cabin,
			WOOD
		)
	end
	Build.block(
		Vector3.new(w, h, 0.9),
		f * CFrame.new(0, wallY, 2 + d / 2),
		Palette.logs,
		cabin,
		WOOD
	)
	for _, side in { -1, 1 } do
		Build.block(
			Vector3.new(w / 2 - 1.6, h, 0.9),
			f * CFrame.new(side * (w / 4 + 0.8), wallY, 2 - d / 2),
			Palette.logs,
			cabin,
			WOOD
		)
	end
	Build.block(
		Vector3.new(3.2, 1.6, 0.9),
		f * CFrame.new(0, h + 0.05, 2 - d / 2),
		Palette.logs,
		cabin,
		WOOD
	)
	-- round log ends at the corners
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local corner = f * CFrame.new(sx * w / 2, 0, 2 + sz * d / 2)
			Build.rod(
				corner.Position + Vector3.new(0, 0.85, 0),
				corner.Position + Vector3.new(0, h + 0.85, 0),
				1.3,
				Palette.woodDark,
				cabin,
				WOOD
			)
		end
	end
	window(f * CFrame.new(-w / 4 - 0.8, 4.6, 2 - d / 2 - 0.5), cabin)
	window(f * CFrame.new(w / 4 + 0.8, 4.6, 2 - d / 2 - 0.5), cabin)
	window(f * CFrame.new(w / 2 + 0.5, 4.6, 2) * CFrame.Angles(0, math.pi / 2, 0), cabin)
	-- the door, with a little brass knob
	local door = f * CFrame.new(0, 3.55, 2 - d / 2 + 0.1)
	Build.block(
		Vector3.new(3.2, 5.4, 0.4),
		door,
		Palette.woodDark,
		cabin,
		with(PLANKS, { name = "Door" })
	)
	Build.ball(0.35, (door * CFrame.new(1.1, -0.2, -0.3)).Position, Palette.brass, cabin, {
		decor = true,
		collide = false,
		material = Enum.Material.Metal,
	})
	-- roof: two shingled slopes and a ridge beam
	local roofY = h + 0.85
	for _, side in { -1, 1 } do
		Build.wedge(
			Vector3.new(d + 3, 5, w / 2 + 1.5),
			-- the tall back of each wedge (+Z) meets the other at the ridge
			f
				* CFrame.new(side * (w / 4 + 0.75), roofY + 2.5, 2)
				* CFrame.Angles(0, -side * math.pi / 2, 0),
			Palette.roof,
			cabin,
			{ name = "Roof", material = Enum.Material.RoofShingles }
		)
	end
	Build.block(
		Vector3.new(1, 0.8, d + 3),
		f * CFrame.new(0, roofY + 5.2, 2),
		Palette.woodDark,
		cabin,
		with(WOOD, {
			decor = true,
		})
	)
	-- stone chimney with a wisp of smoke
	local chimney = Build.block(
		Vector3.new(2.2, 7, 2.2),
		f * CFrame.new(w / 4 + 1, roofY + 3.5, 5),
		Palette.rock,
		cabin,
		{
			name = "Chimney",
			material = Enum.Material.Cobblestone,
		}
	)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(226, 226, 232))
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 5),
	})
	smoke.Lifetime = NumberRange.new(5, 8)
	smoke.Rate = 3
	smoke.Speed = NumberRange.new(2, 3)
	smoke.SpreadAngle = Vector2.new(10, 10)
	smoke.Acceleration = Vector3.new(1, 0.3, 0)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Parent = chimney
	-- porch: posts, a little roof and two chairs facing the lake
	for _, side in { -1, 1 } do
		Build.block(
			Vector3.new(0.6, h, 0.6),
			f * CFrame.new(side * (w / 2 + 2), h / 2 + 0.85, -d / 2 - 2.5),
			Palette.woodDark,
			cabin,
			WOOD
		)
	end
	Build.block(
		Vector3.new(w + 6, 0.5, 6.6),
		f * CFrame.new(0, h + 0.65, -d / 2 - 1.75) * CFrame.Angles(math.rad(-12), 0, 0),
		Palette.roof,
		cabin,
		{ decor = true, material = Enum.Material.RoofShingles }
	)
	for _, side in { -1, 1 } do
		local seatCf = f * CFrame.new(side * 4.5, 1.95, -d / 2 - 1.4)
		Build.block(
			Vector3.new(1.8, 0.8, 1.8),
			seatCf * CFrame.new(0, -0.7, 0),
			Palette.woodDark,
			cabin,
			WOOD
		)
		local seat = Instance.new("Seat")
		seat.Name = "PorchChair"
		seat.Anchored = true
		seat.Size = Vector3.new(2.2, 0.6, 2.2)
		seat.CFrame = seatCf
		seat.Color = Palette.woodLight
		seat.Material = Enum.Material.WoodPlanks
		seat.TopSurface = Enum.SurfaceType.Smooth
		seat.BottomSurface = Enum.SurfaceType.Smooth
		seat.Parent = cabin
		Build.block(
			Vector3.new(2.2, 2.4, 0.4),
			seatCf * CFrame.new(0, 1.2, 1.1),
			Palette.woodLight,
			cabin,
			with(PLANKS, {
				decor = true,
			})
		)
	end
	-- a stack of firewood along the side wall (three logs, two on top)
	for i = 0, 4 do
		local row = if i < 3 then 0 else 1
		local slot = if row == 0 then i else i - 3 + 0.5
		local log = f * CFrame.new(-w / 2 - 1 - slot * 0.85, 1.3 + row * 0.75, 2)
		Build.rod(
			log.Position + f.LookVector * 1.2,
			log.Position - f.LookVector * 1.2,
			0.85,
			Palette.bark,
			cabin,
			with(WOOD, { decor = true })
		)
	end
end

local function buildCampfire(root: Instance)
	local camp = Build.model("Campfire", root)
	local center = ground(Scenery.CAMPFIRE_ANGLE, Scenery.CAMPFIRE_RADIUS)
	local gen = Rng.new(77)
	for i = 0, 9 do
		local a = i * (TAU / 10)
		Build.ellipsoid(
			Vector3.new(1.5, 0.9, 1.3) * (0.9 + gen.next() * 0.3),
			CFrame.new(center + Vector3.new(math.sin(a) * 2.3, 0.25, math.cos(a) * 2.3))
				* CFrame.Angles(0, a, 0),
			if i % 2 == 0 then Palette.rock else Palette.rockDark,
			camp,
			{ decor = true, material = Enum.Material.Rock }
		)
	end
	for i = 0, 3 do
		local a = i * (TAU / 4) + 0.4
		local dir = Vector3.new(math.sin(a), 0, math.cos(a))
		Build.rod(
			center + dir * 1.7 + Vector3.new(0, 0.2, 0),
			center - dir * 0.2 + Vector3.new(0, 1.3, 0),
			0.5,
			Palette.bark,
			camp,
			with(WOOD, { decor = true, collide = false })
		)
	end
	local embers =
		Build.disc(2.6, 0.2, CFrame.new(center + Vector3.new(0, 0.2, 0)), Palette.ember, camp, {
			name = "Embers",
			material = Enum.Material.Neon,
			decor = true,
			collide = false,
			shadow = false,
		})
	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Heat = 7
	fire.Color = Palette.fire
	fire.SecondaryColor = Palette.yellow
	fire.Parent = embers
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Color = ColorSequence.new(Palette.yellow, Palette.fire)
	sparks.LightEmission = 1
	sparks.Rate = 4
	sparks.Lifetime = NumberRange.new(1, 2)
	sparks.Speed = NumberRange.new(3, 6)
	sparks.SpreadAngle = Vector2.new(25, 25)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Parent = embers
	local glow = Instance.new("PointLight")
	glow.Color = Palette.fire
	glow.Range = 22
	glow.Brightness = 2
	glow.Shadows = true
	glow.Parent = embers
	-- three log benches you can sit on, facing the fire
	for i = 0, 2 do
		local a = i * (TAU / 3) + math.rad(30)
		local spot = Land.at(center.X + math.sin(a) * 6.5, center.Z + math.cos(a) * 6.5)
		local cf = CFrame.lookAt(spot, Vector3.new(center.X, spot.Y, center.Z)) -- -Z faces the fire
		Build.rod(
			(cf * CFrame.new(-2.3, 0.7, 0)).Position,
			(cf * CFrame.new(2.3, 0.7, 0)).Position,
			1.5,
			Palette.bark,
			camp,
			with(WOOD, { name = "Log" })
		)
		local seat = Instance.new("Seat")
		seat.Name = "LogSeat"
		seat.Anchored = true
		seat.Transparency = 1
		seat.Size = Vector3.new(2, 0.4, 1.4)
		seat.CFrame = cf * CFrame.new(0, 1.45, 0) -- sitters face the fire
		seat.Parent = camp
	end
end

-- ===== Shore details =====

local function reeds(base: Vector3, gen: Rng.Generator, parent: Instance, tall: number)
	local m = Build.model("Reeds", parent)
	local options: Build.Options =
		{ decor = true, collide = false, shadow = false, material = Enum.Material.Grass }
	for i = 1, 7 do
		local a = gen.next() * TAU
		local r = gen.next() * 1.8
		local foot = Land.at(base.X + math.sin(a) * r, base.Z + math.cos(a) * r, -0.3)
		local height = tall + gen.next() * 2.2
		local lean = Vector3.new(gen.next() - 0.5, 0, gen.next() - 0.5) * 0.7
		local tip = Vector3.new(foot.X, math.max(foot.Y, 0) + height, foot.Z) + lean
		Build.rod(
			foot,
			tip,
			0.14,
			if i % 3 == 0 then Palette.reedDark else Palette.reed,
			m,
			options
		)
		if i % 2 == 0 then
			Build.ellipsoid(
				Vector3.new(0.38, 1, 0.38),
				CFrame.lookAt(tip - (tip - foot).Unit * 0.9, tip),
				Palette.cattail,
				m,
				{ decor = true, collide = false, shadow = false }
			)
		end
	end
end

local function lilyPads(center: Vector3, gen: Rng.Generator, parent: Instance)
	local m = Build.model("LilyPads", parent)
	local options: Build.Options =
		{ decor = true, collide = false, shadow = false, material = Enum.Material.LeafyGrass }
	for i = 1, 4 do
		local a = gen.next() * TAU
		local r = gen.next() * 3
		local p = center + Vector3.new(math.sin(a) * r, 0.05, math.cos(a) * r)
		local size = 1.6 + gen.next() * 1.2
		Build.disc(
			size,
			0.06,
			CFrame.new(p),
			if i % 2 == 0 then Palette.lily else Palette.leafDark,
			m,
			options
		)
		if i == 1 and gen.next() < 0.6 then
			for k = 0, 4 do
				local petal = k * (TAU / 5)
				Build.ellipsoid(
					Vector3.new(0.32, 0.22, 0.6),
					CFrame.new(
						p + Vector3.new(math.sin(petal) * 0.22, 0.18, math.cos(petal) * 0.22)
					)
						* CFrame.Angles(0, petal, 0)
						* CFrame.Angles(math.rad(-30), 0, 0),
					Palette.pink,
					m,
					{ decor = true, collide = false, shadow = false }
				)
			end
		end
	end
end

local function buildShore(root: Instance)
	local shore = Build.model("Shore", root)
	local gen = Rng.new(5)
	-- smooth pebbles scattered over the beach
	local pebbles = { Palette.pebbleLight, Palette.pebble, Palette.pebbleDark, Palette.rockLight }
	for _ = 1, 240 do
		local a = gen.next() * TAU
		local r = Scenery.SHORE_WALL + 0.8 + gen.next() * (BEACH_OUT - Scenery.SHORE_WALL - 1.5)
		if not nearDock(a, r, 1) then
			local size = 0.35 + gen.next() * 0.8
			local p = ground(a, r, size * 0.1)
			Build.ellipsoid(
				Vector3.new(size, size * 0.45, size * (0.7 + gen.next() * 0.4)),
				CFrame.new(p) * CFrame.Angles(0, gen.next() * TAU, 0),
				pebbles[gen.int(1, #pebbles)],
				shore,
				{ decor = true, collide = false, shadow = false, material = Enum.Material.Slate }
			)
		end
	end
	-- reeds standing in the shallows and along the top of the bank
	for i = 0, 31 do
		local a = i * (TAU / 32) + gen.next() * 0.12
		if not nearDock(a, R, 5) and angleGap(a, Scenery.SPAWN_ANGLE) > 0.1 then
			if i % 2 == 0 then
				reeds(Build.polar(a, R - 2 - gen.next() * 3), gen, shore, 4.2)
			else
				reeds(Build.polar(a, Scenery.SHORE_WALL + 0.8 + gen.next() * 1.2), gen, shore, 2.6)
			end
		end
	end
	for i = 0, 13 do
		local a = i * (TAU / 14) + 0.11 + gen.next() * 0.2
		if not nearDock(a, R, 8) then
			lilyPads(Build.polar(a, R - 8 - gen.next() * 7, 0), gen, shore)
		end
	end
	-- lanterns along the path
	for i = 0, 11 do
		local a = i * (TAU / 12) + math.rad(7)
		if not nearDock(a, Scenery.PATH_RADIUS, 4) then
			lantern(ground(a, Scenery.PATH_RADIUS + 3.5, -0.2), shore)
		end
	end
	-- fireflies hovering over the beach (switched on at night by the client)
	for i = 0, 11 do
		local a = i * (TAU / 12) + gen.next() * 0.3
		local anchor = Build.block(
			Vector3.new(14, 4, 14),
			CFrame.new(ground(a, R + 10, 3)),
			Palette.white,
			shore,
			{
				name = "Fireflies",
				transparency = 1,
				collide = false,
				decor = true,
				shadow = false,
			}
		)
		local flies = Instance.new("ParticleEmitter")
		flies.Name = "Fireflies"
		flies.Color = ColorSequence.new(Color3.fromRGB(255, 236, 140))
		flies.LightEmission = 1
		flies.Rate = 3
		flies.Lifetime = NumberRange.new(3, 6)
		flies.Speed = NumberRange.new(0.3, 1)
		flies.SpreadAngle = Vector2.new(180, 180)
		flies.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.2, 0.25),
			NumberSequenceKeypoint.new(0.8, 0.25),
			NumberSequenceKeypoint.new(1, 0),
		})
		flies.Enabled = false
		flies.Parent = anchor
		CollectionService:AddTag(flies, Tags.FIREFLIES)
	end
end

-- ===== Forest =====

local function buildForest(root: Instance)
	local forest = Build.model("Forest", root)
	local gen = Rng.new(17)
	local taken: { Spot } = {
		{ position = Build.polar(Scenery.CABIN_ANGLE, Scenery.CABIN_RADIUS), radius = 22 },
		{ position = Build.polar(Scenery.CAMPFIRE_ANGLE, Scenery.CAMPFIRE_RADIUS), radius = 14 },
		{ position = Build.polar(Scenery.SPAWN_ANGLE, Scenery.SPAWN_RADIUS), radius = 12 },
	}
	for _, angle in Scenery.BOARD_ANGLES do
		table.insert(taken, { position = Build.polar(angle, Scenery.BOARD_RADIUS), radius = 10 })
	end
	local function free(p: Vector3, radius: number, maxSlope: number, maxHeight: number): boolean
		local r = Vector3.new(p.X, 0, p.Z).Magnitude
		if r < Scenery.PATH_RADIUS + 5 + radius then
			return false
		end
		-- nothing straddles the play area's fence
		if math.abs(r - Scenery.PLAY_RADIUS) < radius + 2 then
			return false
		end
		local a = math.atan2(p.X, p.Z)
		if nearDock(a, r, 6 + radius) and r < Lake.DOCK_OUTER + 14 then
			return false
		end
		if Land.slope(p.X, p.Z) > maxSlope or Land.height(p.X, p.Z) > maxHeight then
			return false
		end
		for _, spot in taken do
			if
				(Vector3.new(spot.position.X, 0, spot.position.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude
				< spot.radius + radius
			then
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
		maxSlope: number,
		maxHeight: number,
		build: (Vector3) -> ()
	)
		local placed, tries = 0, 0
		while placed < count and tries < count * 60 do
			tries += 1
			local a = gen.next() * TAU
			-- (no square root: denser near the lake than far out)
			local r = minR + (maxR - minR) * gen.next()
			local p = Build.polar(a, r)
			if free(p, radius, maxSlope, maxHeight) then
				table.insert(taken, { position = p, radius = radius })
				build(Land.at(p.X, p.Z, -0.3))
				placed += 1
			end
		end
	end
	-- tall pines crowd round the lake and climb the foothills
	place(170, 6, 146, 335, 0.5, 40, function(p)
		Props.pine(p, 1.2 + gen.next() * 0.9, gen, forest)
	end)
	place(220, 7, 345, 560, 0.65, 55, function(p)
		Props.pine(p, 1.5 + gen.next() * 1.1, gen, forest)
	end)
	place(40, 7, 140, 300, 0.4, 40, function(p)
		Props.tree(p, 1.05 + gen.next() * 0.45, gen, forest)
	end)
	place(50, 3, 136, 320, 0.5, 40, function(p)
		Props.bush(p, 0.7 + gen.next() * 0.5, gen, forest)
	end)
	place(30, 2.5, 136, 260, 0.4, 40, function(p)
		Props.flowers(p, 0.9 + gen.next() * 0.3, gen, forest)
	end)
	place(30, 3, 136, 320, 0.5, 40, function(p)
		Props.fern(p, 0.8 + gen.next() * 0.5, gen, forest)
	end)
	place(24, 4, 140, 330, 0.6, 40, function(p)
		Props.rock(p, 0.8 + gen.next() * 0.9, gen, forest)
	end)
	place(24, 7, 350, 520, 1, 70, function(p)
		Props.rock(p, 1.8 + gen.next() * 1.6, gen, forest)
	end)
end

-- ===== Welcome sign and leaderboards =====

local function buildSign(root: Instance)
	-- just in front of the spawn, between it and the beach, facing the spawn
	local base = ground(Scenery.SPAWN_ANGLE + 0.075, BEACH_OUT + 2.5)
	local f = facingLake(base) * CFrame.Angles(0, math.pi, 0)
	local sign = Build.model("WelcomeSign", root)
	for _, side in { -1, 1 } do
		Build.block(
			Vector3.new(0.6, 6, 0.6),
			f * CFrame.new(side * 3.2, 2.2, 0),
			Palette.woodDark,
			sign,
			WOOD
		)
	end
	local board = Build.block(
		Vector3.new(7.6, 3.4, 0.5),
		f * CFrame.new(0, 4.2, 0),
		Palette.woodLight,
		sign,
		with(PLANKS, {
			name = "Board",
		})
	)
	Build.block(Vector3.new(8.4, 0.35, 0.9), f * CFrame.new(0, 6.05, 0.05), Palette.roof, sign, {
		decor = true,
		material = Enum.Material.RoofShingles,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0.6
	gui.PixelsPerStud = 40
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.Parent = board
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(0.9, 0.5)
	title.Position = UDim2.fromScale(0.05, 0.06)
	title.Font = Enum.Font.FredokaOne
	title.Text = "Still Lake"
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(64, 42, 30)
	title.Parent = gui
	local line = title:Clone()
	line.Font = Enum.Font.BuilderSansMedium
	line.Text = "Walk to the water and skip a stone"
	line.Size = UDim2.fromScale(0.9, 0.26)
	line.Position = UDim2.fromScale(0.05, 0.62)
	line.Parent = gui
end

local function buildBoards(root: Instance): { [string]: SurfaceGui }
	local guis: { [string]: SurfaceGui } = {}
	local boards = Build.model("Leaderboards", root)
	for i, board in BoardData.BOARDS do
		local base = ground(Scenery.BOARD_ANGLES[i], Scenery.BOARD_RADIUS, -0.2)
		guis[board.key] =
			Boards.build(board.key, board.title, board.color, facingLake(base), boards)
	end
	return guis
end

-- ===== Everything =====

function Scenery.build(parent: Instance): Built
	local root = Instance.new("Folder")
	root.Name = "StillLake"
	buildFences(root)
	local docks = Build.model("Docks", root)
	for i, angle in Lake.DOCK_ANGLES do
		buildDock(angle, i, docks)
	end
	buildCabin(root)
	buildCampfire(root)
	buildShore(root)
	buildForest(root)
	buildSign(root)
	local boards = buildBoards(root)

	local spawnPosition = ground(Scenery.SPAWN_ANGLE, Scenery.SPAWN_RADIUS)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = facingLake(spawnPosition - Vector3.new(0, 0.4, 0))
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root

	root.Parent = parent
	return { root = root, spawn = spawn, boards = boards }
end

-- Is `angle` (around the lake) clear of the docks at `radius`?
function Scenery.clearOfDocks(angle: number, radius: number, margin: number): boolean
	return not nearDock(angle, radius, margin)
end

return Scenery
