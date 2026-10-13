--!strict
-- Rebirth: once you have enough coins, trade ALL of them (wallet and coin
-- pad) for a permanent +REBIRTH_BONUS coin boost. Dinos, eggs, upgrades and
-- the Dex are kept. Each rebirth costs REBIRTH_COST_GROWTH times the last.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Analytics = require(script.Parent.Analytics)
local Coins = require(script.Parent.Coins)
local Data = require(script.Parent.Data)
local Plots = require(script.Parent.Plots)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)
local Notify = require(script.Parent.Parent.Lib.Notify)

local Rebirth = {}

local function rebirth(player: Player)
	local profile = Data.get(player)
	local session = Sessions.get(player)
	if not profile or not session or not session.ready then
		return
	end
	local cost = Economy.rebirthCost(profile.rebirths)
	if profile.coins < cost then
		Notify.send(player, `You need 💰 {Format.number(cost)} to rebirth.`, "bad")
		return
	end
	if not Coins.spend(player, profile.coins, "Gameplay", "Rebirth") then
		return
	end
	profile.pendingCoins = 0
	profile.rebirths += 1
	Plots.updatePad(player, 0)
	Plots.updateSign(player)
	Coins.setRebirths(player, profile.rebirths)
	State.markDirty(player)
	Analytics.event(player, "Rebirth", profile.rebirths)
	Notify.effect(player, "Reward", {})
	local bonus = math.floor((Economy.rebirthMultiplier(profile.rebirths) - 1) * 100 + 0.5)
	Notify.send(
		player,
		`⭐ REBIRTH {profile.rebirths}! Everything you earn now gets +{bonus}% coins, forever!`,
		"rare"
	)
end

function Rebirth.init()
	Net.on("Rebirth", 0.5, 2, function(player: Player)
		rebirth(player)
	end)
end

return Rebirth
