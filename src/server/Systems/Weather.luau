--!strict
-- Storms. While a storm is on, every online player's unmutated dinos have a
-- chance each tick to catch that storm's mutation. Storm timing is
-- deterministic (Cycle), so this system only announces and applies effects.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Config = require(ReplicatedStorage.Shared.Config)
local Cycle = require(ReplicatedStorage.Shared.Util.Cycle)
local DinoData = require(ReplicatedStorage.Shared.Data.DinoData)
local MutationData = require(ReplicatedStorage.Shared.Data.MutationData)
local Data = require(script.Parent.Data)
local Nest = require(script.Parent.Nest)
local Plots = require(script.Parent.Plots)
local Sessions = require(script.Parent.Sessions)
local Notify = require(script.Parent.Parent.Lib.Notify)

local Weather = {}

local rng = Random.new()

local function stormTick(storm: Cycle.StormState)
	local mutation = MutationData.stormGives(storm.kind, storm.mega)
	if not mutation then
		return
	end
	local chanceBp = MutationData.stormTickBp(storm.mega)
	local info = MutationData.get(mutation)
	for _, session in Sessions.ready() do
		local player = session.player
		local profile = Data.get(player)
		if not profile then
			continue
		end
		for _, dino in profile.dinos do
			if dino.mutation == nil and rng:NextInteger(0, 9999) < chanceBp then
				Nest.setMutation(player, dino.id, mutation)
				local species = DinoData.get(dino.species)
				local name = if species then species.name else "dino"
				Notify.send(
					player,
					`{info and info.emoji or "✨"} Your {name} turned {mutation}!`,
					"rare"
				)
				local model = Plots.dinoModel(player, dino.id)
				if model then
					Notify.effect(
						player,
						"Mutate",
						{ position = model:GetPivot().Position, mutation = mutation }
					)
				end
			end
		end
	end
end

function Weather.start()
	local wasActive = false
	local wasMega = false
	local lastTick = 0
	while true do
		task.wait(1)
		local now = Clock.cycleNow()
		local storm = Cycle.storm(now)
		if storm.active and (not wasActive or storm.mega ~= wasMega) then
			if storm.mega then
				Notify.all(
					`{MutationData.MEGA_STORM_EMOJI} {MutationData.MEGA_STORM_NAME}! Rainbow dinos are possible right now!`,
					"event"
				)
			elseif storm.kind then
				local info = MutationData.stormInfo(storm.kind)
				Notify.all(
					`{info.emoji} A {info.name} is here! Dinos can turn {storm.kind}!`,
					"event"
				)
			end
			lastTick = now
		elseif not storm.active and wasActive then
			Notify.all("🌤 The storm has passed.", "info")
		end
		wasActive = storm.active
		wasMega = storm.mega
		if storm.active and now - lastTick >= Config.STORM_TICK then
			lastTick = now
			stormTick(storm)
		end
	end
end

return Weather
