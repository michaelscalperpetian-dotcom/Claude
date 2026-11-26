--!strict
-- Types that cross the client/server boundary, so both sides agree.

-- Saved for each player.
export type Profile = {
	version: number,
	stones: { [string]: number }, -- stone id -> times found (you start with one Pebble)
	equipped: string,
	bestSkips: number,
	bestDistance: number,
	nightSkips: number, -- best skips in one throw at night
	shore: boolean, -- has skipped a stone all the way across the lake
	throws: number,
	totalSkips: number,
	perfects: number,
	goals: { [string]: boolean }, -- finished journal goals
	firstJoin: number,
	lastSeen: number,
}

-- What a player's own client gets (sent when it changes).
export type Snapshot = {
	stones: { [string]: number },
	equipped: string,
	bestSkips: number,
	bestDistance: number,
	nightSkips: number,
	shore: boolean,
	throws: number,
	totalSkips: number,
	perfects: number,
	goals: { [string]: boolean },
	title: string?,
	isDev: boolean,
}

-- Sent to everyone when someone throws, so every screen draws the same throw.
export type ThrowEvent = {
	userId: number,
	stone: string,
	origin: Vector3, -- where the stone leaves the thrower's hand
	entry: Vector3, -- its first touch on the water
	direction: Vector3, -- flat unit vector
	hops: { number },
	skips: number,
	distance: number,
	verdict: string, -- Skip.Verdict
	perfect: boolean,
	power: number, -- where the needle was when they let go (0..1)
	night: boolean,
	newBestSkips: boolean, -- a personal record (only matters to the thrower)
	newBestDistance: boolean,
}

return nil
