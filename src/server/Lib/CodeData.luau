--!strict
-- Promo codes (server only, so they can't be read by exploiters before you
-- announce them). Add a code: pick a NAME in capitals, a reward, and
-- optionally `expires` (unix seconds). Each player can use each code once.

local Streak = require(game:GetService("ReplicatedStorage").Shared.Util.Streak)

export type Code = { reward: Streak.Reward, expires: number? }

local CODES: { [string]: Code } = {
	DINO = {
		reward = { kind = "coins", minutes = 10, minimum = 1000, label = "Coins", emoji = "💰" },
	},
	RAWR = {
		reward = { kind = "luck", seconds = 900, label = "15 min Luck", emoji = "🍀" },
	},
	EGGCELLENT = {
		reward = { kind = "coinBoost", seconds = 900, label = "15 min 2x Coins", emoji = "⚡" },
	},
}

return CODES
