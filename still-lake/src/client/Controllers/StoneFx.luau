--!strict
-- Draws every throw on the lake, the same way on every screen: the stone
-- arcs from the thrower's hand to the water, then skips hop after hop (each
-- one shorter and quicker), leaving a ripple, a little splash and a "plip"
-- that rises in pitch at every touch, until it sinks, or slides up onto the
-- far beach. Good throws leave a floating "×12" where the stone went down.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Lake = require(ReplicatedStorage.Shared.Lake)
local Net = require(ReplicatedStorage.Shared.Net)
local StoneModel = require(ReplicatedStorage.Shared.StoneModel)
local Types = require(ReplicatedStorage.Shared.Types)
local Audio = require(script.Parent.Audio)
local ClientState = require(script.Parent.ClientState)

local StoneFx = {}

StoneFx.BEACH_HEIGHT = 0.35 -- the far beach's surface (Scenery.BEACH_TOP)
StoneFx.MAX_RIPPLES = 60
StoneFx.MAX_FLIGHTS = 12 -- older stones are skipped to the end if more fly at once

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
	stone: BasePart,
	segments: { Segment },
	current: number,
	segmentStart: number,
	spin: number,
}

local folder: Folder? = nil
local splashEmitter: ParticleEmitter? = nil
local splashAnchor: Part? = nil
local flights: { Flight } = {}
local ripples: { Part } = {}
local nextRipple = 1

local RIPPLE_GROW = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- ===== Water effects =====

local function newRipple(parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = "Ripple"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(236, 250, 255)
	part.Transparency = 1
	part.Size = Vector3.new(0.04, 0.5, 0.5)
	part.Parent = parent
	return part
end

-- A ring of water spreading out from `position` (on the surface).
function StoneFx.ripple(position: Vector3, size: number)
	local part = ripples[nextRipple]
	if not part then
		return
	end
	nextRipple = nextRipple % #ripples + 1
	part.CFrame = CFrame.new(position.X, 0.03, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	part.Size = Vector3.new(0.04, 0.4, 0.4)
	part.Transparency = 0.35
	TweenService:Create(part, RIPPLE_GROW, {
		Size = Vector3.new(0.04, size, size),
		Transparency = 1,
	}):Play()
end

function StoneFx.splash(position: Vector3, amount: number)
	local anchor, emitter = splashAnchor, splashEmitter
	if not anchor or not emitter then
		return
	end
	anchor.CFrame = CFrame.new(position.X, 0.1, position.Z)
	emitter:Emit(amount)
end

-- A floating "×12" over where a good throw went down.
local function scoreTag(position: Vector3, event: Types.ThrowEvent)
	local parent = folder
	if not parent or event.skips < 5 then
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
	anchor.CFrame = CFrame.new(position + Vector3.new(0, 2, 0))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(140, 50)
	gui.LightInfluence = 0
	gui.MaxDistance = 260
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = `×{event.skips}`
	label.TextColor3 = if event.perfect then Color3.fromRGB(255, 226, 120) else Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.fromRGB(28, 40, 58)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	anchor.Parent = parent
	local rise = TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(anchor, rise, { CFrame = anchor.CFrame + Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, rise, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(2.8, function()
		anchor:Destroy()
	end)
end

-- ===== Planning a flight =====

local function hopDuration(length: number): number
	return math.clamp(0.08 + math.sqrt(length) * 0.085, 0.09, 0.5)
end

local function hopHeight(length: number): number
	return math.clamp(0.05 * length + 0.12, 0.15, 2.6)
end

-- Splits a throw into segments: hand -> water, then one per hop, plus a
-- slide up the far beach if it got all the way across.
function StoneFx.plan(event: Types.ThrowEvent): { Segment }
	local segments: { Segment } = {}
	local reach =
		Vector3.new(event.entry.X - event.origin.X, 0, event.entry.Z - event.origin.Z).Magnitude
	local dive = event.verdict == "dive"
	table.insert(segments, {
		from = event.origin,
		to = event.entry,
		height = if dive then 0.4 else math.clamp(reach * 0.12, 0.5, 2.5),
		duration = math.clamp(reach / 40, 0.18, 0.45),
		touch = false,
		index = 0,
	})
	local point = event.entry
	for i, length in event.hops do
		local finish = Lake.along(point, event.direction, length)
		table.insert(segments, {
			from = point,
			to = finish,
			height = hopHeight(length),
			duration = hopDuration(length),
			touch = true,
			index = i,
		})
		point = finish
	end
	if event.verdict == "shore" then
		-- skitter up onto the far beach
		local rest = Lake.along(point, event.direction, 3.5)
		table.insert(segments, {
			from = point,
			to = Vector3.new(rest.X, StoneFx.BEACH_HEIGHT + 0.15, rest.Z),
			height = 0.3,
			duration = 0.35,
			touch = true,
			index = #event.hops + 1,
		})
	end
	return segments
end

-- Where the stone is `t` (0..1) of the way through a segment.
function StoneFx.positionOn(segment: Segment, t: number): Vector3
	local base = segment.from:Lerp(segment.to, t)
	return base + Vector3.new(0, 4 * segment.height * t * (1 - t), 0)
end

-- ===== Running flights =====

local function finish(flight: Flight)
	local event = flight.event
	local last = flight.segments[#flight.segments]
	local position = last.to
	local stone = flight.stone
	if event.verdict == "shore" then
		-- it rests on the beach for a moment, then fades
		stone.CFrame = CFrame.new(position)
		TweenService:Create(
			stone,
			TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.In, 0, false, 5),
			{
				Transparency = 1,
			}
		):Play()
		task.delay(7, function()
			stone:Destroy()
		end)
	else
		local big = event.verdict == "dive"
		StoneFx.ripple(position, if big then 9 else 6)
		StoneFx.splash(position, if big then 22 else 10)
		Audio.splash(position, big)
		TweenService:Create(stone, TweenInfo.new(0.5), {
			CFrame = CFrame.new(position - Vector3.new(0, 1.2, 0)),
			Transparency = 1,
		}):Play()
		task.delay(0.6, function()
			stone:Destroy()
		end)
	end
	scoreTag(position, event)
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
		local size = math.clamp(2 + (segment.to - segment.from).Magnitude * 0.35, 2.5, 6)
		StoneFx.ripple(at, size)
		StoneFx.splash(at, 4)
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
			flight.stone.CFrame = CFrame.new(StoneFx.positionOn(segment, t))
				* CFrame.Angles(0, flight.spin, 0)
		end
	end
end

-- Starts drawing one throw.
function StoneFx.play(event: Types.ThrowEvent)
	local parent = folder
	if not parent then
		return
	end
	if #flights >= StoneFx.MAX_FLIGHTS then
		-- too many at once: let the oldest one sink now
		local oldest = table.remove(flights, 1)
		if oldest then
			oldest.current = #oldest.segments
			finish(oldest)
		end
	end
	local stone = StoneModel.build(event.stone, 0.8)
	stone.CFrame = CFrame.new(event.origin)
	stone.Parent = parent
	local flight: Flight = {
		event = event,
		stone = stone,
		segments = StoneFx.plan(event),
		current = 1,
		segmentStart = os.clock(),
		spin = 0,
	}
	table.insert(flights, flight)
	startSegment(flight, 1, os.clock())
end

function StoneFx.init()
	local f = Instance.new("Folder")
	f.Name = "LakeFx"
	f.Parent = Workspace
	folder = f
	for _ = 1, StoneFx.MAX_RIPPLES do
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
		StoneFx.play(event)
	end)
end

function StoneFx.start()
	RunService.RenderStepped:Connect(function()
		step(os.clock())
	end)
end

return StoneFx
