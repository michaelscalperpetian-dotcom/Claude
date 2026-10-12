--!strict
-- Operations on a player's nest: dinos, incubators and the laid-egg tray.
-- Every change re-renders the plot and marks the HUD dirty. Higher-level
-- systems (Eggs, Raids, Progress...) build on these.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Config = require(ReplicatedStorage.Shared.Config)
local DinoData = require(ReplicatedStorage.Shared.Data.DinoData)
local Growth = require(ReplicatedStorage.Shared.Util.Growth)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Types = require(ReplicatedStorage.Shared.Types)
local Data = require(script.Parent.Data)
local Plots = require(script.Parent.Plots)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)
local Stats = require(script.Parent.Parent.Lib.Stats)

local Nest = {}

-- (player, dino) fired whenever a dino is added or changes mutation; Progress
-- uses it to fill in the Dino-Dex.
Nest.DinoChanged = Signal.new() :: Signal.Signal<Player, Types.DinoRecord>

function Nest.newId(profile: Types.Profile): string
	local id = tostring(profile.nextId)
	profile.nextId += 1
	return id
end

function Nest.findDino(profile: Types.Profile, id: string): (Types.DinoRecord?, number?)
	for index, dino in profile.dinos do
		if dino.id == id then
			return dino, index
		end
	end
	return nil, nil
end

function Nest.hasFreeSlot(player: Player): boolean
	local profile = Data.get(player)
	local session = Sessions.get(player)
	if not profile or not session then
		return false
	end
	return #profile.dinos < Stats.maxSlots(profile, session)
end

-- Adds a dino at the given stage (default Baby). Returns nil if the nest is full.
function Nest.addDino(
	player: Player,
	species: string,
	mutation: string?,
	stage: number?
): Types.DinoRecord?
	local profile = Data.get(player)
	local data = DinoData.get(species)
	if not profile or not data or not Nest.hasFreeSlot(player) then
		return nil
	end
	local now = Clock.now()
	local dino: Types.DinoRecord = {
		id = Nest.newId(profile),
		species = species,
		mutation = mutation,
		bornAt = Growth.bornAtForStage(now, stage or Growth.BABY, data.growth),
		lastLaidAt = 0,
	}
	table.insert(profile.dinos, dino)
	Plots.syncDinos(player)
	State.markDirty(player)
	Nest.DinoChanged:fire(player, dino)
	return dino
end

function Nest.removeDino(player: Player, id: string): Types.DinoRecord?
	local profile = Data.get(player)
	if not profile then
		return nil
	end
	local dino, index = Nest.findDino(profile, id)
	if not dino or not index then
		return nil
	end
	table.remove(profile.dinos, index)
	Plots.syncDinos(player)
	State.markDirty(player)
	return dino
end

function Nest.setMutation(player: Player, id: string, mutation: string)
	local profile = Data.get(player)
	if not profile then
		return
	end
	local dino = Nest.findDino(profile, id)
	if not dino then
		return
	end
	dino.mutation = mutation
	Plots.syncDinos(player)
	State.markDirty(player)
	Nest.DinoChanged:fire(player, dino)
end

-- ===== Incubators =====

function Nest.freeIncubator(player: Player): string?
	local profile = Data.get(player)
	if not profile then
		return nil
	end
	for slot = 1, Stats.maxIncubators(profile) do
		local key = tostring(slot)
		if profile.incubators[key] == nil then
			return key
		end
	end
	return nil
end

-- Puts an egg into a free incubator. Returns the slot, or nil if all are full.
function Nest.placeEgg(player: Player, egg: Types.IncubatorEgg): string?
	local profile = Data.get(player)
	local slot = Nest.freeIncubator(player)
	if not profile or not slot then
		return nil
	end
	profile.incubators[slot] = egg
	Plots.syncIncubators(player)
	State.markDirty(player)
	return slot
end

function Nest.removeEgg(player: Player, slot: string): Types.IncubatorEgg?
	local profile = Data.get(player)
	if not profile then
		return nil
	end
	local egg = profile.incubators[slot]
	if not egg then
		return nil
	end
	profile.incubators[slot] = nil
	Plots.syncIncubators(player)
	State.markDirty(player)
	return egg
end

function Nest.setHatchAt(player: Player, slot: string, hatchAt: number)
	local profile = Data.get(player)
	local egg = profile and profile.incubators[slot]
	if not egg then
		return
	end
	egg.hatchAt = hatchAt
	Plots.syncIncubators(player)
	State.markDirty(player)
end

-- ===== Tray =====

function Nest.findTrayEgg(profile: Types.Profile, id: string): (Types.TrayEgg?, number?)
	for index, egg in profile.tray do
		if egg.id == id then
			return egg, index
		end
	end
	return nil, nil
end

function Nest.trayRoom(profile: Types.Profile): number
	return Config.TRAY_CAPACITY - #profile.tray
end

function Nest.addTrayEgg(player: Player, species: string): Types.TrayEgg?
	local profile = Data.get(player)
	if not profile or Nest.trayRoom(profile) <= 0 then
		return nil
	end
	local egg: Types.TrayEgg = { id = Nest.newId(profile), species = species, laidAt = Clock.now() }
	table.insert(profile.tray, egg)
	Plots.syncTray(player)
	State.markDirty(player)
	return egg
end

function Nest.removeTrayEgg(player: Player, id: string): Types.TrayEgg?
	local profile = Data.get(player)
	if not profile then
		return nil
	end
	local egg, index = Nest.findTrayEgg(profile, id)
	if not egg or not index then
		return nil
	end
	table.remove(profile.tray, index)
	Plots.syncTray(player)
	State.markDirty(player)
	return egg
end

return Nest
