--!strict
-- Builds the little 3D rock for a RockData id: a squashed sphere in the
-- rock's colour and material, glassy for gems, with a sparkle for the special
-- ones. Used for the rock in your hand, the shop and rocks in flight.

local RockData = require(script.Parent.Data.RockData)

local RockModel = {}

local MATERIALS: { [string]: Enum.Material } = {
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Glass = Enum.Material.Glass,
	Neon = Enum.Material.Neon,
	Slate = Enum.Material.Slate,
	Marble = Enum.Material.Marble,
}

function RockModel.color(id: string): Color3
	local rock = (RockData.get(id) or RockData.get(RockData.STARTER)) :: RockData.Rock
	return Color3.fromRGB(rock.color[1], rock.color[2], rock.color[3])
end

-- An anchored, non-colliding part. `scale` 1 = a rock you can hold.
function RockModel.build(id: string, scale: number?): Part
	local rock = (RockData.get(id) or RockData.get(RockData.STARTER)) :: RockData.Rock
	local s = scale or 1
	local part = Instance.new("Part")
	part.Name = "Rock"
	part.Size = Vector3.new(rock.size[1], rock.size[2], rock.size[3]) * s
	part.Color = RockModel.color(rock.id)
	part.Material = MATERIALS[rock.material] or Enum.Material.SmoothPlastic
	part.Reflectance = if rock.material == "Glass" then 0.15 else 0.05
	part.Transparency = if rock.material == "Glass" then 0.1 else 0
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("Rock", rock.id)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	if rock.sparkle then
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

return RockModel
