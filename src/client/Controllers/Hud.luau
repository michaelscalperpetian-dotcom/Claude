--!strict
-- The always-on HUD: coins, day/night + storm timers, active boosts, menu
-- buttons (right side) and action buttons (bottom row, clear of the mobile
-- thumbstick and jump button).

local AdService = game:GetService("AdService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Config = require(ReplicatedStorage.Shared.Config)
local Cycle = require(ReplicatedStorage.Shared.Util.Cycle)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local MutationData = require(ReplicatedStorage.Shared.Data.MutationData)
local Net = require(ReplicatedStorage.Shared.Net)
local Streak = require(ReplicatedStorage.Shared.Util.Streak)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientState = require(script.Parent.ClientState)
local Panels = require(script.Parent.Parent.Lib.Panels)
local UI = require(script.Parent.Parent.Lib.UI)

local Hud = {}

local screen: ScreenGui
local coinsLabel: TextLabel
local incomeLabel: TextLabel
local coinsPill: Frame
local cycleLabel: TextLabel
local cyclePill: Frame
local stormPill: Frame
local stormLabel: TextLabel
local boostList: Frame
local rewardsBadge: TextLabel
local lockButton: TextButton
local adButton: TextButton
local dismountButton: TextButton
local coinValue: NumberValue

local adAvailable = false

Hud.buttons = {} :: { [string]: TextButton }

local function pill(
	name: string,
	size: Vector2,
	position: UDim2,
	anchor: Vector2,
	color: Color3
): Frame
	return UI.new("Frame", {
		Name = name,
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = position,
		AnchorPoint = anchor,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.1,
		Parent = screen,
	}, {
		UI.corner(math.floor(size.Y / 2)),
		UI.stroke(UI.Theme.ink, 3),
	}) :: Frame
end

local function menuButton(
	name: string,
	emoji: string,
	label: string,
	color: Color3,
	order: number,
	onClick: () -> ()
): TextButton
	local button = UI.button({
		text = emoji,
		size = UDim2.fromOffset(78, 78),
		color = color,
		order = order,
		maxTextSize = 40,
		onClick = onClick,
	})
	button.Name = name
	UI.text({
		text = label,
		size = UDim2.new(1, 8, 0, 22),
		position = UDim2.new(0.5, 0, 1, 2),
		anchor = Vector2.new(0.5, 0),
		maxTextSize = 18,
		parent = button,
	})
	Hud.buttons[name] = button
	return button
end

local boostPills: { [string]: { frame: Frame, label: TextLabel } } = {}

local function boostPill(
	id: string,
	text: string,
	color: Color3,
	order: number,
	seen: { [string]: boolean }
)
	seen[id] = true
	local existing = boostPills[id]
	if existing then
		existing.label.Text = text
		return
	end
	local frame = UI.new("Frame", {
		Name = id,
		Size = UDim2.fromOffset(210, 40),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.1,
		LayoutOrder = order,
		Parent = boostList,
	}, { UI.corner(20), UI.stroke(UI.Theme.ink, 2) }) :: Frame
	local label = UI.text({
		text = text,
		size = UDim2.new(1, -16, 1, -8),
		position = UDim2.fromOffset(8, 4),
		maxTextSize = 22,
		parent = frame,
	})
	boostPills[id] = { frame = frame, label = label }
	UI.pop(frame)
end

local function refreshBoosts(snapshot: Types.Snapshot, now: number)
	local seen: { [string]: boolean } = {}
	if snapshot.boosts.luckUntil > now then
		boostPill(
			"Luck",
			"🍀 Luck " .. Format.time(snapshot.boosts.luckUntil - now),
			UI.Theme.green,
			1,
			seen
		)
	end
	if snapshot.boosts.coinsUntil > now then
		boostPill(
			"Coins",
			"⚡ 2x Coins " .. Format.time(snapshot.boosts.coinsUntil - now),
			UI.Theme.orange,
			2,
			seen
		)
	end
	if snapshot.lockUntil > now then
		boostPill(
			"Lock",
			"🔒 Locked " .. Format.time(snapshot.lockUntil - now),
			UI.Theme.red,
			3,
			seen
		)
	end
	if snapshot.shieldUntil > now then
		boostPill(
			"Shield",
			"🛡 Shield " .. Format.duration(snapshot.shieldUntil - now),
			UI.Theme.blue,
			4,
			seen
		)
	end
	if snapshot.friendsHere > 0 then
		local bonus =
			math.min(snapshot.friendsHere * Config.FRIEND_BOOST_PER_FRIEND, Config.FRIEND_BOOST_MAX)
		boostPill(
			"Friends",
			`👥 Friends +{math.floor(bonus * 100 + 0.5)}%`,
			UI.Theme.purple,
			5,
			seen
		)
	end
	if snapshot.multiplier > 1.01 then
		boostPill(
			"Multiplier",
			`💰 x{string.format("%.1f", snapshot.multiplier)} coins`,
			UI.Theme.hud,
			6,
			seen
		)
	end
	for id, entry in boostPills do
		if not seen[id] then
			entry.frame:Destroy()
			boostPills[id] = nil
		end
	end
end

local function refreshTimers()
	local snapshot = ClientState.get()
	local cycleNow = Clock.cycleNow()
	local now = Clock.now()

	local dn = Cycle.dayNight(cycleNow)
	local raids = ReplicatedStorage:GetAttribute("RaidsEnabled") ~= false
	if dn.isNight then
		cycleLabel.Text = `🌙 Night {Format.time(dn.secondsLeft)}`
			.. (if raids then " • Raids on!" else "")
		cyclePill.BackgroundColor3 = UI.Theme.night
	else
		cycleLabel.Text = `☀️ Day {Format.time(dn.secondsLeft)}`
		cyclePill.BackgroundColor3 = UI.Theme.hud
	end

	local storm = Cycle.storm(cycleNow)
	if storm.active then
		stormPill.Visible = true
		if storm.mega then
			stormLabel.Text = `{MutationData.MEGA_STORM_EMOJI} Rainbow Mega Storm {Format.time(
				storm.secondsLeft
			)}`
			stormPill.BackgroundColor3 = UI.Theme.purple
		elseif storm.kind then
			local info = MutationData.stormInfo(storm.kind)
			stormLabel.Text = `{info.emoji} {info.name} {Format.time(storm.secondsLeft)}`
			stormPill.BackgroundColor3 = UI.Theme.orange
		end
	else
		stormPill.Visible = true
		local nextInfo = if storm.nextKind then MutationData.stormInfo(storm.nextKind) else nil
		stormLabel.Text = if nextInfo
			then `Next: {nextInfo.emoji} {nextInfo.name} in {Format.time(storm.secondsLeft)}`
			else ""
		stormPill.BackgroundColor3 = UI.Theme.hud
	end

	if not snapshot then
		return
	end
	refreshBoosts(snapshot, now)

	if snapshot.lockUntil > now then
		lockButton.Text = "🔒 " .. Format.time(snapshot.lockUntil - now)
		UI.setEnabled(lockButton, false, UI.Theme.red)
	elseif snapshot.lockCooldownUntil > now then
		lockButton.Text = "⏳ " .. Format.time(snapshot.lockCooldownUntil - now)
		UI.setEnabled(lockButton, false, UI.Theme.red)
	else
		lockButton.Text = "🔒 Lock"
		UI.setEnabled(lockButton, true, if dn.isNight then UI.Theme.red else UI.Theme.hud)
	end

	local canClaim = Streak.status(snapshot.streak, Cycle.dayNumber(now))
	rewardsBadge.Visible = canClaim
	adButton.Visible = adAvailable and snapshot.tutorial == 99
	dismountButton.Visible = snapshot.riding ~= nil
end

local function onState(snapshot: Types.Snapshot)
	TweenService
		:Create(coinValue, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Value = snapshot.coins })
		:Play()
	incomeLabel.Text = "+" .. Format.number(snapshot.incomePerSecond) .. "/s"
end

local function checkAds()
	if Config.PRODUCT_IDS.AdCoinBoost == 0 then
		adAvailable = false
		return
	end
	local ok, result = pcall(function()
		return AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
	end)
	adAvailable = ok
		and type(result) == "table"
		and result.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable
end

local function invite()
	local player = Players.LocalPlayer
	local ok, canInvite = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if ok and canInvite then
		pcall(function()
			SocialService:PromptGameInvite(player)
		end)
	end
end

-- Screen position of the coin counter (for flying-coin effects).
function Hud.coinTarget(): Vector2
	return coinsPill.AbsolutePosition + coinsPill.AbsoluteSize / 2
end

function Hud.init()
	screen = UI.screen("HUD", 1)

	coinValue = Instance.new("NumberValue")
	coinValue.Changed:Connect(function(value: number)
		coinsLabel.Text = "💰 " .. Format.number(math.floor(value))
	end)

	coinsPill = pill(
		"Coins",
		Vector2.new(300, 60),
		UDim2.new(0.5, 0, 0, 8),
		Vector2.new(0.5, 0),
		UI.Theme.hud
	)
	coinsLabel = UI.text({
		text = "💰 0",
		size = UDim2.new(0.68, 0, 1, -10),
		position = UDim2.fromOffset(12, 5),
		color = UI.Theme.gold,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 36,
		parent = coinsPill,
	})
	incomeLabel = UI.text({
		text = "+0/s",
		size = UDim2.new(0.3, -10, 0.6, 0),
		position = UDim2.new(1, -10, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = UI.Theme.green,
		align = Enum.TextXAlignment.Right,
		maxTextSize = 24,
		parent = coinsPill,
	})

	cyclePill = pill(
		"Cycle",
		Vector2.new(300, 40),
		UDim2.new(0.5, 0, 0, 74),
		Vector2.new(0.5, 0),
		UI.Theme.hud
	)
	cycleLabel = UI.text({
		text = "☀️ Day",
		size = UDim2.new(1, -20, 1, -8),
		position = UDim2.fromOffset(10, 4),
		maxTextSize = 24,
		parent = cyclePill,
	})
	stormPill = pill(
		"Storm",
		Vector2.new(360, 34),
		UDim2.new(0.5, 0, 0, 120),
		Vector2.new(0.5, 0),
		UI.Theme.hud
	)
	stormLabel = UI.text({
		text = "",
		size = UDim2.new(1, -20, 1, -6),
		position = UDim2.fromOffset(10, 3),
		maxTextSize = 20,
		parent = stormPill,
	})

	boostList = UI.new("Frame", {
		Name = "Boosts",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0.32, 0),
		Size = UDim2.fromOffset(210, 280),
		Parent = screen,
	}, { UI.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left) }) :: Frame

	-- Menu buttons (right side)
	local menu = UI.new("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.46, 0),
		Size = UDim2.fromOffset(84, 430),
		Parent = screen,
	}, {
		UI.list(
			Enum.FillDirection.Vertical,
			26,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Center
		),
	}) :: Frame
	menuButton("Shop", "🥚", "Eggs", UI.Theme.green, 1, function()
		Panels.toggle("Shop")
	end).Parent =
		menu
	menuButton("Store", "💎", "Store", UI.Theme.blue, 2, function()
		Panels.toggle("Store")
	end).Parent =
		menu
	local rewards = menuButton("Rewards", "🎁", "Rewards", UI.Theme.orange, 3, function()
		Panels.toggle("Rewards")
	end)
	rewards.Parent = menu
	rewardsBadge = UI.text({
		text = "!",
		size = UDim2.fromOffset(28, 28),
		position = UDim2.new(1, 4, 0, -6),
		anchor = Vector2.new(1, 0),
		color = UI.Theme.white,
		maxTextSize = 24,
		parent = rewards,
	})
	rewardsBadge.BackgroundTransparency = 0
	rewardsBadge.BackgroundColor3 = UI.Theme.red
	UI.corner(14).Parent = rewardsBadge
	menuButton("Dex", "📖", "Dex", UI.Theme.purple, 4, function()
		Panels.toggle("Dex")
	end).Parent =
		menu

	-- Action row (bottom center)
	local actions = UI.new("Frame", {
		Name = "Actions",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(640, 64),
		Parent = screen,
	}, {
		UI.list(
			Enum.FillDirection.Horizontal,
			10,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Center
		),
	}) :: Frame
	lockButton = UI.button({
		text = "🔒 Lock",
		size = UDim2.fromOffset(150, 58),
		color = UI.Theme.hud,
		order = 1,
		parent = actions,
		onClick = function()
			Net.send("LockGate")
		end,
	})
	Hud.buttons.Lock = lockButton
	Hud.buttons.Roar = UI.button({
		text = "🦖 Roar",
		size = UDim2.fromOffset(130, 58),
		color = UI.Theme.orange,
		order = 2,
		parent = actions,
		onClick = function()
			Net.send("Roar")
		end,
	})
	Hud.buttons.Invite = UI.button({
		text = "📣 Invite",
		size = UDim2.fromOffset(130, 58),
		color = UI.Theme.blue,
		order = 3,
		parent = actions,
		onClick = invite,
	})
	adButton = UI.button({
		text = "▶ Free 2x",
		size = UDim2.fromOffset(140, 58),
		color = UI.Theme.purple,
		order = 4,
		parent = actions,
		onClick = function()
			Net.send("WatchAd")
		end,
	})
	adButton.Visible = false
	task.spawn(pcall, function()
		AdService:RegisterAdOpportunityAsync(adButton)
	end)
	dismountButton = UI.button({
		text = "⬇ Get off",
		size = UDim2.fromOffset(140, 58),
		color = UI.Theme.grey,
		order = 5,
		parent = actions,
		onClick = function()
			Net.send("Ride", nil)
		end,
	})
	dismountButton.Visible = false

	ClientState.changed:connect(onState)
end

function Hud.start()
	task.spawn(function()
		while true do
			checkAds()
			task.wait(45)
		end
	end)
	while true do
		refreshTimers()
		task.wait(0.25)
	end
end

return Hud
