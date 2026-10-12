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

-- ===== Dino wandering =====
-- Each dino strolls around its home spot: it turns toward a new spot, hops
-- along with a little waddle, then rests and breathes before the next walk.
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
}

local walkers: { [Model]: Walker } = {}
local FAR = 220

local function flatten(v: Vector3, fallback: Vector3): Vector3
	local flat = Vector3.new(v.X, 0, v.Z)
	return if flat.Magnitude > 1e-4 then flat.Unit else fallback
end

local function addWalker(model: Model)
	if walkers[model] then
		return
	end
	local root = model.PrimaryPart
	local home = model:GetAttribute("Home")
	if not root or typeof(home) ~= "CFrame" then
		return
	end
	local height = model:GetAttribute("Height")
	local h = if typeof(height) == "number" then height else 4
	local rng = Random.new()
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
	}
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
		if (w.position - eye).Magnitude > FAR then
			continue
		end
		-- the server moves dinos to a new home when the nest is rearranged
		local home = model:GetAttribute("Home")
		if typeof(home) == "CFrame" and (home.Position - w.home).Magnitude > 0.1 then
			w.home = home.Position
			w.position = home.Position
			w.target = nil
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
			local angle = w.rng:NextNumber(0, math.pi * 2)
			local radius = w.rng:NextNumber(1, WANDER_RADIUS)
			w.target = w.home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
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

local function rainbowStep()
	local hue = (os.clock() * 0.25) % 1
	for i, part in CollectionService:GetTagged(DinoModel.RAINBOW_TAG) do
		if part:IsA("BasePart") then
			part.Color = Color3.fromHSV((hue + i * 0.03) % 1, 0.65, 1)
		end
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
local stormPart: Part
local stormEmitter: ParticleEmitter
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

local STORM_LOOKS: { [string]: { tint: Color3, particles: Color3, rate: number, speed: number } } =
	{
		Lava = {
			tint = Color3.fromRGB(255, 200, 170),
			particles = Color3.fromRGB(255, 120, 40),
			rate = 60,
			speed = 10,
		},
		Frost = {
			tint = Color3.fromRGB(200, 225, 255),
			particles = Color3.fromRGB(255, 255, 255),
			rate = 120,
			speed = 8,
		},
		Cosmic = {
			tint = Color3.fromRGB(215, 190, 255),
			particles = Color3.fromRGB(190, 140, 255),
			rate = 50,
			speed = 30,
		},
		Rainbow = {
			tint = Color3.fromRGB(255, 225, 245),
			particles = Color3.fromRGB(255, 150, 220),
			rate = 90,
			speed = 12,
		},
	}

local function setStorm(kind: string)
	if kind == "" then
		stormEmitter.Enabled = false
		TweenService:Create(colorCorrection, TweenInfo.new(3), { TintColor = Color3.new(1, 1, 1) })
			:Play()
		return
	end
	local look = STORM_LOOKS[kind]
	if not look then
		return
	end
	stormEmitter.Color = if kind == "Rainbow"
		then ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 90)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(90, 220, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 120, 255)),
		})
		else ColorSequence.new(look.particles)
	stormEmitter.Rate = look.rate
	stormEmitter.Speed = NumberRange.new(look.speed, look.speed * 1.4)
	stormEmitter.Enabled = true
	TweenService:Create(colorCorrection, TweenInfo.new(3), { TintColor = look.tint }):Play()
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
	if camera and stormEmitter.Enabled then
		stormPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 40, 0))
	end
end

function WorldFx.init()
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "StormTint"
	colorCorrection.Parent = Lighting

	stormPart = Instance.new("Part")
	stormPart.Name = "StormEmitter"
	stormPart.Anchored = true
	stormPart.CanCollide = false
	stormPart.CanQuery = false
	stormPart.CanTouch = false
	stormPart.Transparency = 1
	stormPart.Size = Vector3.new(160, 1, 160)
	stormPart.Parent = Workspace.CurrentCamera or Workspace
	stormEmitter = Instance.new("ParticleEmitter")
	stormEmitter.EmissionDirection = Enum.NormalId.Bottom
	stormEmitter.Lifetime = NumberRange.new(4, 6)
	stormEmitter.Size = NumberSequence.new(0.6)
	stormEmitter.LightEmission = 0.6
	stormEmitter.Enabled = false
	stormEmitter.Parent = stormPart

	for _, instance in CollectionService:GetTagged(DinoModel.TAG) do
		onDinoAdded(instance)
	end
	CollectionService:GetInstanceAddedSignal(DinoModel.TAG):Connect(onDinoAdded)
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
		rainbowStep()
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
