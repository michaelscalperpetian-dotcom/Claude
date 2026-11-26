--!strict
-- Turns the sun. The server sets Lighting.ClockTime from the shared server
-- clock (so every player sees the same sky) and softens the light at night:
-- a cool blue ambient, a dimmer sun and denser haze. Lanterns, windows and
-- fireflies are switched on by each client (see the Ambience controller).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Config = require(ReplicatedStorage.Shared.Config)
local DayCycle = require(ReplicatedStorage.Shared.DayCycle)

local DayNight = {}

DayNight.STEP = 0.25 -- seconds between updates

type Look = {
	brightness: number,
	ambient: Color3,
	outdoor: Color3,
	shiftTop: Color3,
	haze: number,
	atmosphere: Color3,
}

local DAY: Look = {
	brightness = 2.4,
	ambient = Color3.new(0.42, 0.4, 0.46),
	outdoor = Color3.new(0.56, 0.54, 0.6),
	shiftTop = Color3.new(1, 0.92, 0.8),
	haze = 1.4,
	atmosphere = Color3.new(0.86, 0.84, 0.88),
}

local NIGHT: Look = {
	brightness = 1.2,
	ambient = Color3.new(0.2, 0.22, 0.34),
	outdoor = Color3.new(0.3, 0.33, 0.5),
	shiftTop = Color3.new(0.6, 0.7, 1),
	haze = 2,
	atmosphere = Color3.new(0.36, 0.4, 0.58),
}

local offset = 0 -- seconds added to the server clock (testing)

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- The clock right now (0..24).
function DayNight.clockTime(): number
	return DayCycle.clockTime(Clock.now() + offset)
end

function DayNight.isNight(): boolean
	return DayCycle.isNightAt(DayNight.clockTime())
end

-- Testing: jump the clock to `clock` hours. Everyone sees the jump.
function DayNight.setClock(clock: number)
	local now = Clock.now()
	local wanted = DayCycle.phaseFor(clock) * Config.DAY_LENGTH
	offset = wanted - (now % Config.DAY_LENGTH)
	DayNight.apply()
end

function DayNight.apply()
	local clock = DayNight.clockTime()
	local t = DayCycle.darkness(clock)
	Lighting.ClockTime = clock
	Lighting.Brightness = lerp(DAY.brightness, NIGHT.brightness, t)
	Lighting.Ambient = DAY.ambient:Lerp(NIGHT.ambient, t)
	Lighting.OutdoorAmbient = DAY.outdoor:Lerp(NIGHT.outdoor, t)
	Lighting.ColorShift_Top = DAY.shiftTop:Lerp(NIGHT.shiftTop, t)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Haze = lerp(DAY.haze, NIGHT.haze, t)
		atmosphere.Color = DAY.atmosphere:Lerp(NIGHT.atmosphere, t)
	end
end

function DayNight.start()
	while true do
		DayNight.apply()
		task.wait(DayNight.STEP)
	end
end

return DayNight
