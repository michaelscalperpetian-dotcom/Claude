--!strict
-- Daily rewards: the 7-day streak calendar plus the Dino Club daily gift.

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

type Tile = { frame: Frame, status: TextLabel, stroke: UIStroke }

local tiles: { Tile } = {}
local claimButton: TextButton
local nextLabel: TextLabel
local clubButton: TextButton

local function refresh(snapshot: Types.Snapshot)
	local now = Clock.now()
	local today = Cycle.dayNumber(now)
	local canClaim, day = Streak.status(snapshot.streak, today)
	local claimedThrough = if canClaim then day - 1 else day
	for index, tile in tiles do
		if index <= claimedThrough then
			tile.status.Text = "✓"
			tile.frame.BackgroundColor3 = Color3.fromRGB(200, 235, 200)
			tile.stroke.Color = UI.Theme.green
		elseif canClaim and index == day then
			tile.status.Text = "TODAY"
			tile.frame.BackgroundColor3 = Color3.fromRGB(255, 236, 170)
			tile.stroke.Color = UI.Theme.orange
		else
			tile.status.Text = ""
			tile.frame.BackgroundColor3 = UI.Theme.panelDark
			tile.stroke.Color = UI.Theme.ink
		end
	end
	if canClaim then
		claimButton.Text = `🎁 Claim day {day}!`
		UI.setEnabled(claimButton, true, UI.Theme.green)
		nextLabel.Text = "Come back every day. Miss a day and the streak restarts."
	else
		claimButton.Text = "Claimed today ✓"
		UI.setEnabled(claimButton, false, UI.Theme.green)
		local secondsToMidnight = (today + 1) * 86400 - now
		nextLabel.Text = `Next reward in {Format.time(secondsToMidnight)}`
	end
	local configured = Config.SUBSCRIPTION_ID ~= ""
	clubButton.Visible = configured
	if snapshot.subscribed then
		local claimed = snapshot.clubClaimDay == today
		clubButton.Text = if claimed
			then "🦖 Club gift claimed ✓"
			else "🦖 Claim Dino Club gift"
		UI.setEnabled(clubButton, not claimed, UI.Theme.purple)
	else
		clubButton.Text = "🦖 Join Dino Club for a daily gift"
		UI.setEnabled(clubButton, true, UI.Theme.purple)
	end
end

function RewardsUI.init()
	local _, content =
		Panels.window("Rewards", "🎁 Daily Rewards", Vector2.new(820, 470), UI.Theme.orange)
	local row = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 200),
		Parent = content,
	}, {
		UI.list(
			Enum.FillDirection.Horizontal,
			8,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Center
		),
	}) :: Frame
	for day, reward in Streak.REWARDS do
		local stroke = UI.stroke(UI.Theme.ink, 3) :: UIStroke
		local frame = UI.new("Frame", {
			Size = UDim2.fromOffset(104, 180),
			BackgroundColor3 = UI.Theme.panelDark,
			LayoutOrder = day,
			Parent = row,
		}, { UI.corner(14), stroke }) :: Frame
		UI.text({
			text = `Day {day}`,
			size = UDim2.new(1, -8, 0, 28),
			position = UDim2.fromOffset(4, 6),
			color = UI.Theme.ink,
			stroke = false,
			maxTextSize = 22,
			parent = frame,
		})
		UI.text({
			text = reward.emoji,
			size = UDim2.new(1, -8, 0, 52),
			position = UDim2.fromOffset(4, 36),
			maxTextSize = 44,
			parent = frame,
		})
		UI.text({
			text = reward.label,
			size = UDim2.new(1, -8, 0, 44),
			position = UDim2.fromOffset(4, 92),
			color = UI.Theme.ink,
			stroke = false,
			font = UI.BodyFont,
			maxTextSize = 16,
			parent = frame,
		})
		local status = UI.text({
			text = "",
			size = UDim2.new(1, -8, 0, 30),
			position = UDim2.fromOffset(4, 142),
			color = UI.Theme.green,
			maxTextSize = 22,
			parent = frame,
		})
		table.insert(tiles, { frame = frame, status = status, stroke = stroke })
	end
	claimButton = UI.button({
		text = "",
		size = UDim2.fromOffset(320, 60),
		position = UDim2.new(0.5, 0, 0, 214),
		anchor = Vector2.new(0.5, 0),
		color = UI.Theme.green,
		parent = content,
		onClick = function()
			Net.send("ClaimStreak")
		end,
	})
	nextLabel = UI.text({
		text = "",
		size = UDim2.new(1, 0, 0, 28),
		position = UDim2.fromOffset(0, 280),
		color = UI.Theme.ink,
		stroke = false,
		font = UI.BodyFont,
		maxTextSize = 18,
		parent = content,
	})
	clubButton = UI.button({
		text = "",
		size = UDim2.fromOffset(420, 54),
		position = UDim2.new(0.5, 0, 0, 318),
		anchor = Vector2.new(0.5, 0),
		color = UI.Theme.purple,
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
