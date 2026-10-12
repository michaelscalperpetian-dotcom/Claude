--!strict
-- Permanent nest upgrades bought with coins (the long-term coin sink):
-- more dino slots and more incubators.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Net = require(ReplicatedStorage.Shared.Net)
local Coins = require(script.Parent.Coins)
local Data = require(script.Parent.Data)
local Plots = require(script.Parent.Plots)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)
local Notify = require(script.Parent.Parent.Lib.Notify)

local Upgrades = {}

local function buy(player: Player, kind: unknown)
	local profile = Data.get(player)
	local session = Sessions.get(player)
	if not profile or not session or not session.ready then
		return
	end
	if kind == "slots" then
		local cost = Economy.nextUpgradeCost(Config.SLOT_UPGRADE_COSTS, profile.upgrades.slots)
		if not cost then
			return
		end
		if not Coins.spend(player, cost, "Shop", "SlotUpgrade") then
			Notify.send(player, "Not enough coins yet!", "bad")
			return
		end
		profile.upgrades.slots += 1
		Notify.send(player, "🦖 Your nest has room for another dino!", "good")
	elseif kind == "incubators" then
		local cost =
			Economy.nextUpgradeCost(Config.INCUBATOR_UPGRADE_COSTS, profile.upgrades.incubators)
		if not cost then
			return
		end
		if not Coins.spend(player, cost, "Shop", "IncubatorUpgrade") then
			Notify.send(player, "Not enough coins yet!", "bad")
			return
		end
		profile.upgrades.incubators += 1
		Plots.syncIncubators(player)
		Notify.send(player, "🥚 New incubator unlocked!", "good")
	else
		return
	end
	State.markDirty(player)
end

function Upgrades.init()
	Net.on("BuyUpgrade", 2, 3, buy)
end

return Upgrades
