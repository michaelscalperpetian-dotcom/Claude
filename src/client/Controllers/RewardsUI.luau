--!strict
-- Daily rewards: the 7-day streak calendar (day 7 is a big special prize)
-- plus the Dino Club daily gift.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Config = require(ReplicatedStorage.Shared.Config)
local Cycle = require(ReplicatedStorage.Shared.Util.Cycle)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Streak = require(ReplicatedStorage.Shared.Util.Streak)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientState = require(script.Parent.ClientState)
local Panels = require(script.Parent.Parent.Lib.Panels)
local UI = require(script.Parent.Parent.Lib.UI)

local RewardsUI = {}

type Tile = { frame: Frame, stroke: UIStroke, check: Frame, today: UI.Chip, big: boolean }

local tiles: { Tile } = {}
local claimButton: UI.Button
local nextLabel: TextLabel
local clubButton: UI.Button

local GOLD_TILE = Color3.fromRGB(255, 236, 170)

local function refresh(snapshot: Types.Snapshot)
	local now = Clock.now()
	local today = Cycle.dayNumber(now)
	local canClaim, day = Streak.status(snapshot.streak, today)
	local claimedThrough = if canClaim then day - 1 else day
	for index, tile in tiles do
		local claimed = index <= claimedThrough
		local isToday = canClaim and index == day
		tile.check.Visible = claimed
		tile.today.root.Visible = isToday
		if isToday then
			tile.frame.BackgroundColor3 = UI.lighten(UI.Theme.green, 0.75)
			tile.stroke.Color = UI.Theme.green
			tile.stroke.Thickness = 4
		else
			tile.frame.BackgroundColor3 = if tile.big then GOLD_TILE else UI.Theme.card
			tile.stroke.Color = if tile.big then UI.Theme.gold else UI.Theme.cardEdge
			tile.stroke.Thickness = if tile.big then 3.5 else 2.5
		end
	end
	if canClaim then
		UI.setButton(claimButton, { text = `🎁 Claim Day {day}!`, enabled = true })
		nextLabel.Text = "Come back every day! Miss a day and the streak starts over."
	else
		UI.setButton(claimButton, { text = "Claimed today ✓", enabled = false })
		local secondsToMidnight = (today + 1) * 86400 - now
		nextLabel.Text = `Next reward in {Format.time(secondsToMidnight)}`
	end
	local configured = Config.SUBSCRIPTION_ID ~= ""
	clubButton.root.Visible = configured
	if snapshot.subscribed then
		local claimed = snapshot.clubClaimDay == today
		UI.setButton(clubButton, {
			text = if claimed then "👑 Club gift claimed ✓" else "👑 Claim Dino Club gift",
			enabled = not claimed,
		})
	else
		UI.setButton(clubButton, { text = "👑 Join Dino Club for a daily gift", enabled = true })
	end
end

local function buildTile(parent: Instance, day: number, reward: Streak.Reward): Tile
	local big = day == #Streak.REWARDS
	local stroke = UI.stroke(UI.Theme.cardEdge, 2.5) :: UIStroke
	local frame = UI.new("Frame", {
		Name = "Day" .. day,
		Size = UDim2.fromOffset(if big then 170 else 98, 176),
		BackgroundColor3 = if big then GOLD_TILE else UI.Theme.card,
		LayoutOrder = day,
		Parent = parent,
	}, { UI.corner(18), stroke }) :: Frame
	UI.body({
		text = if big then "Day 7 ⭐" else `Day {day}`,
		size = UDim2.new(1, -10, 0, 26),
		position = UDim2.fromOffset(5, 8),
		font = UI.Font,
		maxTextSize = 22,
		parent = frame,
	})
	UI.text({
		text = reward.emoji,
		size = UDim2.new(1, -10, 0, if big then 70 else 56),
		position = UDim2.new(0.5, 0, 0, 38),
		anchor = Vector2.new(0.5, 0),
		maxTextSize = if big then 64 else 48,
		noOutline = true,
		parent = frame,
	})
	UI.body({
		text = reward.label,
		size = UDim2.new(1, -12, 0, 40),
		position = UDim2.new(0, 6, 1, -50),
		color = UI.Theme.inkSoft,
		font = UI.HeavyFont,
		maxTextSize = 16,
		parent = frame,
	})
	local check = UI.new("Frame", {
		Name = "Claimed",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UI.Theme.green,
		BackgroundTransparency = 0.35,
		Visible = false,
		ZIndex = 3,
		Parent = frame,
	}, { UI.corner(18) }) :: Frame
	UI.text({
		text = "✓",
		size = UDim2.fromScale(0.6, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		maxTextSize = 64,
		outline = UI.darken(UI.Theme.green, 0.5),
		outlineThickness = 3,
		zIndex = 4,
		parent = check,
	})
	local todayChip = UI.chip({
		name = "Today",
		text = "TODAY",
		size = UDim2.fromOffset(84, 26),
		position = UDim2.new(0.5, 0, 0, -12),
		anchor = Vector2.new(0.5, 0),
		color = UI.Theme.green,
		maxTextSize = 16,
		parent = frame,
	})
	todayChip.root.ZIndex = 5
	todayChip.root.Visible = false
	return { frame = frame, stroke = stroke, check = check, today = todayChip, big = big }
end

function RewardsUI.init()
	local _, content =
		Panels.window("Rewards", "🎁 Daily Rewards", Vector2.new(880, 470), UI.Theme.orange)
	local row = UI.new("Frame", {
		Name = "Days",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 196),
		Parent = content,
	}, {
		UI.list(
			Enum.FillDirection.Horizontal,
			10,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Bottom
		),
	}) :: Frame
	for day, reward in Streak.REWARDS do
		table.insert(tiles, buildTile(row, day, reward))
	end
	claimButton = UI.button({
		name = "Claim",
		text = "",
		size = UDim2.fromOffset(340, 64),
		position = UDim2.new(0.5, 0, 0, 212),
		anchor = Vector2.new(0.5, 0),
		color = UI.Theme.green,
		maxTextSize = 32,
		parent = content,
		onClick = function()
			Net.send("ClaimStreak")
		end,
	})
	nextLabel = UI.body({
		text = "",
		size = UDim2.new(1, 0, 0, 26),
		position = UDim2.fromOffset(0, 288),
		color = UI.Theme.inkSoft,
		maxTextSize = 19,
		parent = content,
	})
	clubButton = UI.button({
		name = "Club",
		text = "",
		size = UDim2.fromOffset(440, 52),
		position = UDim2.new(0.5, 0, 0, 324),
		anchor = Vector2.new(0.5, 0),
		color = UI.Theme.purple,
		maxTextSize = 24,
		parent = content,
		onClick = function()
			local snapshot = ClientState.get()
			if snapshot and snapshot.subscribed then
				Net.send("ClaimClub")
			else
				Net.send("PromptPurchase", "subscription", "DinoClub")
			end
		end,
	})

	ClientState.changed:connect(function(snapshot: Types.Snapshot)
		if Panels.isOpen("Rewards") then
			refresh(snapshot)
		end
	end)
	Panels.onOpen("Rewards", function()
		local snapshot = ClientState.get()
		if snapshot then
			refresh(snapshot)
		end
	end)
end

function RewardsUI.start()
	while true do
		task.wait(1)
		local snapshot = ClientState.get()
		if snapshot and Panels.isOpen("Rewards") then
			refresh(snapshot)
		end
	end
end

return RewardsUI
