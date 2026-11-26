--!strict
-- Builds the lake when the server starts: the parts first (instantly), then
-- the terrain valley in the background, nearest the lake first. Players
-- spawn once it's ready (see Lifecycle). It also keeps everyone on dry land:
-- a player who somehow ends up in the water or past the edge of the world
-- is put back by the spawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Lake = require(ReplicatedStorage.Shared.Lake)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Ground = require(script.Parent.Parent.Lib.Ground)
local Scenery = require(script.Parent.Parent.Lib.Scenery)

local World = {}

World.Ready = Signal.new() :: Signal.Signal<()>
World.IN_WATER_BELOW = 1.6 -- a root part this low inside the shore wall is swimming

local built: Scenery.Built? = nil
local ready = false

function World.get(): Scenery.Built
	assert(built, "World not built yet")
	return built
end

function World.isReady(): boolean
	return ready
end

function World.spawnCFrame(): CFrame
	return World.get().spawn.CFrame + Vector3.new(0, 3.5, 0)
end

-- Is a character's root part at `p` in the lake (not on a dock)?
function World.inWater(p: Vector3): boolean
	return Lake.distanceFromCentre(p) < Scenery.SHORE_WALL
		and p.Y < World.IN_WATER_BELOW
		and not Lake.underDock(p, 1)
end

-- Put a character back by the spawn if it's in the water or out of bounds.
function World.rescue(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not root or not root:IsA("BasePart") then
		return false
	end
	local p = root.CFrame.Position
	local far = Lake.distanceFromCentre(p) > Scenery.PLAY_RADIUS + 20 or p.Y < -30
	if not far and not World.inWater(p) then
		return false
	end
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(World.spawnCFrame())
	return true
end

-- Writes the terrain. Yields until done, then lets players in.
function World.buildTerrain()
	Ground.build(Workspace.Terrain)
	ready = true
	World.Ready:fire()
end

function World.init()
	local placeholder = Workspace:FindFirstChild("PressPlay")
	if placeholder then
		placeholder:Destroy()
	end
	built = Scenery.build(Workspace)
end

function World.start()
	task.spawn(World.buildTerrain)
	while true do
		task.wait(1)
		if ready then
			for _, player in Players:GetPlayers() do
				World.rescue(player)
			end
		end
	end
end

return World
