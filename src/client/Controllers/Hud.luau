--!strict
-- The always-on HUD:
--   * top centre: coin counter with income, day/night + storm chips, boosts
--   * left: menu buttons (2 columns), kept above the mobile thumbstick
--   * bottom centre: action buttons, clear of the thumbstick and jump button

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
local coinsPill: Frame
local coinsLabel: TextLabel
local incomeLabel: TextLabel
local cycleChip: UI.Chip
local stormChip: UI.Chip
local boostRow: Frame
local lockButton: UI.Button
local adButton: UI.Button
local dismountButton: UI.Button
local coinValue: NumberValue

local adAvailable = false

-- Buttons other controllers poke (tutorial highlights, tests).
Hud.buttons = {} :: { [string]: UI.Button }
Hud.menu = {} :: { [string]: UI.MenuButton }
-- Other controllers can add badge logic for their menu buttons.
Hud.badgeRefreshers = {} :: { (Types.Snapshot) -> () }

-- ===== Coins =====

local function buildCoins()
	coinsPill = UI.new("Frame", {
		Name = "Coins",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(310, 58),
		BackgroundColor3 = UI.Theme.hud,
		BackgroundTransparency = 0.18,
		Parent = screen,
	}, { UI.round(), UI.stroke(UI.Theme.ink, 3) }) :: Frame
	local coin = UI.coin(52, coinsPill)
	coin.Position = UDim2.new(0, -6, 0.5, 0)
	coin.AnchorPoint = Vector2.new(0, 0.5)
	coinsLabel = UI.text({
		name = "Amount",
		text = "0",
		size = UDim2.new(1, -150, 0, 42),
		position = UDim2.new(0, 56, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		align = Enum.TextXAlignment.Left,
		maxTextSize = 36,
		outlineThickness = 3,
		parent = coinsPill,
	})
	local income = UI.new("Frame", {
		Name = "Income",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(92, 36),
		BackgroundColor3 = UI.Theme.green,
		Parent = coinsPill,
	}, { UI.round(), UI.stroke(UI.darken(UI.Theme.green, 0.45), 2.5), UI.shade(0.84) }) :: Frame
	incomeLabel = UI.text({
		text = "+0/s",
		size = UDim2.new(1, -12, 1, -8),
		position = UDim2.fromOffset(6, 4),
		maxTextSize = 22,
		outline = UI.darken(UI.Theme.green, 0.6),
		parent = income,
	})
end

-- ===== Timers and boosts =====

local boostChips: { [string]: UI.Chip } = {}

local function boostChip(
	id: string,
	text: string,
	color: Color3,
	order: number,
	seen: { [string]: boolean }
)
	seen[id] = true
	local existing = boostChips[id]
	if existing then
		existing.label.Text = text
		return
	end
	local chip = UI.chip({
		name = id,
		text = text,
		size = UDim2.fromOffset(150, 34),
		color = color,
		order = order,
		maxTextSize = 19,
		parent = boostRow,
	})
	boostChips[id] = chip
	UI.pop(chip.root)
end

local function refreshBoosts(snapshot: Types.Snapshot, now: number)
	local seen: { [string]: boolean } = {}
	if snapshot.boosts.luckUntil > now then
		boostChip(
			"Luck",
			"🍀 Luck " .. Format.time(snapshot.boosts.luckUntil - now),
			UI.Theme.green,
			1,
			seen
		)
	end
	if snapshot.boosts.coinsUntil > now then
		boostChip(
			"Coins",
			"⚡ 2x " .. Format.time(snapshot.boosts.coinsUntil - now),
			UI.Theme.orange,
			2,
			seen
		)
	end
	if snapshot.lockUntil > now then
		boostChip("Lock", "🔒 " .. Format.time(snapshot.lockUntil - now), UI.Theme.red, 3, seen)
	end
	if snapshot.shieldUntil > now then
		boostChip(
			"Shield",
			"🛡 " .. Format.duration(snapshot.shieldUntil - now),
			UI.Theme.blue,
			4,
			seen
		)
	end
	if snapshot.friendsHere > 0 then
		local bonus =
			math.min(snapshot.friendsHere * Config.FRIEND_BOOST_PER_FRIEND, Config.FRIEND_BOOST_MAX)
		boostChip("Friends", `👥 +{math.floor(bonus * 100 + 0.5)}%`, UI.Theme.purple, 5, seen)
	end
	if snapshot.multiplier > 1.01 then
		boostChip(
			"Multiplier",
			`💰 x{string.format("%.1f", snapshot.multiplier)}`,
			UI.Theme.teal,
			6,
			seen
		)
	end
	for id, chip in boostChips do
		if not seen[id] then
			chip.root:Destroy()
			boostChips[id] = nil
		end
	end
end

local function refreshTimers()
	local snapshot = ClientState.get()
	coinsLabel.Text = Format.number(math.floor(coinValue.Value))
	local cycleNow = Clock.cycleNow()
	local now = Clock.now()

	local dn = Cycle.dayNight(cycleNow)
	local raids = ReplicatedStorage:GetAttribute("RaidsEnabled") ~= false
	if dn.isNight then
		cycleChip.label.Text = `🌙 Night {Format.time(dn.secondsLeft)}`
			.. (if raids then " • Raids!" else "")
		UI.setChipColor(cycleChip, UI.Theme.night)
	else
		cycleChip.label.Text = `☀️ Day {Format.time(dn.secondsLeft)}`
		UI.setChipColor(cycleChip, UI.Theme.day)
	end

	local storm = Cycle.storm(cycleNow)
	if storm.active then
		stormChip.root.Visible = true
		if storm.mega then
			stormChip.label.Text =
				`{MutationData.MEGA_STORM_EMOJI} Mega Storm {Format.time(storm.secondsLeft)}`
			UI.setChipColor(stormChip, UI.Theme.purple)
		elseif storm.kind then
			local info = MutationData.stormInfo(storm.kind)
			stormChip.label.Text = `{info.emoji} {info.name} {Format.time(storm.secondsLeft)}`
			UI.setChipColor(stormChip, UI.Theme.orange)
		end
	else
		local nextInfo = if storm.nextKind then MutationData.stormInfo(storm.nextKind) else nil
		stormChip.root.Visible = nextInfo ~= nil
		if nextInfo then
			stormChip.label.Text = `Next {nextInfo.emoji} in {Format.time(storm.secondsLeft)}`
			UI.setChipColor(stormChip, UI.Theme.hud)
		end
	end

	if not snapshot then
		return
	end
	refreshBoosts(snapshot, now)

	if snapshot.lockUntil > now then
		UI.setButton(
			lockButton,
			{ text = "🔒 " .. Format.time(snapshot.lockUntil - now), enabled = false }
		)
	elseif snapshot.lockCooldownUntil > now then
		UI.setButton(
			lockButton,
			{ text = "⏳ " .. Format.time(snapshot.lockCooldownUntil - now), enabled = false }
		)
	else
		UI.setButton(lockButton, {
			text = "🔒 Lock",
			enabled = true,
			color = if dn.isNight then UI.Theme.red else UI.Theme.night,
		})
	end

	local rewards = Hud.menu.Rewards
	if rewards then
		rewards.badge.Visible = (Streak.status(snapshot.streak, Cycle.dayNumber(now)))
	end
	adButton.root.Visible = adAvailable and snapshot.tutorial == 99
	dismountButton.root.Visible = snapshot.riding ~= nil
	for _, refresh in Hud.badgeRefreshers do
		refresh(snapshot)
	end
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

function Hud.coinPill(): Frame
	return coinsPill
end

-- ===== Menu =====

local MENU = {
	{ name = "Shop", icon = "🥚", caption = "Eggs", color = UI.Theme.green },
	{ name = "Store", icon = "💎", caption = "Store", color = UI.Theme.blue },
	{ name = "Rewards", icon = "🎁", caption = "Daily", color = UI.Theme.orange },
	{ name = "Quests", icon = "📜", caption = "Quests", color = UI.Theme.purple },
	{ name = "Dex", icon = "📖", caption = "Dex", color = UI.Theme.pink },
	{ name = "Rebirth", icon = "⭐", caption = "Rebirth", color = UI.Theme.gold },
	{ name = "Settings", icon = "⚙️", caption = "Settings", color = UI.Theme.teal },
}

local function buildMenu()
	local menu = UI.new("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(70 * 2 + 18, 4 * 70 + 3 * 34),
		Parent = screen,
	}, {
		UI.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(70, 70),
			CellPadding = UDim2.fromOffset(18, 34),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame
	for order, entry in MENU do
		local item = UI.menuButton({
			icon = entry.icon,
			caption = entry.caption,
			color = entry.color,
			order = order,
			parent = menu,
			onClick = function()
				Panels.toggle(entry.name)
			end,
		})
		item.button.root.Name = entry.name
		Hud.menu[entry.name] = item
	end
end

-- Hide menu buttons whose window doesn't exist (e.g. a feature turned off).
local function syncMenu()
	for name, item in Hud.menu do
		item.button.root.Visible = Panels.has(name)
	end
end

-- ===== Actions =====

local function buildActions()
	local actions = UI.new("Frame", {
		Name = "Actions",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(700, 60),
		Parent = screen,
	}, {
		UI.list(
			Enum.FillDirection.Horizontal,
			12,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Center
		),
	}) :: Frame
	local function action(
		name: string,
		text: string,
		color: Color3,
		order: number,
		onClick: () -> ()
	): UI.Button
		local button = UI.button({
			name = name,
			text = text,
			size = UDim2.fromOffset(138, 56),
			color = color,
			order = order,
			maxTextSize = 26,
			parent = actions,
			onClick = onClick,
		})
		Hud.buttons[name] = button
		return button
	end
	lockButton = action("Lock", "🔒 Lock", UI.Theme.night, 1, function()
		Net.send("LockGate")
	end)
	action("Roar", "🦖 Roar", UI.Theme.orange, 2, function()
		Net.send("Roar")
	end)
	action("Invite", "📣 Invite", UI.Theme.blue, 3, invite)
	adButton = action("Ad", "▶ Free 2x", UI.Theme.purple, 4, function()
		Net.send("WatchAd")
	end)
	adButton.root.Visible = false
	task.spawn(pcall, function()
		AdService:RegisterAdOpportunityAsync(adButton.face)
	end)
	dismountButton = action("Dismount", "⬇ Get off", UI.Theme.grey, 5, function()
		Net.send("Ride", nil)
	end)
	dismountButton.root.Visible = false
end

function Hud.init()
	screen = UI.screen("HUD", 1)

	coinValue = Instance.new("NumberValue")
	coinValue.Changed:Connect(function(value: number)
		coinsLabel.Text = Format.number(math.floor(value))
	end)

	buildCoins()
	local timers = UI.new("Frame", {
		Name = "Timers",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 76),
		Size = UDim2.fromOffset(640, 36),
		Parent = screen,
	}, { UI.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) }) :: Frame
	cycleChip = UI.chip({
		name = "Cycle",
		text = "☀️ Day",
		size = UDim2.fromOffset(210, 36),
		color = UI.Theme.day,
		order = 1,
		maxTextSize = 21,
		parent = timers,
	})
	stormChip = UI.chip({
		name = "Storm",
		text = "",
		size = UDim2.fromOffset(250, 36),
		color = UI.Theme.hud,
		order = 2,
		maxTextSize = 21,
		parent = timers,
	})
	stormChip.root.Visible = false
	boostRow = UI.new("Frame", {
		Name = "Boosts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 122),
		Size = UDim2.fromOffset(820, 34),
		Parent = screen,
	}, { UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) }) :: Frame

	buildMenu()
	buildActions()

	ClientState.changed:connect(onState)
end

function Hud.start()
	syncMenu()
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
