--!strict
-- Builds Still Lake from parts when the server starts: a round lake with
-- sandy shallows and a pebble beach, three wooden docks, a cabin, a campfire
-- with log seats, a lantern-lit path, reeds and lily pads, forest, snowy
-- mountains on the horizon and fireflies for the night. Decorations come from
-- a fixed random seed, so every server looks the same.
--
-- Heights: water surface Y = 0, beach top BEACH_TOP, grass top GRASS_TOP.
-- Angles: 0 points along +Z, like Build.polar.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Lake = require(ReplicatedStorage.Shared.Lake)
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

Scenery.BEACH_TOP = 0.35
Scenery.GRASS_TOP = 0.8
Scenery.DOCK_TOP = Lake.DOCK_TOP
Scenery.DOCK_INNER = Lake.DOCK_INNER
Scenery.DOCK_OUTER = Lake.DOCK_OUTER
Scenery.DOCK_WIDTH = Lake.DOCK_WIDTH
Scenery.DOCK_ANGLES = Lake.DOCK_ANGLES
Scenery.WALL_HEIGHT = 12 -- invisible walls: taller than anyone can jump
Scenery.PATH_RADIUS = BEACH_OUT + 8
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

local function polar(angle: number, radius: number, y: number?): Vector3
	return Build.polar(angle, radius, y)
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
	for _, dockAngle in Scenery.DOCK_ANGLES do
		if angleGap(angle, dockAngle) * radius < Scenery.DOCK_WIDTH / 2 + margin then
			return true
		end
	end
	return false
end

-- ===== Ground and water =====

local function buildGround(root: Instance)
	local land = Build.model("Land", root)
	-- lakebed under everything (only the part under the water shows)
	Build.disc(2 * 480, 2, CFrame.new(0, -9, 0), Color3.fromRGB(38, 82, 110), land, {
		name = "Lakebed",
		shadow = false,
	})
	-- sandy shallows near the shore, seen through the water
	Build.ring(CFrame.new(0, -1.6, 0), R - 9, 18, 1.2, 96, Palette.sand, land, {
		name = "Shallows",
		decor = true,
		shadow = false,
	})
	Build.ring(CFrame.new(0, -3.4, 0), R - 26, 18, 1.2, 96, Palette.pebbleDark, land, {
		name = "Shelf",
		decor = true,
		shadow = false,
	})
	Build.disc(2 * (R + 1), 0.6, CFrame.new(0, -0.3, 0), Palette.water, land, {
		name = "Water",
		transparency = 0.32,
		reflectance = 0.08,
		collide = false,
		decor = true,
		shadow = false,
	})
	-- pebble beach and grass, as rings around the lake
	Build.ring(
		CFrame.new(0, Scenery.BEACH_TOP - 0.75, 0),
		R + Config.SHORE_WIDTH / 2,
		Config.SHORE_WIDTH,
		1.5,
		120,
		Palette.pebble,
		land,
		{ name = "Beach", shadow = false }
	)
	local grassY = Scenery.GRASS_TOP - 1
	Build.ring(CFrame.new(0, grassY, 0), BEACH_OUT + 27, 54, 2, 120, Palette.grass, land, {
		name = "Meadow",
		shadow = false,
	})
	Build.ring(CFrame.new(0, grassY, 0), BEACH_OUT + 94, 80, 2, 120, Palette.grass, land, {
		name = "Meadow",
		shadow = false,
	})
	Build.ring(
		CFrame.new(0, grassY - 0.05, 0),
		BEACH_OUT + 184,
		100,
		2,
		140,
		Palette.grassDark,
		land,
		{
			name = "Meadow",
			shadow = false,
		}
	)
	Build.ring(CFrame.new(0, grassY - 0.1, 0), BEACH_OUT + 290, 112, 2, 140, Palette.moss, land, {
		name = "Foothills",
		shadow = false,
	})
	-- out to the mountains, so there is never a gap at the horizon
	Build.ring(CFrame.new(0, grassY - 0.15, 0), 590, 244, 2, 160, Palette.moss, land, {
		name = "Foothills",
		shadow = false,
		decor = true,
	})
	-- the walking path around the lake
	Build.ring(
		CFrame.new(0, Scenery.GRASS_TOP - 0.45, 0),
		Scenery.PATH_RADIUS,
		4.5,
		1,
		120,
		Palette.sand,
		land,
		{ name = "Path", shadow = false, decor = true }
	)
end

-- Invisible walls: one along the water's edge and around each dock so
-- nobody walks or jumps into the lake, one at the edge of the play area.
-- They ignore raycasts, so the camera never bumps into them.
local FENCE: Build.Options = { name = "Fence", transparency = 1, shadow = false }

local function wall(size: Vector3, cframe: CFrame, parent: Instance)
	local part = Build.block(size, cframe, Palette.white, parent, FENCE)
	part.CanQuery = false
	part.CanTouch = false
end

local function buildFences(root: Instance)
	local fences = Build.model("Fences", root)
	local h = Scenery.WALL_HEIGHT
	local radius = R + 1
	-- the shoreline, in short straight pieces; the docks cut gaps in it
	local segments = 180
	local step = TAU / segments
	local length = 2 * radius * math.tan(step / 2) + 0.1
	for i = 0, segments - 1 do
		local angle = i * step
		if not nearDock(angle, radius, length / 2) then
			wall(
				Vector3.new(length, h, 0.5),
				CFrame.lookAt(polar(angle, radius, h / 2 - 1), Vector3.new(0, h / 2 - 1, 0)),
				fences
			)
		end
	end
	-- each dock: walls down both sides (from the beach out) and across the end,
	-- plus short pieces along the shore that close the gap beside it
	local half = Scenery.DOCK_WIDTH / 2
	for _, angle in Scenery.DOCK_ANGLES do
		local inner, outerEnd = Scenery.DOCK_INNER, R + 3
		local frame = CFrame.lookAt(polar(angle, (inner + outerEnd) / 2), polar(angle, inner))
		local dockLength = outerEnd - inner
		for _, side in { -1, 1 } do
			wall(
				Vector3.new(0.5, h, dockLength),
				frame * CFrame.new(side * (half + 0.25), h / 2 - 1, 0),
				fences
			)
			-- along the shore from the dock's side to the next shoreline piece
			local shore = CFrame.lookAt(polar(angle, radius), Vector3.zero)
			local span = step * radius + 2.5
			wall(
				Vector3.new(span, h, 0.5),
				shore * CFrame.new(side * (half + 0.5 + span / 2), h / 2 - 1, 0),
				fences
			)
		end
		wall(
			Vector3.new(Scenery.DOCK_WIDTH + 1, h, 0.5),
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

-- ===== Mountains and sky =====

local function buildHorizon(root: Instance)
	local horizon = Build.model("Horizon", root)
	local gen = Rng.new(31)
	local options = { decor = true, collide = false, shadow = false }
	local count = 18
	for i = 0, count - 1 do
		local angle = i * (TAU / count) + (gen.next() - 0.5) * 0.25
		local width = 150 + gen.next() * 90
		local height = 90 + gen.next() * 90
		local radius = 430 + gen.next() * 50
		local base = polar(angle, radius, height * 0.12)
		local color = if i % 2 == 0 then Palette.mountain else Palette.mountainDark
		Build.ellipsoid(
			Vector3.new(width, height, width * 0.8),
			CFrame.new(base) * CFrame.Angles(0, angle, 0),
			color,
			horizon,
			options
		)
		if height > 135 then
			Build.ellipsoid(
				Vector3.new(width * 0.42, height * 0.3, width * 0.34),
				CFrame.new(base + Vector3.new(0, height * 0.36, 0)) * CFrame.Angles(0, angle, 0),
				Palette.snow,
				horizon,
				options
			)
		end
		-- a green foothill in front of every other mountain
		if i % 2 == 1 then
			local hill = polar(angle + 0.1, radius - 70, 4)
			Build.ellipsoid(
				Vector3.new(110, 46, 80),
				CFrame.new(hill) * CFrame.Angles(0, angle, 0),
				Palette.pineDark,
				horizon,
				options
			)
		end
	end
	for i = 0, 9 do
		local angle = i * (TAU / 10) + gen.next() * 0.4
		Props.cloud(
			polar(angle, 180 + gen.next() * 220, 120 + gen.next() * 50),
			0.9 + gen.next() * 0.6,
			gen,
			horizon
		)
	end
end

-- ===== Docks =====

local function lantern(position: Vector3, parent: Instance, height: number?)
	local h = height or 6
	local m = Build.model("Lantern", parent)
	local dark = Palette.woodDark
	Build.block(Vector3.new(0.7, h, 0.7), CFrame.new(position + Vector3.new(0, h / 2, 0)), dark, m)
	Build.block(
		Vector3.new(1.8, 0.35, 0.7),
		CFrame.new(position + Vector3.new(0.55, h - 0.2, 0)),
		dark,
		m,
		{
			decor = true,
		}
	)
	local glass = Build.block(
		Vector3.new(0.9, 1.1, 0.9),
		CFrame.new(position + Vector3.new(1.1, h - 1, 0)),
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
	Build.block(
		Vector3.new(1.1, 0.25, 1.1),
		CFrame.new(position + Vector3.new(1.1, h - 0.35, 0)),
		dark,
		m,
		{
			decor = true,
			collide = false,
		}
	)
	local light = Instance.new("PointLight")
	light.Color = Palette.lantern
	light.Range = 18
	light.Brightness = 1.4
	light.Shadows = false
	light.Enabled = false
	light.Parent = glass
	CollectionService:AddTag(light, Tags.NIGHT_LIGHT)
end

local function buildDock(angle: number, index: number, parent: Instance)
	local dock = Build.model("Dock" .. index, parent)
	local inner, outer = Scenery.DOCK_INNER, Scenery.DOCK_OUTER
	local length = outer - inner
	local deckY = Scenery.DOCK_TOP - 0.25
	-- local -Z points along the dock toward the lake
	local frame =
		CFrame.lookAt(polar(angle, (inner + outer) / 2, deckY), polar(angle, inner, deckY))
	local planks = math.floor(length / 1.25)
	for i = 0, planks - 1 do
		local z = length / 2 - 0.62 - i * 1.25
		Build.block(
			Vector3.new(Scenery.DOCK_WIDTH, 0.5, 1.12),
			frame * CFrame.new(0, 0, z),
			if i % 3 == 0 then Palette.woodLight else Palette.wood,
			dock,
			{ name = "Plank", shadow = false }
		)
	end
	for _, side in { -1, 1 } do
		Build.block(
			Vector3.new(0.5, 0.6, length),
			frame * CFrame.new(side * (Scenery.DOCK_WIDTH / 2 - 0.25), -0.5, 0),
			Palette.woodDark,
			dock,
			{ decor = true, shadow = false }
		)
		-- posts down into the lake (only where the dock is over the water)
		for z = -length / 2 + 1, length / 2, 6 do
			local top = frame * CFrame.new(side * (Scenery.DOCK_WIDTH / 2 - 0.3), 0, z)
			if (Vector3.new(top.Position.X, 0, top.Position.Z)).Magnitude < R + 2 then
				Build.rod(
					top.Position,
					top.Position - Vector3.new(0, 9, 0),
					0.8,
					Palette.woodDark,
					dock,
					{ decor = true, shadow = false }
				)
			end
		end
	end
	-- a lantern on the end and a crate of stones
	lantern(
		(frame * CFrame.new(Scenery.DOCK_WIDTH / 2 - 0.4, 0.25, -length / 2 + 1)).Position,
		dock,
		5.5
	)
	Build.block(
		Vector3.new(1.6, 1.2, 1.6),
		frame
			* CFrame.new(-Scenery.DOCK_WIDTH / 2 + 1.1, 0.85, -length / 2 + 4)
			* CFrame.Angles(0, 0.3, 0),
		Palette.woodLight,
		dock,
		{ name = "Crate", decor = true }
	)
end

-- ===== Cabin and campfire =====

local function window(cf: CFrame, parent: Instance)
	local glass =
		Build.block(Vector3.new(2.6, 2.2, 0.3), cf, Color3.fromRGB(150, 196, 220), parent, {
			name = "Window",
			decor = true,
			shadow = false,
		})
	CollectionService:AddTag(glass, Tags.WINDOW)
	Build.block(Vector3.new(3, 0.3, 0.45), cf * CFrame.new(0, -1.25, 0.05), Palette.cream, parent, {
		decor = true,
		shadow = false,
	})
end

local function buildCabin(root: Instance)
	local cabin = Build.model("Cabin", root)
	local base = polar(Scenery.CABIN_ANGLE, Scenery.CABIN_RADIUS, Scenery.GRASS_TOP)
	local f = facingLake(base) -- front faces the lake
	local w, d, h = 16, 12, 7
	Build.block(Vector3.new(w + 6, 1, d + 8), f * CFrame.new(0, 0.3, -2), Palette.woodDark, cabin, {
		name = "Floor",
	})
	-- log walls (front wall has a door gap)
	for _, side in { -1, 1 } do
		Build.block(
			Vector3.new(0.9, h, d),
			f * CFrame.new(side * w / 2, h / 2 + 0.8, 2),
			Palette.wood,
			cabin
		)
	end
	Build.block(
		Vector3.new(w, h, 0.9),
		f * CFrame.new(0, h / 2 + 0.8, 2 + d / 2),
		Palette.wood,
		cabin
	)
	for _, side in { -1, 1 } do
		Build.block(
			Vector3.new(w / 2 - 1.6, h, 0.9),
			f * CFrame.new(side * (w / 4 + 0.8), h / 2 + 0.8, 2 - d / 2),
			Palette.wood,
			cabin
		)
	end
	Build.block(
		Vector3.new(3.2, 1.6, 0.9),
		f * CFrame.new(0, h + 0.8 - 0.8, 2 - d / 2),
		Palette.wood,
		cabin
	)
	window(f * CFrame.new(-w / 4 - 0.8, 4.4, 2 - d / 2 - 0.5), cabin)
	window(f * CFrame.new(w / 4 + 0.8, 4.4, 2 - d / 2 - 0.5), cabin)
	-- dark doorway so the door gap doesn't look hollow
	Build.block(
		Vector3.new(3.2, 5.4, 0.3),
		f * CFrame.new(0, 3.5, 2 - d / 2 + 1.4),
		Palette.woodDark,
		cabin,
		{
			decor = true,
		}
	)
	-- roof: two slopes and a ridge
	local roofY = h + 0.8
	for _, side in { -1, 1 } do
		Build.wedge(
			Vector3.new(d + 3, 5, w / 2 + 1.5),
			-- the tall back of each wedge (+Z) meets the other at the ridge
			f
				* CFrame.new(side * (w / 4 + 0.75), roofY + 2.5, 2)
				* CFrame.Angles(0, -side * math.pi / 2, 0),
			Palette.roof,
			cabin,
			{ name = "Roof" }
		)
	end
	Build.block(
		Vector3.new(1, 0.8, d + 3),
		f * CFrame.new(0, roofY + 5.2, 2),
		Palette.woodDark,
		cabin,
		{
			decor = true,
		}
	)
	-- chimney with a wisp of smoke
	local chimney = Build.block(
		Vector3.new(2, 6, 2),
		f * CFrame.new(w / 4 + 1, roofY + 4, 5),
		Palette.rock,
		cabin,
		{ name = "Chimney" }
	)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(230, 230, 236))
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 4),
	})
	smoke.Lifetime = NumberRange.new(4, 6)
	smoke.Rate = 3
	smoke.Speed = NumberRange.new(2, 3)
	smoke.SpreadAngle = Vector2.new(12, 12)
	smoke.Acceleration = Vector3.new(1, 0.4, 0)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Parent = chimney
	-- porch: roof posts and two seats facing the lake
	for _, side in { -1, 1 } do
		Build.block(
			Vector3.new(0.6, h, 0.6),
			f * CFrame.new(side * (w / 2 + 2), h / 2 + 0.8, -d / 2 - 2.5),
			Palette.woodDark,
			cabin
		)
	end
	Build.block(
		Vector3.new(w + 6, 0.5, 6.6),
		f * CFrame.new(0, h + 0.6, -d / 2 - 1.75) * CFrame.Angles(math.rad(-12), 0, 0),
		Palette.roof,
		cabin,
		{ decor = true }
	)
	for _, side in { -1, 1 } do
		local seatCf = f * CFrame.new(side * 4.5, 1.9, -d / 2 - 1.4)
		Build.block(
			Vector3.new(1.8, 0.8, 1.8),
			seatCf * CFrame.new(0, -0.7, 0),
			Palette.woodDark,
			cabin
		)
		local seat = Instance.new("Seat")
		seat.Name = "PorchChair"
		seat.Anchored = true
		seat.Size = Vector3.new(2.2, 0.6, 2.2)
		seat.CFrame = seatCf
		seat.Color = Palette.woodLight
		seat.Material = Enum.Material.SmoothPlastic
		seat.TopSurface = Enum.SurfaceType.Smooth
		seat.BottomSurface = Enum.SurfaceType.Smooth
		seat.Parent = cabin
		Build.block(
			Vector3.new(2.2, 2.4, 0.4),
			seatCf * CFrame.new(0, 1.2, 1.1),
			Palette.woodLight,
			cabin,
			{
				decor = true,
			}
		)
	end
end

local function buildCampfire(root: Instance)
	local camp = Build.model("Campfire", root)
	local center = polar(Scenery.CAMPFIRE_ANGLE, Scenery.CAMPFIRE_RADIUS, Scenery.GRASS_TOP)
	for i = 0, 7 do
		local a = i * (TAU / 8)
		Build.ellipsoid(
			Vector3.new(1.6, 1, 1.4),
			CFrame.new(center + Vector3.new(math.sin(a) * 2.3, 0.3, math.cos(a) * 2.3)),
			if i % 2 == 0 then Palette.rock else Palette.rockDark,
			camp,
			{ decor = true }
		)
	end
	for i = 0, 2 do
		local a = i * (TAU / 3)
		local dir = Vector3.new(math.sin(a), 0, math.cos(a))
		Build.rod(
			center + dir * 1.6 + Vector3.new(0, 0.2, 0),
			center - dir * 0.3 + Vector3.new(0, 1.2, 0),
			0.5,
			Palette.woodDark,
			camp,
			{ decor = true, collide = false }
		)
	end
	local flame = Build.ellipsoid(
		Vector3.new(1.6, 2.4, 1.6),
		CFrame.new(center + Vector3.new(0, 1.4, 0)),
		Palette.fire,
		camp,
		{
			name = "Flame",
			material = Enum.Material.Neon,
			decor = true,
			collide = false,
			shadow = false,
		}
	)
	Build.ellipsoid(
		Vector3.new(0.9, 1.5, 0.9),
		CFrame.new(center + Vector3.new(0, 1.5, 0)),
		Palette.yellow,
		camp,
		{ material = Enum.Material.Neon, decor = true, collide = false, shadow = false }
	)
	local fire = Instance.new("Fire")
	fire.Size = 4
	fire.Heat = 6
	fire.Color = Palette.fire
	fire.SecondaryColor = Palette.yellow
	fire.Parent = flame
	local glow = Instance.new("PointLight")
	glow.Color = Palette.fire
	glow.Range = 20
	glow.Brightness = 1.8
	glow.Shadows = false
	glow.Parent = flame
	-- three log benches you can sit on, facing the fire
	for i = 0, 2 do
		local a = i * (TAU / 3) + math.rad(30)
		local spot = center + Vector3.new(math.sin(a) * 6.5, 0, math.cos(a) * 6.5)
		local cf = CFrame.lookAt(spot, center) -- -Z faces the fire
		Build.rod(
			(cf * CFrame.new(-2.2, 0.75, 0)).Position,
			(cf * CFrame.new(2.2, 0.75, 0)).Position,
			1.5,
			Palette.wood,
			camp,
			{ name = "Log" }
		)
		local seat = Instance.new("Seat")
		seat.Name = "LogSeat"
		seat.Anchored = true
		seat.Transparency = 1
		seat.Size = Vector3.new(2, 0.4, 1.4)
		seat.CFrame = cf * CFrame.new(0, 1.5, 0) -- sitters face the fire
		seat.Parent = camp
	end
end

-- ===== Shore details =====

local function reeds(base: Vector3, gen: Rng.Generator, parent: Instance)
	local m = Build.model("Reeds", parent)
	local options = { decor = true, collide = false, shadow = false }
	for i = 1, 6 do
		local a = gen.next() * TAU
		local r = gen.next() * 1.6
		local foot = base + Vector3.new(math.sin(a) * r, 0, math.cos(a) * r)
		local height = 2.4 + gen.next() * 2
		local lean = Vector3.new(gen.next() - 0.5, 0, gen.next() - 0.5) * 0.6
		local tip = foot + Vector3.new(0, height, 0) + lean
		Build.rod(foot, tip, 0.16, Palette.reed, m, options)
		if i % 2 == 0 then
			Build.ellipsoid(
				Vector3.new(0.4, 0.9, 0.4),
				CFrame.new(tip - lean * 0.15 - Vector3.new(0, 0.5, 0)),
				Palette.cattail,
				m,
				options
			)
		end
	end
end

local function lilyPads(center: Vector3, gen: Rng.Generator, parent: Instance)
	local m = Build.model("LilyPads", parent)
	local options = { decor = true, collide = false, shadow = false }
	for i = 1, 4 do
		local a = gen.next() * TAU
		local r = gen.next() * 3
		local p = center + Vector3.new(math.sin(a) * r, 0.04, math.cos(a) * r)
		local size = 1.6 + gen.next() * 1.2
		Build.disc(
			size,
			0.08,
			CFrame.new(p),
			if i % 2 == 0 then Palette.lily else Palette.leafDark,
			m,
			options
		)
		if i == 1 and gen.next() < 0.6 then
			Build.ellipsoid(
				Vector3.new(0.7, 0.45, 0.7),
				CFrame.new(p + Vector3.new(0, 0.25, 0)),
				Palette.pink,
				m,
				options
			)
		end
	end
end

local function buildShore(root: Instance)
	local shore = Build.model("Shore", root)
	local gen = Rng.new(5)
	-- pebbles scattered over the beach
	local pebbles = { Palette.pebbleLight, Palette.pebble, Palette.pebbleDark, Palette.rockLight }
	local options = { decor = true, collide = false, shadow = false }
	for _ = 1, 260 do
		local a = gen.next() * TAU
		local r = R + 1 + gen.next() * (Config.SHORE_WIDTH - 1.5)
		if not nearDock(a, r, 1) then
			local size = 0.4 + gen.next() * 0.9
			Build.ellipsoid(
				Vector3.new(size, size * 0.45, size * (0.7 + gen.next() * 0.4)),
				CFrame.new(polar(a, r, Scenery.BEACH_TOP)) * CFrame.Angles(0, gen.next() * TAU, 0),
				pebbles[gen.int(1, #pebbles)],
				shore,
				options
			)
		end
	end
	-- reeds at the water's edge and lily pads in the shallows
	for i = 0, 27 do
		local a = i * (TAU / 28) + gen.next() * 0.15
		if not nearDock(a, R, 4) and angleGap(a, Scenery.SPAWN_ANGLE) > 0.12 then
			reeds(polar(a, R + 1.5 + gen.next() * 1.5, Scenery.BEACH_TOP), gen, shore)
		end
	end
	for i = 0, 13 do
		local a = i * (TAU / 14) + 0.11 + gen.next() * 0.2
		if not nearDock(a, R, 8) then
			lilyPads(polar(a, R - 6 - gen.next() * 6, 0), gen, shore)
		end
	end
	-- lanterns along the path
	for i = 0, 11 do
		local a = i * (TAU / 12) + math.rad(7)
		if not nearDock(a, Scenery.PATH_RADIUS, 4) then
			lantern(polar(a, Scenery.PATH_RADIUS + 3, Scenery.GRASS_TOP), shore)
		end
	end
	-- fireflies hovering over the beach (switched on at night by the client)
	for i = 0, 11 do
		local a = i * (TAU / 12) + gen.next() * 0.3
		local anchor = Build.block(
			Vector3.new(14, 4, 14),
			CFrame.new(polar(a, R + 10, 3)),
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
		{ position = polar(Scenery.CABIN_ANGLE, Scenery.CABIN_RADIUS), radius = 22 },
		{ position = polar(Scenery.CAMPFIRE_ANGLE, Scenery.CAMPFIRE_RADIUS), radius = 14 },
		{ position = polar(Scenery.SPAWN_ANGLE, Scenery.SPAWN_RADIUS), radius = 12 },
	}
	for _, angle in Scenery.BOARD_ANGLES do
		table.insert(taken, { position = polar(angle, Scenery.BOARD_RADIUS), radius = 10 })
	end
	local function free(p: Vector3, radius: number): boolean
		local r = Vector3.new(p.X, 0, p.Z).Magnitude
		if r < Scenery.PATH_RADIUS + 5 + radius or r > Scenery.PLAY_RADIUS - 4 then
			return false
		end
		local a = math.atan2(p.X, p.Z)
		if nearDock(a, r, 6 + radius) and r < Scenery.DOCK_OUTER + 14 then
			return false
		end
		for _, spot in taken do
			if (spot.position - p).Magnitude < spot.radius + radius then
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
		local placed, tries = 0, 0
		while placed < count and tries < count * 50 do
			tries += 1
			local a = gen.next() * TAU
			local r = minR + (maxR - minR) * math.sqrt(gen.next())
			local p = polar(a, r, Scenery.GRASS_TOP)
			if free(p, radius) then
				table.insert(taken, { position = p, radius = radius })
				build(p)
				placed += 1
			end
		end
	end
	place(70, 5, 150, 330, function(p)
		Props.pine(p, 0.9 + gen.next() * 0.5, gen, forest)
	end)
	place(34, 6, 140, 300, function(p)
		Props.tree(p, 0.85 + gen.next() * 0.35, gen, forest)
	end)
	place(40, 3, 136, 300, function(p)
		Props.bush(p, 0.7 + gen.next() * 0.4, gen, forest)
	end)
	place(34, 2.5, 134, 260, function(p)
		Props.flowers(p, 0.9 + gen.next() * 0.3, gen, forest)
	end)
	place(26, 3, 134, 300, function(p)
		Props.fern(p, 0.8 + gen.next() * 0.4, gen, forest)
	end)
	place(18, 4, 140, 320, function(p)
		Props.rock(p, 0.8 + gen.next() * 0.8, gen, forest)
	end)
end

-- ===== Welcome sign and leaderboards =====

local function buildSign(root: Instance)
	-- just in front of the spawn, between it and the beach, facing the spawn
	local base = polar(Scenery.SPAWN_ANGLE + 0.045, BEACH_OUT + 2.5, Scenery.GRASS_TOP)
	local f = facingLake(base) * CFrame.Angles(0, math.pi, 0)
	local sign = Build.model("WelcomeSign", root)
	for _, side in { -1, 1 } do
		Build.block(
			Vector3.new(0.6, 5, 0.6),
			f * CFrame.new(side * 3.2, 2.5, 0),
			Palette.woodDark,
			sign
		)
	end
	local board = Build.block(
		Vector3.new(7.6, 3.4, 0.5),
		f * CFrame.new(0, 4.2, 0),
		Palette.woodLight,
		sign,
		{
			name = "Board",
		}
	)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0.4
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
	title.TextColor3 = Color3.fromRGB(70, 48, 36)
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
		local base = polar(Scenery.BOARD_ANGLES[i], Scenery.BOARD_RADIUS, Scenery.GRASS_TOP)
		guis[board.key] =
			Boards.build(board.key, board.title, board.color, facingLake(base), boards)
	end
	return guis
end

-- ===== Everything =====

function Scenery.build(parent: Instance): Built
	local root = Instance.new("Folder")
	root.Name = "StillLake"
	buildGround(root)
	buildFences(root)
	buildHorizon(root)
	local docks = Build.model("Docks", root)
	for i, angle in Scenery.DOCK_ANGLES do
		buildDock(angle, i, docks)
	end
	buildCabin(root)
	buildCampfire(root)
	buildShore(root)
	buildForest(root)
	buildSign(root)
	local boards = buildBoards(root)

	local spawnPosition = polar(Scenery.SPAWN_ANGLE, Scenery.SPAWN_RADIUS, Scenery.GRASS_TOP)
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
