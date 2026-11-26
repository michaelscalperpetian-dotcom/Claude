--!strict
-- Everything built from parts on top of the terrain (see Ground for the
-- coast itself): five wooden piers out into the bay, a sandy beach with
-- umbrellas and palms, a boardwalk plaza with the Rock Shop, the Strength
-- Gym, the Rebirth Shrine and the leaderboards, a lighthouse on the
-- headland, distance buoys and islands far out at sea, and the invisible
-- walls that keep everyone out of the water. Decorations come from fixed
-- random seeds, so every server looks the same.
--
-- Land is z < 0, the sea is z > 0; everything stands on Land.height(x, z).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IslandData = require(ReplicatedStorage.Shared.Data.IslandData)
local Land = require(ReplicatedStorage.Shared.Land)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Sea = require(ReplicatedStorage.Shared.Sea)
local Tags = require(ReplicatedStorage.Shared.Tags)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Rng = require(ReplicatedStorage.Shared.Util.Rng)
local BoardData = require(script.Parent.BoardData)
local Boards = require(script.Parent.Boards)
local Build = require(script.Parent.Build)
local Props = require(script.Parent.Props)

local Scenery = {}

local TAU = 2 * math.pi

Scenery.WALL_HEIGHT = 12 -- invisible walls: taller than anyone can jump
Scenery.SHORE_WALL = 0.5 -- the wall along the water's edge (z)
Scenery.PLAY_HALF_WIDTH = 300 -- players stay within this far of the middle...
Scenery.PLAY_BACK = -260 -- ...and in front of this (z)
Scenery.DECK_TOP = Land.PLAZA_HEIGHT + 0.5 -- the boardwalk's surface
Scenery.DECK_FRONT, Scenery.DECK_BACK = -44, -106
Scenery.DECK_HALF_WIDTH = 172
Scenery.SPAWN = Vector3.new(0, Scenery.DECK_TOP, -82)
Scenery.SHOP_SPOTS = {
	Rocks = Vector3.new(-96, Scenery.DECK_TOP, -72),
	Upgrades = Vector3.new(96, Scenery.DECK_TOP, -72),
	Rebirth = Vector3.new(0, Scenery.DECK_TOP, -98),
}
Scenery.BOARD_XS = { 118, 133, 148 }
Scenery.BOARD_Z = -100
Scenery.LIGHTHOUSE = Vector2.new(372, 70)
Scenery.MARKERS = { 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000 }
Scenery.MARKER_HALF_WIDTH = 200
Scenery.FARTHEST_MODEL = 9000 -- islands further out than this (map studs) aren't built

export type Built = {
	root: Folder,
	spawn: SpawnLocation,
	boards: { [string]: SurfaceGui }, -- by BoardData key
}

local WOOD: Build.Options = { material = Enum.Material.Wood }
local PLANKS: Build.Options = { material = Enum.Material.WoodPlanks }

local function with(options: Build.Options, extra: Build.Options): Build.Options
	local merged: Build.Options = table.clone(options)
	for key, value in extra :: any do
		(merged :: any)[key] = value
	end
	return merged
end

local function ground(x: number, z: number, lift: number?): Vector3
	return Land.at(x, z, lift)
end

local function seaward(position: Vector3): CFrame
	return CFrame.lookAt(position, position + Sea.FORWARD)
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	for key, value in props do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

local function surface(part: BasePart, face: Enum.NormalId): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.LightInfluence = 0.4
	gui.PixelsPerStud = 30
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.Parent = part
	return gui
end

-- ===== Invisible walls =====

local FENCE: Build.Options = { name = "Fence", transparency = 1, shadow = false }

local function wall(size: Vector3, cframe: CFrame, parent: Instance)
	local part = Build.block(size, cframe, Palette.white, parent, FENCE)
	part.CanQuery = false
	part.CanTouch = false
end

local function buildFences(root: Instance)
	local fences = Build.model("Fences", root)
	local h = Scenery.WALL_HEIGHT
	local y = h / 2 - 1
	local half = Scenery.PLAY_HALF_WIDTH
	-- along the water's edge, with a gap onto each pier
	local gaps = {}
	for _, x in Sea.PIER_XS do
		table.insert(gaps, { x - Sea.PIER_WIDTH / 2, x + Sea.PIER_WIDTH / 2 })
	end
	local from = -half
	for _, gap in gaps do
		wall(
			Vector3.new(gap[1] - from, h, 0.5),
			CFrame.new((from + gap[1]) / 2, y, Scenery.SHORE_WALL),
			fences
		)
		from = gap[2]
	end
	wall(
		Vector3.new(half - from, h, 0.5),
		CFrame.new((from + half) / 2, y, Scenery.SHORE_WALL),
		fences
	)
	-- each pier: both sides out from the shore, and across the end
	for _, x in Sea.PIER_XS do
		local length = Sea.PIER_END - Scenery.SHORE_WALL
		for _, side in { -1, 1 } do
			wall(
				Vector3.new(0.5, h, length),
				CFrame.new(
					x + side * (Sea.PIER_WIDTH / 2 + 0.25),
					y + 1,
					Scenery.SHORE_WALL + length / 2
				),
				fences
			)
		end
		wall(
			Vector3.new(Sea.PIER_WIDTH + 1, h, 0.5),
			CFrame.new(x, y + 1, Sea.PIER_END + 0.25),
			fences
		)
	end
	-- the sides and back of the play area (tall: the ground climbs there)
	local depth = Scenery.SHORE_WALL - Scenery.PLAY_BACK
	for _, side in { -1, 1 } do
		wall(
			Vector3.new(1, 160, depth),
			CFrame.new(side * half, 60, Scenery.PLAY_BACK + depth / 2),
			fences
		)
	end
	wall(Vector3.new(2 * half, 220, 1), CFrame.new(0, 90, Scenery.PLAY_BACK), fences)
end

-- ===== Lanterns and lamps =====

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
		with(WOOD, {
			decor = true,
		})
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
	light.Range = 20
	light.Brightness = 1.6
	light.Shadows = true
	light.Enabled = false
	light.Parent = glass
	CollectionService:AddTag(light, Tags.NIGHT_LIGHT)
end

-- ===== Piers =====

local function buildPier(x: number, index: number, parent: Instance)
	local pier = Build.model("Pier" .. index, parent)
	local gen = Rng.new(60 + index)
	local length = Sea.PIER_END - Sea.PIER_START
	local deckY = Sea.PIER_TOP - 0.25
	local center = (Sea.PIER_START + Sea.PIER_END) / 2
	local planks = math.floor(length / 1.25)
	for i = 0, planks - 1 do
		local z = Sea.PIER_START + 0.62 + i * 1.25
		Build.block(
			Vector3.new(Sea.PIER_WIDTH, 0.5, 1.14),
			CFrame.new(x, deckY + (gen.next() - 0.5) * 0.04, z),
			if i % 3 == 0
				then Palette.woodLight
				elseif i % 3 == 1 then Palette.wood
				else Palette.weathered,
			pier,
			with(PLANKS, { name = "Plank", shadow = false })
		)
	end
	for _, side in { -1, 1 } do
		local edgeX = x + side * (Sea.PIER_WIDTH / 2 - 0.25)
		Build.block(
			Vector3.new(0.5, 0.7, length),
			CFrame.new(edgeX, deckY - 0.55, center),
			Palette.woodDark,
			pier,
			with(WOOD, {
				decor = true,
				shadow = false,
			})
		)
		-- posts down into the sea bed, and a low rail to lean on
		for z = Sea.PIER_START + 2, Sea.PIER_END, 6 do
			local floor = Land.height(edgeX, z)
			local top = Vector3.new(edgeX, Sea.PIER_TOP + 1.6, z)
			Build.rod(
				top,
				Vector3.new(edgeX, floor - 1.5, z),
				0.8,
				Palette.woodDark,
				pier,
				with(WOOD, { shadow = false })
			)
		end
		Build.block(
			Vector3.new(0.35, 0.3, length - 2),
			CFrame.new(edgeX, Sea.PIER_TOP + 1.45, center + 1),
			Palette.wood,
			pier,
			with(WOOD, { decor = true, shadow = false })
		)
	end
	-- a lantern at the end, and a ring painted where the best throws start
	lantern(Vector3.new(x + Sea.PIER_WIDTH / 2 - 0.5, Sea.PIER_TOP, Sea.PIER_END - 1), pier, 5.5)
	Build.disc(
		4.2,
		0.05,
		CFrame.new(x, Sea.PIER_TOP + 0.03, Sea.PIER_END - 5),
		Palette.canvas,
		pier,
		{
			name = "ThrowSpot",
			decor = true,
			collide = false,
			shadow = false,
		}
	)
	Build.disc(
		3.4,
		0.06,
		CFrame.new(x, Sea.PIER_TOP + 0.04, Sea.PIER_END - 5),
		Palette.wood,
		pier,
		{
			decor = true,
			collide = false,
			shadow = false,
			material = Enum.Material.WoodPlanks,
		}
	)
end

-- ===== The beach =====

local function umbrella(base: Vector3, color: Color3, parent: Instance, gen: Rng.Generator)
	local m = Build.model("Umbrella", parent)
	local tilt =
		CFrame.Angles((gen.next() - 0.5) * 0.25, gen.next() * TAU, (gen.next() - 0.5) * 0.25)
	local top = base + tilt.UpVector * 7
	Build.rod(
		base - Vector3.new(0, 0.5, 0),
		top,
		0.3,
		Palette.white,
		m,
		{ decor = true, material = Enum.Material.Metal }
	)
	-- a soft striped canopy: a dome with a band of colour and a white cap
	Build.ellipsoid(
		Vector3.new(8, 2.2, 8),
		CFrame.new(top - Vector3.new(0, 0.4, 0)) * tilt.Rotation,
		color,
		m,
		{
			decor = true,
			collide = false,
			material = Enum.Material.Fabric,
		}
	)
	Build.ellipsoid(
		Vector3.new(4.2, 1.5, 4.2),
		CFrame.new(top + tilt.UpVector * 0.25) * tilt.Rotation,
		Palette.white,
		m,
		{
			decor = true,
			collide = false,
			material = Enum.Material.Fabric,
		}
	)
	-- a towel beside it
	local towel = CFrame.new(base + Vector3.new(2.5, 0.05, 1.5))
		* CFrame.Angles(0, gen.next() * TAU, 0)
	Build.block(
		Vector3.new(2.4, 0.1, 4.6),
		towel,
		color,
		m,
		{ decor = true, collide = false, material = Enum.Material.Fabric }
	)
	Build.block(Vector3.new(2.4, 0.11, 0.6), towel * CFrame.new(0, 0, 1.2), Palette.white, m, {
		decor = true,
		collide = false,
		material = Enum.Material.Fabric,
	})
end

local function lifeguardTower(base: Vector3, parent: Instance)
	local m = Build.model("LifeguardTower", parent)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Build.rod(
				base + Vector3.new(sx * 2.4, -0.5, sz * 2.4),
				base + Vector3.new(sx * 2, 7, sz * 2),
				0.6,
				Palette.white,
				m,
				WOOD
			)
		end
	end
	local floor = CFrame.new(base + Vector3.new(0, 7, 0))
	Build.block(Vector3.new(5.6, 0.4, 5.6), floor, Palette.wood, m, PLANKS)
	Build.block(Vector3.new(5.2, 3.2, 4.4), floor * CFrame.new(0, 1.8, 0.4), Palette.buoyRed, m, {
		material = Enum.Material.WoodPlanks,
	})
	Build.block(
		Vector3.new(6.6, 0.5, 6.2),
		floor * CFrame.new(0, 3.65, 0.3),
		Palette.white,
		m,
		PLANKS
	)
	-- a ramp up the back
	Build.beam(
		base + Vector3.new(0, 0.2, -9),
		base + Vector3.new(0, 7, -2.8),
		2,
		0.4,
		Palette.wood,
		m,
		PLANKS
	)
end

local function buildBeach(root: Instance)
	local beach = Build.model("Beach", root)
	local gen = Rng.new(5)
	-- shells and pebbles
	local pebbles = { Palette.pebbleLight, Palette.pebble, Palette.pebbleDark, Palette.cream }
	for _ = 1, 220 do
		local x = (gen.next() - 0.5) * 2 * (Scenery.PLAY_HALF_WIDTH - 60)
		local z = Land.BEACH_BACK + 2 + gen.next() * (-2 - Land.BEACH_BACK - 2)
		local p = Vector3.new(x, 0, z)
		if not Sea.pierAt(p, 0.5) then
			local size = 0.3 + gen.next() * 0.7
			Build.ellipsoid(
				Vector3.new(size, size * 0.45, size * (0.7 + gen.next() * 0.4)),
				CFrame.new(ground(x, z, size * 0.1)) * CFrame.Angles(0, gen.next() * TAU, 0),
				pebbles[gen.int(1, #pebbles)],
				beach,
				{ decor = true, collide = false, shadow = false, material = Enum.Material.Slate }
			)
		end
	end
	-- umbrellas between the piers
	local colors = { Palette.awningBlue, Palette.awningRed, Palette.awningYellow }
	for i, x in { -150, -90, -30, 30, 90, 150 } do
		local z = -26 + gen.next() * 6
		umbrella(ground(x + (gen.next() - 0.5) * 10, z), colors[(i - 1) % #colors + 1], beach, gen)
	end
	lifeguardTower(ground(-185, -18), beach)
	-- palms along the back of the beach
	for i = 0, 15 do
		local x = -200 + i * 26.6 + (gen.next() - 0.5) * 8
		if math.abs(x) > 14 then -- keep the walkway to the arch clear
			Props.palm(
				ground(x, Land.BEACH_BACK + 1 + gen.next() * 3, -0.3),
				0.85 + gen.next() * 0.35,
				gen,
				beach
			)
		end
	end
	-- fireflies over the sand at night
	for i = 0, 9 do
		local anchor = Build.block(
			Vector3.new(16, 4, 10),
			CFrame.new(ground(-180 + i * 40, -18, 3)),
			Palette.white,
			beach,
			{ name = "Fireflies", transparency = 1, collide = false, decor = true, shadow = false }
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

-- ===== The boardwalk =====

local function stall(
	name: string,
	title: string,
	color: Color3,
	spot: Vector3,
	menu: string,
	parent: Instance
)
	local m = Build.model(name, parent)
	local f = seaward(spot)
	local w, d = 16, 8
	-- counter, back wall and posts
	Build.block(
		Vector3.new(w, 3, 2),
		f * CFrame.new(0, 1.5, -d / 2 + 1),
		Palette.wood,
		m,
		with(PLANKS, { name = "Counter" })
	)
	Build.block(
		Vector3.new(w, 0.4, 2.4),
		f * CFrame.new(0, 3.2, -d / 2 + 1),
		Palette.woodLight,
		m,
		PLANKS
	)
	Build.block(Vector3.new(w, 9, 0.8), f * CFrame.new(0, 4.5, d / 2), Palette.canvas, m, PLANKS)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Build.block(
				Vector3.new(0.7, 9, 0.7),
				f * CFrame.new(sx * (w / 2 - 0.35), 4.5, sz * (d / 2 - 0.35)),
				Palette.woodDark,
				m,
				WOOD
			)
		end
	end
	-- a striped awning, sloping down toward the front
	local stripes = 8
	for i = 0, stripes - 1 do
		Build.block(
			Vector3.new(w / stripes, 0.3, d + 3),
			f
				* CFrame.new(-w / 2 + (i + 0.5) * w / stripes, 9.4, -1)
				* CFrame.Angles(math.rad(14), 0, 0),
			if i % 2 == 0 then color else Palette.white,
			m,
			{ decor = true, material = Enum.Material.Fabric }
		)
	end
	-- the sign on top
	local sign =
		Build.block(Vector3.new(w - 2, 2.6, 0.5), f * CFrame.new(0, 11.6, -d / 2 + 0.6), color, m, {
			name = "Sign",
			material = Enum.Material.WoodPlanks,
		})
	local gui = surface(sign, Enum.NormalId.Front)
	text(gui, {
		Text = title,
		Size = UDim2.fromScale(0.92, 0.8),
		Position = UDim2.fromScale(0.04, 0.1),
		TextStrokeTransparency = 0.4,
	})
	-- walk up to the counter to open the menu (the client listens for this)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = title
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Menu", menu)
	prompt.Parent = sign
	return m
end

local function shrine(spot: Vector3, parent: Instance)
	local m = Build.model("RebirthShrine", parent)
	for i = 0, 7 do
		local a = i * (TAU / 8)
		Build.block(
			Vector3.new(1.4, 6 + (i % 2) * 2, 1.4),
			CFrame.new(spot + Vector3.new(math.sin(a) * 8, 3 + (i % 2), math.cos(a) * 8))
				* CFrame.Angles(0, a, 0),
			Palette.rockLight,
			m,
			{ material = Enum.Material.Marble }
		)
	end
	Build.disc(
		9,
		1,
		CFrame.new(spot + Vector3.new(0, 0.5, 0)),
		Palette.rockLight,
		m,
		{ material = Enum.Material.Marble }
	)
	Build.disc(
		5,
		1.2,
		CFrame.new(spot + Vector3.new(0, 1.1, 0)),
		Palette.rock,
		m,
		{ material = Enum.Material.Marble }
	)
	local crystal = Build.ellipsoid(
		Vector3.new(2.6, 5.5, 2.6),
		CFrame.new(spot + Vector3.new(0, 5.2, 0)),
		Palette.crystal,
		m,
		{ name = "Crystal", material = Enum.Material.Neon, collide = false, shadow = false }
	)
	local glow = Instance.new("PointLight")
	glow.Color = Palette.crystal
	glow.Range = 16
	glow.Brightness = 1.5
	glow.Parent = crystal
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(Palette.crystal, Color3.new(1, 1, 1))
	sparkle.LightEmission = 1
	sparkle.Rate = 6
	sparkle.Lifetime = NumberRange.new(1, 2)
	sparkle.Speed = NumberRange.new(1, 2)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Parent = crystal
	local board = Build.block(
		Vector3.new(10, 2.2, 0.4),
		CFrame.lookAt(spot + Vector3.new(0, 9.6, 0), spot + Vector3.new(0, 9.6, 0) + Sea.FORWARD),
		Palette.woodDark,
		m,
		{
			name = "Sign",
			decor = true,
			material = Enum.Material.WoodPlanks,
		}
	)
	text(surface(board, Enum.NormalId.Front), {
		Text = "🔁 Rebirth",
		Size = UDim2.fromScale(0.92, 0.8),
		Position = UDim2.fromScale(0.04, 0.1),
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Rebirth"
	prompt.ObjectText = "Rebirth Shrine"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Menu", "Rebirth")
	prompt.Parent = crystal
end

local function arch(parent: Instance)
	local m = Build.model("WelcomeArch", parent)
	local z = Scenery.DECK_FRONT + 1
	for _, side in { -1, 1 } do
		Build.block(
			Vector3.new(2, 16, 2),
			CFrame.new(side * 11, Scenery.DECK_TOP + 8, z),
			Palette.woodDark,
			m,
			WOOD
		)
	end
	local board = Build.block(
		Vector3.new(26, 5, 1),
		CFrame.new(0, Scenery.DECK_TOP + 15, z),
		Palette.awningBlue,
		m,
		{
			name = "Sign",
			material = Enum.Material.WoodPlanks,
		}
	)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		text(surface(board, face), {
			Text = "🪨 SKIP A ROCK 🌊",
			Size = UDim2.fromScale(0.94, 0.8),
			Position = UDim2.fromScale(0.03, 0.1),
			TextStrokeTransparency = 0.3,
		})
	end
end

local function buildBoardwalk(root: Instance): { [string]: SurfaceGui }
	local walk = Build.model("Boardwalk", root)
	local gen = Rng.new(9)
	-- the deck: long boards running across, on a stone edge
	local depth = Scenery.DECK_FRONT - Scenery.DECK_BACK
	local boards = math.floor(depth / 2)
	for i = 0, boards - 1 do
		local z = Scenery.DECK_BACK + 1 + i * 2
		Build.block(
			Vector3.new(2 * Scenery.DECK_HALF_WIDTH, 0.6, 1.9),
			CFrame.new(0, Scenery.DECK_TOP - 0.3, z),
			if i % 4 == 0
				then Palette.woodLight
				elseif i % 4 == 2 then Palette.weathered
				else Palette.wood,
			walk,
			with(PLANKS, { name = "Board", shadow = false })
		)
	end
	-- steps down from the front edge onto the sand
	Build.block(
		Vector3.new(2 * Scenery.DECK_HALF_WIDTH, 0.6, 2),
		CFrame.new(0, Scenery.DECK_TOP - 0.7, Scenery.DECK_FRONT + 1),
		Palette.woodDark,
		walk,
		with(PLANKS, { name = "Step" })
	)
	-- lamps along the front and back
	for x = -160, 160, 40 do
		lantern(Vector3.new(x + 2, Scenery.DECK_TOP, Scenery.DECK_FRONT + 3), walk, 6)
		lantern(Vector3.new(x - 2, Scenery.DECK_TOP, Scenery.DECK_BACK + 2), walk, 6)
	end
	-- benches facing the sea
	for _, x in { -150, -40, 40, 150 } do
		local f = seaward(Vector3.new(x, Scenery.DECK_TOP, Scenery.DECK_FRONT + 7))
		Build.block(Vector3.new(6, 0.4, 1.6), f * CFrame.new(0, 1.2, 0), Palette.wood, walk, PLANKS)
		Build.block(Vector3.new(6, 1.6, 0.3), f * CFrame.new(0, 2, 0.8), Palette.wood, walk, PLANKS)
		for _, sx in { -2.6, 2.6 } do
			Build.block(
				Vector3.new(0.3, 1.2, 1.4),
				f * CFrame.new(sx, 0.6, 0),
				Palette.iron,
				walk,
				{
					material = Enum.Material.Metal,
				}
			)
		end
	end
	-- flower boxes
	for _, x in { -60, -20, 20, 60 } do
		local box = CFrame.new(x, Scenery.DECK_TOP + 0.6, Scenery.DECK_BACK + 6)
		Build.block(Vector3.new(6, 1.2, 2), box, Palette.woodDark, walk, PLANKS)
		Props.flowers(box.Position + Vector3.new(0, 0.6, 0), 0.8, gen, walk)
	end
	stall("RockShop", "🪨 Rock Shop", Palette.awningBlue, Scenery.SHOP_SPOTS.Rocks, "Rocks", walk)
	stall(
		"StrengthGym",
		"💪 Strength Gym",
		Palette.awningRed,
		Scenery.SHOP_SPOTS.Upgrades,
		"Upgrades",
		walk
	)
	shrine(Scenery.SHOP_SPOTS.Rebirth, walk)
	arch(walk)
	local guis: { [string]: SurfaceGui } = {}
	local boardsModel = Build.model("Leaderboards", walk)
	for i, board in BoardData.BOARDS do
		local base = Vector3.new(Scenery.BOARD_XS[i], Scenery.DECK_TOP, Scenery.BOARD_Z)
		guis[board.key] =
			Boards.build(board.key, board.title, board.color, seaward(base), boardsModel)
	end
	return guis
end

-- ===== Lighthouse =====

local function buildLighthouse(root: Instance)
	local m = Build.model("Lighthouse", root)
	local base = ground(Scenery.LIGHTHOUSE.X, Scenery.LIGHTHOUSE.Y, -1)
	local rings = 6
	local h = 0
	for i = 1, rings do
		local width = 9 - i * 0.7
		Build.disc(
			width,
			5,
			CFrame.new(base + Vector3.new(0, h + 2.5, 0)),
			if i % 2 == 0 then Palette.buoyRed else Palette.buoyWhite,
			m,
			{
				material = Enum.Material.Concrete,
			}
		)
		h += 5
	end
	Build.disc(
		7,
		0.6,
		CFrame.new(base + Vector3.new(0, h + 0.3, 0)),
		Palette.iron,
		m,
		{ material = Enum.Material.Metal }
	)
	local lamp =
		Build.disc(3.4, 3, CFrame.new(base + Vector3.new(0, h + 2, 0)), Palette.lantern, m, {
			name = "Lamp",
			material = Enum.Material.Neon,
			collide = false,
		})
	Build.ellipsoid(
		Vector3.new(4.4, 2.6, 4.4),
		CFrame.new(base + Vector3.new(0, h + 4, 0)),
		Palette.buoyRed,
		m,
		{
			material = Enum.Material.Metal,
		}
	)
	local light = Instance.new("PointLight")
	light.Color = Palette.lantern
	light.Range = 40
	light.Brightness = 2
	light.Enabled = false
	light.Parent = lamp
	CollectionService:AddTag(light, Tags.NIGHT_LIGHT)
end

-- ===== Forest on the hills =====

local function buildHills(root: Instance)
	local forest = Build.model("Forest", root)
	local gen = Rng.new(17)
	local placed = 0
	local tries = 0
	while placed < 260 and tries < 6000 do
		tries += 1
		local x = (gen.next() - 0.5) * 2 * (Land.EAST - 40)
		local z = Land.SOUTH + 40 + gen.next() * (Scenery.DECK_BACK - 14 - Land.SOUTH - 40)
		-- also some on the headlands, toward the sea
		if gen.next() < 0.25 then
			z = Scenery.DECK_BACK - 10 + gen.next() * 260
			x = (if gen.next() < 0.5 then -1 else 1) * (Land.BAY_HALF + 60 + gen.next() * 300)
		end
		local h = Land.height(x, z)
		if h > 3 and Land.slope(x, z) < 0.6 and math.abs(x) > 6 then
			if gen.next() < 0.8 then
				Props.pine(ground(x, z, -0.3), 1.3 + gen.next() * 1, gen, forest)
			else
				Props.tree(ground(x, z, -0.3), 1 + gen.next() * 0.5, gen, forest)
			end
			placed += 1
		end
	end
	for _ = 1, 40 do
		local x = (gen.next() - 0.5) * 2 * 600
		local z = -40 + gen.next() * 260
		if math.abs(x) > Land.BAY_HALF then
			Props.rock(ground(x, z, -0.5), 2 + gen.next() * 2.5, gen, forest)
		end
	end
end

-- ===== Out at sea: distance buoys and islands =====

local function buoy(position: Vector3, color: Color3, parent: Instance, tall: number?)
	local m = Build.model("Buoy", parent)
	Build.ellipsoid(
		Vector3.new(2.2, 2.2, 2.2),
		CFrame.new(position + Vector3.new(0, 0.4, 0)),
		color,
		m,
		{
			decor = true,
			material = Enum.Material.Plastic,
		}
	)
	Build.rod(
		position + Vector3.new(0, 1, 0),
		position + Vector3.new(0, 1 + (tall or 2.5), 0),
		0.25,
		Palette.iron,
		m,
		{
			decor = true,
			material = Enum.Material.Metal,
		}
	)
	return m
end

local function buildMarkers(root: Instance)
	local sea = Build.model("DistanceMarkers", root)
	local entryZ = Sea.FIRST_WATER
	for i, distance in Scenery.MARKERS do
		local z = entryZ + Sea.toWorld(distance)
		local line = Build.model(Format.short(distance), sea)
		for x = -Scenery.MARKER_HALF_WIDTH, Scenery.MARKER_HALF_WIDTH, 40 do
			buoy(
				Vector3.new(x, 0, z),
				if (x // 40) % 2 == 0 then Palette.buoyRed else Palette.buoyWhite,
				line
			)
		end
		-- a floating sign with the distance, readable from the shore
		Build.block(Vector3.new(10, 1, 4), CFrame.new(0, 0.4, z), Palette.buoyWhite, line, {
			decor = true,
			material = Enum.Material.Plastic,
		})
		local board =
			Build.block(Vector3.new(12, 5, 0.5), CFrame.new(0, 4.5, z), Palette.awningBlue, line, {
				name = "Sign",
				decor = true,
				material = Enum.Material.WoodPlanks,
			})
		local gui = surface(board, Enum.NormalId.Back) -- faces the shore (-Z)
		text(gui, {
			Text = Format.short(distance),
			Size = UDim2.fromScale(0.9, 0.8),
			Position = UDim2.fromScale(0.05, 0.1),
			TextStrokeTransparency = 0.3,
		})
		-- far-off signs stay readable as a floating label
		if i >= 4 then
			local tag = Instance.new("BillboardGui")
			tag.Size = UDim2.fromOffset(110, 40)
			tag.StudsOffset = Vector3.new(0, 6, 0)
			tag.MaxDistance = 6000
			tag.LightInfluence = 0
			tag.Parent = board
			text(tag, {
				Text = Format.short(distance),
				Size = UDim2.fromScale(1, 1),
				TextStrokeTransparency = 0.2,
			})
		end
	end
end

local function island(def: IslandData.Island, parent: Instance, gen: Rng.Generator)
	local z = Sea.FIRST_WATER + Sea.toWorld(def.distance)
	if z > Scenery.FARTHEST_MODEL or not def.model then
		return
	end
	local m = Build.model(def.id, parent)
	-- off to one side of the throwing lanes, so rocks fly past
	local side = if gen.next() < 0.5 then -1 else 1
	local center = Vector3.new(side * (Scenery.MARKER_HALF_WIDTH + 90 + gen.next() * 80), 0, z)
	local kind = def.model
	if kind == "buoys" then
		for i = 0, 6 do
			local a = i * (TAU / 7)
			buoy(
				center + Vector3.new(math.sin(a) * 12, 0, math.cos(a) * 12),
				if i % 2 == 0 then Palette.awningYellow else Palette.buoyRed,
				m,
				4
			)
		end
		Build.block(
			Vector3.new(12, 1, 12),
			CFrame.new(center + Vector3.new(0, 0.3, 0)),
			Palette.wood,
			m,
			PLANKS
		)
	elseif kind == "rock" then
		for i = 0, 4 do
			local offset = Vector3.new((gen.next() - 0.5) * 30, 0, (gen.next() - 0.5) * 20)
			Build.ellipsoid(
				Vector3.new(18, 30 + gen.next() * 25, 16) * (1 - i * 0.12),
				CFrame.new(center + offset) * CFrame.Angles(0, gen.next() * TAU, 0),
				if i % 2 == 0 then Palette.rock else Palette.rockDark,
				m,
				{ decor = true, material = Enum.Material.Rock }
			)
		end
	else
		-- a sandy island with palms (bigger and further each time)
		local size = if kind == "palm" then 70 elseif kind == "atoll" then 140 else 110
		Build.ellipsoid(Vector3.new(size, 10, size * 0.7), CFrame.new(center), Palette.sand, m, {
			decor = true,
			material = Enum.Material.Sand,
		})
		Build.ellipsoid(
			Vector3.new(size * 0.6, 14, size * 0.4),
			CFrame.new(center + Vector3.new(0, 2, 0)),
			Palette.grass,
			m,
			{
				decor = true,
				material = Enum.Material.Grass,
			}
		)
		for _ = 1, 6 do
			local p = center
				+ Vector3.new(
					(gen.next() - 0.5) * size * 0.45,
					7.5,
					(gen.next() - 0.5) * size * 0.3
				)
			Props.palm(p, 1.6 + gen.next() * 0.6, gen, m)
		end
	end
	-- the island's name, floating above it
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(180, 46)
	tag.StudsOffset = Vector3.new(0, 30, 0)
	tag.MaxDistance = 10000
	tag.LightInfluence = 0
	local anchor = Build.block(Vector3.new(1, 1, 1), CFrame.new(center), Palette.white, m, {
		name = "NameAnchor",
		transparency = 1,
		collide = false,
		decor = true,
		shadow = false,
	})
	tag.Parent = anchor
	text(tag, {
		Text = `🏝️ {def.name}`,
		Size = UDim2.fromScale(1, 1),
		TextStrokeTransparency = 0.2,
	})
end

local function buildIslands(root: Instance)
	local islands = Build.model("Islands", root)
	local gen = Rng.new(23)
	for _, def in IslandData.LIST do
		island(def, islands, gen)
	end
end

-- ===== Everything =====

function Scenery.build(parent: Instance): Built
	local root = Instance.new("Folder")
	root.Name = "SkipARock"
	buildFences(root)
	local piers = Build.model("Piers", root)
	for i, x in Sea.PIER_XS do
		buildPier(x, i, piers)
	end
	buildBeach(root)
	local boards = buildBoardwalk(root)
	buildLighthouse(root)
	buildHills(root)
	buildMarkers(root)
	buildIslands(root)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = seaward(Scenery.SPAWN - Vector3.new(0, 0.5, 0))
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root

	root.Parent = parent
	return { root = root, spawn = spawn, boards = boards }
end

return Scenery
