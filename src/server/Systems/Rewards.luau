--!strict
-- Grants a reward (coins scaled to the player's income, a boost, or a dino).
-- Shared by the login streak, daily quests, Dex milestones and codes so they
-- all pay out the same way.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Streak = require(ReplicatedStorage.Shared.Util.Streak)
local Analytics = require(script.Parent.Analytics)
local Coins = require(script.Parent.Coins)
local Data = require(script.Parent.Data)
local Nest = require(script.Parent.Nest)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)
local Stats = require(script.Parent.Parent.Lib.Stats)

local Rewards = {}

-- Coins a coin reward is worth right now (it grows with the player's income).
function Rewards.coinAmount(player: Player, reward: Streak.Reward): number
	local profile = Data.get(player)
	local session = Sessions.get(player)
	if not profile or not session then
		return reward.minimum or 0
	end
	local income = Stats.incomePerSecond(profile, session, Clock.now())
	return Economy.incomeReward(income, reward.minutes or 10, reward.minimum or 100)
end

-- Gives the reward and returns a short description for a message.
function Rewards.grant(
	player: Player,
	reward: Streak.Reward,
	transaction: Analytics.Transaction,
	sku: string
): string
	local profile = Data.get(player)
	if not profile then
		return "a reward"
	end
	local now = Clock.now()
	local what = "a reward"
	if reward.kind == "coins" then
		local amount = Coins.add(player, Rewards.coinAmount(player, reward), transaction, sku)
		what = `💰 {Format.number(amount)} coins`
	elseif reward.kind == "luck" then
		profile.boosts.luckUntil = math.max(profile.boosts.luckUntil, now) + (reward.seconds or 900)
		what = `🍀 {Format.duration(reward.seconds or 900)} of Luck`
	elseif reward.kind == "coinBoost" then
		profile.boosts.coinsUntil = math.max(profile.boosts.coinsUntil, now)
			+ (reward.seconds or 1800)
		what = `⚡ {Format.duration(reward.seconds or 1800)} of 2x Coins`
	elseif reward.kind == "dino" and reward.species then
		if Nest.addDino(player, reward.species) then
			what = "🦕 a new baby dino"
		else
			local amount = Coins.add(player, 25000, transaction, sku .. "Fallback")
			what = `💰 {Format.number(amount)} coins (your nest was full)`
		end
	end
	State.markDirty(player)
	return what
end

return Rewards
