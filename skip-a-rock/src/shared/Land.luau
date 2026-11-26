--!strict
-- The shape of the coast, as a height for every point near the lobby: a
-- sandy beach sloping into a bay, a flat plaza behind it for the boardwalk,
-- wooded hills rising behind that, and two rocky headlands that frame the
-- bay and run out into the sea. Beyond them the open ocean goes on forever
-- (Ground fills it with water). Also which terrain material belongs where.
-- Pure maths, so the server builds terrain from it, everything is placed on
-- it, and the tests check it.
--
-- Land is z < 0, the sea is z > 0, the water surface is Y = 0.

local Land = {}

Land.WATER_LEVEL = 0
Land.BOTTOM = -32 -- solid ground goes no deeper than this
Land.WEST, Land.EAST = -768, 768 -- the terrain written from this heightmap
Land.SOUTH, Land.NORTH = -768, 512 -- (south = inland, north = out to sea)
Land.BEACH_BACK = -40 -- the beach runs from here down to the water
Land.BANK = 3 -- the water is deep enough for terrain from here on (z)
Land.PLAZA_BACK = -110 -- the flat plaza behind the beach
Land.PLAZA_HEIGHT = 1.8
Land.BAY_HALF = 250 -- the headlands start this far either side of the middle
Land.HEADLAND_END = 290 -- and reach about this far out to sea

export type Material =
	"Water"
	| "Sand"
	| "Mud"
	| "Grass"
	| "LeafyGrass"
	| "Ground"
	| "Rock"
	| "Slate"
	| "Basalt"

local function clamp01(t: number): number
	return math.clamp(t, 0, 1)
end

local function smooth(t: number): number
	local x = clamp01(t)
	return x * x * (3 - 2 * x)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * clamp01(t)
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

-- The ground without the headlands.
local function base(x: number, z: number): number
	if z > Land.BANK then
		-- the sea floor: a sandy shelf, then down into deep water
		if z < 60 then
			return lerp(-2.8, -9, (z - Land.BANK) / (60 - Land.BANK))
		end
		return lerp(-9, -22, (z - 60) / 160) + fbm(x, z, 60, 2, 2.4) * 3 * smooth((z - 60) / 100)
	elseif z > -1 then
		-- a short bank from the wet sand into the water
		return lerp(0.6, -2.8, (z + 1) / (Land.BANK + 1))
	elseif z > Land.BEACH_BACK then
		return lerp(Land.PLAZA_HEIGHT, 0.6, (z - Land.BEACH_BACK) / (-1 - Land.BEACH_BACK))
	elseif z > Land.PLAZA_BACK then
		return Land.PLAZA_HEIGHT
	end
	-- hills behind the plaza, rising into wooded ridges
	local t = smooth((Land.PLAZA_BACK - z) / 240)
	return Land.PLAZA_HEIGHT
		+ t * (55 + fbm(x, z, 120, 3, 5.5) * 50)
		+ fbm(x, z, 40, 2, 1.1) * 4 * t
end

-- How much of a headland stands at (x, z): 0 in the bay, 1 on the cliffs.
local function headland(x: number, z: number): number
	local across = smooth((math.abs(x) - Land.BAY_HALF + fbm(x, z, 70, 2, 8.8) * 50) / 110)
	local reach = Land.HEADLAND_END + fbm(x, z, 120, 2, 3.7) * 80
	local along = 1 - smooth((z - (reach - 140)) / 140)
	return across * along
end

-- Height of the ground's surface at (x, z).
function Land.height(x: number, z: number): number
	local h = base(x, z)
	local m = headland(x, z)
	if m > 0 then
		local cliff = 48 + fbm(x, z, 90, 3, 6.1) * 40 + math.max(Land.PLAZA_BACK - z, 0) * 0.12
		h = h + (math.max(cliff, 20) - h) * m
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
	if slope > 1.4 then
		return if height > 30 then "Slate" else "Basalt"
	elseif slope > 0.85 then
		return "Rock"
	end
	if height < -12 then
		return "Mud"
	elseif height < 3 and z > Land.BEACH_BACK - 6 then
		return "Sand"
	end
	if height > 40 and slope > 0.5 then
		return "Ground"
	end
	return if fbm(x, z, 40, 2, 6.6) > 0.15 then "LeafyGrass" else "Grass"
end

-- A point on the ground (handy for placing things).
function Land.at(x: number, z: number, lift: number?): Vector3
	return Vector3.new(x, Land.height(x, z) + (lift or 0), z)
end

return Land
