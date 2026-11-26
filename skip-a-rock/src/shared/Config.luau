--!strict
-- Every tunable number in one place (the economy's curves live in Economy).

local Config = {
	-- Saving
	DATASTORE_NAME = "SkipARock_Profiles_v1",
	AUTOSAVE_INTERVAL = 120,
	SESSION_LOCK_STALE_SECONDS = 600,

	-- The coast: land is z < 0, the open ocean is z > 0 (stones fly toward +Z)
	THROW_ZONE_BACK = -26, -- you can throw from anywhere on the beach in front of this...
	THROW_ZONE_HALF_WIDTH = 200, -- ...within this far either side of the middle
	MAX_THROW_HEIGHT = 14, -- no throwing from rooftops

	-- Throwing
	THROW_COOLDOWN = 1.2, -- seconds between throws
	MIN_CHARGE_SECONDS = 0.08, -- shorter presses are taps, not throws
	MAX_CHARGE_SECONDS = 8, -- holding longer than this cancels the throw

	-- Treasure that washes up on the beach
	TREASURE_COUNT = 8,
	TREASURE_RESPAWN_MIN = 30,
	TREASURE_RESPAWN_MAX = 70,

	-- One day by the sea (day, dusk, night, dawn) in real seconds
	DAY_LENGTH = 20 * 60,

	-- Leaderboards
	LEADERBOARD_REFRESH = 120,

	-- Calm background music: Roblox audio asset ids (numbers) to play in a
	-- loop, e.g. tracks from the Creator Store's music library. Empty = quiet.
	MUSIC_TRACKS = {} :: { number },

	-- People who see the test tools in live games (Studio always shows them).
	DEV_USER_IDS = {} :: { number },
}

return Config
