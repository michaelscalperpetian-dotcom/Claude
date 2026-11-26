--!strict
-- Builds the lake when the server starts and keeps everyone on dry land: a
-- player who somehow ends up in the water or past the edge of the world is
-- put back on the beach by the spawn.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Scenery = require(script.Parent.Parent.Lib.Scenery)

local World = {}

World.LOWEST = -4 -- feet below this means they're in the lake

local built: Scenery.Built? = nil

function World.get(): Scenery.Built
	assert(built, "World not built yet")
	return built
end

function World.spawnCFrame(): CFrame
	return World.get().spawn.CFrame + Vector3.new(0, 3.5, 0)
end

-- Put a character back by the spawn if it's in the water or out of bounds.
function World.rescue(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not root or not root:IsA("BasePart") then
		return false
	end
	local p = root.CFrame.Position
	local far = Vector3.new(p.X, 0, p.Z).Magnitude > Scenery.PLAY_RADIUS + 20
	if p.Y >= World.LOWEST and not far then
		return false
	end
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(World.spawnCFrame())
	return true
end

function World.init()
	local placeholder = Workspace:FindFirstChild("PressPlay")
	if placeholder then
		placeholder:Destroy()
	end
	built = Scenery.build(Workspace)
end

function World.start()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			World.rescue(player)
		end
	end
end

return World
