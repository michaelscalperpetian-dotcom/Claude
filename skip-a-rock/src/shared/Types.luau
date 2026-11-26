--!strict
-- Types that cross the client/server boundary, so both sides agree.

-- Saved for each player.
export type Profile = {
	version: number,
	coins: number,
	totalCoins: number, -- earned over all time (never goes down)
	strength: number, -- arm strength level (resets on rebirth)
	rocks: { [string]: boolean }, -- rocks owned (kept through rebirths)
	equipped: string,
	rebirths: number,
	islands: { [string]: boolean }, -- islands reached (kept through rebirths)
	bestDistance: number,
	bestSkips: number,
	throws: number,
	totalSkips: number,
	perfects: number,
	goals: { [string]: boolean },
	firstJoin: number,
	lastSeen: number,
}

-- What a player's own client gets (sent when it changes).
export type Snapshot = {
	coins: number,
	totalCoins: number,
	strength: number,
	rocks: { [string]: boolean },
	equipped: string,
	rebirths: number,
	islands: { [string]: boolean },
	bestDistance: number,
	bestSkips: number,
	throws: number,
	totalSkips: number,
	perfects: number,
	goals: { [string]: boolean },
	-- worked out by the server, so the client never has to
	coinMultiplier: number,
	distanceMultiplier: number,
	strengthCost: number,
	rebirthCost: number,
	title: string?,
	isDev: boolean,
}

-- Sent to everyone when someone throws, so every screen draws the same throw.
export type ThrowEvent = {
	userId: number,
	rock: string,
	origin: Vector3, -- where the rock leaves the thrower's hand
	entry: Vector3, -- its first touch on the water
	hops: { number }, -- each hop's true length in studs (draw with Sea.toWorld)
	skips: number,
	distance: number, -- true studs from the first touch
	coins: number,
	verdict: string, -- Skip.Verdict
	perfect: boolean,
	power: number, -- where the needle was when they let go (0..1)
	night: boolean,
	newBest: boolean, -- a longest throw (only matters to the thrower)
}

return nil
