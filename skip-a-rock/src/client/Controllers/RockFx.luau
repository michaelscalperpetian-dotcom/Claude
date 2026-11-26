--!strict
-- Draws every throw out at sea, the same way on every screen: the rock arcs
-- from the thrower's hand to the water, then skips hop after hop (each one
-- shorter and quicker), leaving a ring on the water, a little splash and a
-- "plip" that rises in pitch at every touch, until it sinks far out at sea.
-- Distances use the sea's squeezed scale (see Sea), so huge throws still
-- land on the map, and long flights are sped up to finish in a few seconds.
--
-- For your own throws a chase camera follows the rock out to sea (it stops
-- following once the rock is very far out, and watches it go). Click or
-- press throw to skip it; the 🎥 button turns it off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local RockModel = require(ReplicatedStorage.Shared.RockModel)
local Sea = require(ReplicatedStorage.Shared.Sea)
local Types = require(ReplicatedStorage.Shared.Types)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Audio = require(script.Parent.Audio)
local ClientState = require(script.Parent.ClientState)

local RockFx = {}

RockFx.MAX_RIPPLES = 60
RockFx.MAX_FLIGHTS = 12 -- older rocks sink at once if more fly together
RockFx.MAX_FLIGHT_SECONDS = 6.5 -- long throws are sped up to fit
RockFx.CHASE_MIN = 60 -- map studs: shorter throws aren't worth chasing
RockFx.CHASE_MAX = 2600 -- the camera stops following this far out from the thrower
RockFx.CHASE_LINGER = 1.4 -- seconds to watch the splash before coming back
RockFx.chaseEnabled = true

type Segment = {
	from: Vector3,
	to: Vector3,
	height: number,
	duration: number,
	touch: boolean, -- a skip on the water as this segment starts
	index: number,
}

type Flight = {
	event: Types.ThrowEvent,
	rock: BasePart,
	segments: { Segment },
	current: number,
	segmentStart: number,
	spin: number,
	chase: boolean,
}

local folder: Folder? = nil
local splashEmitter: ParticleEmitter? = nil
local splashAnchor: Part? = nil
local flights: { Flight } = {}
local ripples: { Part } = {}
local nextRipple = 1
local chasing: Flight? = nil
local chaseEndsAt = math.huge
local chaseHold: Vector3? = nil -- where the camera stopped following

local RIPPLE_GROW = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- ===== Water effects =====

local RIPPLE_PIXELS = 24 -- per stud
local RIPPLE_LINE = 4 -- pixels

local function newRipple(parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = "Ripple"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.5, 0.05, 0.5)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Ring"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = RIPPLE_PIXELS
	gui.LightInfluence = 0.7
	gui.Parent = part
	local ring = Instance.new("Frame")
	ring.Name = "Circle"
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.fromScale(1, 1)
	ring.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	local line = Instance.new("UIStroke")
	line.Name = "Line"
	line.Color = Color3.fromRGB(236, 250, 255)
	line.Thickness = RIPPLE_LINE
	line.Transparency = 1
	line.Parent = ring
	part.Parent = parent
	return part
end

-- A ring of water spreading out from `position` (on the surface).
function RockFx.ripple(position: Vector3, size: number)
	local part = ripples[nextRipple]
	if not part then
		return
	end
	nextRipple = nextRipple % #ripples + 1
	local gui = part:FindFirstChild("Ring")
	local circle = gui and gui:FindFirstChild("Circle")
	local line = circle and circle:FindFirstChild("Line")
	if not line or not line:IsA("UIStroke") then
		return
	end
	part.CFrame = CFrame.new(position.X, 0.08, position.Z)
	part.Size = Vector3.new(0.5, 0.05, 0.5)
	line.Transparency = 0.15
	TweenService:Create(part, RIPPLE_GROW, { Size = Vector3.new(size, 0.05, size) }):Play()
	TweenService:Create(line, RIPPLE_GROW, { Transparency = 1 }):Play()
end

function RockFx.splash(position: Vector3, amount: number)
	local anchor, emitter = splashAnchor, splashEmitter
	if not anchor or not emitter then
		return
	end
	anchor.CFrame = CFrame.new(position.X, 0.1, position.Z)
	emitter:Emit(amount)
end

-- A floating "1.2K studs" (and coins, for good throws) where a rock went down.
local function scoreTag(position: Vector3, event: Types.ThrowEvent)
	local parent = folder
	if not parent or event.skips < 1 then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "ScoreTag"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(180, 54)
	gui.LightInfluence = 0
	gui.MaxDistance = 4000
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = Format.distance(event.distance)
	label.TextColor3 = if event.perfect then Color3.fromRGB(255, 226, 120) else Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.fromRGB(20, 36, 64)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	anchor.Parent = parent
	local rise = TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(anchor, rise, { CFrame = anchor.CFrame + Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(label, rise, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(3.2, function()
		anchor:Destroy()
	end)
end

-- ===== Planning a flight =====

local function hopHeight(length: number): number
	return math.clamp(0.05 * length + 0.12, 0.15, 18)
end

local function hopDuration(length: number): number
	return math.clamp(0.08 + math.sqrt(length) * 0.085, 0.06, 2.5)
end

-- Splits a throw into segments: hand -> water, then one per hop.
function RockFx.plan(event: Types.ThrowEvent): { Segment }
	local segments: { Segment } = {}
	local reach = (Vector3.new(event.entry.X, event.origin.Y, event.entry.Z) - event.origin).Magnitude
	local dive = event.verdict == "dive"
	table.insert(segments, {
		from = event.origin,
		to = event.entry,
		height = if dive then 0.4 else math.clamp(reach * 0.12, 0.6, 6),
		duration = math.clamp(reach / 40, 0.2, 0.6),
		touch = false,
		index = 0,
	})
	local travelled = 0
	local point = event.entry
	local hopTime = 0
	for i, length in event.hops do
		travelled += length
		local finish = Sea.along(event.entry, travelled)
		local world = (finish - point).Magnitude
		local segment: Segment = {
			from = point,
			to = finish,
			height = hopHeight(world),
			duration = hopDuration(world),
			touch = true,
			index = i,
		}
		hopTime += segment.duration
		table.insert(segments, segment)
		point = finish
	end
	-- long throws are sped up so a flight never drags on
	if hopTime > RockFx.MAX_FLIGHT_SECONDS then
		local scale = RockFx.MAX_FLIGHT_SECONDS / hopTime
		for i = 2, #segments do
			segments[i].duration = math.max(segments[i].duration * scale, 0.04)
		end
	end
	return segments
end

-- Where the rock is `t` (0..1) of the way through a segment.
function RockFx.positionOn(segment: Segment, t: number): Vector3
	local base = segment.from:Lerp(segment.to, t)
	return base + Vector3.new(0, 4 * segment.height * t * (1 - t), 0)
end

-- How long a planned flight lasts, in seconds.
function RockFx.duration(segments: { Segment }): number
	local total = 0
	for _, segment in segments do
		total += segment.duration
	end
	return total
end

-- ===== The chase camera =====

local function restoreCamera()
	chasing = nil
	chaseHold = nil
	chaseEndsAt = math.huge
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Custom
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

-- Stops following a rock (and puts the camera back on the player).
function RockFx.stopChase()
	if chasing or chaseEndsAt < math.huge then
		restoreCamera()
	end
end

function RockFx.isChasing(): boolean
	return chasing ~= nil or chaseEndsAt < math.huge
end

local function updateChase(now: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if now >= chaseEndsAt then
		restoreCamera()
		return
	end
	local flight = chasing
	local target: Vector3
	if flight and flight.rock.Parent then
		target = flight.rock.CFrame.Position
	else
		target = chaseHold or camera.Focus.Position
	end
	local thrower = if flight then flight.event.origin else target
	local out = target.Z - thrower.Z
	local follow: Vector3
	if out > RockFx.CHASE_MAX then
		-- too far to follow: stay put and watch it go
		chaseHold = chaseHold or camera.CFrame.Position
		follow = chaseHold :: Vector3
	else
		follow = target + Vector3.new(0, 7 + out * 0.004, -18 - out * 0.01)
	end
	local wanted = CFrame.lookAt(follow, target + Vector3.new(0, 0, 10))
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = camera.CFrame:Lerp(wanted, 0.18)
end

-- ===== Running flights =====

local function finish(flight: Flight)
	local event = flight.event
	local last = flight.segments[#flight.segments]
	local position = last.to
	local rock = flight.rock
	local big = event.verdict == "dive"
	RockFx.ripple(position, if big then 9 else 7)
	RockFx.splash(position, if big then 22 else 12)
	Audio.splash(position, big)
	TweenService:Create(rock, TweenInfo.new(0.5), {
		CFrame = CFrame.new(position - Vector3.new(0, 1.2, 0)),
		Transparency = 1,
	}):Play()
	task.delay(0.6, function()
		rock:Destroy()
	end)
	scoreTag(position, event)
	if chasing == flight then
		chasing = nil
		chaseHold = chaseHold or position
		chaseEndsAt = os.clock() + RockFx.CHASE_LINGER
	end
	if event.userId == Players.LocalPlayer.UserId then
		ClientState.landed:fire(event)
	end
end

local function startSegment(flight: Flight, index: number, now: number)
	flight.current = index
	flight.segmentStart = now
	local segment = flight.segments[index]
	if segment.touch then
		local at = segment.from
		local size = math.clamp(2 + (segment.to - segment.from).Magnitude * 0.35, 2.5, 10)
		RockFx.ripple(at, size)
		RockFx.splash(at, 4)
		Audio.skip(at, segment.index)
	end
end

local function step(now: number)
	for i = #flights, 1, -1 do
		local flight = flights[i]
		local segment = flight.segments[flight.current]
		local t = (now - flight.segmentStart) / segment.duration
		while t >= 1 and flight.current < #flight.segments do
			local overshoot = now - (flight.segmentStart + segment.duration)
			startSegment(flight, flight.current + 1, now - overshoot)
			segment = flight.segments[flight.current]
			t = (now - flight.segmentStart) / segment.duration
		end
		if t >= 1 then
			table.remove(flights, i)
			finish(flight)
		else
			flight.spin += 0.6
			flight.rock.CFrame = CFrame.new(RockFx.positionOn(segment, t))
				* CFrame.Angles(0, flight.spin, 0)
		end
	end
	if chasing or chaseEndsAt < math.huge then
		updateChase(now)
	end
end

-- Starts drawing one throw.
function RockFx.play(event: Types.ThrowEvent)
	local parent = folder
	if not parent then
		return
	end
	if #flights >= RockFx.MAX_FLIGHTS then
		local oldest = table.remove(flights, 1)
		if oldest then
			oldest.current = #oldest.segments
			finish(oldest)
		end
	end
	local rock = RockModel.build(event.rock, 0.8)
	rock.CFrame = CFrame.new(event.origin)
	-- a faint streak behind the rock as it flies
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 0.12, 0)
	top.Parent = rock
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -0.12, 0)
	bottom.Parent = rock
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.25
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new(0.5, 1)
	trail.Parent = rock
	rock.Parent = parent
	local segments = RockFx.plan(event)
	local mine = event.userId == Players.LocalPlayer.UserId
	local reach = segments[#segments].to.Z - event.entry.Z
	local flight: Flight = {
		event = event,
		rock = rock,
		segments = segments,
		current = 1,
		segmentStart = os.clock(),
		spin = 0,
		chase = mine and RockFx.chaseEnabled and reach >= RockFx.CHASE_MIN,
	}
	table.insert(flights, flight)
	if flight.chase then
		chasing = flight
		chaseHold = nil
		chaseEndsAt = math.huge
	end
	startSegment(flight, 1, os.clock())
end

function RockFx.init()
	local f = Instance.new("Folder")
	f.Name = "SeaFx"
	f.Parent = Workspace
	folder = f
	for _ = 1, RockFx.MAX_RIPPLES do
		table.insert(ripples, newRipple(f))
	end
	local anchor = Instance.new("Part")
	anchor.Name = "Splash"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.4, 0.2, 0.4)
	anchor.Parent = f
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(236, 250, 255))
	emitter.LightEmission = 0.3
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.35, 0.6)
	emitter.Speed = NumberRange.new(5, 9)
	emitter.SpreadAngle = Vector2.new(30, 30)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.28),
		NumberSequenceKeypoint.new(1, 0.08),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 0.8),
	})
	emitter.Parent = anchor
	splashAnchor = anchor
	splashEmitter = emitter
	Net.listen("Throw", function(event: Types.ThrowEvent)
		RockFx.play(event)
	end)
end

function RockFx.start()
	RunService.RenderStepped:Connect(function()
		step(os.clock())
	end)
	-- a respawn always gets the normal camera back
	Players.LocalPlayer.CharacterAdded:Connect(function()
		RockFx.stopChase()
	end)
end

return RockFx
