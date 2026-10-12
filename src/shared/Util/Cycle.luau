--!strict
-- Day/night, storms and egg-shop restocks. Everything is computed from the
-- current time with a deterministic RNG, so every server and every client
-- agrees on "is it night?", "what storm is on?" and "what's in stock?"
-- without sending a single network message.

local Config = require(script.Parent.Parent.Config)
local EggData = require(script.Parent.Parent.Data.EggData)
local MutationData = require(script.Parent.Parent.Data.MutationData)
local Rng = require(script.Parent.Rng)

local Cycle = {}

export type DayNight = {
	isNight: boolean,
	secondsLeft: number, -- until the phase flips
	phaseFraction: number, -- 0..1 through the current phase
	cycleIndex: number,
}

export type StormState = {
	active: boolean,
	kind: MutationData.StormKind?, -- nil during a mega storm
	mega: boolean,
	secondsLeft: number, -- until it ends (if active) or starts (if not)
	nextKind: MutationData.StormKind?, -- the kind of the next regular storm
	slot: number,
}

local SECONDS_PER_DAY = 86400
local SECONDS_PER_WEEK = 7 * SECONDS_PER_DAY
-- 1970-01-01 was a Thursday; with Sunday = 0 that's weekday 4.
local EPOCH_WEEKDAY = 4

function Cycle.dayNight(now: number): DayNight
	local length = Config.DAY_SECONDS + Config.NIGHT_SECONDS
	local cycleIndex = math.floor(now / length)
	local position = now - cycleIndex * length
	if position < Config.DAY_SECONDS then
		return {
			isNight = false,
			secondsLeft = Config.DAY_SECONDS - position,
			phaseFraction = position / Config.DAY_SECONDS,
			cycleIndex = cycleIndex,
		}
	end
	local intoNight = position - Config.DAY_SECONDS
	return {
		isNight = true,
		secondsLeft = Config.NIGHT_SECONDS - intoNight,
		phaseFraction = intoNight / Config.NIGHT_SECONDS,
		cycleIndex = cycleIndex,
	}
end

local function stormKindForSlot(slot: number): MutationData.StormKind
	local total = 0
	for _, s in MutationData.STORMS do
		total += s.weight
	end
	local r = Rng.new(Rng.hash(slot, 7919)).next() * total
	local acc = 0
	for _, s in MutationData.STORMS do
		acc += s.weight
		if r < acc then
			return s.kind
		end
	end
	return MutationData.STORMS[#MutationData.STORMS].kind
end

-- Start time of the most recent weekly mega storm at or before `now`.
local function lastMegaStart(now: number): number
	local days = math.floor(now / SECONDS_PER_DAY)
	local weekday = (days + EPOCH_WEEKDAY) % 7
	local daysBack = (weekday - Config.MEGA_STORM_WEEKDAY) % 7
	local start = (days - daysBack) * SECONDS_PER_DAY + Config.MEGA_STORM_HOUR_UTC * 3600
	if start > now then
		start -= SECONDS_PER_WEEK
	end
	return start
end

function Cycle.megaStorm(now: number): (boolean, number)
	local start = lastMegaStart(now)
	local elapsed = now - start
	if elapsed < Config.MEGA_STORM_DURATION then
		return true, Config.MEGA_STORM_DURATION - elapsed
	end
	return false, start + SECONDS_PER_WEEK - now
end

function Cycle.storm(now: number): StormState
	local megaActive, megaSeconds = Cycle.megaStorm(now)
	local slot = math.floor(now / Config.STORM_INTERVAL)
	local offset = now - slot * Config.STORM_INTERVAL
	if megaActive then
		return {
			active = true,
			kind = nil,
			mega = true,
			secondsLeft = megaSeconds,
			nextKind = stormKindForSlot(slot + 1),
			slot = slot,
		}
	end
	if offset < Config.STORM_DURATION then
		return {
			active = true,
			kind = stormKindForSlot(slot),
			mega = false,
			secondsLeft = Config.STORM_DURATION - offset,
			nextKind = stormKindForSlot(slot + 1),
			slot = slot,
		}
	end
	return {
		active = false,
		kind = nil,
		mega = false,
		secondsLeft = Config.STORM_INTERVAL - offset,
		nextKind = stormKindForSlot(slot + 1),
		slot = slot,
	}
end

export type Restock = {
	index: number,
	secondsLeft: number,
	stock: { [string]: number },
}

function Cycle.restock(now: number): Restock
	local index = math.floor(now / Config.RESTOCK_SECONDS)
	local stock: { [string]: number } = {}
	for _, egg in EggData.LIST do
		local rng = Rng.new(Rng.hash(index, egg.order * 104729))
		local count = 0
		if rng.next() < egg.stock.chance then
			count = rng.int(egg.stock.min, egg.stock.max)
		end
		stock[egg.id] = count
	end
	return {
		index = index,
		secondsLeft = (index + 1) * Config.RESTOCK_SECONDS - now,
		stock = stock,
	}
end

-- Whole UTC days since 1970, used for daily rewards.
function Cycle.dayNumber(now: number): number
	return math.floor(now / SECONDS_PER_DAY)
end

return Cycle
