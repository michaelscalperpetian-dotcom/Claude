--!strict
-- Promo codes typed into the Settings window. Codes live server-side
-- (Lib/CodeData); each one works once per player.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Net = require(ReplicatedStorage.Shared.Net)
local Analytics = require(script.Parent.Analytics)
local Data = require(script.Parent.Data)
local Rewards = require(script.Parent.Rewards)
local State = require(script.Parent.State)
local CodeData = require(script.Parent.Parent.Lib.CodeData)
local Notify = require(script.Parent.Parent.Lib.Notify)

local Codes = {}

local MAX_LENGTH = 24

function Codes.normalize(text: string): string
	return (string.upper(text):gsub("[^%w]", ""))
end

function Codes.redeem(player: Player, raw: unknown)
	local profile = Data.get(player)
	if not profile or typeof(raw) ~= "string" or #raw > MAX_LENGTH * 2 then
		return
	end
	local code = Codes.normalize(raw)
	if code == "" or #code > MAX_LENGTH then
		Notify.send(player, "Type a code first!", "bad")
		return
	end
	local entry = CodeData[code]
	if not entry or (entry.expires and Clock.now() > entry.expires) then
		Notify.send(player, "Hmm, that code doesn't work. Check the spelling!", "bad")
		return
	end
	if profile.codes[code] then
		Notify.send(player, "You already used that code!", "info")
		return
	end
	profile.codes[code] = true
	local what = Rewards.grant(player, entry.reward, "Gameplay", "Code_" .. code)
	Notify.send(player, `🎟 Code redeemed: {what}!`, "good")
	Notify.effect(player, "Reward", {})
	Analytics.event(player, "Code_" .. code)
	State.markDirty(player)
end

function Codes.init()
	-- slow on purpose: nobody needs to guess codes quickly
	Net.on("RedeemCode", 0.5, 3, Codes.redeem)
end

return Codes
