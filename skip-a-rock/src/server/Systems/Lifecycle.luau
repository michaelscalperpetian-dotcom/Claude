--!strict
-- Join and leave, in the right order:
--   join:  session -> load the save -> wait for the terrain -> spawn ->
--          ready (leaderstats, title, held stone)
--   leave: everyone else forgets the player -> final save + release the lock
-- Characters are spawned here (not automatically), so nobody drops into the
-- valley before its ground exists, and respawned a moment after falling.

local Players = game:GetService("Players")

local Data = require(script.Parent.Data)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)
local World = require(script.Parent.World)

local Lifecycle = {}

Lifecycle.RESPAWN_SECONDS = 3

local function spawn(player: Player)
	local ok, err = pcall(function()
		player:LoadCharacterAsync()
	end)
	if not ok then
		warn(`[Lifecycle] couldn't spawn {player.Name}: {err}`)
	end
end

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.Died:Connect(function()
		task.delay(Lifecycle.RESPAWN_SECONDS, function()
			if player.Parent ~= nil and Sessions.get(player) and player.Character == character then
				spawn(player)
			end
		end)
	end)
end

local function onJoin(player: Player)
	local session = Sessions.create(player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	local profile = Data.load(player)
	local function left(): boolean
		return player.Parent == nil or Sessions.get(player) ~= session
	end
	if left() then
		Data.release(player)
		Sessions.remove(player)
		return
	end
	if not profile then
		Sessions.remove(player)
		player:Kick("We couldn't load your stones right now. Please rejoin in a moment!")
		return
	end
	while not World.isReady() and not left() do
		task.wait(0.2)
	end
	if left() then
		return
	end
	spawn(player)
	if left() then
		return
	end
	session.ready = true
	Sessions.Ready:fire(player)
	State.markDirty(player)
end

local function onLeave(player: Player)
	local session = Sessions.get(player)
	if not session then
		return
	end
	local wasReady = session.ready
	session.ready = false
	if wasReady then
		Sessions.Leaving:fire(player)
	end
	Data.release(player)
	Sessions.remove(player)
end

function Lifecycle.init()
	Players.CharacterAutoLoads = false
end

function Lifecycle.start()
	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(onLeave)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
end

return Lifecycle
