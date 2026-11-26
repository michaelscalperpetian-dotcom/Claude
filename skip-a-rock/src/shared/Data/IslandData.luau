--!strict
-- Islands and markers far out at sea. Skip a rock past one for the first
-- time and it's yours for good: a lasting coin bonus, and some unlock new
-- rocks in the shop. The ocean never ends, so neither do the milestones.

export type Island = {
	id: string,
	name: string,
	distance: number, -- studs from where you threw
	bonus: number, -- extra coins for good (0.1 = +10%)
	model: "buoys" | "rock" | "palm" | "atoll" | "reef" | "lagoon" | nil, -- what stands out at sea
}

local LIST: { Island } = {
	{ id = "buoy", name = "Buoy Bay", distance = 300, bonus = 0.05, model = "buoys" },
	{ id = "gull", name = "Gull Rock", distance = 1500, bonus = 0.1, model = "rock" },
	{ id = "palm", name = "Palm Isle", distance = 10000, bonus = 0.15, model = "palm" },
	{ id = "turtle", name = "Turtle Atoll", distance = 100000, bonus = 0.25, model = "atoll" },
	{ id = "whale", name = "Whale Reef", distance = 1e6, bonus = 0.35, model = "reef" },
	{ id = "lagoon", name = "Glass Lagoon", distance = 1e7, bonus = 0.5, model = "lagoon" },
	{ id = "storm", name = "Storm Sea", distance = 1e8, bonus = 0.75 },
	{ id = "edge", name = "Edge of the Map", distance = 1e10, bonus = 1 },
	{ id = "starfall", name = "Starfall Deep", distance = 1e13, bonus = 1.5 },
	{ id = "beyond", name = "The Beyond", distance = 1e16, bonus = 2.5 },
}

local BY_ID: { [string]: Island } = {}
for _, island in LIST do
	BY_ID[island.id] = island
end

local IslandData = { LIST = LIST }

function IslandData.get(id: string): Island?
	return BY_ID[id]
end

-- The first island not reached yet (nil once you've reached them all).
function IslandData.next(reached: { [string]: boolean }): Island?
	for _, island in LIST do
		if not reached[island.id] then
			return island
		end
	end
	return nil
end

return IslandData
