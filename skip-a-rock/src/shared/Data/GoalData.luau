--!strict
-- Goals to aim for (shown in the menu) and the titles that float over a
-- skipper's head as their longest throw grows.

local Format = require(script.Parent.Parent.Util.Format)

export type Kind = "skips" | "distance" | "perfects" | "rocks" | "rebirths" | "throws" | "coins"

export type Goal = {
	id: string,
	text: string,
	emoji: string,
	kind: Kind,
	value: number,
}

-- What goals are measured against (built from a saved profile).
export type Stats = {
	bestSkips: number,
	bestDistance: number,
	perfects: number,
	rocks: number, -- kinds of rock owned, the Pebble included
	rebirths: number,
	throws: number,
	totalCoins: number,
}

export type Title = { distance: number, name: string }

local GOALS: { Goal } = {}
local function add(id: string, emoji: string, kind: Kind, value: number, text: string)
	table.insert(GOALS, { id = id, text = text, emoji = emoji, kind = kind, value = value })
end

add("skip1", "💧", "skips", 1, "Skip a rock")
add("skip10", "🌊", "skips", 10, "10 skips in one throw")
add("skip20", "✨", "skips", 20, "20 skips in one throw")
add("skip30", "🏆", "skips", 30, "30 skips in one throw")
for _, d in { 1000, 1e5, 1e7, 1e9, 1e12 } do
	add("far" .. d, "📏", "distance", d, `Throw {Format.short(d)} studs`)
end
add("perfect1", "🎯", "perfects", 1, "Make a perfect release")
add("perfect100", "🎯", "perfects", 100, "Make 100 perfect releases")
add("rocks3", "🪨", "rocks", 3, "Own 3 kinds of rock")
add("rocks6", "🪨", "rocks", 6, "Own 6 kinds of rock")
add("rocks12", "💎", "rocks", 12, "Own every rock")
add("rebirth1", "🔁", "rebirths", 1, "Rebirth for the first time")
add("rebirth5", "🔁", "rebirths", 5, "Rebirth 5 times")
add("rebirth25", "🌟", "rebirths", 25, "Rebirth 25 times")
add("throws100", "🧺", "throws", 100, "Skip 100 rocks")
add("throws10000", "🧺", "throws", 10000, "Skip 10,000 rocks")
add("coins1m", "💰", "coins", 1e6, "Earn 1M coins in total")
add("coins1t", "💰", "coins", 1e12, "Earn 1T coins in total")

-- Longest throw -> title. Highest first.
local TITLES: { Title } = {
	{ distance = 1e12, name = "Starfall Skipper" },
	{ distance = 1e9, name = "Horizon Breaker" },
	{ distance = 1e7, name = "Ocean Master" },
	{ distance = 1e6, name = "Sea Legend" },
	{ distance = 1e5, name = "Wave Rider" },
	{ distance = 1e4, name = "Tide Turner" },
	{ distance = 1000, name = "Skimmer" },
}

local BY_ID: { [string]: Goal } = {}
for _, goal in GOALS do
	BY_ID[goal.id] = goal
end

local GoalData = {
	GOALS = GOALS,
	TITLES = TITLES,
}

function GoalData.get(id: string): Goal?
	return BY_ID[id]
end

-- How far along a goal is (same units as goal.value).
function GoalData.progress(goal: Goal, stats: Stats): number
	local kind = goal.kind
	if kind == "skips" then
		return stats.bestSkips
	elseif kind == "distance" then
		return stats.bestDistance
	elseif kind == "perfects" then
		return stats.perfects
	elseif kind == "rocks" then
		return stats.rocks
	elseif kind == "rebirths" then
		return stats.rebirths
	elseif kind == "coins" then
		return stats.totalCoins
	end
	return stats.throws
end

function GoalData.isDone(goal: Goal, stats: Stats): boolean
	return GoalData.progress(goal, stats) >= goal.value
end

-- The title for a longest throw of `distance`, or nil below the first one.
function GoalData.title(distance: number): string?
	for _, title in TITLES do
		if distance >= title.distance then
			return title.name
		end
	end
	return nil
end

return GoalData
