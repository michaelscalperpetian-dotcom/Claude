--!strict
-- Tutorial steps (with onboarding funnel analytics), the Dino-Dex, the 7-day
-- login streak and the Dino Club daily reward.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Config = require(ReplicatedStorage.Shared.Config)
local Cycle = require(ReplicatedStorage.Shared.Util.Cycle)
local DexRewards = require(ReplicatedStorage.Shared.Data.DexRewards)
local DinoData = require(ReplicatedStorage.Shared.Data.DinoData)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Net = require(ReplicatedStorage.Shared.Net)
local Streak = require(ReplicatedStorage.Shared.Util.Streak)
local TutorialData = require(ReplicatedStorage.Shared.Data.TutorialData)
local Types = require(ReplicatedStorage.Shared.Types)
local Analytics = require(script.Parent.Analytics)
local Coins = require(script.Parent.Coins)
local Data = require(script.Parent.Data)
local Nest = require(script.Parent.Nest)
local Rewards = require(script.Parent.Rewards)
local Sessions = require(script.Parent.Sessions)
local State = require(script.Parent.State)
local Notify = require(script.Parent.Parent.Lib.Notify)
local Stats = require(script.Parent.Parent.Lib.Stats)

local Progress = {}

-- ===== Tutorial =====

local function setStep(player: Player, profile: Types.Profile, step: number)
	profile.tutorial = step
	if step == TutorialData.DONE then
		Analytics.funnel(player, #TutorialData.STEPS + 1, "Completed")
	else
		local info = TutorialData.STEPS[step]
		if info then
			Analytics.funnel(player, step, info.funnelName)
		end
	end
	State.markDirty(player)
end

local function hasEggOfKind(profile: Types.Profile, kind: Types.EggKind): boolean
	for _, egg in profile.incubators do
		if egg.kind == kind then
			return true
		end
	end
	return false
end

local function giveStarterEgg(player: Player, profile: Types.Profile)
	local now = Clock.now()
	Nest.placeEgg(player, {
		id = Nest.newId(profile),
		kind = "starter",
		species = TutorialData.STARTER_SPECIES,
		placedAt = now,
		hatchAt = now + Config.STARTER_EGG_SECONDS,
	})
end

local function ensureGift(player: Player, profile: Types.Profile)
	if profile.tutorial ~= 4 or hasEggOfKind(profile, "gift") then
		return
	end
	local now = Clock.now()
	local slot = Nest.placeEgg(player, {
		id = Nest.newId(profile),
		kind = "gift",
		species = TutorialData.GIFT_SPECIES,
		mutation = TutorialData.GIFT_MUTATION,
		placedAt = now,
		hatchAt = now + Config.GIFT_EGG_SECONDS,
	})
	if slot then
		Notify.send(player, "🎁 A shiny Gift Egg appeared in your nest!", "rare")
	end
end

-- Tutorial events: "hatch_starter", "collect", "buy_egg", "hatch_gift", "hatch",
-- "finish".
function Progress.event(player: Player, name: string)
	local profile = Data.get(player)
	if not profile or profile.tutorial == TutorialData.DONE or profile.tutorial == 0 then
		return
	end
	local step = profile.tutorial
	if name == "hatch_starter" and step == 1 then
		setStep(player, profile, 2)
	elseif name == "collect" and step == 2 then
		setStep(player, profile, 3)
	elseif name == "buy_egg" and step >= 1 and step <= 3 then
		setStep(player, profile, 4)
		ensureGift(player, profile)
	elseif name == "hatch_gift" and step == 4 then
		setStep(player, profile, 5)
	elseif name == "hatch" and step == 4 then
		ensureGift(player, profile)
	elseif name == "finish" and step == #TutorialData.STEPS then
		setStep(player, profile, TutorialData.DONE)
		Notify.send(
			player,
			"🎉 You're a real dino keeper now! Come back tomorrow for streak rewards.",
			"good"
		)
	end
end

-- ===== Dino-Dex =====

local function dexCount(profile: Types.Profile): number
	local count = 0
	for _ in profile.dex do
		count += 1
	end
	return count
end

local function recordDex(player: Player, dino: Types.DinoRecord)
	local profile = Data.get(player)
	if not profile then
		return
	end
	local entry = profile.dex[dino.species]
	local isNewSpecies = entry == nil
	if not entry then
		entry = {}
		profile.dex[dino.species] = entry
	end
	local key = dino.mutation or "Normal"
	if dino.golden and not entry.Golden then
		entry.Golden = true
		State.markDirty(player)
	end
	if entry[key] then
		return
	end
	entry[key] = true
	Coins.setDexCount(player, dexCount(profile))
	State.markDirty(player)
	local species = DinoData.get(dino.species)
	if isNewSpecies and species then
		Notify.effect(player, "Dex", { species = dino.species })
	end
end

-- Claim a Dex milestone prize (`count` = how many species it needs).
local function claimDex(player: Player, count: unknown)
	local profile = Data.get(player)
	if not profile or typeof(count) ~= "number" then
		return
	end
	local key = tostring(count)
	if profile.dexClaimed[key] then
		return
	end
	for _, milestone in DexRewards.MILESTONES do
		if milestone.count == count then
			if DexRewards.discovered(profile.dex) < count then
				return
			end
			profile.dexClaimed[key] = true
			local what = Rewards.grant(player, milestone.reward, "Gameplay", "Dex" .. key)
			Notify.send(player, `📖 Dex prize for {count} dinos: {what}!`, "rare")
			Notify.effect(player, "Reward", {})
			Analytics.event(player, "DexPrize" .. key)
			State.markDirty(player)
			return
		end
	end
end

-- ===== Streak + club =====

local function claimStreak(player: Player)
	local profile = Data.get(player)
	if not profile then
		return
	end
	local today = Cycle.dayNumber(Clock.now())
	local canClaim, day = Streak.status(profile.streak, today)
	if not canClaim then
		return
	end
	local reward = Streak.REWARDS[day]
	profile.streak = { count = day, lastDay = today }
	local what = Rewards.grant(player, reward, "TimedReward", "Streak")
	Analytics.event(player, "StreakDay" .. day)
	Notify.send(player, `Day {day} reward: {what}!`, "good")
	Notify.effect(player, "Reward", { day = day })
	State.markDirty(player)
end

local function claimClub(player: Player)
	local profile = Data.get(player)
	local session = Sessions.get(player)
	if not profile or not session or not session.subscribed then
		return
	end
	local today = Cycle.dayNumber(Clock.now())
	if profile.club.lastClaimDay == today then
		return
	end
	profile.club.lastClaimDay = today
	local income = Stats.incomePerSecond(profile, session, Clock.now())
	local amount = Economy.incomeReward(
		income,
		Config.CLUB_DAILY_COINS.minutes,
		Config.CLUB_DAILY_COINS.minimum
	)
	Coins.add(player, amount, "TimedReward", "DinoClub")
	Notify.send(player, `🦖 Dino Club daily gift: {amount} coins!`, "good")
	State.markDirty(player)
end

-- Called by Lifecycle once the player's nest is ready.
function Progress.onJoin(player: Player)
	local profile = Data.get(player)
	if not profile then
		return
	end
	Coins.setDexCount(player, dexCount(profile))
	if profile.tutorial > #TutorialData.STEPS and profile.tutorial ~= TutorialData.DONE then
		-- Saved during an older, longer tutorial: resume on the last step.
		setStep(player, profile, #TutorialData.STEPS)
	end
	if profile.tutorial == 0 then
		giveStarterEgg(player, profile)
		setStep(player, profile, 1)
	elseif
		profile.tutorial == 1
		and not hasEggOfKind(profile, "starter")
		and #profile.dinos == 0
	then
		giveStarterEgg(player, profile)
	elseif profile.tutorial == 4 then
		ensureGift(player, profile)
	end
	local canClaim = Streak.status(profile.streak, Cycle.dayNumber(Clock.now()))
	if canClaim and profile.tutorial == TutorialData.DONE then
		Notify.send(player, "🎁 Your daily streak reward is ready!", "good")
	end
end

function Progress.init()
	Nest.DinoChanged:connect(recordDex)
	Net.on("ClaimDex", 2, 4, claimDex)
	Net.on("ClaimStreak", 1, 2, function(player: Player)
		claimStreak(player)
	end)
	Net.on("ClaimClub", 1, 2, function(player: Player)
		claimClub(player)
	end)
	Net.on("TutorialAction", 2, 4, function(player: Player, action: unknown)
		if action == "Finish" then
			Progress.event(player, "finish")
		end
	end)
end

return Progress
