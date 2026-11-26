--!strict
-- Journal goals (little things to aim for) and the titles that float over a
-- skipper's head as their best throw gets better.

export type Kind = "skips" | "distance" | "perfects" | "stones" | "shore" | "nightSkips" | "throws"

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
	stones: number, -- kinds of stone found, the Pebble included
	shore: boolean, -- has skipped a stone all the way across
	nightSkips: number, -- best skips in one throw at night
	throws: number,
}

export type Title = { skips: number, name: string }

local GOALS: { Goal } = {
	{ id = "skip1", text = "Skip a stone", emoji = "💧", kind = "skips", value = 1 },
	{ id = "skip5", text = "5 skips in one throw", emoji = "💧", kind = "skips", value = 5 },
	{ id = "skip10", text = "10 skips in one throw", emoji = "🌊", kind = "skips", value = 10 },
	{ id = "skip15", text = "15 skips in one throw", emoji = "🌊", kind = "skips", value = 15 },
	{ id = "skip20", text = "20 skips in one throw", emoji = "✨", kind = "skips", value = 20 },
	{ id = "skip25", text = "25 skips in one throw", emoji = "✨", kind = "skips", value = 25 },
	{ id = "skip30", text = "30 skips in one throw", emoji = "🏆", kind = "skips", value = 30 },
	{ id = "far50", text = "Skip a stone 50 studs", emoji = "📏", kind = "distance", value = 50 },
	{
		id = "far100",
		text = "Skip a stone 100 studs",
		emoji = "📏",
		kind = "distance",
		value = 100,
	},
	{
		id = "far150",
		text = "Skip a stone 150 studs",
		emoji = "📏",
		kind = "distance",
		value = 150,
	},
	{
		id = "shore",
		text = "Skip a stone all the way across the lake",
		emoji = "🏝️",
		kind = "shore",
		value = 1,
	},
	{
		id = "perfect1",
		text = "Make a perfect release",
		emoji = "🎯",
		kind = "perfects",
		value = 1,
	},
	{
		id = "perfect25",
		text = "Make 25 perfect releases",
		emoji = "🎯",
		kind = "perfects",
		value = 25,
	},
	{ id = "stones4", text = "Find 4 kinds of stone", emoji = "🪨", kind = "stones", value = 4 },
	{ id = "stones8", text = "Find 8 kinds of stone", emoji = "🪨", kind = "stones", value = 8 },
	{
		id = "stones12",
		text = "Find every kind of stone",
		emoji = "💎",
		kind = "stones",
		value = 12,
	},
	{
		id = "night10",
		text = "10 skips in one throw at night",
		emoji = "🌙",
		kind = "nightSkips",
		value = 10,
	},
	{ id = "throws100", text = "Skip 100 stones", emoji = "🧺", kind = "throws", value = 100 },
	{
		id = "throws1000",
		text = "Skip 1,000 stones",
		emoji = "🧺",
		kind = "throws",
		value = 1000,
	},
}

-- Best skips in one throw -> title. Highest first.
local TITLES: { Title } = {
	{ skips = 30, name = "Legend of Still Lake" },
	{ skips = 25, name = "Stone Whisperer" },
	{ skips = 20, name = "Lake Dancer" },
	{ skips = 15, name = "Skimmer" },
	{ skips = 10, name = "Splash Artist" },
	{ skips = 5, name = "Ripple Rookie" },
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
	if goal.kind == "skips" then
		return stats.bestSkips
	elseif goal.kind == "distance" then
		return stats.bestDistance
	elseif goal.kind == "perfects" then
		return stats.perfects
	elseif goal.kind == "stones" then
		return stats.stones
	elseif goal.kind == "shore" then
		return if stats.shore then 1 else 0
	elseif goal.kind == "nightSkips" then
		return stats.nightSkips
	end
	return stats.throws
end

function GoalData.isDone(goal: Goal, stats: Stats): boolean
	return GoalData.progress(goal, stats) >= goal.value
end

-- The title for a best throw of `bestSkips`, or nil below the first one.
function GoalData.title(bestSkips: number): string?
	for _, title in TITLES do
		if bestSkips >= title.skips then
			return title.name
		end
	end
	return nil
end

return GoalData
