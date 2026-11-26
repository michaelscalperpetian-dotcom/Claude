--!strict
-- Turns the valley in Land into real Roblox terrain: smooth voxels for the
-- lake bowl, beach, meadow and mountains, terrain water in the lake (with
-- gentle waves and reflections), swaying grass, soft material colours and
-- drifting clouds. Built in chunks, nearest the lake first, pausing between
-- chunks so the server never stalls.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Land = require(ReplicatedStorage.Shared.Land)
local Palette = require(ReplicatedStorage.Shared.Palette)

local Ground = {}

Ground.VOXEL = 4
Ground.CHUNK = 64 -- studs per side of each block of terrain written at once
Ground.BUDGET = 0.025 -- seconds of work between pauses

local MATERIALS: { [Land.Material]: Enum.Material } = {
	Water = Enum.Material.Water,
	Sand = Enum.Material.Sand,
	Mud = Enum.Material.Mud,
	Grass = Enum.Material.Grass,
	LeafyGrass = Enum.Material.LeafyGrass,
	Ground = Enum.Material.Ground,
	Rock = Enum.Material.Rock,
	Slate = Enum.Material.Slate,
	Snow = Enum.Material.Snow,
}

-- Soft, slightly warm colours for each material (Roblox's defaults are harsh).
export type Tint = { material: Enum.Material, color: Color3 }
Ground.COLORS = {
	{ material = Enum.Material.Grass, color = Color3.fromRGB(108, 150, 76) },
	{ material = Enum.Material.LeafyGrass, color = Color3.fromRGB(92, 134, 66) },
	{ material = Enum.Material.Sand, color = Color3.fromRGB(214, 196, 156) },
	{ material = Enum.Material.Mud, color = Color3.fromRGB(96, 84, 66) },
	{ material = Enum.Material.Ground, color = Color3.fromRGB(142, 116, 84) },
	{ material = Enum.Material.Rock, color = Color3.fromRGB(124, 122, 128) },
	{ material = Enum.Material.Slate, color = Color3.fromRGB(100, 104, 112) },
	{ material = Enum.Material.Snow, color = Color3.fromRGB(240, 244, 252) },
} :: { Tint }

local function floorTo(value: number, step: number): number
	return math.floor(value / step) * step
end

local function ceilTo(value: number, step: number): number
	return math.ceil(value / step) * step
end

-- The water, grass and colours (no voxels).
function Ground.style(terrain: Terrain)
	terrain.WaterColor = Palette.lakeDay
	terrain.WaterTransparency = 0.55
	terrain.WaterReflectance = 0.6
	terrain.WaterWaveSize = 0.06
	terrain.WaterWaveSpeed = 5
	-- grass blades that sway in the wind (cosmetic: never let it stop the build)
	pcall(function()
		terrain.Decoration = true
	end)
	for _, tint in Ground.COLORS do
		terrain:SetMaterialColor(tint.material, tint.color)
	end
	if not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.52
		clouds.Density = 0.55
		clouds.Color = Color3.fromRGB(255, 252, 246)
		clouds.Parent = terrain
	end
end

-- Every chunk's lower corner, nearest the lake first.
function Ground.chunks(): { Vector2 }
	local list: { Vector2 } = {}
	for x = -Land.SIZE, Land.SIZE - Ground.CHUNK, Ground.CHUNK do
		for z = -Land.SIZE, Land.SIZE - Ground.CHUNK, Ground.CHUNK do
			table.insert(list, Vector2.new(x, z))
		end
	end
	table.sort(list, function(a, b)
		local c = Ground.CHUNK / 2
		return (a + Vector2.new(c, c)).Magnitude < (b + Vector2.new(c, c)).Magnitude
	end)
	return list
end

export type Voxels = {
	region: Region3,
	materials: { { { Enum.Material } } },
	occupancies: { { { number } } },
}

-- The voxels for one chunk with its lower corner at (x0, z0).
function Ground.chunk(x0: number, z0: number): Voxels
	local v = Ground.VOXEL
	local columns = Ground.CHUNK // v
	local heights: { { number } } = {}
	local kinds: { { Enum.Material } } = {}
	local low, high = math.huge, -math.huge
	for i = 1, columns do
		heights[i] = {}
		kinds[i] = {}
		for k = 1, columns do
			local x = x0 + (i - 0.5) * v
			local z = z0 + (k - 0.5) * v
			local h = Land.height(x, z)
			heights[i][k] = h
			kinds[i][k] = MATERIALS[Land.material(x, z, h, Land.slope(x, z))]
			low = math.min(low, h)
			high = math.max(high, h)
		end
	end
	-- solid ground a dozen studs deep under the surface is plenty; below
	-- the lake it reaches down to the bottom
	local bottom = math.max(floorTo(low - 12, v), Land.BOTTOM)
	local top = ceilTo(math.max(high, Land.WATER_LEVEL) + v, v)
	local layers = (top - bottom) // v
	local materials: { { { Enum.Material } } } = {}
	local occupancies: { { { number } } } = {}
	for i = 1, columns do
		materials[i] = {}
		occupancies[i] = {}
		for j = 1, layers do
			local mats = {}
			local occs = {}
			local y0 = bottom + (j - 1) * v
			for k = 1, columns do
				local h = heights[i][k]
				local fill = math.clamp((h - y0) / v, 0, 1)
				if y0 + v <= Land.WATER_LEVEL and fill < 0.5 then
					-- under the lake's surface: water fills what the ground doesn't
					mats[k] = Enum.Material.Water
					occs[k] = 1
				elseif fill > 0 then
					mats[k] = kinds[i][k]
					occs[k] = fill
				else
					mats[k] = Enum.Material.Air
					occs[k] = 0
				end
			end
			materials[i][j] = mats
			occupancies[i][j] = occs
		end
	end
	local region = Region3.new(
		Vector3.new(x0, bottom, z0),
		Vector3.new(x0 + Ground.CHUNK, top, z0 + Ground.CHUNK)
	)
	return { region = region:ExpandToGrid(v), materials = materials, occupancies = occupancies }
end

-- Builds all of it. Yields (call from its own thread).
function Ground.build(terrain: Terrain)
	Ground.style(terrain)
	local started = os.clock()
	for _, corner in Ground.chunks() do
		local voxels = Ground.chunk(corner.X, corner.Y)
		terrain:WriteVoxels(voxels.region, Ground.VOXEL, voxels.materials, voxels.occupancies)
		if os.clock() - started > Ground.BUDGET then
			task.wait()
			started = os.clock()
		end
	end
end

return Ground
