--!strict
-- Robust ways to orient a part along a direction. CFrame.lookAt is undefined
-- when the direction is straight up or down (it can produce NaN rotations),
-- which broke vertical legs, so every "point this along that" goes through here.

local Frames = {}

local X_AXIS = Vector3.new(1, 0, 0)
local Y_AXIS = Vector3.new(0, 1, 0)
local Z_AXIS = Vector3.new(0, 0, 1)

-- CFrame at `center` whose local X axis points along `direction`
-- (Roblox cylinders run along X).
function Frames.alongX(center: Vector3, direction: Vector3): CFrame
	local x = direction.Unit
	local reference = if math.abs(x.Y) > 0.99 then Z_AXIS else Y_AXIS
	local z = x:Cross(reference).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix(center, x, y, z)
end

-- CFrame at `center` whose local Z axis points along `direction`
-- (stretched spheres and blocks use Z as their long axis).
function Frames.alongZ(center: Vector3, direction: Vector3): CFrame
	local z = direction.Unit
	local reference = if math.abs(z.Y) > 0.99 then X_AXIS else Y_AXIS
	local x = reference:Cross(z).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix(center, x, y, z)
end

-- Facing a point on the horizontal plane (the usual "look at" for characters).
function Frames.facing(position: Vector3, target: Vector3): CFrame
	local flat = Vector3.new(target.X - position.X, 0, target.Z - position.Z)
	if flat.Magnitude < 1e-4 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, position + flat)
end

return Frames
