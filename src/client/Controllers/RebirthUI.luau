--!strict
-- Rebirth window: how many rebirths you have, your permanent coin boost, and
-- progress toward the next one. The menu button shows a badge when you can
-- afford it. Rebirthing needs a second tap, since it spends all your coins.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientState = require(script.Parent.ClientState)
local Hud = require(script.Parent.Hud)
local Panels = require(script.Parent.Parent.Lib.Panels)
local UI = require(script.Parent.Parent.Lib.UI)

local RebirthUI = {}

local countLabel: TextLabel
local boostLabel: TextLabel
local nextLabel: TextLabel
local progress: UI.Bar
local rebirthButton: UI.Button
local armedUntil = 0

local function bonusPercent(rebirths: number): number
	return math.floor((Economy.rebirthMultiplier(rebirths) - 1) * 100 + 0.5)
end

function RebirthUI.ready(snapshot: Types.Snapshot): boolean
	return snapshot.coins >= Economy.rebirthCost(snapshot.rebirths)
end

local function refresh(snapshot: Types.Snapshot)
	local rebirths = snapshot.rebirths
	local cost = Economy.rebirthCost(rebirths)
	countLabel.Text = `⭐ {rebirths}`
	boostLabel.Text = if rebirths > 0
		then `Your coins: +{bonusPercent(rebirths)}% forever`
		else "No rebirths yet"
	nextLabel.Text =
		`Rebirth {rebirths + 1}: +{bonusPercent(rebirths + 1)}% coins on everything, forever`
	UI.setBar(
		progress,
		math.clamp(snapshot.coins / cost, 0, 1),
		`💰 {Format.number(snapshot.coins)} / {Format.number(cost)}`
	)
	if not RebirthUI.ready(snapshot) then
		UI.setButton(rebirthButton, {
			text = `Need 💰{Format.number(cost - snapshot.coins)} more`,
			color = UI.Theme.gold,
			enabled = false,
		})
	elseif Clock.now() < armedUntil then
		UI.setButton(
			rebirthButton,
			{ text = "Sure? All coins reset! Tap again", color = UI.Theme.red, enabled = true }
		)
	else
		UI.setButton(
			rebirthButton,
			{ text = "⭐ Rebirth!", color = UI.Theme.gold, enabled = true }
		)
	end
end

local function infoCard(
	parent: Instance,
	position: UDim2,
	title: string,
	text: string,
	color: Color3
)
	local card = UI.card({
		size = UDim2.new(0.5, -8, 0, 116),
		position = position,
		color = UI.lighten(color, 0.82),
		edge = color,
		radius = 16,
		parent = parent,
	})
	UI.body({
		text = title,
		size = UDim2.new(1, -24, 0, 28),
		position = UDim2.fromOffset(12, 8),
		font = UI.Font,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 22,
		parent = card,
	})
	UI.body({
		text = text,
		size = UDim2.new(1, -24, 0, 70),
		position = UDim2.fromOffset(12, 38),
		color = UI.Theme.inkSoft,
		align = Enum.TextXAlignment.Left,
		valign = Enum.TextYAlignment.Top,
		maxTextSize = 18,
		parent = card,
	})
end

function RebirthUI.init()
	local _, content = Panels.window("Rebirth", "⭐ Rebirth", Vector2.new(760, 500), UI.Theme.gold)

	local top = UI.card({
		name = "Current",
		size = UDim2.new(1, 0, 0, 96),
		color = UI.lighten(UI.Theme.gold, 0.75),
		edge = UI.darken(UI.Theme.gold, 0.25),
		radius = 18,
		parent = content,
	})
	countLabel = UI.text({
		text = "⭐ 0",
		size = UDim2.fromOffset(150, 70),
		position = UDim2.new(0, 14, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		color = UI.Theme.gold,
		maxTextSize = 54,
		outlineThickness = 3,
		parent = top,
	})
	boostLabel = UI.body({
		text = "",
		size = UDim2.new(1, -190, 0, 40),
		position = UDim2.new(0, 176, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		font = UI.Font,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 30,
		parent = top,
	})

	nextLabel = UI.body({
		text = "",
		size = UDim2.new(1, 0, 0, 30),
		position = UDim2.fromOffset(0, 110),
		font = UI.Font,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 22,
		parent = content,
	})
	progress = UI.bar({
		size = UDim2.new(1, 0, 0, 34),
		position = UDim2.fromOffset(0, 146),
		color = UI.Theme.gold,
		parent = content,
	})

	infoCard(
		content,
		UDim2.fromOffset(0, 196),
		"✅ You keep",
		"🦖 All your dinos  🥚 Eggs\n⬆️ Upgrades  📖 Dex  🎟 Passes",
		UI.Theme.green
	)
	infoCard(
		content,
		UDim2.new(0.5, 8, 0, 196),
		"🔄 Resets",
		"💰 All your coins, including the ones on your coin pad",
		UI.Theme.orange
	)

	rebirthButton = UI.button({
		name = "RebirthButton",
		text = "⭐ Rebirth!",
		size = UDim2.new(1, -120, 0, 64),
		position = UDim2.new(0.5, 0, 1, -6),
		anchor = Vector2.new(0.5, 1),
		color = UI.Theme.gold,
		maxTextSize = 30,
		parent = content,
		onClick = function()
			local snapshot = ClientState.get()
			if not snapshot or not RebirthUI.ready(snapshot) then
				return
			end
			if Clock.now() < armedUntil then
				armedUntil = 0
				Net.send("Rebirth")
			else
				armedUntil = Clock.now() + 3
				refresh(snapshot)
			end
		end,
	})

	table.insert(Hud.badgeRefreshers, function(snapshot: Types.Snapshot)
		local item = Hud.menu.Rebirth
		if item then
			item.badge.Visible = RebirthUI.ready(snapshot)
		end
	end)
	ClientState.changed:connect(function(snapshot: Types.Snapshot)
		if Panels.isOpen("Rebirth") then
			refresh(snapshot)
		end
	end)
	Panels.onOpen("Rebirth", function()
		armedUntil = 0
		local snapshot = ClientState.get()
		if snapshot then
			refresh(snapshot)
		end
	end)
end

function RebirthUI.start()
	-- the "tap again" prompt times out
	while true do
		task.wait(1)
		local snapshot = ClientState.get()
		if snapshot and Panels.isOpen("Rebirth") then
			refresh(snapshot)
		end
	end
end

return RebirthUI
