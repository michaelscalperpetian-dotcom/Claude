--!strict
-- The lake's mood through the day. As dusk falls the lanterns and cabin
-- windows light up, fireflies drift over the beach and the water darkens;
-- by morning it all fades back. Now and then a fish rises somewhere on the
-- lake and leaves a ring on the water.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local DayCycle = require(ReplicatedStorage.Shared.DayCycle)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Tags = require(ReplicatedStorage.Shared.Tags)
local Audio = require(script.Parent.Audio)
local StoneFx = require(script.Parent.StoneFx)

local Ambience = {}

Ambience.LIGHTS_ON = 0.45 -- darkness at which lanterns come on

local NIGHT_WATER = Color3.fromRGB(34, 62, 104)
local WINDOW_DAY = Color3.fromRGB(150, 196, 220)
local WINDOW_NIGHT = Color3.fromRGB(255, 200, 120)

local lit: boolean? = nil

local function water(): BasePart?
	local root = Workspace:FindFirstChild("StillLake")
	local land = root and root:FindFirstChild("Land")
	local part = land and land:FindFirstChild("Water")
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function setLit(on: boolean)
	if lit == on then
		return
	end
	lit = on
	for _, light in CollectionService:GetTagged(Tags.NIGHT_LIGHT) do
		if light:IsA("Light") then
			light.Enabled = on
			local glass = light.Parent
			if glass and glass:IsA("BasePart") then
				glass.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
			end
		end
	end
	for _, flies in CollectionService:GetTagged(Tags.FIREFLIES) do
		if flies:IsA("ParticleEmitter") then
			flies.Enabled = on
		end
	end
	for _, window in CollectionService:GetTagged(Tags.WINDOW) do
		if window:IsA("BasePart") then
			window.Color = if on then WINDOW_NIGHT else WINDOW_DAY
			window.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

function Ambience.update()
	local darkness = DayCycle.darkness(Lighting.ClockTime)
	setLit(darkness >= Ambience.LIGHTS_ON)
	local part = water()
	if part then
		part.Color = Palette.water:Lerp(NIGHT_WATER, darkness)
	end
end

local function fishRise()
	local angle = math.random() * 2 * math.pi
	local radius = math.sqrt(math.random()) * (Config.LAKE_RADIUS - 12)
	local spot = Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
	StoneFx.ripple(spot, 4 + math.random() * 3)
	if math.random() < 0.5 then
		Audio.at(spot, "water", 2.2 + math.random() * 0.4, 0.12)
	end
end

function Ambience.start()
	-- lanterns placed later (streaming, or a slow load) are caught next pass
	CollectionService:GetInstanceAddedSignal(Tags.NIGHT_LIGHT):Connect(function()
		lit = nil
	end)
	task.spawn(function()
		while true do
			task.wait(math.random(30, 80) / 10)
			fishRise()
		end
	end)
	while true do
		Ambience.update()
		task.wait(0.5)
	end
end

return Ambience
