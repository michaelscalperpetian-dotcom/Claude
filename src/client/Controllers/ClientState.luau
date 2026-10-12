--!strict
-- Holds the latest snapshot of this player's state from the server and tells
-- other controllers when it changes. The client never computes anything that
-- matters; it just draws this.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Cycle = require(ReplicatedStorage.Shared.Util.Cycle)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Types = require(ReplicatedStorage.Shared.Types)

local ClientState = {}

ClientState.changed = Signal.new() :: Signal.Signal<Types.Snapshot>

local current: Types.Snapshot? = nil

function ClientState.get(): Types.Snapshot?
	return current
end

-- The player's own plot model (nil until assigned).
function ClientState.myPlot(): Model?
	local snapshot = current
	if not snapshot or snapshot.plotIndex == 0 then
		return nil
	end
	local plots = Workspace:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild("Plot" .. snapshot.plotIndex)
	if plot and plot:IsA("Model") then
		return plot
	end
	return nil
end

function ClientState.isNight(): boolean
	return Cycle.dayNight(Clock.cycleNow()).isNight
end

function ClientState.tutorialActive(): boolean
	local snapshot = current
	return snapshot ~= nil and snapshot.tutorial ~= 99
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
