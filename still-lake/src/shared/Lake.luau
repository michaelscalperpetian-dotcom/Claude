--!strict
-- The lake's shape, shared by server and client: a circle of LAKE_RADIUS
-- around the origin with the water surface at Y = 0. Works on the flat X/Z
-- plane; heights are ignored.

local Config = require(script.Parent.Config)

local Lake = {}

Lake.RADIUS = Config.LAKE_RADIUS
Lake.EDGE = Config.LAKE_RADIUS - 1 -- stones touch down at least this far inside the shoreline
Lake.DOCK_LEAD = 2 -- from a dock, the stone first touches at least this far in front of you
Lake.MIN_OPEN_WATER = 8 -- a throw needs at least this much water ahead of it

-- Three wooden docks reach out over the water from the beach. Each one runs
-- straight toward the centre along its angle (0 points along +Z).
Lake.DOCK_ANGLES = { math.rad(15), math.rad(140), math.rad(255) }
Lake.DOCK_INNER = 86 -- the lake end, from the centre
Lake.DOCK_OUTER = Config.LAKE_RADIUS + Config.SHORE_WIDTH + 4 -- the land end
Lake.DOCK_WIDTH = 7
Lake.DOCK_TOP = 1.2 -- height of the deck

-- Distances along a ray (px, pz) + t (dx, dz) where it crosses a circle of
-- radius r around the origin: (near, far), or nil if it misses.
local function crossings(
	px: number,
	pz: number,
	dx: number,
	dz: number,
	r: number
): (number?, number?)
	local b = px * dx + pz * dz
	local c = px * px + pz * pz - r * r
	local disc = b * b - c
	if disc < 0 then
		return nil, nil
	end
	local root = math.sqrt(disc)
	return -b - root, -b + root
end

-- The direction on the flat plane, or nil if it has no horizontal part.
function Lake.flatten(direction: Vector3): Vector3?
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local length = flat.Magnitude
	if length ~= length or length < 0.1 or length == math.huge then
		return nil -- NaN, (almost) straight up, or infinite
	end
	local unit = flat.Unit
	if unit.X ~= unit.X or unit.Z ~= unit.Z then
		return nil
	end
	return unit
end

function Lake.distanceFromCentre(position: Vector3): number
	return Vector3.new(position.X, 0, position.Z).Magnitude
end

function Lake.isOverWater(position: Vector3): boolean
	return Lake.distanceFromCentre(position) < Lake.EDGE
end

-- Is this point (on the flat plane) under one of the docks, `margin` studs
-- of slack included?
function Lake.underDock(position: Vector3, margin: number?): boolean
	local slack = margin or 0
	for _, angle in Lake.DOCK_ANGLES do
		local along = position.X * math.sin(angle) + position.Z * math.cos(angle)
		local across = position.X * math.cos(angle) - position.Z * math.sin(angle)
		if
			along >= Lake.DOCK_INNER - slack
			and along <= Lake.DOCK_OUTER + slack
			and math.abs(across) <= Lake.DOCK_WIDTH / 2 + slack
		then
			return true
		end
	end
	return false
end

Lake.MAX_DOCK_CLEARANCE = 30 -- a stone flies at most this far to get clear of a dock

-- Where a stone thrown from `origin` along flat unit `direction` first touches
-- the water, and how far the thrower is from the water that way (0 when
-- already standing over it, on a dock). Nil if it never would.
--
-- The stone always lands clear of the docks: from on (or beside) a dock it
-- flies on until it is past the planks. Thrown back along a dock it never
-- gets clear, so that doesn't count.
function Lake.entry(origin: Vector3, direction: Vector3): (Vector3?, number)
	local start = Vector3.new(origin.X, 0, origin.Z)
	local reach: number
	local lead: number
	if Lake.distanceFromCentre(origin) < Lake.EDGE then
		reach = 0
		lead = Lake.DOCK_LEAD
	else
		local near, far = crossings(origin.X, origin.Z, direction.X, direction.Z, Lake.EDGE)
		if near == nil or far == nil or far <= 0 then
			return nil, math.huge
		end
		reach = math.max(near, 0)
		lead = reach
	end
	local cleared = 0
	while Lake.underDock(start + direction * lead, 0.5) do
		lead += 0.5
		cleared += 0.5
		if cleared > Lake.MAX_DOCK_CLEARANCE then
			return nil, math.huge
		end
	end
	return start + direction * lead, reach
end

-- Open water ahead of a point on the lake along flat unit `direction`.
function Lake.openWater(point: Vector3, direction: Vector3): number
	local _, far = crossings(point.X, point.Z, direction.X, direction.Z, Lake.EDGE)
	return if far then math.max(far, 0) else 0
end

-- Where a stone is after travelling `distance` from `entry` along `direction`.
function Lake.along(entry: Vector3, direction: Vector3, distance: number): Vector3
	return Vector3.new(entry.X + direction.X * distance, 0, entry.Z + direction.Z * distance)
end

return Lake
