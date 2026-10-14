--!strict
-- Types that cross the client/server boundary (saved profile, state snapshot)
-- live here so both sides agree by construction.

export type DinoRecord = {
	id: string,
	species: string,
	mutation: string?,
	bornAt: number, -- unix seconds; stage is computed from age
	lastLaidAt: number,
	name: string?, -- nickname, already through Roblox's text filter
	golden: boolean?, -- fused from 3 of its species; earns Config.GOLDEN_MULTIPLIER x
}

-- "shop": species rolled at hatch from the egg's odds
-- "laid": laid by one of your dinos; species is fixed, mutation rolled at hatch
-- "starter"/"gift": tutorial eggs with a fixed result (not purchasable)
export type EggKind = "shop" | "laid" | "starter" | "gift"

export type IncubatorEgg = {
	id: string,
	kind: EggKind,
	eggType: string?, -- shop eggs
	species: string?, -- laid/starter/gift eggs
	mutation: string?, -- gift eggs
	placedAt: number,
	hatchAt: number,
}

export type TrayEgg = {
	id: string,
	species: string,
	laidAt: number,
}

export type Profile = {
	version: number,
	coins: number,
	pendingCoins: number,
	totalEarned: number,
	nextId: number,
	dinos: { DinoRecord },
	incubators: { [string]: IncubatorEgg }, -- keyed "1".."5" (string keys save cleanly)
	tray: { TrayEgg },
	dex: { [string]: { [string]: boolean } }, -- species -> mutation ("Normal" or id) -> true
	upgrades: { slots: number, incubators: number },
	boosts: { luckUntil: number, coinsUntil: number },
	instantHatchTokens: number,
	streak: { count: number, lastDay: number },
	club: { lastClaimDay: number },
	tutorial: number,
	starterPackBought: boolean,
	shop: { restock: number, bought: { [string]: number } },
	likes: number,
	stats: { hatched: number, stolen: number, eggsLost: number, sold: number },
	receipts: { string },
	firstJoin: number,
	lastSeen: number,
	quests: QuestState,
	dexClaimed: { [string]: boolean }, -- Dex milestone (species count) -> claimed
	codes: { [string]: boolean }, -- redeemed codes
	settings: Settings,
	buddy: string?, -- id of the dino following the player around
	nicknames: { [string]: string }, -- dino id -> name as typed (server only, re-filtered on join)
	rebirths: number,
	fruit: { [string]: number }, -- basket: FruitData kind -> count
	liked: { day: number, owners: { [string]: boolean } }, -- nests liked today (by owner UserId)
}

-- Today's quest progress; reset when the UTC day changes.
export type QuestState = {
	day: number,
	progress: { [string]: number },
	claimed: { [string]: boolean },
	bonusClaimed: boolean,
}

export type Settings = { music: boolean, sfx: boolean }

-- Everything the client needs to draw its own HUD. Sent on change.
export type Snapshot = {
	coins: number,
	pendingCoins: number,
	incomePerSecond: number,
	multiplier: number,
	dinos: { DinoRecord },
	incubators: { [string]: IncubatorEgg },
	tray: { TrayEgg },
	dex: { [string]: { [string]: boolean } },
	upgrades: { slots: number, incubators: number },
	boosts: { luckUntil: number, coinsUntil: number },
	instantHatchTokens: number,
	streak: { count: number, lastDay: number },
	clubClaimDay: number,
	tutorial: number,
	starterPackBought: boolean,
	shopBought: { restock: number, bought: { [string]: number } },
	likes: number,
	passes: { [string]: boolean },
	subscribed: boolean,
	restricted: boolean, -- paid random items restricted for this player (PolicyService)
	plotIndex: number,
	maxSlots: number,
	maxIncubators: number,
	lockUntil: number,
	lockCooldownUntil: number,
	shieldUntil: number,
	friendsHere: number,
	isDev: boolean,
	raidsEnabled: boolean,
	riding: string?,
	carrying: boolean,
	quests: QuestState,
	dexClaimed: { [string]: boolean },
	settings: Settings,
	buddy: string?,
	rebirths: number,
	fruit: { [string]: number },
}

-- Tutorial steps (server is authoritative; client only renders hints).
export type TutorialStep = number

return nil
