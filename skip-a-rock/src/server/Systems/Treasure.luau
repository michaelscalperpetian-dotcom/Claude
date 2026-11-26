--!strict
-- Treasure that washes up on the beach now and then: glinting shells and
-- little chests. Walk over and pick one up for a handful of coins (more the
-- further along you are).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Land = require(ReplicatedStorage.Shared.Land)
local Sea = require(ReplicatedStorage.Shared.Sea)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Notify = require(script.Parent.Parent.Lib.Notify)
local Data = require(script.Parent.Data)
local Progress = require(script.Parent.Progress)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)

local Treasure = {}

Treasure.PICKUP_RANGE = 10 -- a little more than the prompt's, for lag
Treasure.BACK = Land.BEACH_BACK + 4 -- treasure washes up between here...
Treasure.FRONT = -3 -- ...and the water's edge
Treasure.HALF_WIDTH = Config.THROW_ZONE_HALF_WIDTH - 10
Treasure.SPACING = 14
Treasure.THROWS_WORTH = 3 -- a find pays about this many decent throws

local folder: Folder? = nil
local pieces: { [BasePart]: true } = {}
local random = Random.new()

-- Coins a find is worth to this player right now.
function Treasure.reward(profile: Economy.Stats): number
	-- about what a ~150-stud base throw pays, a few times over
	local distance = 150 * Economy.distanceMultiplier(profile, false)
	return math.max(10, Economy.coinsFor(distance, 10, false, profile) * Treasure.THROWS_WORTH)
end

local function findSpot(): Vector3?
	for _ = 1, 40 do
		local x = random:NextNumber(-Treasure.HALF_WIDTH, Treasure.HALF_WIDTH)
		local z = random:NextNumber(Treasure.BACK, Treasure.FRONT)
		local p = Vector3.new(x, 0, z)
		local clear = not Sea.pierAt(p, 3)
		if clear then
			for piece in pieces do
				local q = piece.CFrame.Position
				if Vector3.new(q.X - x, 0, q.Z - z).Magnitude < Treasure.SPACING then
					clear = false
					break
				end
			end
		end
		if clear then
			return Land.at(x, z, 0.35)
		end
	end
	return nil
end

local spawnPiece: () -> ()

local function collect(piece: BasePart, player: Player)
	if not pieces[piece] or not Sessions.getReady(player) then
		return
	end
	local profile = Data.get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not profile or not root or not root:IsA("BasePart") then
		return
	end
	if (root.CFrame.Position - piece.CFrame.Position).Magnitude > Treasure.PICKUP_RANGE then
		return
	end
	pieces[piece] = nil
	piece:Destroy()
	local coins = Treasure.reward(Economy.statsOf(profile))
	profile.coins += coins
	profile.totalCoins += coins
	Notify.send(player, `✨ Treasure! +{Format.short(coins)} coins`, "good")
	Progress.check(player)
	State.markDirty(player)
	task.delay(
		random:NextNumber(Config.TREASURE_RESPAWN_MIN, Config.TREASURE_RESPAWN_MAX),
		spawnPiece
	)
end

function spawnPiece()
	local parent = folder
	if not parent then
		return
	end
	local spot = findSpot()
	if not spot then
		task.delay(10, spawnPiece)
		return
	end
	local chest = random:NextNumber() < 0.3
	local piece = Instance.new("Part")
	piece.Name = "Treasure"
	piece.Size = if chest then Vector3.new(1.6, 1.1, 1.1) else Vector3.new(1, 0.4, 0.9)
	piece.CFrame = CFrame.new(spot) * CFrame.Angles(0, random:NextNumber(0, 2 * math.pi), 0)
	piece.Color = if chest then Color3.fromRGB(176, 120, 64) else Color3.fromRGB(255, 226, 210)
	piece.Material = if chest then Enum.Material.WoodPlanks else Enum.Material.Marble
	piece.Anchored = true
	piece.CanCollide = false
	piece.CanTouch = false
	piece.CastShadow = false
	piece.TopSurface = Enum.SurfaceType.Smooth
	piece.BottomSurface = Enum.SurfaceType.Smooth
	if not chest then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = piece
	end
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "Sparkle"
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 240, 180))
	sparkle.LightEmission = 1
	sparkle.Rate = 5
	sparkle.Lifetime = NumberRange.new(0.6, 1.2)
	sparkle.Speed = NumberRange.new(0.5, 1.5)
	sparkle.SpreadAngle = Vector2.new(40, 40)
	sparkle.EmissionDirection = Enum.NormalId.Top
	sparkle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkle.Parent = piece
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = if chest then "Little chest" else "Glinting shell"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = piece
	prompt.Triggered:Connect(function(player: Player)
		collect(piece, player)
	end)
	pieces[piece] = true
	piece.Parent = parent
end

function Treasure.count(): number
	local n = 0
	for _ in pieces do
		n += 1
	end
	return n
end

function Treasure.list(): { BasePart }
	local list = {}
	for piece in pieces do
		table.insert(list, piece)
	end
	return list
end

-- Testing: wash it all away and bring a fresh lot.
function Treasure.refresh()
	for piece in pieces do
		piece:Destroy()
	end
	table.clear(pieces)
	for _ = 1, Config.TREASURE_COUNT do
		spawnPiece()
	end
end

function Treasure.init()
	local f = Instance.new("Folder")
	f.Name = "Treasure"
	f.Parent = Workspace
	folder = f
end

function Treasure.start()
	for _ = 1, Config.TREASURE_COUNT do
		spawnPiece()
	end
end

return Treasure
