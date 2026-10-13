--!strict
-- Fruit you pick up under the fruit trees and feed to dinos to grow them faster.

export type Kind = "apple" | "golden"

export type Fruit = {
	kind: Kind,
	name: string,
	emoji: string,
	color: { number },
	grows: number, -- seconds of growth one fruit gives
	cap: number, -- how many fit in your basket
}

local FRUITS: { [string]: Fruit } = {
	apple = {
		kind = "apple",
		name = "Dino Apple",
		emoji = "🍎",
		color = { 235, 60, 60 },
		grows = 300,
		cap = 20,
	},
	golden = {
		kind = "golden",
		name = "Golden Apple",
		emoji = "🌟",
		color = { 255, 200, 50 },
		grows = 1800,
		cap = 5,
	},
}

local FruitData = {
	FRUITS = FRUITS,
	-- feeding uses apples first, then golden apples
	ORDER = { "apple", "golden" } :: { Kind },
	RESPAWN_SECONDS = 60,
	GOLDEN_CHANCE = 0.08,
	PICK_DISTANCE = 12,
}

function FruitData.get(kind: string): Fruit?
	return FRUITS[kind]
end

-- Which fruit a feed would use, given what's in the basket.
function FruitData.nextToFeed(basket: { [string]: number }): Kind?
	for _, kind in FruitData.ORDER do
		if (basket[kind] or 0) > 0 then
			return kind :: Kind
		end
	end
	return nil
end

return FruitData
