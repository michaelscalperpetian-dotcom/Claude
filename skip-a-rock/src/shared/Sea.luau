--!strict
-- The coast and the ocean, shared by server and client. Land is z < 0 and
-- the open sea stretches forever toward +Z; the water surface is Y = 0.
-- Every rock flies straight out to sea from where it was thrown.
--
-- The ocean is endless but the world isn't, so distances out at sea are
-- drawn on a gently squeezed scale: true to life for the first 1,500 studs,
-- then each extra stud covers a little less of the map. Buoys and islands
-- use the same scale, so a rock that lands by the 10K buoy really did go
-- 10,000 studs.

local Config = require(script.Parent.Config)

local Sea = {}

Sea.LINEAR = 1500 -- true-to-life distances up to here...
Sea.SQUEEZE = 1600 -- ...then this sets how gently the scale squeezes
Sea.ENTRY_LEAD = 6 -- a rock first touches the water this far in front of you
Sea.FIRST_WATER = 6 -- and never closer to the beach than this
Sea.FORWARD = Vector3.new(0, 0, 1)

-- The five wooden piers, out into the bay.
Sea.PIER_XS = { -120, -60, 0, 60, 120 }
Sea.PIER_START = -14
Sea.PIER_END = 56
Sea.PIER_WIDTH = 8
Sea.PIER_TOP = 1.8 -- height of the deck

-- How far along the map (from the throw) a true distance is drawn.
function Sea.toWorld(distance: number): number
	local d = math.max(distance, 0)
	if d ~= d or d == math.huge then
		return Sea.LINEAR + Sea.SQUEEZE * 50
	end
	if d <= Sea.LINEAR then
		return d
	end
	return Sea.LINEAR + Sea.SQUEEZE * math.log(1 + (d - Sea.LINEAR) / Sea.SQUEEZE)
end

-- The inverse: the true distance drawn at `world` studs out.
function Sea.fromWorld(world: number): number
	local w = math.max(world, 0)
	if w <= Sea.LINEAR then
		return w
	end
	return Sea.LINEAR + Sea.SQUEEZE * (math.exp((w - Sea.LINEAR) / Sea.SQUEEZE) - 1)
end

-- Which pier (if any) a point is over, by its index in PIER_XS.
function Sea.pierAt(position: Vector3, margin: number?): number?
	local slack = margin or 0
	if position.Z < Sea.PIER_START - slack or position.Z > Sea.PIER_END + slack then
		return nil
	end
	for i, x in Sea.PIER_XS do
		if math.abs(position.X - x) <= Sea.PIER_WIDTH / 2 + slack then
			return i
		end
	end
	return nil
end

-- Can a rock be thrown from here? (On the beach or a pier, near the middle.)
function Sea.canThrowFrom(position: Vector3): boolean
	if position.Y > Config.MAX_THROW_HEIGHT then
		return false
	end
	if math.abs(position.X) > Config.THROW_ZONE_HALF_WIDTH then
		return false
	end
	return position.Z >= Config.THROW_ZONE_BACK
end

-- Where a rock thrown from `origin` first touches the water: straight out
-- in front, clear of the piers (it sails over one if you're behind it).
function Sea.entry(origin: Vector3): Vector3
	local z = math.max(origin.Z + Sea.ENTRY_LEAD, Sea.FIRST_WATER)
	local point = Vector3.new(origin.X, 0, z)
	if Sea.pierAt(point, 1) then
		z = math.max(z, Sea.PIER_END + 3)
	end
	return Vector3.new(origin.X, 0, z)
end

-- Where a rock is after travelling `distance` (true studs) from `entry`.
function Sea.along(entry: Vector3, distance: number): Vector3
	return Vector3.new(entry.X, 0, entry.Z + Sea.toWorld(distance))
end

return Sea
