--!strict
-- The shape of the valley, as a height for every point on the map: a round
-- lake bowl with a sandy shelf, a gentle beach, a meadow that starts to roll
-- further out, and a ring of ridged, snow-capped mountains all round. Also
-- which terrain material belongs where. Pure maths (no instances), so the
-- server can build the terrain from it, everything can be placed on the
-- ground, and the tests can check it.
--
-- The water surface is Y = 0. Distances are from the lake's centre.

local Config = require(script.Parent.Config)

local Land = {}

local R = Config.LAKE_RADIUS
local BEACH_OUT = Config.LAKE_RADIUS + Config.SHORE_WIDTH

Land.WATER_LEVEL = 0
Land.SIZE = 704 -- the terrain covers -SIZE..SIZE on both axes
Land.BOTTOM = -24 -- solid ground goes no deeper than this
Land.PATH_RADIUS = BEACH_OUT + 8 -- a dirt path round the lake
Land.PATH_WIDTH = 5
Land.SHELF = R - 10 -- the lake floor flattens into a sandy shelf from here...
Land.BANK = R + 1 -- ...which ends at a short bank up to the beach...
Land.SHORE = R + 3 -- ...whose top is the water's edge (players walk from here)
Land.DEEPEST = -16
Land.MOUNTAINS_FROM = 350 -- the foothills start rising here...
Land.MOUNTAINS_FULL = 570 -- ...and the mountains are full height from here out

export type Material =
	"Water"
	| "Sand"
	| "Mud"
	| "Grass"
	| "LeafyGrass"
	| "Ground"
	| "Rock"
	| "Slate"
	| "Snow"

local function clamp01(t: number): number
	return math.clamp(t, 0, 1)
end

local function smooth(t: number): number
	local x = clamp01(t)
	return x * x * (3 - 2 * x)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Layered noise, roughly -0.5..0.5.
local function fbm(x: number, z: number, scale: number, octaves: number, seed: number): number
	local total, amplitude, frequency, norm = 0, 1, 1 / scale, 0
	for i = 1, octaves do
		total += math.noise(x * frequency, z * frequency, seed + i * 17.31) * amplitude
		norm += amplitude
		amplitude *= 0.5
		frequency *= 2
	end
	return total / norm
end
Land.fbm = fbm

-- The ground's height under the meadow (no mountains), r = distance out.
local function meadow(x: number, z: number, r: number): number
	local base = 1.1 + (r - BEACH_OUT) * 0.012
	-- flat by the lake (where the cabin, campfire and boards stand), rolling further out
	local roll = 3.5 * smooth((r - 170) / 150)
	return base + fbm(x, z, 90, 3, 1.7) * 2 * roll
end

-- Height of the ground's surface at (x, z).
function Land.height(x: number, z: number): number
	local r = math.sqrt(x * x + z * z)
	if r < Land.SHELF then
		-- the bowl: deepest in the middle, with a gently lumpy floor
		local t = smooth(r / Land.SHELF)
		return lerp(Land.DEEPEST, -3, t) + fbm(x, z, 30, 2, 4.2) * 1.2 * (1 - t)
	elseif r < Land.BANK then
		-- a sandy shelf, kept more than half a voxel under the surface so
		-- terrain water covers it right up to the bank (and the stones'
		-- first touch, at Lake.EDGE, is always on water)
		return lerp(-3, -2.6, (r - Land.SHELF) / (Land.BANK - Land.SHELF))
	elseif r < Land.SHORE then
		return lerp(-2.6, 0.6, (r - Land.BANK) / (Land.SHORE - Land.BANK))
	elseif r < BEACH_OUT then
		return lerp(0.6, 1.1, (r - Land.SHORE) / (BEACH_OUT - Land.SHORE))
	end
	local h = meadow(x, z, r)
	local rise = smooth((r - Land.MOUNTAINS_FROM) / (Land.MOUNTAINS_FULL - Land.MOUNTAINS_FROM))
	if rise > 0 then
		-- ridged noise gives sharp crests and valleys between the peaks
		-- (clamped: noise can stray a little past ±0.5, and a negative
		-- ridge to a fractional power would be NaN)
		local ridge = math.clamp(1 - math.abs(fbm(x, z, 170, 4, 9.1)) * 2, 0, 1)
		-- some stretches of the ring are lower saddles, some tall massifs
		local massif = 0.6 + 0.8 * math.clamp(fbm(x, z, 420, 2, 2.2) + 0.5, 0, 1)
		local mountain = (45 + 175 * ridge ^ 1.8) * massif + 35 * fbm(x, z, 55, 3, 3.3)
		-- and the ground keeps climbing toward the edge of the map
		mountain += math.max(r - 560, 0) * 0.12
		h += rise * math.max(mountain, 55)
	end
	return h
end

-- How steep the ground is at (x, z) (rise over run).
function Land.slope(x: number, z: number): number
	local d = 2
	local dx = Land.height(x + d, z) - Land.height(x - d, z)
	local dz = Land.height(x, z + d) - Land.height(x, z - d)
	return math.sqrt(dx * dx + dz * dz) / (2 * d)
end

-- Which terrain material covers the ground at (x, z), given its height and slope.
function Land.material(x: number, z: number, height: number, slope: number): Material
	local r = math.sqrt(x * x + z * z)
	if r < Land.BANK then
		return if height < -6 then "Mud" else "Sand"
	elseif r < BEACH_OUT - 1 then
		return "Sand"
	end
	if r < 220 and math.abs(r - Land.PATH_RADIUS) < Land.PATH_WIDTH / 2 then
		return "Ground"
	end
	local jitter = fbm(x, z, 40, 2, 6.6)
	if height > 165 + jitter * 40 then
		return "Snow"
	elseif slope > 1.3 then
		return if height > 90 then "Slate" else "Rock"
	elseif slope > 0.95 or height > 125 + jitter * 30 then
		return "Rock"
	elseif height > 70 + jitter * 40 and slope > 0.55 then
		return "Ground"
	end
	if jitter > 0.17 then
		return "LeafyGrass"
	end
	return "Grass"
end

-- A point on the ground (handy for placing things).
function Land.at(x: number, z: number, lift: number?): Vector3
	return Vector3.new(x, Land.height(x, z) + (lift or 0), z)
end

return Land
