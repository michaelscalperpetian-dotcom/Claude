--!strict
-- The test panel (Studio, the game's owner and Config.DEV_USER_IDS only):
-- coins, strength, every rock and island, night or day, fresh treasure,
-- start over.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
local IslandData = require(ReplicatedStorage.Shared.Data.IslandData)
local Net = require(ReplicatedStorage.Shared.Net)
local RockData = require(ReplicatedStorage.Shared.Data.RockData)
local Access = require(script.Parent.Parent.Lib.Access)
local Notify = require(script.Parent.Parent.Lib.Notify)
local Data = require(script.Parent.Data)
local DayNight = require(script.Parent.DayNight)
local Progress = require(script.Parent.Progress)
local Sessions = require(script.Parent.Sessions)
local Shop = require(script.Parent.Shop)
local State = require(script.Parent.State)
local Treasure = require(script.Parent.Treasure)

local Cheats = {}

local ACTIONS: { [string]: (Player) -> () } = {
	coins = function(player)
		local profile = Data.get(player)
		if profile then
			-- enough for the next rebirth, or a big handful early on
			local amount = math.max(Economy.rebirthCost(profile.rebirths), 100000)
			profile.coins += amount
			profile.totalCoins += amount
			Progress.check(player)
			Notify.send(player, "💰 Coins added", "good")
		end
	end,
	strength = function(player)
		local profile = Data.get(player)
		if profile then
			profile.strength = math.min(profile.strength + 10, Economy.MAX_STRENGTH)
			Notify.send(player, "💪 +10 strength", "good")
		end
	end,
	everything = function(player)
		local profile = Data.get(player)
		if not profile then
			return
		end
		for _, rock in RockData.LIST do
			profile.rocks[rock.id] = true
		end
		for _, island in IslandData.LIST do
			profile.islands[island.id] = true
		end
		Progress.check(player)
		Notify.send(player, "Every rock and island unlocked", "good")
	end,
	night = function(player)
		DayNight.setClock(22)
		Notify.send(player, "Night falls over the sea", "info")
	end,
	day = function(player)
		DayNight.setClock(10)
		Notify.send(player, "Good morning, sea", "info")
	end,
	treasure = function(player)
		Treasure.refresh()
		Notify.send(player, "Fresh treasure washed up", "info")
	end,
	reset = function(player)
		if Data.reset(player) then
			Shop.updateHeld(player)
			Progress.refresh(player)
			Notify.send(player, "Back to a single Pebble", "info")
		end
	end,
}

function Cheats.run(player: Player, action: unknown): boolean
	if type(action) ~= "string" or not Access.isDev(player) or not Sessions.getReady(player) then
		return false
	end
	local run = ACTIONS[action]
	if not run then
		return false
	end
	run(player)
	State.markDirty(player)
	return true
end

function Cheats.init()
	Net.on("Dev", 2, 4, function(player: Player, action: unknown)
		Cheats.run(player, action)
	end)
end

return Cheats
