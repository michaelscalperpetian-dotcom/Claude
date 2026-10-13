--!strict
-- Player settings (music / sound effects) and the buddy dino that follows
-- the player around. The buddy is shown to everyone through a "Buddy"
-- attribute on the Player ("species|mutation|stage"); every client animates it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local DinoData = require(ReplicatedStorage.Shared.Data.DinoData)
local Growth = require(ReplicatedStorage.Shared.Util.Growth)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local Data = require(script.Parent.Data)
local Nest = require(script.Parent.Nest)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)
local Notify = require(script.Parent.Parent.Lib.Notify)

local Preferences = {}

Preferences.BUDDY_ATTRIBUTE = "Buddy"

local SETTINGS = { music = true, sfx = true }

local function findDino(profile: Types.Profile, id: string): Types.DinoRecord?
	for _, dino in profile.dinos do
		if dino.id == id then
			return dino
		end
	end
	return nil
end

-- What other clients need to draw the buddy, or nil for no buddy.
function Preferences.buddyLook(profile: Types.Profile): string?
	local id = profile.buddy
	local dino = id and findDino(profile, id)
	local species = dino and DinoData.get(dino.species)
	if not dino or not species then
		return nil
	end
	local stage = Growth.progress(Clock.now() - dino.bornAt, species.growth)
	return `{dino.species}|{dino.mutation or ""}|{stage}|{if dino.golden then "g" else ""}`
end

function Preferences.syncBuddy(player: Player)
	local profile = Data.get(player)
	if not profile then
		return
	end
	if profile.buddy and not findDino(profile, profile.buddy) then
		profile.buddy = nil -- sold or gone
		State.markDirty(player)
	end
	local look = Preferences.buddyLook(profile)
	if player:GetAttribute(Preferences.BUDDY_ATTRIBUTE) ~= look then
		player:SetAttribute(Preferences.BUDDY_ATTRIBUTE, look)
	end
end

local function setBuddy(player: Player, id: unknown)
	local profile = Data.get(player)
	if not profile then
		return
	end
	if id == nil then
		profile.buddy = nil
	elseif typeof(id) == "string" and findDino(profile, id) then
		profile.buddy = id
		local dino = findDino(profile, id) :: Types.DinoRecord
		local species = DinoData.get(dino.species)
		Notify.send(
			player,
			`💗 Your {if species then species.name else "dino"} will follow you around!`,
			"good"
		)
	else
		return
	end
	Preferences.syncBuddy(player)
	State.markDirty(player)
end

local function setSetting(player: Player, key: unknown, value: unknown)
	local profile = Data.get(player)
	if
		not profile
		or typeof(key) ~= "string"
		or not SETTINGS[key]
		or typeof(value) ~= "boolean"
	then
		return
	end
	(profile.settings :: any)[key] = value
	State.markDirty(player)
end

function Preferences.init()
	Net.on("SetBuddy", 2, 4, setBuddy)
	Net.on("SetSetting", 4, 8, setSetting)
	Nest.DinoChanged:connect(function(player: Player)
		Preferences.syncBuddy(player)
	end)
	Nest.DinoRemoved:connect(function(player: Player)
		Preferences.syncBuddy(player)
	end)
end

function Preferences.start()
	-- the buddy grows up with the dino
	while true do
		task.wait(10)
		for _, session in Sessions.ready() do
			Preferences.syncBuddy(session.player)
		end
	end
end

return Preferences
