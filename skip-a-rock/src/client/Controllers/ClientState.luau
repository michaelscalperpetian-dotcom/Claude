--!strict
-- The latest snapshot of this player's progress from the server, and
-- signals other controllers listen to. The client never decides anything
-- that matters; it just draws this.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DayCycle = require(ReplicatedStorage.Shared.DayCycle)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Types = require(ReplicatedStorage.Shared.Types)

local ClientState = {}

ClientState.changed = Signal.new() :: Signal.Signal<Types.Snapshot>
-- One of this player's own stones has finished skipping (fired by StoneFx).
ClientState.landed = Signal.new() :: Signal.Signal<Types.ThrowEvent>

local current: Types.Snapshot? = nil

function ClientState.get(): Types.Snapshot?
	return current
end

function ClientState.isNight(): boolean
	return DayCycle.isNightAt(Lighting.ClockTime)
end

function ClientState.localPlayer(): Player
	return Players.LocalPlayer
end

function ClientState.init()
	Net.listen("State", function(snapshot: Types.Snapshot)
		current = snapshot
		ClientState.changed:fire(snapshot)
	end)
end

function ClientState.start()
	Net.send("Ready")
end

return ClientState
