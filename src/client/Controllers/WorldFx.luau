--!strict
-- Client-only visuals: dinos wandering around their home spot, rainbow
-- mutation colors, egg timers and wobbles, day/night lighting, and storm
-- weather. None of this affects gameplay; it only makes the world feel alive.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Cycle = require(ReplicatedStorage.Shared.Util.Cycle)
local DinoModel = require(ReplicatedStorage.Shared.Visual.DinoModel)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Tags = require(ReplicatedStorage.Shared.Tags)

local WorldFx = {}

local EGG_TAG = "IncubatorEgg"
local WANDER_RADIUS = 7
local WALK_DISTANCE = 16

-- ===== Dino wandering =====
-- Each dino roams its whole pen: it turns toward a random nearby spot inside
-- the fence, hops along with a little waddle, then rests and breathes before
-- the next walk.
-- Simulated per frame on the client (pure decoration), skipped when far away.

type Walker = {
	root: BasePart,
	home: Vector3,
	position: Vector3,
	facing: Vector3,
	target: Vector3?,
	waitUntil: number,
	phase: number,
	hop: number,
	speed: number,
	rng: Random,
	floor: BasePart?, -- the pen's floor; walks stay inside it
	margin: number, -- distance kept from the fence
	homeCheck: number, -- frames until we look for a new home spot
}

local walkers: { [Model]: Walker } = {}
local FAR = 150 -- dinos further from the camera than this stand still
local NEAR = 70 -- idle dinos only breathe when this close
local HOME_CHECK_FRAMES = 30

local function flatten(v: Vector3, fallback: Vector3): Vector3
	local flat = Vector3.new(v.X, 0, v.Z)
	return if flat.Magnitude > 1e-4 then flat.Unit else fallback
end

local function addWalker(model: Model, tries: number?)
	if walkers[model] or not model.Parent then
		return
	end
	local root = model.PrimaryPart
	local home = model:GetAttribute("Home")
	if not root or typeof(home) ~= "CFrame" then
		-- Its parts can arrive a moment after the model itself; try again.
		local attempt = (tries or 0) + 1
		if attempt <= 20 then
			task.delay(0.25, addWalker, model, attempt)
		end
		return
	end
	local height = model:GetAttribute("Height")
	local h = if typeof(height) == "number" then height else 4
	local rng = Random.new()
	local plot = model.Parent and model.Parent.Parent
	local floor = plot and plot:FindFirstChild("Floor")
	walkers[model] = {
		root = root,
		home = home.Position,
		position = root.CFrame.Position,
		facing = flatten(home.LookVector, Vector3.new(0, 0, -1)),
		target = nil,
		waitUntil = os.clock() + rng:NextNumber(0, 3),
		phase = rng:NextNumber(0, 10),
		hop = math.clamp(h * 0.06, 0.12, 1.2),
		speed = math.clamp(2.5 + h * 0.35, 2.5, 8),
		rng = rng,
		floor = if floor and floor:IsA("BasePart") then floor else nil,
		margin = math.clamp(h * 0.6, 4, 10),
		homeCheck = rng:NextInteger(1, HOME_CHECK_FRAMES),
	}
end

-- A random spot a short walk away, kept inside the pen (or near home if the
-- pen's floor can't be found).
local function pickTarget(w: Walker): Vector3
	local angle = w.rng:NextNumber(0, math.pi * 2)
	local floor = w.floor
	if not floor or not floor.Parent then
		local radius = w.rng:NextNumber(1, WANDER_RADIUS)
		return w.home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	end
	local radius = w.rng:NextNumber(4, WALK_DISTANCE)
	local goal = w.position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	local localGoal = floor.CFrame:PointToObjectSpace(goal)
	local halfX = math.max(floor.Size.X / 2 - w.margin, 0)
	local halfZ = math.max(floor.Size.Z / 2 - w.margin, 0)
	local inside = Vector3.new(
		math.clamp(localGoal.X, -halfX, halfX),
		0,
		math.clamp(localGoal.Z, -halfZ, halfZ)
	)
	local world = floor.CFrame:PointToWorldSpace(inside)
	return Vector3.new(world.X, w.home.Y, world.Z)
end

local function stepWalkers(dt: number)
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local now = os.clock()
	for model, w in walkers do
		if not model.Parent then
			walkers[model] = nil
			continue
		end
		local away = (w.position - eye).Magnitude
		if away > FAR then
			continue
		end
		-- the server moves dinos to a new home when the nest is rearranged
		w.homeCheck -= 1
		if w.homeCheck <= 0 then
			w.homeCheck = HOME_CHECK_FRAMES
			local home = model:GetAttribute("Home")
			if typeof(home) == "CFrame" and (home.Position - w.home).Magnitude > 0.1 then
				w.home = home.Position
				w.position = home.Position
				w.target = nil
			end
		end
		local moving = false
		local target = w.target
		if target then
			local flat = Vector3.new(target.X - w.position.X, 0, target.Z - w.position.Z)
			local distance = flat.Magnitude
			if distance < 0.25 then
				w.target = nil
				w.waitUntil = now + w.rng:NextNumber(2, 6)
			else
				local direction = flat.Unit
				w.facing = flatten(w.facing:Lerp(direction, math.min(1, dt * 5)), direction)
				if w.facing:Dot(direction) > 0.85 then
					w.position += direction * math.min(distance, w.speed * dt)
					moving = true
				end
			end
		elseif now >= w.waitUntil then
			w.target = pickTarget(w)
		end
		if not moving and away > NEAR then
			continue -- too far to see it breathe
		end
		w.phase += dt * (if moving then 4 + w.speed * 1.5 else 2)
		local lift = if moving
			then math.abs(math.sin(w.phase)) * w.hop
			else (math.sin(w.phase) * 0.5 + 0.5) * w.hop * 0.15
		local waddle = if moving then math.sin(w.phase) * 0.07 else 0
		local p = w.position + Vector3.new(0, lift, 0)
		w.root.CFrame = CFrame.lookAt(p, p + w.facing) * CFrame.Angles(0, 0, waddle)
	end
end

local function onDinoAdded(instance: Instance)
	if instance:IsA("Model") then
		addWalker(instance)
	end
end

-- ===== Rainbow mutation =====

-- Rainbow parts, kept up to date by tag signals (part -> hue offset).
local rainbowParts: { [BasePart]: number } = {}
local rainbowWait = 0

local function addRainbow(instance: Instance)
	if instance:IsA("BasePart") then
		rainbowParts[instance] = math.random() * 0.3
	end
end

local function rainbowStep(dt: number)
	rainbowWait -= dt
	if rainbowWait > 0 then
		return
	end
	rainbowWait = 1 / 15
	local hue = (os.clock() * 0.25) % 1
	for part, offset in rainbowParts do
		part.Color = Color3.fromHSV((hue + offset) % 1, 0.65, 1)
	end
end

-- ===== Incubator eggs =====

local function updateEgg(model: Instance, now: number)
	if not model:IsA("Model") then
		return
	end
	local hatchAt = model:GetAttribute("HatchAt")
	local root = model.PrimaryPart
	if typeof(hatchAt) ~= "number" or not root then
		return
	end
	local gui = root:FindFirstChild("Timer")
	local text = gui and gui:FindFirstChild("Text")
	local ready = hatchAt <= now
	if text and text:IsA("TextLabel") then
		local friendWarm = model:GetAttribute("FriendWarmAt")
		local warmedRecently = typeof(friendWarm) == "number" and now - friendWarm < 2
		if ready then
			text.Text = "🐣 Ready to hatch!"
			text.TextColor3 = Color3.fromRGB(120, 255, 120)
		else
			text.Text = (if warmedRecently then "🔥x2 " else "⏱ ") .. Format.time(hatchAt - now)
			text.TextColor3 = Color3.new(1, 1, 1)
		end
	end
	for _, descendant in root:GetDescendants() do
		if
			descendant:IsA("ProximityPrompt")
			and descendant:GetAttribute("Action") == "IncubatorTap"
		then
			descendant.ActionText = if ready then "Hatch! 🐣" else "Warm 🔥"
		end
	end
	if ready and not model:GetAttribute("Wobbling") then
		model:SetAttribute("Wobbling", true)
		local base = root.CFrame
		local wobble = TweenService:Create(
			root,
			TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ CFrame = base * CFrame.Angles(0, 0, math.rad(9)) }
		)
		wobble:Play()
		model.Destroying:Connect(function()
			wobble:Cancel()
		end)
	end
end

-- ===== Lighting =====

local colorCorrection: ColorCorrectionEffect
local stormAbove: Part -- falling weather, above the camera
local stormBelow: Part -- rising weather (embers), around the player
local stormEmitters: { [string]: { ParticleEmitter } } = {}
local stormActive = false
local lastNight: boolean? = nil
local lastStorm = ""

-- Bright cartoon day; a blue, readable night lit by lamps.
local DAY = {
	lighting = {
		ClockTime = 14.2,
		Brightness = 2.6,
		Ambient = Color3.fromRGB(115, 112, 128),
		OutdoorAmbient = Color3.fromRGB(148, 148, 163),
		ColorShift_Top = Color3.fromRGB(255, 242, 220),
	},
	atmosphere = {
		Density = 0.28,
		Color = Color3.fromRGB(199, 230, 255),
		Decay = Color3.fromRGB(122, 178, 242),
	},
}
local NIGHT = {
	lighting = {
		ClockTime = 0.6,
		Brightness = 1.3,
		Ambient = Color3.fromRGB(82, 86, 140),
		OutdoorAmbient = Color3.fromRGB(98, 104, 170),
		ColorShift_Top = Color3.fromRGB(150, 170, 255),
	},
	atmosphere = {
		Density = 0.32,
		Color = Color3.fromRGB(64, 74, 132),
		Decay = Color3.fromRGB(38, 44, 98),
	},
}

local function setNightLights(on: boolean)
	for _, light in CollectionService:GetTagged(Tags.NIGHT_LIGHT) do
		if light:IsA("Light") then
			light.Enabled = on
		end
	end
end

local function setLighting(isNight: boolean)
	local info = TweenInfo.new(6, Enum.EasingStyle.Sine)
	local look = if isNight then NIGHT else DAY
	TweenService:Create(Lighting, info, look.lighting):Play()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, info, look.atmosphere):Play()
	end
	setNightLights(isNight)
end

-- Each storm has its own look: a sky tint plus one or two particle layers.
type EmitterLook = {
	rises: boolean?, -- emitted around the player and floating up (else falls from above)
	color: ColorSequence,
	rate: number,
	speed: NumberRange,
	size: NumberSequence,
	lifetime: NumberRange,
	acceleration: Vector3,
	spread: Vector2,
	light: number,
	transparency: NumberSequence?,
	rotSpeed: NumberRange?,
	streak: boolean?, -- stretched along its motion, like a shooting star
}

type StormLook = { tint: Color3, saturation: number, emitters: { EmitterLook } }

local function seq(...: number): NumberSequence
	local values = { ... }
	if #values == 1 then
		return NumberSequence.new(values[1])
	end
	local keys = {}
	for i, v in values do
		table.insert(keys, NumberSequenceKeypoint.new((i - 1) / (#values - 1), v))
	end
	return NumberSequence.new(keys)
end

local function colors(...: Color3): ColorSequence
	local values = { ... }
	if #values == 1 then
		return ColorSequence.new(values[1])
	end
	local keys = {}
	for i, c in values do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#values - 1), c))
	end
	return ColorSequence.new(keys)
end

local STORM_LOOKS: { [string]: StormLook } = {
	-- Blizzard: thick snow blowing sideways and quick white gusts.
	Frost = {
		tint = Color3.fromRGB(205, 228, 255),
		saturation = -0.15,
		emitters = {
			{
				color = colors(Color3.new(1, 1, 1)),
				rate = 180,
				speed = NumberRange.new(6, 10),
				size = seq(0.25, 0.35, 0.3),
				lifetime = NumberRange.new(6, 9),
				acceleration = Vector3.new(9, -2, 3),
				spread = Vector2.new(35, 35),
				light = 0.3,
				rotSpeed = NumberRange.new(-90, 90),
			},
			{
				color = colors(Color3.fromRGB(220, 240, 255)),
				rate = 35,
				speed = NumberRange.new(12, 18),
				size = seq(0.7, 0),
				lifetime = NumberRange.new(3, 4),
				acceleration = Vector3.new(22, 0, 6),
				spread = Vector2.new(50, 50),
				light = 0.5,
				transparency = seq(0.3, 1),
			},
		},
	},
	-- Meteor Shower: shooting stars streaking across a purple sky, plus stardust.
	Cosmic = {
		tint = Color3.fromRGB(215, 195, 255),
		saturation = 0.1,
		emitters = {
			{
				color = colors(
					Color3.new(1, 1, 1),
					Color3.fromRGB(190, 150, 255),
					Color3.fromRGB(90, 220, 255)
				),
				rate = 7,
				speed = NumberRange.new(90, 130),
				size = seq(1.1, 0.2),
				lifetime = NumberRange.new(0.9, 1.4),
				acceleration = Vector3.new(60, 0, 25),
				spread = Vector2.new(5, 5),
				light = 1,
				streak = true,
			},
			{
				color = colors(Color3.fromRGB(200, 160, 255), Color3.fromRGB(150, 230, 255)),
				rate = 70,
				speed = NumberRange.new(3, 6),
				size = seq(0, 0.4, 0),
				lifetime = NumberRange.new(4, 6),
				acceleration = Vector3.new(0, -1, 0),
				spread = Vector2.new(60, 60),
				light = 1,
			},
		},
	},
	-- Lava Storm: glowing embers floating up around you and grey ash drifting down.
	Lava = {
		tint = Color3.fromRGB(255, 214, 185),
		saturation = 0.05,
		emitters = {
			{
				rises = true,
				color = colors(
					Color3.fromRGB(255, 220, 120),
					Color3.fromRGB(255, 110, 30),
					Color3.fromRGB(200, 40, 20)
				),
				rate = 70,
				speed = NumberRange.new(3, 7),
				size = seq(0.35, 0.05),
				lifetime = NumberRange.new(3, 5),
				acceleration = Vector3.new(2, 5, 1),
				spread = Vector2.new(40, 40),
				light = 1,
				transparency = seq(0, 0.2, 1),
			},
			{
				color = colors(Color3.fromRGB(95, 85, 85)),
				rate = 60,
				speed = NumberRange.new(4, 7),
				size = seq(0.3),
				lifetime = NumberRange.new(6, 8),
				acceleration = Vector3.new(3, -1, 2),
				spread = Vector2.new(40, 40),
				light = 0,
				rotSpeed = NumberRange.new(-60, 60),
			},
		},
	},
	-- Rainbow Mega Storm: rainbow confetti and twinkles.
	Rainbow = {
		tint = Color3.fromRGB(255, 228, 246),
		saturation = 0.25,
		emitters = {
			{
				color = colors(
					Color3.fromRGB(255, 90, 90),
					Color3.fromRGB(255, 230, 90),
					Color3.fromRGB(90, 220, 255),
					Color3.fromRGB(200, 120, 255)
				),
				rate = 110,
				speed = NumberRange.new(8, 12),
				size = seq(0.45),
				lifetime = NumberRange.new(5, 7),
				acceleration = Vector3.new(2, -2, 1),
				spread = Vector2.new(30, 30),
				light = 0.6,
				rotSpeed = NumberRange.new(-180, 180),
			},
			{
				color = colors(Color3.new(1, 1, 1), Color3.fromRGB(255, 170, 230)),
				rate = 50,
				speed = NumberRange.new(2, 4),
				size = seq(0, 0.5, 0),
				lifetime = NumberRange.new(3, 5),
				acceleration = Vector3.zero,
				spread = Vector2.new(60, 60),
				light = 1,
			},
		},
	},
}

local function hostPart(name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	part.Parent = Workspace.CurrentCamera or Workspace
	return part
end

local function buildStormEmitters()
	stormAbove = hostPart("StormAbove", Vector3.new(160, 1, 160))
	stormBelow = hostPart("StormBelow", Vector3.new(90, 1, 90))
	for kind, look in STORM_LOOKS do
		local list = {}
		for _, e in look.emitters do
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = kind
			emitter.EmissionDirection = if e.rises then Enum.NormalId.Top else Enum.NormalId.Bottom
			emitter.Color = e.color
			emitter.Rate = e.rate
			emitter.Speed = e.speed
			emitter.Size = e.size
			emitter.Lifetime = e.lifetime
			emitter.Acceleration = e.acceleration
			emitter.SpreadAngle = e.spread
			emitter.LightEmission = e.light
			if e.transparency then
				emitter.Transparency = e.transparency
			end
			if e.rotSpeed then
				emitter.RotSpeed = e.rotSpeed
				emitter.Rotation = NumberRange.new(0, 360)
			end
			if e.streak then
				emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
				emitter.Squash = NumberSequence.new(-3)
			end
			emitter.Enabled = false
			emitter.Parent = if e.rises then stormBelow else stormAbove
			table.insert(list, emitter)
		end
		stormEmitters[kind] = list
	end
end

local function setStorm(kind: string)
	for _, list in stormEmitters do
		for _, emitter in list do
			emitter.Enabled = false
		end
	end
	local look = STORM_LOOKS[kind]
	stormActive = look ~= nil
	if not look then
		TweenService:Create(colorCorrection, TweenInfo.new(3), {
			TintColor = Color3.new(1, 1, 1),
			Saturation = 0,
		}):Play()
		return
	end
	local emitters: { ParticleEmitter } = stormEmitters[kind] or {}
	for _, emitter in emitters do
		emitter.Enabled = true
	end
	TweenService:Create(colorCorrection, TweenInfo.new(3), {
		TintColor = look.tint,
		Saturation = look.saturation,
	}):Play()
end

local function weatherStep()
	local now = Clock.cycleNow()
	local isNight = Cycle.dayNight(now).isNight
	if isNight ~= lastNight then
		lastNight = isNight
		setLighting(isNight)
	end
	local storm = Cycle.storm(now)
	local kind = if not storm.active then "" elseif storm.mega then "Rainbow" else storm.kind or ""
	if kind ~= lastStorm then
		lastStorm = kind
		setStorm(kind)
	end
end

local function followCamera()
	local camera = Workspace.CurrentCamera
	if camera and stormActive then
		stormAbove.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 40, 0))
		stormBelow.CFrame = CFrame.new(camera.Focus.Position - Vector3.new(0, 3, 0))
	end
end

-- Switch the storm look directly ("" = clear sky). Used by tests.
WorldFx.setStorm = setStorm

function WorldFx.init()
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "StormTint"
	colorCorrection.Parent = Lighting

	buildStormEmitters()

	for _, instance in CollectionService:GetTagged(DinoModel.TAG) do
		onDinoAdded(instance)
	end
	CollectionService:GetInstanceAddedSignal(DinoModel.TAG):Connect(onDinoAdded)
	for _, part in CollectionService:GetTagged(DinoModel.RAINBOW_TAG) do
		addRainbow(part)
	end
	CollectionService:GetInstanceAddedSignal(DinoModel.RAINBOW_TAG):Connect(addRainbow)
	CollectionService:GetInstanceRemovedSignal(DinoModel.RAINBOW_TAG):Connect(function(instance)
		if instance:IsA("BasePart") then
			rainbowParts[instance] = nil
		end
	end)
	CollectionService:GetInstanceAddedSignal(Tags.NIGHT_LIGHT):Connect(function(instance)
		if instance:IsA("Light") then
			instance.Enabled = lastNight == true
		end
	end)
	CollectionService:GetInstanceRemovedSignal(DinoModel.TAG):Connect(function(instance)
		if instance:IsA("Model") then
			walkers[instance] = nil
		end
	end)
end

function WorldFx.start()
	RunService.Heartbeat:Connect(function(dt: number)
		rainbowStep(dt)
		followCamera()
		stepWalkers(dt)
	end)
	while true do
		local now = Clock.now()
		for _, egg in CollectionService:GetTagged(EGG_TAG) do
			updateEgg(egg, now)
		end
		weatherStep()
		task.wait(0.25)
	end
end

return WorldFx
