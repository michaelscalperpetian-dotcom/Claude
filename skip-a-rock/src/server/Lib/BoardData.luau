--!strict
-- The global leaderboards on the boardwalk (built by Scenery, filled in by
-- the Leaderboards system).

export type Key = "Distance" | "Coins" | "Rebirths"

export type Board = {
	key: Key,
	title: string,
	store: string, -- OrderedDataStore name
	color: Color3,
	logScale: boolean, -- stored as a scaled logarithm (simulator numbers outgrow integers)
}

local BoardData = {
	ROWS = 10,
	LOG_SCALE = 1e10, -- stored value = floor(log10(1 + score) x LOG_SCALE)
	BOARDS = {
		{
			key = "Distance",
			title = "📏 Longest Throw",
			store = "SkipARock_LB_Distance_v1",
			color = Color3.fromRGB(70, 150, 220),
			logScale = true,
		},
		{
			key = "Coins",
			title = "💰 Most Coins",
			store = "SkipARock_LB_Coins_v1",
			color = Color3.fromRGB(236, 172, 52),
			logScale = true,
		},
		{
			key = "Rebirths",
			title = "🔁 Most Rebirths",
			store = "SkipARock_LB_Rebirths_v1",
			color = Color3.fromRGB(160, 110, 230),
			logScale = false,
		},
	} :: { Board },
}

function BoardData.encode(board: Board, score: number): number
	local s = if score ~= score then 0 else math.max(score, 0)
	if board.logScale then
		return math.floor(math.log10(1 + math.min(s, 1e300)) * BoardData.LOG_SCALE)
	end
	return math.floor(math.min(s, 2 ^ 53))
end

function BoardData.decode(board: Board, stored: number): number
	if board.logScale then
		return 10 ^ (stored / BoardData.LOG_SCALE) - 1
	end
	return stored
end

return BoardData
