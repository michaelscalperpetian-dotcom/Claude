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

local WorldFx = {}

local EGG_TAG = "IncubatorEgg"
local WANDER_RADIUS = 7

-- ===== Dino wandering =====

local active: { [Model]: boolean } = {}

local function wander(model: Model)
	if active[model] then
		return
	end
	active[model] = true
	local root = model.PrimaryPart
	if not root then
		return
	end
	local rng = Random.new()
	task.spawn(function()
		task.wait(rng:NextNumber(0, 3))
		while active[model] and model.Parent do
			local home = model:GetAttribute("Home")
			if typeof(home) ~= "CFrame" then
				break
			end
			local angle = rng:NextNumber(0, math.pi * 2)
			local distance = rng:NextNumber(0, WANDER_RADIUS)
			local target = home.Position
				+ Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			local current = root.CFrame.Position
			local flat = Vector3.new(target.X, current.Y, target.Z)
			local travel = (flat - current).Magnitude
			if travel > 0.5 then
				local facing = CFrame.lookAt(current, flat)
				-- turn, then walk
				local turn = TweenService:Create(root, TweenInfo.new(0.4), { CFrame = facing })
				turn:Play()
				turn.Completed:Wait()
				if not active[model] or not model.Parent then
					break
				end
				local walk = TweenService:Create(
					root,
					TweenInfo.new(travel / 5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ CFrame = CFrame.lookAt(flat, flat + facing.LookVector) }
				)
				walk:Play()
				walk.Completed:Wait()
			end
			task.wait(rng:NextNumber(2, 6))
		end
		active[model] = nil
	end)
end

local function onDinoAdded(instance: Instance)
	if instance:IsA("Model") then
		wander(instance)
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

local function setLighting(isNight: boolean)
	local info = TweenInfo.new(6, Enum.EasingStyle.Sine)
	if isNight then
		TweenService:Create(Lighting, info, {
			ClockTime = 0.3,
			Brightness = 1.2,
			Ambient = Color3.fromRGB(70, 75, 120),
			OutdoorAmbient = Color3.fromRGB(80, 85, 140),
		}):Play()
	else
		TweenService:Create(Lighting, info, {
			ClockTime = 14.2,
			Brightness = 2.4,
			Ambient = Color3.fromRGB(110, 110, 110),
			OutdoorAmbient = Color3.fromRGB(140, 140, 140),
		}):Play()
	end
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
	CollectionService:GetInstanceRemovedSignal(DinoModel.TAG):Connect(function(instance)
		if instance:IsA("Model") then
			active[instance] = nil
		end
	end)
end

function WorldFx.start()
	RunService.Heartbeat:Connect(function()
		rainbowStep()
		followCamera()
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
