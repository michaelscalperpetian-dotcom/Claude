--!strict
-- Tunable gameplay values. Replicated to clients, so nothing secret lives here,
-- and the server never trusts a client-reported value from this file.
-- This module requires nothing, so the Lune unit tests can load it too.

local Config = {
	-- World
	PLOT_COUNT = 8,
	PLOT_SIZE = 64,
	PLOT_RING_RADIUS = 132,
	-- How every surface looks:
	--   "square"  square studs on every face of every part (dinos and eggs too),
	--             from the SquareStuds MaterialVariant in MaterialService. Its
	--             images live in assets/textures; add them once in Studio (README).
	--   "classic" Roblox's built-in round studs on the top of every brick.
	--   "none"    smooth plastic everywhere.
	-- Glowing, glass and ice parts always stay smooth.
	STUD_STYLE = "square" :: "square" | "classic" | "none",

	-- Starting state
	STARTING_COINS = 100,
	BASE_INCUBATORS = 3,
	MAX_INCUBATORS = 5,
	BASE_DINO_SLOTS = 8,
	NICKNAME_MAX_LENGTH = 20,
	-- Golden dinos: fuse 3 of one species into a Golden one that earns this much more.
	GOLDEN_MULTIPLIER = 3,
	GOLDEN_FEE_SECONDS = 300, -- fee = this many seconds of the species' adult income
	PASS_EXTRA_SLOTS = 4,
	TRAY_CAPACITY = 6,

	-- Saving
	AUTOSAVE_INTERVAL = 60,
	SESSION_LOCK_STALE_SECONDS = 180,

	-- Offline progress
	OFFLINE_EARNINGS_CAP_SECONDS = 8 * 3600,
	OFFLINE_EARNINGS_RATE = 0.5,

	-- Day / night (seconds)
	DAY_SECONDS = 480,
	NIGHT_SECONDS = 150,

	-- Storms (seconds). Storm type for each slot is picked deterministically from time,
	-- so every server and client agrees without any networking.
	STORM_INTERVAL = 1800,
	STORM_DURATION = 180,
	STORM_TICK = 20,
	-- Weekly "Rainbow Mega Storm": Saturday 17:00 UTC for 15 minutes.
	MEGA_STORM_WEEKDAY = 6, -- 0 = Sunday ... 6 = Saturday (UTC)
	MEGA_STORM_HOUR_UTC = 17,
	MEGA_STORM_DURATION = 900,

	-- Egg shop restock (seconds)
	RESTOCK_SECONDS = 300,

	-- Hatching
	WARM_TAP_SECONDS = 0.25, -- each tap on your own egg shaves this much off the timer
	WARM_TAP_RATE = 4, -- max taps per second the server accepts
	FRIEND_WARM_RANGE = 12, -- studs: a friend this close to your egg doubles hatch speed
	FAST_HATCH_MULTIPLIER = 1.5,
	STARTER_EGG_SECONDS = 15,
	GIFT_EGG_SECONDS = 25,

	-- Laying (only Adult and Giant dinos lay)
	LAY_INTERVAL_ADULT = 1800,
	LAY_INTERVAL_GIANT = 1200,

	-- Raids
	GATE_LOCK_SECONDS = 60,
	GATE_COOLDOWN_SECONDS = 120,
	SUPER_LOCK_SECONDS = 300,
	NEW_PLAYER_SHIELD_SECONDS = 24 * 3600,
	STEAL_HOLD_SECONDS = 1.5,
	CARRY_WALKSPEED = 10,
	NORMAL_WALKSPEED = 16,
	RIDE_WALKSPEED = 26,
	TAG_RANGE = 7,
	GUARD_TICK = 3,
	GUARD_CHANCE_PER_POWER = 0.05,
	GUARD_MAX_CHANCE = 0.6,
	STUN_SECONDS = 1.5,
	RAIDS_IN_PRIVATE_SERVERS = false,

	-- Coin multipliers
	FRIEND_BOOST_PER_FRIEND = 0.1,
	FRIEND_BOOST_MAX = 0.4,
	CLUB_COIN_BONUS = 0.1,
	VIP_COIN_MULTIPLIER = 1.2,
	DOUBLE_COINS_MULTIPLIER = 2,
	AD_BOOST_MULTIPLIER = 2,

	-- Timed boosts (seconds)
	AD_BOOST_SECONDS = 600,
	LUCK_POTION_SECONDS = 900,
	LUCK_MULTIPLIER = 2, -- weight multiplier for Rare and better dinos while luck is active

	-- Coin sinks: permanent upgrades bought with coins
	SLOT_UPGRADE_COSTS = { 5000, 50000, 500000, 5000000 },
	INCUBATOR_UPGRADE_COSTS = { 25000, 1000000 },

	-- Robux coin packs: you get this many minutes of your current income, or the
	-- minimum, whichever is bigger. Keeps packs useful at every stage of the game.
	COIN_PACKS = {
		CoinsSmall = { minutes = 10, minimum = 1000 },
		CoinsMedium = { minutes = 45, minimum = 5000 },
		CoinsLarge = { minutes = 120, minimum = 15000 },
		CoinsHuge = { minutes = 300, minimum = 40000 },
		CoinsMega = { minutes = 720, minimum = 100000 },
	},

	STARTER_PACK = { coins = 2500, luckSeconds = 1800 },
	CLUB_DAILY_COINS = { minutes = 60, minimum = 5000 },

	-- Instant hatch tiers: which developer product to sell depends on time left.
	INSTANT_HATCH_SMALL_MAX_SECONDS = 120,
	INSTANT_HATCH_MEDIUM_MAX_SECONDS = 600,

	-- ================================================================
	-- Monetization IDs. Create these in the Creator Hub (Monetization tab of
	-- your game) and paste the numeric IDs here. Anything left at 0 is hidden
	-- in the store. In Studio, the cheat panel can fake pass ownership.
	-- ================================================================
	GAME_PASS_IDS = {
		RideDinos = 0,
		DoubleCoins = 0,
		ExtraSlots = 0,
		AutoCollect = 0,
		FastHatch = 0,
		VIP = 0,
	},

	PRODUCT_IDS = {
		StarterPack = 0,
		CoinsSmall = 0,
		CoinsMedium = 0,
		CoinsLarge = 0,
		CoinsHuge = 0,
		CoinsMega = 0,
		InstantHatchSmall = 0,
		InstantHatchMedium = 0,
		InstantHatchLarge = 0,
		LuckyPotion = 0,
		SuperLock = 0,
		AdCoinBoost = 0, -- reward product for rewarded video ads (not sold in the store)
	},

	-- Subscription ID from the Creator Hub, e.g. "EXP-1234567890". Empty = disabled.
	SUBSCRIPTION_ID = "",

	-- Background music: audio asset IDs (numbers) played as a shuffled
	-- playlist. Pick tracks you're allowed to use from the Creator Store
	-- (Audio, e.g. ones uploaded by Roblox) and paste their IDs here. Empty =
	-- no music, and the Music switch is hidden in Settings.
	MUSIC_TRACKS = {} :: { number },

	-- Suggested Robux prices to enter in the Creator Hub (the store shows the live price).
	SUGGESTED_PRICES = {
		RideDinos = 249,
		DoubleCoins = 299,
		ExtraSlots = 149,
		AutoCollect = 99,
		FastHatch = 199,
		VIP = 399,
		StarterPack = 49,
		CoinsSmall = 25,
		CoinsMedium = 99,
		CoinsLarge = 249,
		CoinsHuge = 499,
		CoinsMega = 999,
		InstantHatchSmall = 9,
		InstantHatchMedium = 19,
		InstantHatchLarge = 49,
		LuckyPotion = 39,
		SuperLock = 19,
	},

	-- Roblox UserIds allowed to use the cheat panel in live servers. Everyone can in Studio.
	DEV_USER_IDS = {} :: { number },
}

return Config
