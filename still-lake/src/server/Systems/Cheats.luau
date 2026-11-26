--!strict
-- The test panel (Studio, the game's owner and Config.DEV_USER_IDS only):
-- every stone, jump to night or day, fresh glints, start over.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local StoneData = require(ReplicatedStorage.Shared.Data.StoneData)
local Access = require(script.Parent.Parent.Lib.Access)
local Notify = require(script.Parent.Parent.Lib.Notify)
local Data = require(script.Parent.Data)
local DayNight = require(script.Parent.DayNight)
local Progress = require(script.Parent.Progress)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)
local Stones = require(script.Parent.Stones)

local Cheats = {}

export type Action = "stones" | "night" | "day" | "glints" | "reset"

local ACTIONS: { [string]: (Player) -> () } = {
	stones = function(player)
		local profile = Data.get(player)
		if not profile then
			return
		end
		for _, stone in StoneData.LIST do
			profile.stones[stone.id] = math.max(profile.stones[stone.id] or 0, 1)
		end
		Progress.check(player)
		Notify.send(player, "Every stone is in your pouch", "good")
	end,
	night = function(player)
		DayNight.setClock(22)
		Notify.send(player, "Night falls on the lake", "info")
	end,
	day = function(player)
		DayNight.setClock(9)
		Notify.send(player, "Good morning, lake", "info")
	end,
	glints = function(player)
		Stones.refreshGlints()
		Notify.send(player, "Fresh glints washed up on the beach", "info")
	end,
	reset = function(player)
		if Data.reset(player) then
			Stones.updateHeld(player)
			Progress.refresh(player)
			Notify.send(player, "Your journal is blank again", "info")
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
