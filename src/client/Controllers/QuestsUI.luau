--!strict
-- Daily quests window: today's three quests with progress bars and prizes,
-- plus a bonus for finishing them all. The menu button shows a badge when
-- something is ready to claim.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Cycle = require(ReplicatedStorage.Shared.Util.Cycle)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local QuestData = require(ReplicatedStorage.Shared.Data.QuestData)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientState = require(script.Parent.ClientState)
local Hud = require(script.Parent.Hud)
local Panels = require(script.Parent.Parent.Lib.Panels)
local UI = require(script.Parent.Parent.Lib.UI)

local QuestsUI = {}

type Row = {
	frame: Frame,
	icon: TextLabel,
	title: TextLabel,
	bar: UI.Bar,
	reward: TextLabel,
	button: UI.Button,
	questId: string?,
}

local rows: { Row } = {}
local resetChip: UI.Chip
local bonusButton: UI.Button
local bonusLabel: TextLabel

type Status = { quest: QuestData.Quest, progress: number, claimed: boolean }

-- Today's quests with this player's progress.
local function statuses(snapshot: Types.Snapshot): ({ Status }, boolean)
	local day = Cycle.dayNumber(Clock.now())
	local state = snapshot.quests
	local current = state.day == day
	local list: { Status } = {}
	for _, quest in QuestData.forDay(day) do
		table.insert(list, {
			quest = quest,
			progress = if current then state.progress[quest.id] or 0 else 0,
			claimed = current and state.claimed[quest.id] == true,
		})
	end
	return list, current and state.bonusClaimed
end

-- Is anything ready to claim? (drives the menu badge)
function QuestsUI.claimable(snapshot: Types.Snapshot): boolean
	if snapshot.tutorial ~= 99 then
		return false
	end
	local list, bonusClaimed = statuses(snapshot)
	local allClaimed = true
	for _, status in list do
		if not status.claimed then
			allClaimed = false
			if status.progress >= status.quest.goal then
				return true
			end
		end
	end
	return allClaimed and not bonusClaimed
end

local function refresh(snapshot: Types.Snapshot)
	local list, bonusClaimed = statuses(snapshot)
	local allClaimed = true
	for i, row in rows do
		local status = list[i]
		row.frame.Visible = status ~= nil
		if status then
			local quest = status.quest
			row.questId = quest.id
			row.icon.Text = quest.emoji
			row.title.Text = quest.text
			row.reward.Text = `{quest.reward.emoji} {quest.reward.label}`
			UI.setBar(row.bar, status.progress / quest.goal, `{status.progress} / {quest.goal}`)
			if status.claimed then
				UI.setButton(row.button, { text = "Done ✓", enabled = false })
			elseif status.progress >= quest.goal then
				UI.setButton(row.button, { text = "Claim!", enabled = true })
			else
				UI.setButton(row.button, { text = "Go!", enabled = false })
				allClaimed = false
			end
			if not status.claimed then
				allClaimed = false
			end
		end
	end
	local bonus = QuestData.ALL_DONE_REWARD
	bonusLabel.Text = `🏆 Finish all of today's quests: {bonus.emoji} {bonus.label}`
	if bonusClaimed then
		UI.setButton(bonusButton, { text = "Done ✓", enabled = false })
	else
		UI.setButton(
			bonusButton,
			{ text = if allClaimed then "Claim!" else "Bonus", enabled = allClaimed }
		)
	end
end

local function buildRow(parent: Instance, order: number): Row
	local frame = UI.card({
		name = "Quest" .. order,
		size = UDim2.new(1, -8, 0, 92),
		order = order,
		radius = 18,
		parent = parent,
	})
	local bubble = UI.new("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(66, 66),
		Position = UDim2.new(0, 14, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = UI.lighten(UI.Theme.purple, 0.65),
		Parent = frame,
	}, { UI.round(), UI.stroke(UI.Theme.purple, 3) }) :: Frame
	local icon = UI.text({
		text = "",
		size = UDim2.fromScale(0.68, 0.68),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		maxTextSize = 40,
		noOutline = true,
		parent = bubble,
	})
	local title = UI.body({
		text = "",
		size = UDim2.new(1, -290, 0, 28),
		position = UDim2.fromOffset(94, 12),
		font = UI.Font,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 23,
		parent = frame,
	})
	local bar = UI.bar({
		size = UDim2.new(1, -440, 0, 24),
		position = UDim2.fromOffset(94, 52),
		color = UI.Theme.purple,
		parent = frame,
	})
	local reward = UI.body({
		text = "",
		size = UDim2.fromOffset(150, 24),
		position = UDim2.new(1, -330, 0, 52),
		color = UI.Theme.money,
		font = UI.HeavyFont,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 17,
		parent = frame,
	})
	local row: Row
	local button = UI.button({
		name = "Claim",
		text = "Go!",
		size = UDim2.fromOffset(150, 56),
		position = UDim2.new(1, -16, 0.5, -2),
		anchor = Vector2.new(1, 0.5),
		color = UI.Theme.green,
		parent = frame,
		onClick = function()
			if row.questId then
				Net.send("ClaimQuest", row.questId)
			end
		end,
	})
	row = {
		frame = frame,
		icon = icon,
		title = title,
		bar = bar,
		reward = reward,
		button = button,
		questId = nil,
	}
	return row
end

function QuestsUI.init()
	local _, content =
		Panels.window("Quests", "📜 Daily Quests", Vector2.new(820, 512), UI.Theme.purple)
	UI.body({
		text = "New quests every day. Finish them for prizes!",
		size = UDim2.new(1, -270, 0, 32),
		position = UDim2.fromOffset(0, 2),
		font = UI.Font,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 22,
		parent = content,
	})
	resetChip = UI.chip({
		name = "Reset",
		text = "",
		size = UDim2.fromOffset(240, 36),
		position = UDim2.new(1, 0, 0, 0),
		anchor = Vector2.new(1, 0),
		color = UI.Theme.purple,
		maxTextSize = 19,
		parent = content,
	})
	local list = UI.new("Frame", {
		Name = "List",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 0, 3 * 92 + 2 * 10),
		Parent = content,
	}, { UI.list(Enum.FillDirection.Vertical, 10) }) :: Frame
	for i = 1, QuestData.PER_DAY do
		table.insert(rows, buildRow(list, i))
	end
	local bonus = UI.card({
		name = "Bonus",
		size = UDim2.new(1, -8, 0, 62),
		position = UDim2.new(0, 4, 1, -64),
		color = Color3.fromRGB(255, 240, 196),
		edge = UI.Theme.gold,
		radius = 18,
		parent = content,
	})
	bonusLabel = UI.body({
		text = "",
		size = UDim2.new(1, -200, 0, 30),
		position = UDim2.new(0, 18, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		font = UI.Font,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 22,
		parent = bonus,
	})
	bonusButton = UI.button({
		name = "Claim",
		text = "Bonus",
		size = UDim2.fromOffset(150, 46),
		position = UDim2.new(1, -16, 0.5, -2),
		anchor = Vector2.new(1, 0.5),
		color = UI.Theme.orange,
		parent = bonus,
		onClick = function()
			Net.send("ClaimQuest", "bonus")
		end,
	})

	table.insert(Hud.badgeRefreshers, function(snapshot: Types.Snapshot)
		local item = Hud.menu.Quests
		if item then
			item.badge.Visible = QuestsUI.claimable(snapshot)
		end
	end)
	ClientState.changed:connect(function(snapshot: Types.Snapshot)
		if Panels.isOpen("Quests") then
			refresh(snapshot)
		end
	end)
	Panels.onOpen("Quests", function()
		local snapshot = ClientState.get()
		if snapshot then
			refresh(snapshot)
		end
	end)
end

function QuestsUI.start()
	while true do
		local now = Clock.now()
		local day = Cycle.dayNumber(now)
		resetChip.label.Text = `🔄 New quests in {Format.time((day + 1) * 86400 - now)}`
		task.wait(1)
	end
end

return QuestsUI
