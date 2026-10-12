--!strict
-- Dino growth stages. Growth is pure time math from the dino's birth time, so it
-- keeps going while the player is offline and costs nothing to simulate.
-- Pure: runs under Lune.

local Growth = {}

export type Stage = "Baby" | "Juvenile" | "Adult" | "Giant"

Growth.STAGES = { "Baby", "Juvenile", "Adult", "Giant" } :: { Stage }
Growth.BABY = 1
Growth.JUVENILE = 2
Growth.ADULT = 3
Growth.GIANT = 4

-- Per-stage multipliers (index = stage).
Growth.INCOME = { 0.25, 0.5, 1, 2 }
Growth.SIZE = { 0.45, 0.7, 1, 1.6 }
Growth.SELL = { 0.3, 0.6, 1, 2 }

-- thresholds = ages (seconds) to reach Juvenile, Adult, Giant.
function Growth.stageIndex(ageSeconds: number, thresholds: { number }): number
	local stage = 1
	for i, t in thresholds do
		if ageSeconds >= t then
			stage = i + 1
		end
	end
	return stage
end

-- Returns stage, fraction of the way to the next stage (1 at Giant), and seconds left.
function Growth.progress(ageSeconds: number, thresholds: { number }): (number, number, number)
	local stage = Growth.stageIndex(ageSeconds, thresholds)
	if stage >= #thresholds + 1 then
		return stage, 1, 0
	end
	local startAge = if stage == 1 then 0 else thresholds[stage - 1]
	local endAge = thresholds[stage]
	local span = endAge - startAge
	local fraction = if span > 0 then (ageSeconds - startAge) / span else 1
	return stage, math.clamp(fraction, 0, 1), math.max(0, endAge - ageSeconds)
end

function Growth.stageName(stage: number): Stage
	return Growth.STAGES[math.clamp(stage, 1, 4)]
end

-- Age a dino born at `bornAt` needs so that it is exactly `stage` now.
function Growth.bornAtForStage(now: number, stage: number, thresholds: { number }): number
	if stage <= 1 then
		return now
	end
	return now - thresholds[math.min(stage - 1, #thresholds)]
end

function Growth.income(baseIncome: number, stage: number, mutationMultiplier: number): number
	return baseIncome * Growth.INCOME[math.clamp(stage, 1, 4)] * mutationMultiplier
end

-- Time a dino of this stage needs between laid eggs, or nil if it doesn't lay.
function Growth.layInterval(stage: number, adultInterval: number, giantInterval: number): number?
	if stage >= Growth.GIANT then
		return giantInterval
	elseif stage == Growth.ADULT then
		return adultInterval
	end
	return nil
end

-- How many eggs a dino lays right now (at most `room`) and its new lastLaidAt.
-- Works for offline catch-up too: a full tray drops the backlog instead of
-- piling up eggs forever.
function Growth.laysDue(
	bornAt: number,
	lastLaidAt: number,
	thresholds: { number },
	now: number,
	adultInterval: number,
	giantInterval: number,
	room: number
): (number, number)
	local stage = Growth.stageIndex(now - bornAt, thresholds)
	local interval = Growth.layInterval(stage, adultInterval, giantInterval)
	if interval == nil then
		return 0, lastLaidAt
	end
	local adultAt = bornAt + thresholds[Growth.ADULT - 1]
	local last = math.max(lastLaidAt, adultAt)
	local due = math.floor((now - last) / interval)
	if due <= 0 then
		return 0, last
	end
	local laid = math.min(due, math.max(room, 0))
	if laid < due then
		return laid, now
	end
	return laid, last + laid * interval
end

return Growth
