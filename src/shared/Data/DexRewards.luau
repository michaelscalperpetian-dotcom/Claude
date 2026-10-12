--!strict
-- Prizes for filling the Dino-Dex: discover enough different species and a
-- milestone unlocks. The last one is for finding every species.

local DinoData = require(script.Parent.DinoData)
local Streak = require(script.Parent.Parent.Util.Streak)

export type Milestone = { count: number, reward: Streak.Reward }

local DexRewards = {
	MILESTONES = {
		{
			count = 3,
			reward = {
				kind = "coins",
				minutes = 20,
				minimum = 2000,
				label = "Coin bag",
				emoji = "💰",
			},
		},
		{
			count = 6,
			reward = { kind = "luck", seconds = 1800, label = "30 min Luck", emoji = "🍀" },
		},
		{
			count = 9,
			reward = {
				kind = "coinBoost",
				seconds = 3600,
				label = "1 hour 2x Coins",
				emoji = "⚡",
			},
		},
		{
			count = #DinoData.LIST,
			reward = {
				kind = "coins",
				minutes = 240,
				minimum = 500000,
				label = "Treasure",
				emoji = "👑",
			},
		},
	} :: { Milestone },
}

function DexRewards.discovered(dex: { [string]: { [string]: boolean } }): number
	local count = 0
	for species in dex do
		if DinoData.get(species) then
			count += 1
		end
	end
	return count
end

return DexRewards
