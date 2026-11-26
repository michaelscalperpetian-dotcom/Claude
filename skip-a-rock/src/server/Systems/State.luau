--!strict
-- Sends each player a snapshot of their own progress whenever it changes
-- (batched, at most 5 times a second), plus a full one when their client says
-- it's ready. Clients only draw it; the server decides everything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GoalData = require(ReplicatedStorage.Shared.Data.GoalData)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local Access = require(script.Parent.Parent.Lib.Access)
local Data = require(script.Parent.Data)
local Sessions = require(script.Parent.Sessions)

local State = {}

local dirty: { [Player]: boolean } = {}
local clientReady: { [Player]: boolean } = {}

function State.markDirty(player: Player)
	dirty[player] = true
end

function State.snapshot(player: Player): Types.Snapshot?
	local profile = Data.get(player)
	if not profile or not Sessions.getReady(player) then
		return nil
	end
	local stats = Economy.statsOf(profile)
	return {
		coins = profile.coins,
		totalCoins = profile.totalCoins,
		strength = profile.strength,
		rocks = profile.rocks,
		equipped = profile.equipped,
		rebirths = profile.rebirths,
		islands = profile.islands,
		bestDistance = profile.bestDistance,
		bestSkips = profile.bestSkips,
		throws = profile.throws,
		totalSkips = profile.totalSkips,
		perfects = profile.perfects,
		goals = profile.goals,
		coinMultiplier = Economy.coinMultiplier(stats),
		distanceMultiplier = Economy.distanceMultiplier(stats, false),
		strengthCost = Economy.strengthCost(profile.strength),
		rebirthCost = Economy.rebirthCost(profile.rebirths),
		title = GoalData.title(profile.bestDistance),
		isDev = Access.isDev(player),
	}
end

local function send(player: Player)
	local snapshot = State.snapshot(player)
	if snapshot then
		Net.fire(player, "State", snapshot)
	end
end

function State.init()
	Net.on("Ready", 1, 3, function(player: Player)
		clientReady[player] = true
		send(player)
	end)
	-- The client may say it's ready before its profile finishes loading.
	Sessions.Ready:connect(function(player: Player)
		if clientReady[player] then
			send(player)
		end
	end)
	local function forget(player: Player)
		dirty[player] = nil
		clientReady[player] = nil
	end
	Sessions.Leaving:connect(forget)
	-- players kicked while joining never fire Leaving
	Players.PlayerRemoving:Connect(forget)
end

function State.start()
	while true do
		task.wait(0.2)
		for player in dirty do
			dirty[player] = nil
			if clientReady[player] and player.Parent ~= nil then
				send(player)
			end
		end
	end
end

return State
