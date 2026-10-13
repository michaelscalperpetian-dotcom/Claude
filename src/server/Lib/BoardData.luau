--!strict
-- The global leaderboards in the hub's Hall of Fame (built by Island, filled
-- in by the Leaderboards system).

export type Board = {
	key: string,
	title: string,
	store: string, -- OrderedDataStore name
	color: Color3,
}

local BoardData = {
	ROWS = 10,
	BOARDS = {
		{
			key = "Earned",
			title = "🏆 Top Earners",
			store = "RaiseADino_LB_Earned_v1",
			color = Color3.fromRGB(255, 196, 46),
		},
		{
			key = "Dex",
			title = "📖 Dex Masters",
			store = "RaiseADino_LB_Dex_v1",
			color = Color3.fromRGB(255, 120, 170),
		},
		{
			key = "Rebirths",
			title = "⭐ Most Rebirths",
			store = "RaiseADino_LB_Rebirths_v1",
			color = Color3.fromRGB(150, 110, 240),
		},
	} :: { Board },
}

return BoardData
