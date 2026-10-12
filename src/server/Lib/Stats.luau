--!strict
-- Derived numbers every system agrees on: slots, multipliers, income, boosts.
-- Reads profile + session; never mutates anything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DinoData = require(ReplicatedStorage.Shared.Data.DinoData)
local MutationData = require(ReplicatedStorage.Shared.Data.MutationData)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Growth = require(ReplicatedStorage.Shared.Util.Growth)
local Types = require(ReplicatedStorage.Shared.Types)
local Sessions = require(script.Parent.Parent.Systems.Sessions)

type Profile = Types.Profile
type Session = Sessions.Session

local Stats = {}

function Stats.hasPass(session: Session, key: string): boolean
	return session.passes[key] == true or session.fakePasses[key] == true
end

function Stats.maxSlots(profile: Profile, session: Session): number
	local extra = if Stats.hasPass(session, "ExtraSlots") then Config.PASS_EXTRA_SLOTS else 0
	return Config.BASE_DINO_SLOTS + profile.upgrades.slots + extra
end

function Stats.maxIncubators(profile: Profile): number
	return math.min(Config.BASE_INCUBATORS + profile.upgrades.incubators, Config.MAX_INCUBATORS)
end

function Stats.friendsHere(session: Session): number
	local count = 0
	for userId in session.friendIds do
		if Players:GetPlayerByUserId(userId) then
			count += 1
		end
	end
	return count
end

function Stats.multiplier(profile: Profile, session: Session, now: number): number
	return Economy.coinMultiplier({
		doubleCoins = Stats.hasPass(session, "DoubleCoins"),
		vip = Stats.hasPass(session, "VIP"),
		club = session.subscribed,
		adBoost = profile.boosts.coinsUntil > now,
		friends = Stats.friendsHere(session),
	})
end

function Stats.dinoStage(dino: Types.DinoRecord, now: number): number
	local species = DinoData.get(dino.species)
	if not species then
		return 1
	end
	return Growth.stageIndex(now - dino.bornAt, species.growth)
end

-- Base coins/second for one dino (before player multipliers).
function Stats.dinoIncome(dino: Types.DinoRecord, now: number): number
	local species = DinoData.get(dino.species)
	if not species then
		return 0
	end
	local stage = Growth.stageIndex(now - dino.bornAt, species.growth)
	return Growth.income(species.income, stage, MutationData.multiplier(dino.mutation))
end

function Stats.incomePerSecond(profile: Profile, session: Session, now: number): number
	local total = 0
	for _, dino in profile.dinos do
		total += Stats.dinoIncome(dino, now)
	end
	return total * Stats.multiplier(profile, session, now)
end

function Stats.luckActive(profile: Profile, now: number): boolean
	return profile.boosts.luckUntil > now
end

function Stats.shieldUntil(profile: Profile): number
	return profile.firstJoin + Config.NEW_PLAYER_SHIELD_SECONDS
end

function Stats.hatchSpeed(session: Session): number
	return if Stats.hasPass(session, "FastHatch") then Config.FAST_HATCH_MULTIPLIER else 1
end

function Stats.raidsEnabled(): boolean
	if Config.RAIDS_IN_PRIVATE_SERVERS then
		return true
	end
	return game.PrivateServerId == ""
end

function Stats.isDev(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return table.find(Config.DEV_USER_IDS, player.UserId) ~= nil
end

return Stats
