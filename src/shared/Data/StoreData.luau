--!strict
-- What the Robux store shows. IDs and suggested prices live in Config; the
-- live price is fetched from Roblox so regional pricing and sales just work.

export type Item = {
	key: string,
	kind: "pass" | "product",
	emoji: string,
	name: string,
	description: string,
	feedsRandom: boolean?, -- hidden for players restricted from paid random items
}

local StoreData = {
	PASSES = {
		{
			key = "RideDinos",
			kind = "pass",
			emoji = "🦖",
			name = "Ride Your Dinos",
			description = "Hop on your grown dinos and ride around the island!",
		},
		{
			key = "DoubleCoins",
			kind = "pass",
			emoji = "💰",
			name = "2x Coins",
			description = "Every dino earns double coins, forever.",
		},
		{
			key = "ExtraSlots",
			kind = "pass",
			emoji = "🏡",
			name = "+4 Nest Slots",
			description = "Room for 4 more dinos in your nest.",
		},
		{
			key = "AutoCollect",
			kind = "pass",
			emoji = "🧲",
			name = "Auto-Collect",
			description = "Coins go straight into your wallet.",
		},
		{
			key = "FastHatch",
			kind = "pass",
			emoji = "⚡",
			name = "Fast Hatch",
			description = "Every egg hatches 1.5x faster.",
		},
		{
			key = "VIP",
			kind = "pass",
			emoji = "⭐",
			name = "VIP",
			description = "A shiny VIP tag and 1.2x coins.",
		},
	} :: { Item },
	PRODUCTS = {
		{
			key = "LuckyPotion",
			kind = "product",
			emoji = "🍀",
			name = "Lucky Potion",
			description = "15 minutes: rare dinos are 2x as likely.",
			feedsRandom = true,
		},
		{
			key = "SuperLock",
			kind = "product",
			emoji = "🔒",
			name = "Super Lock",
			description = "Seal your nest from thieves for 5 minutes.",
		},
		{
			key = "CoinsSmall",
			kind = "product",
			emoji = "💰",
			name = "Coin Pouch",
			description = "10 minutes of your income (at least 1K).",
			feedsRandom = true,
		},
		{
			key = "CoinsMedium",
			kind = "product",
			emoji = "💰",
			name = "Coin Bag",
			description = "45 minutes of your income (at least 5K).",
			feedsRandom = true,
		},
		{
			key = "CoinsLarge",
			kind = "product",
			emoji = "💰",
			name = "Coin Chest",
			description = "2 hours of your income (at least 15K).",
			feedsRandom = true,
		},
		{
			key = "CoinsHuge",
			kind = "product",
			emoji = "💰",
			name = "Coin Vault",
			description = "5 hours of your income (at least 40K).",
			feedsRandom = true,
		},
		{
			key = "CoinsMega",
			kind = "product",
			emoji = "💰",
			name = "Coin Mountain",
			description = "12 hours of your income (at least 100K).",
			feedsRandom = true,
		},
	} :: { Item },
	STARTER_PACK = {
		key = "StarterPack",
		kind = "product",
		emoji = "🎁",
		name = "Starter Pack",
		description = "2,500 coins + 30 minutes of Luck. One time only!",
		feedsRandom = true,
	} :: Item,
}

return StoreData
