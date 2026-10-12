--!strict
-- Builds the world at server start: the island scenery (Lib/Island) and 8
-- player nests (plots). Everything is generated in code so the place works
-- with no hand-built map; decorate freely in Studio (anything you add to
-- Workspace yourself is left alone).
--
-- Plot space: origin at the plot's center on the ground, -Z faces the hub.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Rng = require(ReplicatedStorage.Shared.Util.Rng)
local Build = require(script.Parent.Parent.Lib.Build)
local Island = require(script.Parent.Parent.Lib.Island)
local Props = require(script.Parent.Parent.Lib.Props)
local Prompts = require(script.Parent.Prompts)

local World = {}

export type PlotInfo = {
	index: number,
	model: Model,
	cframe: CFrame,
	floorTop: number,
	accent: Color3,
	incubators: { BasePart }, -- pedestal tops, index = slot
	incubatorLocks: { BillboardGui },
	incubatorRings: { BasePart },
	traySpots: { CFrame },
	pad: BasePart,
	padLabel: TextLabel,
	signName: TextLabel,
	signInfo: TextLabel,
	signPart: BasePart,
	ownerTag: TextLabel,
	barrier: { BasePart },
	spawn: SpawnLocation,
	homeSpots: { CFrame },
	dinoFolder: Folder,
	eggFolder: Folder,
	trayFolder: Folder,
}

local HALF = Config.PLOT_SIZE / 2
local FLOOR_TOP = 1
local GATE_GAP = 11

local GOLD = Color3.fromRGB(255, 205, 60)
local GOLD_DARK = Color3.fromRGB(226, 156, 38)

World.plots = {} :: { PlotInfo }

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
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(43, 33, 64)
	stroke.Thickness = 2.5
	stroke.Parent = l
	l.Parent = parent
	return l
end

-- ===== Nest pieces =====

-- Chunky wooden fence along a side of the plot; posts get the nest's colour.
local function fenceSegment(model: Model, cf: CFrame, a: Vector3, b: Vector3, accent: Color3)
	local length = (b - a).Magnitude
	local direction = (b - a).Unit
	local posts = math.max(1, math.floor(length / 8 + 0.5))
	for i = 0, posts do
		local p = a + direction * (length * i / posts)
		Build.block(
			Vector3.new(1.4, 4.4, 1.4),
			cf * CFrame.new(p + Vector3.new(0, FLOOR_TOP + 2.2, 0)),
			Palette.wood,
			model,
			{ name = "Post" }
		)
		Build.ball(
			1.9,
			(cf * CFrame.new(p + Vector3.new(0, FLOOR_TOP + 4.6, 0))).Position,
			accent,
			model,
			{
				name = "PostCap",
				decor = true,
				shadow = false,
			}
		)
	end
	for _, height in { 1.7, 3.3 } do
		local lift = Vector3.new(0, FLOOR_TOP + height, 0)
		Build.beam(
			(cf * CFrame.new(a + lift)).Position,
			(cf * CFrame.new(b + lift)).Position,
			0.5,
			0.75,
			Palette.woodLight,
			model,
			{
				name = "Rail",
			}
		)
	end
end

-- Lantern hanging from a bracket on the outside of a gate pillar.
local function lantern(model: Model, position: Vector3, outward: Vector3, accent: Color3)
	local tip = position + outward * 2.6
	Build.beam(position, tip, 0.45, 0.45, Palette.woodDark, model, { decor = true, shadow = false })
	local options = { decor = true, shadow = false, collide = false }
	Build.rod(tip, tip - Vector3.new(0, 0.6, 0), 0.15, Palette.woodDark, model, options)
	Build.disc(1.6, 0.35, CFrame.new(tip - Vector3.new(0, 0.75, 0)), accent, model, options)
	local bulb = Build.ball(1.25, tip - Vector3.new(0, 1.5, 0), Palette.lampGlow, model, {
		name = "Lantern",
		material = Enum.Material.Neon,
		decor = true,
		shadow = false,
		collide = false,
	})
	local light = Instance.new("PointLight")
	light.Color = Palette.lampGlow
	light.Range = 16
	light.Brightness = 1.4
	light.Shadows = false
	light.Enabled = false
	light.Parent = bulb
	CollectionService:AddTag(light, Props.NIGHT_LIGHT_TAG)
end

local function buildGate(model: Model, cf: CFrame, accent: Color3)
	local top = FLOOR_TOP + 11
	for _, side in { -1, 1 } do
		local foot = (cf * CFrame.new(side * GATE_GAP, FLOOR_TOP - 0.5, -HALF)).Position
		local head = (cf * CFrame.new(side * GATE_GAP, top, -HALF)).Position
		Build.rod(foot, head, 2.6, Palette.woodDark, model, { name = "GatePillar" })
		Build.disc(
			3.1,
			0.7,
			CFrame.new(head - Vector3.new(0, 1.4, 0)),
			accent,
			model,
			{ decor = true }
		)
		Build.ball(
			3.4,
			head + Vector3.new(0, 0.9, 0),
			accent,
			model,
			{ name = "GateCap", decor = true }
		)
		local outward = cf:VectorToWorldSpace(Vector3.new(0, 0, -1))
		lantern(
			model,
			(cf * CFrame.new(side * GATE_GAP, FLOOR_TOP + 7.5, -HALF)).Position,
			outward,
			accent
		)
	end
	-- log arch between the pillars
	local left = (cf * CFrame.new(-GATE_GAP, top - 0.6, -HALF)).Position
	local right = (cf * CFrame.new(GATE_GAP, top - 0.6, -HALF)).Position
	Build.rod(left, right, 1.6, Palette.woodLight, model, { name = "GateArch", decor = true })
	-- ramp up onto the raised nest floor
	Build.wedge(
		Vector3.new(GATE_GAP * 2, FLOOR_TOP, 3),
		cf * CFrame.new(0, FLOOR_TOP / 2, -HALF - 1.5),
		Palette.path,
		model,
		{ name = "Ramp" }
	)
end

-- Name board beside the gate (outside the fence, facing the paths).
local function buildSign(model: Model, cf: CFrame, accent: Color3): (BasePart, TextLabel, TextLabel)
	local center = cf * CFrame.new(-GATE_GAP - 10.5, 5.6, -HALF - 3.2)
	for _, x in { -4.6, 4.6 } do
		local foot = (center * CFrame.new(x, -5.6, 0)).Position
		Build.rod(
			foot,
			foot + Vector3.new(0, 3.5, 0),
			0.9,
			Palette.woodDark,
			model,
			{ decor = true }
		)
	end
	local board =
		Build.block(Vector3.new(13, 6, 0.8), center, Palette.wood, model, { name = "Sign" })
	Build.block(
		Vector3.new(13.8, 1, 1.1),
		center * CFrame.new(0, 3.3, 0),
		accent,
		model,
		{ decor = true }
	)
	Build.block(
		Vector3.new(12, 5, 0.2),
		center * CFrame.new(0, -0.2, 0),
		Palette.woodLight,
		model,
		{
			decor = true,
			shadow = false,
		}
	)
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.LightInfluence = 0
	surface.PixelsPerStud = 40
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.Parent = board
	local signName = label(
		surface,
		"OwnerName",
		"Empty Nest",
		UDim2.fromScale(0.9, 0.5),
		UDim2.fromScale(0.05, 0.1)
	)
	local signInfo = label(
		surface,
		"Info",
		"Walk in to claim!",
		UDim2.fromScale(0.9, 0.3),
		UDim2.fromScale(0.05, 0.62),
		Color3.fromRGB(255, 236, 170)
	)
	local inside = surface:Clone()
	inside.Face = Enum.NormalId.Back
	inside.Parent = board
	return board, signName, signInfo
end

-- Floating name over the gate so friends can find each other's nests.
local function buildOwnerTag(model: Model, cf: CFrame): TextLabel
	local anchor = Build.block(
		Vector3.new(1, 1, 1),
		cf * CFrame.new(0, FLOOR_TOP + 14.5, -HALF),
		Palette.white,
		model,
		{
			name = "OwnerTagAnchor",
			transparency = 1,
			collide = false,
			decor = true,
		}
	)
	local gui = billboard(anchor, "OwnerTag", UDim2.fromOffset(260, 46), Vector3.zero, 220)
	return label(gui, "Name", "Empty Nest", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
end

local function buildIncubator(
	model: Model,
	base: CFrame,
	slot: number,
	accent: Color3
): (BasePart, BillboardGui, BasePart)
	Build.disc(6.4, 0.6, base * CFrame.new(0, 0.3, 0), Palette.stoneDark, model, { decor = true })
	local pedestal = Build.disc(
		5.2,
		2,
		base * CFrame.new(0, 1, 0),
		Palette.stone,
		model,
		{ name = "Incubator" .. slot }
	)
	pedestal:SetAttribute("Slot", slot)
	Build.disc(
		5.5,
		0.5,
		base * CFrame.new(0, 1.2, 0),
		accent,
		model,
		{ decor = true, shadow = false }
	)
	-- straw nest around the egg spot
	for i = 0, 7 do
		local a = i * (2 * math.pi / 8)
		local cf = base
			* CFrame.new(math.sin(a) * 2.25, 2.2, math.cos(a) * 2.25)
			* CFrame.Angles(0, a + math.pi / 2, 0)
		Build.ellipsoid(
			Vector3.new(1, 0.9, 2.3),
			cf,
			if i % 2 == 0 then Palette.sandDark else Palette.woodLight,
			model,
			{
				decor = true,
				shadow = false,
				collide = false,
			}
		)
	end
	local ring = Build.disc(6, 0.3, base * CFrame.new(0, 2.1, 0), Palette.orange, model, {
		name = "HeatRing" .. slot,
		material = Enum.Material.Neon,
		collide = false,
		decor = true,
		shadow = false,
	})
	local lock = billboard(pedestal, "Lock", UDim2.fromOffset(140, 56), Vector3.new(0, 3.5, 0), 60)
	label(lock, "Text", "🔒 Upgrade", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	lock.Enabled = false
	return pedestal, lock, ring
end

local function buildTray(model: Model, center: CFrame): { CFrame }
	Build.disc(
		9.2,
		0.4,
		center * CFrame.new(0, 0.2, 0),
		Palette.sandLight,
		model,
		{ name = "Tray", decor = true }
	)
	for i = 0, 9 do
		local a = i * math.rad(36)
		local cf = center
			* CFrame.new(math.cos(a) * 4.3, 0.55, math.sin(a) * 4.3)
			* CFrame.Angles(0, -a, 0)
		Build.ellipsoid(
			Vector3.new(1.5, 1.1, 2.8),
			cf,
			if i % 2 == 0 then Palette.woodDark else Palette.wood,
			model,
			{
				name = "Twig",
				decor = true,
			}
		)
	end
	local spots: { CFrame } = {}
	for i = 0, Config.TRAY_CAPACITY - 1 do
		local a = i * (2 * math.pi / Config.TRAY_CAPACITY)
		table.insert(spots, center * CFrame.new(math.cos(a) * 2.4, 0.4, math.sin(a) * 2.4))
	end
	local labelPart =
		Build.block(Vector3.new(1, 1, 1), center * CFrame.new(0, 1, 0), Palette.white, model, {
			name = "TrayLabel",
			transparency = 1,
			collide = false,
			decor = true,
		})
	local gui = billboard(labelPart, "Label", UDim2.fromOffset(160, 40), Vector3.new(0, 4, 0), 60)
	label(gui, "Text", "🥚 Laid Eggs", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	return spots
end

local function buildCoinPad(model: Model, center: CFrame): (BasePart, TextLabel)
	Build.disc(9.4, 0.4, center * CFrame.new(0, 0.2, 0), GOLD_DARK, model, { decor = true })
	local pad = Build.disc(8, 0.5, center * CFrame.new(0, 0.35, 0), GOLD, model, {
		name = "CoinPad",
		reflectance = 0.2,
	})
	-- a little stack of coins beside the pad
	for i = 0, 2 do
		Build.disc(
			2,
			0.45,
			center * CFrame.new(4.8, 0.25 + i * 0.5, 2.4),
			if i % 2 == 0 then GOLD else GOLD_DARK,
			model,
			{
				decor = true,
				shadow = false,
			}
		)
	end
	local gui = billboard(pad, "Coins", UDim2.fromOffset(180, 60), Vector3.new(0, 4, 0), 80)
	local padLabel = label(
		gui,
		"Amount",
		"💰 0",
		UDim2.fromScale(1, 1),
		UDim2.fromScale(0, 0),
		Color3.fromRGB(255, 230, 120)
	)
	return pad, padLabel
end

local function buildPlot(index: number, plotsFolder: Folder): PlotInfo
	local angle = (index - 1) * (2 * math.pi / Config.PLOT_COUNT)
	local position = Build.polar(angle, Config.PLOT_RING_RADIUS)
	local cf = CFrame.lookAt(position, Vector3.new(0, 0, 0))
	local accent = Palette.NEST_ACCENTS[(index - 1) % #Palette.NEST_ACCENTS + 1]

	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("OwnerId", 0)
	model:SetAttribute("LockedUntil", 0)
	model:SetAttribute("ShieldUntil", 0)

	-- raised garden-bed floor in a wooden frame
	Build.block(
		Vector3.new(Config.PLOT_SIZE + 2.4, 1.4, Config.PLOT_SIZE + 2.4),
		cf * CFrame.new(0, 0, 0),
		Palette.wood,
		model,
		{
			name = "Frame",
			decor = true,
		}
	)
	Build.block(
		Vector3.new(Config.PLOT_SIZE, 1, Config.PLOT_SIZE),
		cf * CFrame.new(0, FLOOR_TOP - 0.5, 0),
		Palette.grassLight,
		model,
		{
			name = "Floor",
		}
	)

	local gate = GATE_GAP
	fenceSegment(model, cf, Vector3.new(-HALF, 0, HALF), Vector3.new(HALF, 0, HALF), accent)
	fenceSegment(model, cf, Vector3.new(-HALF, 0, -HALF), Vector3.new(-HALF, 0, HALF), accent)
	fenceSegment(model, cf, Vector3.new(HALF, 0, -HALF), Vector3.new(HALF, 0, HALF), accent)
	fenceSegment(
		model,
		cf,
		Vector3.new(-HALF, 0, -HALF),
		Vector3.new(-gate - 1.3, 0, -HALF),
		accent
	)
	fenceSegment(model, cf, Vector3.new(gate + 1.3, 0, -HALF), Vector3.new(HALF, 0, -HALF), accent)
	buildGate(model, cf, accent)
	local signPart, signName, signInfo = buildSign(model, cf, accent)
	local ownerTag = buildOwnerTag(model, cf)

	-- incubators along the back
	local incubators: { BasePart } = {}
	local incubatorLocks: { BillboardGui } = {}
	local incubatorRings: { BasePart } = {}
	for slot = 1, Config.MAX_INCUBATORS do
		local x = -24 + (slot - 1) * 12
		local pedestal, lock, ring =
			buildIncubator(model, cf * CFrame.new(x, FLOOR_TOP, 24), slot, accent)
		incubators[slot] = pedestal
		incubatorLocks[slot] = lock
		incubatorRings[slot] = ring
	end

	local traySpots = buildTray(model, cf * CFrame.new(18, FLOOR_TOP, -22))
	local pad, padLabel = buildCoinPad(model, cf * CFrame.new(-18, FLOOR_TOP, -22))

	-- greenery in the corners (clear of the dinos' wander area)
	local gen = Rng.new(index * 17)
	for _, corner in { Vector3.new(-28.5, 0, 28.8), Vector3.new(28.5, 0, 28.8) } do
		Props.fern(
			(cf * CFrame.new(corner + Vector3.new(0, FLOOR_TOP, 0))).Position,
			0.75,
			gen,
			model
		)
	end
	for _, corner in { Vector3.new(-28.6, 0, -28.6), Vector3.new(28.6, 0, -28.6) } do
		Props.flowers(
			(cf * CFrame.new(corner + Vector3.new(0, FLOOR_TOP, 0))).Position,
			0.8,
			gen,
			model
		)
	end

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
		local p = Build.block(
			wall[1],
			cf * CFrame.new(wall[2] + Vector3.new(0, FLOOR_TOP + wallHeight / 2, 0)),
			Palette.red,
			model,
			{
				name = "Barrier",
				material = Enum.Material.ForceField,
				transparency = 1,
				collide = false,
				decor = true,
			}
		)
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
		accent = accent,
		incubators = incubators,
		incubatorLocks = incubatorLocks,
		incubatorRings = incubatorRings,
		traySpots = traySpots,
		pad = pad,
		padLabel = padLabel,
		signName = signName,
		signInfo = signInfo,
		signPart = signPart,
		ownerTag = ownerTag,
		barrier = barrier,
		spawn = spawn,
		homeSpots = homeSpots,
		dinoFolder = dinoFolder,
		eggFolder = eggFolder,
		trayFolder = trayFolder,
	}
end

-- ===== Shop =====

local function setUpShop(promptPart: BasePart)
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
		Vector3.new(0, 30, 0),
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
	label(gui, "Restock", "New stock in 5:00", UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0.6))
end

-- ===== API =====

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

-- Set the owner text on the sign (both faces) and the floating name tag.
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
	plot.ownerTag.Text = name
end

function World.init()
	-- The edit-mode "Press Play" sign isn't needed once the game runs.
	local sign = Workspace:FindFirstChild("PressPlay")
	if sign then
		sign:Destroy()
	end

	local map = Instance.new("Folder")
	map.Name = "Map"
	local shopPrompt = Island.build(map)
	setUpShop(shopPrompt)
	map.Parent = Workspace

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = Workspace
	for i = 1, Config.PLOT_COUNT do
		World.plots[i] = buildPlot(i, plotsFolder)
	end
end

return World
