--!strict
-- Builds the island at server start: ocean, hub with the egg shop, paths, trees,
-- a volcano landmark, and 8 player nests (plots). Everything is generated in
-- code so the place works with no hand-built map; decorate freely in Studio
-- (anything you add to Workspace yourself is left alone).
--
-- Plot space: origin at the plot's center on the ground, -Z faces the hub.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local EggData = require(ReplicatedStorage.Shared.Data.EggData)
local EggModel = require(ReplicatedStorage.Shared.Visual.EggModel)
local Prompts = require(script.Parent.Prompts)

local World = {}

export type PlotInfo = {
	index: number,
	model: Model,
	cframe: CFrame,
	floorTop: number,
	incubators: { BasePart }, -- pedestal tops, index = slot
	incubatorLocks: { BillboardGui },
	incubatorRings: { BasePart },
	traySpots: { CFrame },
	pad: BasePart,
	padLabel: TextLabel,
	signName: TextLabel,
	signInfo: TextLabel,
	signPart: BasePart,
	barrier: { BasePart },
	spawn: SpawnLocation,
	homeSpots: { CFrame },
	dinoFolder: Folder,
	eggFolder: Folder,
	trayFolder: Folder,
}

local HALF = Config.PLOT_SIZE / 2
local FLOOR_TOP = 1

local PLOT_COLORS = {
	Color3.fromRGB(150, 210, 120),
	Color3.fromRGB(120, 200, 150),
	Color3.fromRGB(175, 205, 110),
	Color3.fromRGB(135, 195, 125),
	Color3.fromRGB(160, 215, 135),
	Color3.fromRGB(125, 190, 140),
	Color3.fromRGB(165, 200, 115),
	Color3.fromRGB(140, 205, 120),
}

local WOOD = Color3.fromRGB(150, 105, 65)
local STONE = Color3.fromRGB(165, 160, 150)

World.plots = {} :: { PlotInfo }

type PartProps = {
	name: string?,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?,
	transparency: number?,
	canCollide: boolean?,
	parent: Instance,
}

local function part(props: PartProps): Part
	local p = Instance.new("Part")
	p.Name = props.name or "Part"
	p.Anchored = true
	p.Size = props.size
	p.CFrame = props.cframe
	p.Color = props.color
	p.Material = props.material or Enum.Material.SmoothPlastic
	if props.shape then
		p.Shape = props.shape
	end
	p.Transparency = props.transparency or 0
	p.CanCollide = if props.canCollide == nil then true else props.canCollide
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = props.parent
	return p
end

-- Vertical cylinder (Roblox cylinders run along X, so rotate onto Y).
local function disc(
	name: string,
	diameter: number,
	height: number,
	center: CFrame,
	color: Color3,
	parent: Instance,
	material: Enum.Material?
): Part
	return part({
		name = name,
		size = Vector3.new(height, diameter, diameter),
		cframe = center * CFrame.Angles(0, 0, math.rad(90)),
		color = color,
		material = material,
		shape = Enum.PartType.Cylinder,
		parent = parent,
	})
end

local function ball(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance,
	material: Enum.Material?
): Part
	local p = part({
		name = name,
		size = size,
		cframe = cframe,
		color = color,
		material = material,
		parent = parent,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function billboard(
	parent: Instance,
	name: string,
	size: UDim2,
	offset: Vector3,
	maxDistance: number
): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = size
	gui.StudsOffsetWorldSpace = offset
	gui.AlwaysOnTop = false
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	gui.Parent = parent
	return gui
end

local function label(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	position: UDim2,
	color: Color3?
): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Text = text
	l.TextScaled = true
	l.Font = Enum.Font.FredokaOne
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.3
	l.Parent = parent
	return l
end

local function tree(position: Vector3, height: number, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Tree"
	part({
		name = "Trunk",
		size = Vector3.new(height, 1.6, 1.6),
		cframe = CFrame.new(position + Vector3.new(0, height / 2, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		color = WOOD,
		material = Enum.Material.Wood,
		shape = Enum.PartType.Cylinder,
		parent = model,
	})
	local leafColor = Color3.fromRGB(70, 160, 70)
	ball(
		"Leaves",
		Vector3.new(9, 6, 9),
		CFrame.new(position + Vector3.new(0, height, 0)),
		leafColor,
		model,
		Enum.Material.Grass
	)
	ball(
		"Leaves",
		Vector3.new(6, 5, 6),
		CFrame.new(position + Vector3.new(2, height + 2.5, 1)),
		leafColor:Lerp(Color3.new(1, 1, 0.6), 0.15),
		model,
		Enum.Material.Grass
	)
	ball(
		"Leaves",
		Vector3.new(5, 4, 5),
		CFrame.new(position + Vector3.new(-2, height + 1.5, -1.5)),
		leafColor:Lerp(Color3.new(0, 0.3, 0), 0.2),
		model,
		Enum.Material.Grass
	)
	model.Parent = parent
end

local function buildTerrain(map: Folder)
	part({
		name = "Ocean",
		size = Vector3.new(3000, 2, 3000),
		cframe = CFrame.new(0, -2.5, 0),
		color = Color3.fromRGB(70, 160, 225),
		material = Enum.Material.SmoothPlastic,
		transparency = 0.1,
		parent = map,
	}).Reflectance =
		0.15
	disc(
		"Sand",
		460,
		4,
		CFrame.new(0, -2.6, 0),
		Color3.fromRGB(235, 215, 160),
		map,
		Enum.Material.Sand
	)
	disc(
		"Island",
		420,
		6,
		CFrame.new(0, -3, 0),
		Color3.fromRGB(110, 185, 90),
		map,
		Enum.Material.Grass
	)
end

local function buildHub(map: Folder)
	local hub = Instance.new("Model")
	hub.Name = "Hub"
	disc(
		"Plaza",
		78,
		0.8,
		CFrame.new(0, 0, 0),
		Color3.fromRGB(205, 195, 175),
		hub,
		Enum.Material.Cobblestone
	)

	-- Egg shop kiosk
	disc("Counter", 18, 4, CFrame.new(0, 2.4, 0), WOOD, hub, Enum.Material.Wood)
	for i = 0, 3 do
		local angle = math.rad(45 + i * 90)
		part({
			name = "Pillar",
			size = Vector3.new(10, 1.2, 1.2),
			cframe = CFrame.new(math.cos(angle) * 8.2, 9.4, math.sin(angle) * 8.2)
				* CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(240, 240, 240),
			shape = Enum.PartType.Cylinder,
			parent = hub,
		})
	end
	disc("Roof", 26, 1, CFrame.new(0, 14.6, 0), Color3.fromRGB(230, 70, 70), hub)
	disc("Roof", 19, 1, CFrame.new(0, 15.6, 0), Color3.fromRGB(250, 250, 250), hub)
	disc("Roof", 12, 1, CFrame.new(0, 16.6, 0), Color3.fromRGB(230, 70, 70), hub)
	disc("Roof", 5, 1.4, CFrame.new(0, 17.6, 0), Color3.fromRGB(255, 205, 60), hub)

	-- Display eggs on the counter
	for i, egg in EggData.LIST do
		local angle = math.rad((i - 1) * 90)
		local model = EggModel.build(EggModel.lookForShopEgg(egg.id), 2.8, true)
		model.Name = egg.id .. "Display"
		model:PivotTo(CFrame.new(math.cos(angle) * 6, 4.4, math.sin(angle) * 6))
		model.Parent = hub
	end

	-- Invisible prompt target
	local promptPart = part({
		name = "ShopPrompt",
		size = Vector3.new(4, 4, 4),
		cframe = CFrame.new(0, 3, 0),
		color = Color3.new(1, 1, 1),
		transparency = 1,
		canCollide = false,
		parent = hub,
	})
	Prompts.create(promptPart, {
		action = "OpenUI",
		openUI = "Shop",
		text = "Egg Shop",
		objectText = "🥚",
		audience = "All",
		distance = 16,
	})

	local gui = billboard(
		promptPart,
		"ShopBillboard",
		UDim2.fromOffset(260, 110),
		Vector3.new(0, 19, 0),
		250
	)
	label(
		gui,
		"Title",
		"🥚 EGG SHOP",
		UDim2.fromScale(1, 0.6),
		UDim2.fromScale(0, 0),
		Color3.fromRGB(255, 230, 120)
	)
	label(gui, "Restock", "Restock in 5:00", UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0.6))

	hub.Parent = map
end

local function buildVolcano(map: Folder)
	local angle = math.rad(22.5)
	local base = Vector3.new(math.sin(angle) * 188, 0, math.cos(angle) * 188)
	local volcano = Instance.new("Model")
	volcano.Name = "Volcano"
	local tiers = { { 60, 10 }, { 46, 10 }, { 34, 10 }, { 24, 9 } }
	local y = 0
	for i, tier in tiers do
		local diameter, height = tier[1], tier[2]
		disc(
			"Rock" .. i,
			diameter,
			height,
			CFrame.new(base + Vector3.new(0, y + height / 2, 0)),
			Color3.fromRGB(110 - i * 8, 90 - i * 8, 80 - i * 8),
			volcano,
			Enum.Material.Rock
		)
		y += height
	end
	local crater = disc(
		"Lava",
		16,
		0.6,
		CFrame.new(base + Vector3.new(0, y + 0.1, 0)),
		Color3.fromRGB(255, 110, 30),
		volcano,
		Enum.Material.Neon
	)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 90, 90))
	smoke.Size = NumberSequence.new(4, 10)
	smoke.Transparency = NumberSequence.new(0.4, 1)
	smoke.Lifetime = NumberRange.new(4, 7)
	smoke.Speed = NumberRange.new(4, 7)
	smoke.Rate = 4
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.SpreadAngle = Vector2.new(15, 15)
	smoke.Parent = crater
	volcano.Parent = map
end

local function buildDecorations(map: Folder)
	local decor = Instance.new("Folder")
	decor.Name = "Decorations"
	local count = Config.PLOT_COUNT
	for i = 1, count do
		local angle = (i - 0.5) * (2 * math.pi / count)
		for _, radius in { 110, 158 } do
			tree(
				Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius),
				10 + (i % 3) * 2,
				decor
			)
		end
	end
	for i = 0, 23 do
		local angle = i * math.rad(15)
		local diff = math.abs(((angle - math.rad(22.5)) + math.pi) % (2 * math.pi) - math.pi)
		if diff > math.rad(14) then
			local radius = 196 + (i % 2) * 6
			tree(
				Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius),
				12 + (i % 4) * 2,
				decor
			)
		end
	end
	for i = 0, 11 do
		local angle = i * math.rad(30) + 0.3
		local radius = 176
		ball(
			"Rock",
			Vector3.new(6 + i % 3 * 2, 4 + i % 2 * 2, 5 + i % 4),
			CFrame.new(math.sin(angle) * radius, 0.8, math.cos(angle) * radius),
			Color3.fromRGB(140, 135, 125),
			decor,
			Enum.Material.Rock
		)
	end
	decor.Parent = map
end

local function buildPath(map: Folder, angle: number)
	local inner, outer = 39, Config.PLOT_RING_RADIUS - HALF
	local length = outer - inner
	local mid = (inner + outer) / 2
	local center = Vector3.new(math.sin(angle) * mid, 0.05, math.cos(angle) * mid)
	part({
		name = "Path",
		size = Vector3.new(10, 0.3, length + 2),
		cframe = CFrame.lookAt(center, Vector3.new(0, 0.05, 0)),
		color = Color3.fromRGB(225, 200, 145),
		material = Enum.Material.Sand,
		parent = map,
	})
end

local function fenceSegment(model: Model, cf: CFrame, a: Vector3, b: Vector3)
	local length = (b - a).Magnitude
	local direction = (b - a).Unit
	local posts = math.max(1, math.floor(length / 8))
	for i = 0, posts do
		local p = a + direction * (length * i / posts)
		part({
			name = "Post",
			size = Vector3.new(1, 4, 1),
			cframe = cf * CFrame.new(p + Vector3.new(0, FLOOR_TOP + 2, 0)),
			color = WOOD,
			material = Enum.Material.Wood,
			parent = model,
		})
	end
	for _, height in { 1.8, 3.2 } do
		local mid = (a + b) / 2 + Vector3.new(0, FLOOR_TOP + height, 0)
		part({
			name = "Rail",
			size = Vector3.new(0.4, 0.5, length),
			cframe = cf * CFrame.lookAt(mid, mid + direction),
			color = WOOD,
			material = Enum.Material.Wood,
			parent = model,
		})
	end
end

local function buildPlot(index: number, plotsFolder: Folder): PlotInfo
	local angle = (index - 1) * (2 * math.pi / Config.PLOT_COUNT)
	local position = Vector3.new(
		math.sin(angle) * Config.PLOT_RING_RADIUS,
		0,
		math.cos(angle) * Config.PLOT_RING_RADIUS
	)
	local cf = CFrame.lookAt(position, Vector3.new(0, 0, 0))

	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("OwnerId", 0)
	model:SetAttribute("LockedUntil", 0)
	model:SetAttribute("ShieldUntil", 0)

	part({
		name = "Floor",
		size = Vector3.new(Config.PLOT_SIZE, 1, Config.PLOT_SIZE),
		cframe = cf * CFrame.new(0, FLOOR_TOP - 0.5, 0),
		color = PLOT_COLORS[(index - 1) % #PLOT_COLORS + 1],
		material = Enum.Material.Grass,
		parent = model,
	})

	-- Fence with an entrance gap toward the hub
	local gap = 11
	fenceSegment(model, cf, Vector3.new(-HALF, 0, HALF), Vector3.new(HALF, 0, HALF))
	fenceSegment(model, cf, Vector3.new(-HALF, 0, -HALF), Vector3.new(-HALF, 0, HALF))
	fenceSegment(model, cf, Vector3.new(HALF, 0, -HALF), Vector3.new(HALF, 0, HALF))
	fenceSegment(model, cf, Vector3.new(-HALF, 0, -HALF), Vector3.new(-gap, 0, -HALF))
	fenceSegment(model, cf, Vector3.new(gap, 0, -HALF), Vector3.new(HALF, 0, -HALF))

	-- Gate pillars + name sign
	for _, side in { -1, 1 } do
		part({
			name = "GatePillar",
			size = Vector3.new(2, 12, 2),
			cframe = cf * CFrame.new(side * gap, FLOOR_TOP + 6, -HALF),
			color = STONE,
			material = Enum.Material.Cobblestone,
			parent = model,
		})
	end
	local signPart = part({
		name = "Sign",
		size = Vector3.new(24, 4.5, 0.8),
		cframe = cf * CFrame.new(0, FLOOR_TOP + 11, -HALF),
		color = WOOD,
		material = Enum.Material.Wood,
		parent = model,
	})
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.LightInfluence = 0
	surface.PixelsPerStud = 40
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.Parent = signPart
	local signName = label(
		surface,
		"OwnerName",
		"Empty Nest",
		UDim2.fromScale(0.96, 0.62),
		UDim2.fromScale(0.02, 0.04)
	)
	local signInfo = label(
		surface,
		"Info",
		"Walk in to claim!",
		UDim2.fromScale(0.96, 0.32),
		UDim2.fromScale(0.02, 0.64),
		Color3.fromRGB(255, 230, 160)
	)
	-- Same text on the inside of the sign
	local inside = surface:Clone()
	inside.Face = Enum.NormalId.Back
	inside.Parent = signPart

	-- Incubators
	local incubators: { BasePart } = {}
	local incubatorLocks: { BillboardGui } = {}
	local incubatorRings: { BasePart } = {}
	for slot = 1, Config.MAX_INCUBATORS do
		local x = -24 + (slot - 1) * 12
		local base = cf * CFrame.new(x, FLOOR_TOP, 24)
		local pedestal = disc(
			"Incubator" .. slot,
			5.5,
			2,
			base * CFrame.new(0, 1, 0),
			STONE,
			model,
			Enum.Material.Slate
		)
		pedestal:SetAttribute("Slot", slot)
		local ring = disc(
			"HeatRing" .. slot,
			6,
			0.3,
			base * CFrame.new(0, 2.1, 0),
			Color3.fromRGB(255, 140, 40),
			model,
			Enum.Material.Neon
		)
		ring.CanCollide = false
		local lock =
			billboard(pedestal, "Lock", UDim2.fromOffset(140, 60), Vector3.new(0, 3.5, 0), 60)
		label(lock, "Text", "🔒 Upgrade", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
		lock.Enabled = false
		incubators[slot] = pedestal
		incubatorLocks[slot] = lock
		incubatorRings[slot] = ring
	end

	-- Laid-egg tray (the nest thieves raid at night)
	local trayCenter = cf * CFrame.new(18, FLOOR_TOP, -22)
	disc(
		"Tray",
		9,
		0.4,
		trayCenter * CFrame.new(0, 0.2, 0),
		Color3.fromRGB(220, 190, 110),
		model,
		Enum.Material.Grass
	)
	for i = 0, 9 do
		local a = i * math.rad(36)
		ball(
			"Twig",
			Vector3.new(1.4, 1, 2.6),
			trayCenter
				* CFrame.new(math.cos(a) * 4.2, 0.5, math.sin(a) * 4.2)
				* CFrame.Angles(0, -a, 0),
			Color3.fromRGB(130, 95, 55),
			model,
			Enum.Material.Wood
		)
	end
	local traySpots: { CFrame } = {}
	for i = 0, Config.TRAY_CAPACITY - 1 do
		local a = i * (2 * math.pi / Config.TRAY_CAPACITY)
		table.insert(traySpots, trayCenter * CFrame.new(math.cos(a) * 2.4, 0.4, math.sin(a) * 2.4))
	end
	local trayLabelPart = part({
		name = "TrayLabel",
		size = Vector3.new(1, 1, 1),
		cframe = trayCenter * CFrame.new(0, 1, 0),
		color = Color3.new(1, 1, 1),
		transparency = 1,
		canCollide = false,
		parent = model,
	})
	local trayGui =
		billboard(trayLabelPart, "Label", UDim2.fromOffset(160, 40), Vector3.new(0, 4, 0), 60)
	label(trayGui, "Text", "🥚 Laid Eggs", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))

	-- Coin pad
	local pad = disc(
		"CoinPad",
		8,
		0.5,
		cf * CFrame.new(-18, FLOOR_TOP + 0.25, -22),
		Color3.fromRGB(255, 200, 50),
		model
	)
	pad.Reflectance = 0.25
	local padGui = billboard(pad, "Coins", UDim2.fromOffset(180, 60), Vector3.new(0, 4, 0), 80)
	local padLabel = label(
		padGui,
		"Amount",
		"💰 0",
		UDim2.fromScale(1, 1),
		UDim2.fromScale(0, 0),
		Color3.fromRGB(255, 230, 120)
	)

	-- Spawn
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = cf * CFrame.new(0, FLOOR_TOP - 0.4, -22)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Enabled = true
	spawn.Parent = model
	for _, child in spawn:GetChildren() do
		if child:IsA("Decal") then
			child:Destroy()
		end
	end

	-- Lock barrier (shown while the gate is locked)
	local barrier: { BasePart } = {}
	local wallHeight = 16
	local walls = {
		{ Vector3.new(Config.PLOT_SIZE, wallHeight, 0.6), Vector3.new(0, 0, -HALF - 0.4) },
		{ Vector3.new(Config.PLOT_SIZE, wallHeight, 0.6), Vector3.new(0, 0, HALF + 0.4) },
		{ Vector3.new(0.6, wallHeight, Config.PLOT_SIZE), Vector3.new(-HALF - 0.4, 0, 0) },
		{ Vector3.new(0.6, wallHeight, Config.PLOT_SIZE), Vector3.new(HALF + 0.4, 0, 0) },
	}
	for _, wall in walls do
		local p = part({
			name = "Barrier",
			size = wall[1],
			cframe = cf * CFrame.new(wall[2] + Vector3.new(0, FLOOR_TOP + wallHeight / 2, 0)),
			color = Color3.fromRGB(255, 80, 80),
			material = Enum.Material.ForceField,
			transparency = 1,
			canCollide = false,
			parent = model,
		})
		p.CanQuery = false
		p.CanTouch = false
		table.insert(barrier, p)
	end

	-- Where dinos live (4 x 4 grid)
	local homeSpots: { CFrame } = {}
	for _, z in { -12, -3, 6, 15 } do
		for _, x in { -21, -7, 7, 21 } do
			table.insert(homeSpots, cf * CFrame.new(x, FLOOR_TOP, z))
		end
	end

	local dinoFolder = Instance.new("Folder")
	dinoFolder.Name = "Dinos"
	dinoFolder.Parent = model
	local eggFolder = Instance.new("Folder")
	eggFolder.Name = "Eggs"
	eggFolder.Parent = model
	local trayFolder = Instance.new("Folder")
	trayFolder.Name = "Tray"
	trayFolder.Parent = model

	model.Parent = plotsFolder

	return {
		index = index,
		model = model,
		cframe = cf,
		floorTop = FLOOR_TOP,
		incubators = incubators,
		incubatorLocks = incubatorLocks,
		incubatorRings = incubatorRings,
		traySpots = traySpots,
		pad = pad,
		padLabel = padLabel,
		signName = signName,
		signInfo = signInfo,
		signPart = signPart,
		barrier = barrier,
		spawn = spawn,
		homeSpots = homeSpots,
		dinoFolder = dinoFolder,
		eggFolder = eggFolder,
		trayFolder = trayFolder,
	}
end

function World.getPlot(index: number): PlotInfo?
	return World.plots[index]
end

-- Is a world position inside a plot (with optional margin in studs)?
function World.isInside(index: number, position: Vector3, margin: number?): boolean
	local plot = World.plots[index]
	if not plot then
		return false
	end
	local m = margin or 0
	local localPos = plot.cframe:PointToObjectSpace(position)
	return math.abs(localPos.X) <= HALF + m
		and math.abs(localPos.Z) <= HALF + m
		and localPos.Y > -6
		and localPos.Y < 80
end

-- Just outside a plot's gate, facing the hub.
function World.outsideGate(index: number): CFrame
	local plot = World.plots[index]
	return plot.cframe * CFrame.new(0, FLOOR_TOP + 3, -HALF - 10)
end

-- Set a text on both faces of the sign.
function World.setSign(plot: PlotInfo, name: string, info: string)
	for _, surface in plot.signPart:GetChildren() do
		if surface:IsA("SurfaceGui") then
			local n = surface:FindFirstChild("OwnerName")
			local i = surface:FindFirstChild("Info")
			if n and n:IsA("TextLabel") then
				n.Text = name
			end
			if i and i:IsA("TextLabel") then
				i.Text = info
			end
		end
	end
end

function World.init()
	-- The edit-mode "Press Play" sign isn't needed once the game runs.
	local sign = Workspace:FindFirstChild("PressPlay")
	if sign then
		sign:Destroy()
	end

	local map = Instance.new("Folder")
	map.Name = "Map"
	buildTerrain(map)
	buildHub(map)
	buildVolcano(map)
	buildDecorations(map)
	for i = 1, Config.PLOT_COUNT do
		buildPath(map, (i - 1) * (2 * math.pi / Config.PLOT_COUNT))
	end
	map.Parent = Workspace

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = Workspace
	for i = 1, Config.PLOT_COUNT do
		World.plots[i] = buildPlot(i, plotsFolder)
	end
end

return World
