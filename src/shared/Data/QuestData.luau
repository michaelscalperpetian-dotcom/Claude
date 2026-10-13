--!strict
-- Daily quests: three a day, the same for everyone (picked from the date), so
-- friends can do them together. Progress comes from normal play, and every
-- quest can be finished alone. Pure data + logic: runs under Lune too.

local Rng = require(script.Parent.Parent.Util.Rng)
local Streak = require(script.Parent.Parent.Util.Streak)

export type Quest = {
	id: string,
	event: string, -- gameplay event that advances it
	goal: number,
	text: string,
	emoji: string,
	reward: Streak.Reward,
}

local POOL: { Quest } = {
	{
		id = "feed",
		event = "feed",
		goal = 3,
		text = "Feed your dinos 3 fruits",
		emoji = "🍎",
		reward = { kind = "coins", minutes = 10, minimum = 400, label = "Coins", emoji = "💰" },
	},
	{
		id = "hatch",
		event = "hatch",
		goal = 3,
		text = "Hatch 3 eggs",
		emoji = "🐣",
		reward = { kind = "coins", minutes = 15, minimum = 500, label = "Coins", emoji = "💰" },
	},
	{
		id = "buy",
		event = "buy_egg",
		goal = 4,
		text = "Buy 4 eggs at the Egg Shop",
		emoji = "🥚",
		reward = { kind = "coins", minutes = 12, minimum = 400, label = "Coins", emoji = "💰" },
	},
	{
		id = "collect",
		event = "collect",
		goal = 5,
		text = "Collect coins from your pad 5 times",
		emoji = "💰",
		reward = { kind = "luck", seconds = 600, label = "10 min Luck", emoji = "🍀" },
	},
	{
		id = "roar",
		event = "roar",
		goal = 5,
		text = "Roar 5 times",
		emoji = "🦖",
		reward = { kind = "coins", minutes = 8, minimum = 300, label = "Coins", emoji = "💰" },
	},
	{
		id = "laid",
		event = "incubate_tray",
		goal = 1,
		text = "Incubate an egg your dino laid",
		emoji = "🧺",
		reward = { kind = "coinBoost", seconds = 600, label = "10 min 2x Coins", emoji = "⚡" },
	},
	{
		id = "sell",
		event = "sell_tray",
		goal = 2,
		text = "Sell 2 laid eggs",
		emoji = "🏷",
		reward = { kind = "coins", minutes = 12, minimum = 400, label = "Coins", emoji = "💰" },
	},
}

local BY_ID: { [string]: Quest } = {}
for _, quest in POOL do
	BY_ID[quest.id] = quest
end

local QuestData = {
	POOL = POOL,
	PER_DAY = 3,
	-- extra prize for finishing all of today's quests
	ALL_DONE_REWARD = { kind = "luck", seconds = 1800, label = "30 min Luck", emoji = "🍀" } :: Streak.Reward,
}

function QuestData.get(id: string): Quest?
	return BY_ID[id]
end

-- Today's quests (same list for every player on the same UTC day).
function QuestData.forDay(day: number): { Quest }
	local gen = Rng.new(Rng.hash(day, 0x5157))
	local remaining = table.clone(POOL)
	local picked: { Quest } = {}
	for _ = 1, math.min(QuestData.PER_DAY, #remaining) do
		local index = gen.int(1, #remaining)
		table.insert(picked, table.remove(remaining, index) :: Quest)
	end
	return picked
end

return QuestData
