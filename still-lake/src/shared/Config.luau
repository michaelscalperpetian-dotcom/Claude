--!strict
-- Every tunable number in one place.

local Config = {
	-- Saving
	DATASTORE_NAME = "StillLake_Profiles_v1",
	AUTOSAVE_INTERVAL = 120,
	SESSION_LOCK_STALE_SECONDS = 600,

	-- The lake: a circle centred on the origin, water surface at Y = 0.
	LAKE_RADIUS = 110,
	SHORE_WIDTH = 16, -- pebble beach between the water and the grass
	THROW_REACH = 18, -- how far from the water's edge you can stand and still throw
	MAX_THROW_HEIGHT = 14, -- no throwing from the tops of trees and roofs

	-- Throwing
	THROW_COOLDOWN = 1.2, -- seconds between throws
	MIN_CHARGE_SECONDS = 0.08, -- shorter presses are taps, not throws
	MAX_CHARGE_SECONDS = 8, -- holding longer than this cancels the throw

	-- Glinting stones on the beach
	GLINT_COUNT = 10, -- how many are out at once
	GLINT_RESPAWN_MIN = 35,
	GLINT_RESPAWN_MAX = 75,

	-- One day on the lake (day, dusk, night, dawn) in real seconds
	DAY_LENGTH = 20 * 60,

	-- Leaderboards
	LEADERBOARD_REFRESH = 120,

	-- People who see the test tools in live games (Studio always shows them).
	DEV_USER_IDS = {} :: { number },
}

return Config
