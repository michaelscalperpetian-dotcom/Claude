--!strict
-- Builds the little 3D stone for a StoneData id: a squashed sphere in the
-- stone's colour, glassy for gem stones, with a sparkle for the special ones.
-- Used for the stone in your hand, glints on the beach and stones in flight.

local StoneData = require(script.Parent.Data.StoneData)

local StoneModel = {}

local MATERIALS: { [string]: Enum.Material } = {
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Glass = Enum.Material.Glass,
	Neon = Enum.Material.Neon,
}

function StoneModel.color(id: string): Color3
	local stone = (StoneData.get(id) or StoneData.get(StoneData.STARTER)) :: StoneData.Stone
	return Color3.fromRGB(stone.color[1], stone.color[2], stone.color[3])
end

-- An anchored, non-colliding part. `scale` 1 = a stone you can hold.
function StoneModel.build(id: string, scale: number?): Part
	local stone = (StoneData.get(id) or StoneData.get(StoneData.STARTER)) :: StoneData.Stone
	local s = scale or 1
	local part = Instance.new("Part")
	part.Name = "Stone"
	part.Size = Vector3.new(stone.size[1], stone.size[2], stone.size[3]) * s
	part.Color = StoneModel.color(stone.id)
	part.Material = MATERIALS[stone.material] or Enum.Material.SmoothPlastic
	part.Reflectance = if stone.material == "Glass" then 0.15 else 0.05
	part.Transparency = if stone.material == "Glass" then 0.1 else 0
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("Stone", stone.id)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	if stone.sparkle then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "Sparkle"
		sparkle.Color = ColorSequence.new(Color3.new(1, 1, 1), part.Color)
		sparkle.LightEmission = 1
		sparkle.Rate = 5
		sparkle.Lifetime = NumberRange.new(0.4, 0.9)
		sparkle.Speed = NumberRange.new(0.2, 0.8)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.18 * s),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkle.Parent = part
	end
	return part
end

return StoneModel
