--!strict
-- 7-day login streak. Claim once per UTC day; missing a day restarts at day 1.

local Streak = {}

export type Reward = {
	kind: "coins" | "luck" | "coinBoost" | "dino",
	minutes: number?, -- coins: minutes of income
	minimum: number?, -- coins: minimum amount
	seconds: number?, -- boosts
	species: string?, -- dino
	label: string,
	emoji: string,
}

Streak.REWARDS = {
	{ kind = "coins", minutes = 10, minimum = 250, label = "Coins", emoji = "💰" },
	{ kind = "coins", minutes = 20, minimum = 1000, label = "More coins", emoji = "💰" },
	{ kind = "luck", seconds = 900, label = "15 min Luck", emoji = "🍀" },
	{ kind = "coins", minutes = 45, minimum = 5000, label = "Coin pile", emoji = "💰" },
	{ kind = "coinBoost", seconds = 1800, label = "30 min 2x Coins", emoji = "⚡" },
	{ kind = "coins", minutes = 90, minimum = 20000, label = "Coin mountain", emoji = "💰" },
	{ kind = "dino", species = "Brachiosaurus", label = "Baby Brachiosaurus!", emoji = "🦕" },
} :: { Reward }

export type State = { count: number, lastDay: number }

-- Returns whether the player can claim today and which day (1-7) they'd claim.
function Streak.status(state: State, today: number): (boolean, number)
	if state.lastDay == today then
		return false, state.count
	end
	if state.lastDay == today - 1 then
		return true, (state.count % #Streak.REWARDS) + 1
	end
	return true, 1
end

return Streak
