--!strict
-- The two global leaderboards beside the cabin (built by Scenery, filled in
-- by the Leaderboards system).

export type Key = "Skips" | "Distance"

export type Board = {
	key: Key,
	title: string,
	store: string, -- OrderedDataStore name
	color: Color3,
}

local BoardData = {
	ROWS = 10,
	BOARDS = {
		{
			key = "Skips",
			title = "🌊 Most Skips",
			store = "StillLake_LB_Skips_v1",
			color = Color3.fromRGB(92, 156, 222),
		},
		{
			key = "Distance",
			title = "📏 Longest Throw",
			store = "StillLake_LB_Distance_v1",
			color = Color3.fromRGB(232, 148, 76),
		},
	} :: { Board },
}

return BoardData
