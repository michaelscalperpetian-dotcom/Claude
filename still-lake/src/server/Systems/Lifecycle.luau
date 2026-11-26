--!strict
-- Join and leave, in the right order:
--   join:  session -> load the save -> ready (leaderstats, title, held stone)
--   leave: everyone else forgets the player -> final save + release the lock

local Players = game:GetService("Players")

local Data = require(script.Parent.Data)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)

local Lifecycle = {}

local function onJoin(player: Player)
	local session = Sessions.create(player)
	local profile = Data.load(player)
	if player.Parent == nil or Sessions.get(player) ~= session then
		-- left while loading
		Data.release(player)
		Sessions.remove(player)
		return
	end
	if not profile then
		Sessions.remove(player)
		player:Kick("We couldn't load your stones right now. Please rejoin in a moment!")
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

function Lifecycle.start()
	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(onLeave)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
end

return Lifecycle
