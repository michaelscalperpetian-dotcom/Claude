--!strict
-- QA commands for testing in Studio (everyone) or live servers (only UserIds in
-- Config.DEV_USER_IDS). The gate is checked here on the server for every
-- command; hiding the panel on the client is just cosmetic. Commands go
-- through the same system APIs real gameplay uses.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Config = require(ReplicatedStorage.Shared.Config)
local Cycle = require(ReplicatedStorage.Shared.Util.Cycle)
local DinoData = require(ReplicatedStorage.Shared.Data.DinoData)
local Growth = require(ReplicatedStorage.Shared.Util.Growth)
local Net = require(ReplicatedStorage.Shared.Net)
local Coins = require(script.Parent.Coins)
local Data = require(script.Parent.Data)
local Monetization = require(script.Parent.Monetization)
local Nest = require(script.Parent.Nest)
local Plots = require(script.Parent.Plots)
local Progress = require(script.Parent.Progress)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)
local Notify = require(script.Parent.Parent.Lib.Notify)
local Stats = require(script.Parent.Parent.Lib.Stats)

local Cheats = {}

local function offset(): number
	local value = ReplicatedStorage:GetAttribute(Clock.OFFSET_ATTRIBUTE)
	return if typeof(value) == "number" then value else 0
end

local function shiftCycle(seconds: number)
	ReplicatedStorage:SetAttribute(Clock.OFFSET_ATTRIBUTE, offset() + seconds)
end

local commands: { [string]: (Player, string?) -> string } = {
	coins = function(player)
		Coins.add(player, 1000000, "Gameplay", "Cheat")
		return "+1M coins"
	end,
	grow = function(player)
		local profile = Data.get(player)
		if not profile then
			return "no profile"
		end
		local now = Clock.now()
		for _, dino in profile.dinos do
			local species = DinoData.get(dino.species)
			if species then
				local stage = Growth.stageIndex(now - dino.bornAt, species.growth)
				dino.bornAt = Growth.bornAtForStage(now, math.min(stage + 1, 4), species.growth)
			end
		end
		Plots.syncDinos(player)
		State.markDirty(player)
		return "dinos grew one stage"
	end,
	hatch = function(player)
		local profile = Data.get(player)
		if not profile then
			return "no profile"
		end
		local now = Clock.now()
		for slot in profile.incubators do
			Nest.setHatchAt(player, slot, now)
		end
		return "all eggs ready"
	end,
	lay = function(player)
		local profile = Data.get(player)
		if not profile then
			return "no profile"
		end
		for _, dino in profile.dinos do
			Nest.addTrayEgg(player, dino.species)
		end
		return "laid eggs"
	end,
	night = function()
		local dn = Cycle.dayNight(Clock.cycleNow())
		if not dn.isNight then
			shiftCycle(dn.secondsLeft + 0.5)
		end
		return "it's night"
	end,
	day = function()
		local dn = Cycle.dayNight(Clock.cycleNow())
		if dn.isNight then
			shiftCycle(dn.secondsLeft + 0.5)
		end
		return "it's day"
	end,
	storm = function()
		local storm = Cycle.storm(Clock.cycleNow())
		if not storm.active then
			shiftCycle(storm.secondsLeft + 0.5)
		end
		return "storm started"
	end,
	mega = function()
		local active, seconds = Cycle.megaStorm(Clock.cycleNow())
		if not active then
			shiftCycle(seconds + 0.5)
		end
		return "mega storm started"
	end,
	resettime = function()
		ReplicatedStorage:SetAttribute(Clock.OFFSET_ATTRIBUTE, 0)
		return "clock back to normal"
	end,
	luck = function(player)
		local profile = Data.get(player)
		if profile then
			profile.boosts.luckUntil = Clock.now() + 900
			State.markDirty(player)
		end
		return "luck for 15 min"
	end,
	pass = function(player, arg)
		if not arg then
			return "which pass?"
		end
		Monetization.toggleFakePass(player, arg)
		local session = Sessions.get(player)
		local on = session ~= nil and session.fakePasses[arg] == true
		return `pass {arg} {if on then "ON" else "OFF"}`
	end,
	trex = function(player)
		return if Nest.addDino(player, "TRex", nil, Growth.ADULT)
			then "adult T-Rex added"
			else "nest full"
	end,
	noshield = function(player)
		local profile = Data.get(player)
		if profile then
			profile.firstJoin = Clock.now() - Config.NEW_PLAYER_SHIELD_SECONDS - 60
			Plots.updateSign(player)
			State.markDirty(player)
		end
		return "new-player shield removed (your nest can be raided now)"
	end,
	skiptutorial = function(player)
		local profile = Data.get(player)
		if profile then
			profile.tutorial = 99
			State.markDirty(player)
		end
		return "tutorial skipped"
	end,
	reset = function(player)
		local profile = Data.reset(player)
		if not profile then
			return "no profile"
		end
		Plots.renderAll(player)
		Progress.onJoin(player)
		State.markDirty(player)
		return "profile reset"
	end,
}

function Cheats.init()
	Net.on("Cheat", 4, 6, function(player: Player, command: unknown, arg: unknown)
		if not Stats.isDev(player) then
			return
		end
		if typeof(command) ~= "string" then
			return
		end
		local fn = commands[command]
		if not fn then
			return
		end
		local result = fn(player, if typeof(arg) == "string" then arg else nil)
		Notify.send(player, "🛠 " .. result, "info")
	end)
end

return Cheats
