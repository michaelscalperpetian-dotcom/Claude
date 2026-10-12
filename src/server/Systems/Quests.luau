--!strict
-- Daily quests: progress from gameplay events, claim each quest's reward,
-- and a bonus for finishing all of today's quests. Quests reset at UTC
-- midnight (the same time as the login streak).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Cycle = require(ReplicatedStorage.Shared.Util.Cycle)
local Net = require(ReplicatedStorage.Shared.Net)
local QuestData = require(ReplicatedStorage.Shared.Data.QuestData)
local TutorialData = require(ReplicatedStorage.Shared.Data.TutorialData)
local Types = require(ReplicatedStorage.Shared.Types)
local Analytics = require(script.Parent.Analytics)
local Data = require(script.Parent.Data)
local Rewards = require(script.Parent.Rewards)
local State = require(script.Parent.State)
local Notify = require(script.Parent.Parent.Lib.Notify)

local Quests = {}

-- Today's quest state, reset if the day has changed.
local function today(profile: Types.Profile): Types.QuestState
	local day = Cycle.dayNumber(Clock.now())
	if profile.quests.day ~= day then
		profile.quests = { day = day, progress = {}, claimed = {}, bonusClaimed = false }
	end
	return profile.quests
end

-- Advance every quest of today that listens to `event`.
function Quests.track(player: Player, event: string, amount: number?)
	local profile = Data.get(player)
	if not profile or profile.tutorial ~= TutorialData.DONE then
		return
	end
	local state = today(profile)
	local changed = false
	for _, quest in QuestData.forDay(state.day) do
		if quest.event == event then
			local before = state.progress[quest.id] or 0
			if before < quest.goal then
				local after = math.min(quest.goal, before + (amount or 1))
				state.progress[quest.id] = after
				changed = true
				if after >= quest.goal then
					Notify.send(player, `📜 Quest done: {quest.text}! Claim your prize.`, "good")
				end
			end
		end
	end
	if changed then
		State.markDirty(player)
	end
end

local function allClaimed(state: Types.QuestState): boolean
	for _, quest in QuestData.forDay(state.day) do
		if not state.claimed[quest.id] then
			return false
		end
	end
	return true
end

local function claim(player: Player, questId: unknown)
	local profile = Data.get(player)
	if not profile or typeof(questId) ~= "string" then
		return
	end
	local state = today(profile)
	if questId == "bonus" then
		if state.bonusClaimed or not allClaimed(state) then
			return
		end
		state.bonusClaimed = true
		local what = Rewards.grant(player, QuestData.ALL_DONE_REWARD, "Gameplay", "QuestBonus")
		Notify.send(player, `🏆 All quests done! Bonus: {what}`, "rare")
		Notify.effect(player, "Reward", {})
		Analytics.event(player, "QuestBonus")
		State.markDirty(player)
		return
	end
	local quest = QuestData.get(questId)
	if not quest or state.claimed[quest.id] or (state.progress[quest.id] or 0) < quest.goal then
		return
	end
	-- only today's quests can be claimed
	local isToday = false
	for _, q in QuestData.forDay(state.day) do
		if q.id == quest.id then
			isToday = true
		end
	end
	if not isToday then
		return
	end
	state.claimed[quest.id] = true
	local what = Rewards.grant(player, quest.reward, "Gameplay", "Quest_" .. quest.id)
	Notify.send(player, `📜 Quest reward: {what}!`, "good")
	Notify.effect(player, "Reward", {})
	Analytics.event(player, "QuestClaim_" .. quest.id)
	State.markDirty(player)
end

-- Make sure the snapshot shows today's quests even before any progress.
function Quests.refresh(player: Player)
	local profile = Data.get(player)
	if profile then
		today(profile)
	end
end

function Quests.init()
	Net.on("ClaimQuest", 2, 4, claim)
end

function Quests.start()
	-- roll quests over at midnight for everyone online
	local lastDay = Cycle.dayNumber(Clock.now())
	while true do
		task.wait(5)
		local day = Cycle.dayNumber(Clock.now())
		if day ~= lastDay then
			lastDay = day
			for _, player in Players:GetPlayers() do
				local profile = Data.get(player)
				if profile then
					today(profile)
					State.markDirty(player)
				end
			end
		end
	end
end

return Quests
