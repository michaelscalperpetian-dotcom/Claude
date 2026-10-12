--!strict
-- Egg Shop: buy eggs (limited stock that restocks every 5 minutes), view each
-- egg's real odds, and buy permanent nest upgrades with coins.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local Config = require(ReplicatedStorage.Shared.Config)
local Cycle = require(ReplicatedStorage.Shared.Util.Cycle)
local DinoData = require(ReplicatedStorage.Shared.Data.DinoData)
local Economy = require(ReplicatedStorage.Shared.Util.Economy)
local EggData = require(ReplicatedStorage.Shared.Data.EggData)
local EggModel = require(ReplicatedStorage.Shared.Visual.EggModel)
local EggOdds = require(ReplicatedStorage.Shared.Util.EggOdds)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local MutationData = require(ReplicatedStorage.Shared.Data.MutationData)
local Net = require(ReplicatedStorage.Shared.Net)
local Odds = require(ReplicatedStorage.Shared.Util.Odds)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientState = require(script.Parent.ClientState)
local Panels = require(script.Parent.Parent.Lib.Panels)
local UI = require(script.Parent.Parent.Lib.UI)

local ShopUI = {}

type Card = {
	egg: EggData.EggType,
	stock: TextLabel,
	buy: UI.Button,
}

type UpgradeRow = { info: TextLabel, bar: UI.Bar, button: UI.Button }

local cards: { Card } = {}
local restockChip: UI.Chip
local luckLabel: TextLabel
local eggsPage: GuiObject
local upgradesPage: GuiObject
local slotRow: UpgradeRow
local incubatorRow: UpgradeRow

local oddsTitle: TextLabel
local oddsList: ScrollingFrame
local oddsEgg: string? = nil

-- ===== Odds window =====

local function rarityColor(speciesId: string): Color3
	local species = DinoData.get(speciesId)
	if not species then
		return UI.Theme.grey
	end
	return UI.rgb(DinoData.rarityInfo(species.rarity).color)
end

local function oddsRow(order: number, left: string, tag: string?, bp: number, color: Color3)
	local row =
		UI.card({ size = UDim2.new(1, -14, 0, 46), order = order, radius = 12, parent = oddsList })
	UI.new("Frame", {
		Name = "Dot",
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.new(0, 12, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = color,
		Parent = row,
	}, { UI.round(), UI.stroke(UI.darken(color, 0.4), 2) })
	UI.body({
		text = left,
		size = UDim2.new(0.42, -44, 0, 26),
		position = UDim2.new(0, 44, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		font = UI.Font,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 22,
		parent = row,
	})
	if tag then
		UI.body({
			text = tag,
			size = UDim2.new(0.16, 0, 0, 20),
			position = UDim2.new(0.42, 0, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			color = UI.darken(color, 0.25),
			font = UI.HeavyFont,
			align = Enum.TextXAlignment.Left,
			maxTextSize = 17,
			parent = row,
		})
	end
	-- share bar: how big this slice is out of 100%
	local track = UI.new("Frame", {
		Name = "Share",
		Size = UDim2.new(0.24, 0, 0, 14),
		Position = UDim2.new(0.6, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = UI.Theme.track,
		Parent = row,
	}, { UI.round() }) :: Frame
	UI.new("Frame", {
		Size = UDim2.fromScale(math.clamp(bp / Odds.TOTAL_BP, 0.02, 1), 1),
		BackgroundColor3 = color,
		Parent = track,
	}, { UI.round() })
	UI.body({
		text = Odds.format(bp),
		size = UDim2.new(0.14, -12, 0, 26),
		position = UDim2.new(1, -12, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		font = UI.Font,
		align = Enum.TextXAlignment.Right,
		maxTextSize = 22,
		parent = row,
	})
end

local function sectionLabel(text: string, order: number)
	UI.body({
		text = text,
		size = UDim2.new(1, -14, 0, 30),
		font = UI.Font,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 22,
		order = order,
		parent = oddsList,
	})
end

local function renderOdds()
	local eggId = oddsEgg
	local egg = eggId and EggData.get(eggId)
	if not egg then
		return
	end
	for _, child in oddsList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local snapshot = ClientState.get()
	local luck = snapshot ~= nil and snapshot.boosts.luckUntil > Clock.now()
	Panels.setTitle("Odds", `📊 {egg.name} Odds`)
	oddsTitle.Text = if luck
		then "🍀 Your Luck boost is included!"
		else "Every dino this egg can hatch:"

	local order = 0
	for _, chance in EggOdds.species(egg.id, luck) do
		order += 1
		local species = DinoData.get(chance.species)
		oddsRow(
			order,
			if species then species.name else chance.species,
			if species then species.rarity else nil,
			chance.bp,
			rarityColor(chance.species)
		)
	end

	order += 1
	sectionLabel("✨ Mutation chance for each hatch right now:", order)
	local mutationTotal = 0
	for _, m in EggOdds.mutations(Clock.cycleNow()) do
		order += 1
		mutationTotal += m.bp
		local info = MutationData.get(m.key)
		local label = if info then `{info.emoji} {info.name}` else m.key
		local tag = if info then `x{info.multiplier} coins` else nil
		oddsRow(order, label, tag, m.bp, if info then UI.rgb(info.color) else UI.Theme.grey)
	end
	order += 1
	oddsRow(order, "No mutation", nil, Odds.TOTAL_BP - mutationTotal, UI.Theme.grey)
	order += 1
	UI.body({
		text = "These are the exact odds and they add up to 100%. Storms raise mutation chances!",
		size = UDim2.new(1, -14, 0, 30),
		color = UI.Theme.inkSoft,
		maxTextSize = 16,
		order = order,
		parent = oddsList,
	})
end

function ShopUI.showOdds(eggId: string)
	oddsEgg = eggId
	renderOdds()
	Panels.open("Odds")
end

-- ===== Shop window =====

local function buildCard(parent: Instance, egg: EggData.EggType): Card
	local eggColor = UI.rgb(egg.colors.main)
	local card = UI.card({
		name = egg.id,
		size = UDim2.fromOffset(188, 318),
		order = egg.order,
		radius = 20,
		parent = parent,
	})
	local showcase = UI.new("Frame", {
		Name = "Showcase",
		Size = UDim2.new(1, -16, 0, 120),
		Position = UDim2.fromOffset(8, 8),
		BackgroundColor3 = UI.lighten(eggColor, 0.55),
		Parent = card,
	}, { UI.corner(14), UI.shade(0.9) }) :: Frame
	local viewport = UI.viewport(
		EggModel.build(EggModel.lookForShopEgg(egg.id), 3, true),
		UDim2.fromOffset(118, 118),
		showcase,
		20
	)
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.52)
	local stock = UI.chip({
		name = "Stock",
		text = "",
		size = UDim2.fromOffset(84, 26),
		position = UDim2.new(1, -6, 0, 6),
		anchor = Vector2.new(1, 0),
		color = UI.Theme.hud,
		maxTextSize = 15,
		parent = showcase,
	})
	UI.body({
		text = egg.name,
		size = UDim2.new(1, -16, 0, 30),
		position = UDim2.fromOffset(8, 134),
		font = UI.Font,
		maxTextSize = 24,
		parent = card,
	})
	UI.price({
		amount = Format.number(egg.price),
		size = UDim2.new(1, -16, 0, 26),
		position = UDim2.fromOffset(8, 166),
		parent = card,
	})
	UI.body({
		text = "⏱ Hatches in " .. Format.duration(egg.hatchSeconds),
		size = UDim2.new(1, -16, 0, 20),
		position = UDim2.fromOffset(8, 196),
		color = UI.Theme.inkSoft,
		maxTextSize = 16,
		parent = card,
	})
	local buy = UI.button({
		name = "Buy",
		text = "Buy",
		size = UDim2.new(1, -20, 0, 48),
		position = UDim2.fromOffset(10, 222),
		color = UI.Theme.green,
		parent = card,
		onClick = function()
			Net.send("BuyEgg", egg.id)
		end,
	})
	UI.button({
		name = "Odds",
		text = "📊 Odds",
		size = UDim2.new(1, -60, 0, 32),
		position = UDim2.new(0.5, 0, 0, 278),
		anchor = Vector2.new(0.5, 0),
		color = UI.Theme.blue,
		depth = 4,
		maxTextSize = 18,
		parent = card,
		onClick = function()
			ShopUI.showOdds(egg.id)
		end,
	})
	return { egg = egg, stock = stock.label, buy = buy }
end

local function upgradeCard(
	parent: Instance,
	order: number,
	icon: string,
	title: string,
	onClick: () -> ()
): UpgradeRow
	local card =
		UI.card({ size = UDim2.new(1, -8, 0, 128), order = order, radius = 20, parent = parent })
	local badge = UI.new("Frame", {
		Size = UDim2.fromOffset(92, 92),
		Position = UDim2.new(0, 18, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = UI.lighten(UI.Theme.blue, 0.6),
		Parent = card,
	}, { UI.round(), UI.stroke(UI.Theme.blue, 3) }) :: Frame
	UI.text({
		text = icon,
		size = UDim2.fromScale(0.7, 0.7),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		maxTextSize = 56,
		noOutline = true,
		parent = badge,
	})
	UI.body({
		text = title,
		size = UDim2.new(0.5, 0, 0, 36),
		position = UDim2.fromOffset(128, 14),
		font = UI.Font,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 30,
		parent = card,
	})
	local info = UI.body({
		text = "",
		size = UDim2.new(0.5, 0, 0, 24),
		position = UDim2.fromOffset(128, 52),
		color = UI.Theme.inkSoft,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 19,
		parent = card,
	})
	local bar = UI.bar({
		size = UDim2.new(0.42, 0, 0, 22),
		position = UDim2.fromOffset(128, 86),
		color = UI.Theme.blue,
		parent = card,
	})
	local button = UI.button({
		name = "Buy",
		text = "",
		size = UDim2.fromOffset(200, 62),
		position = UDim2.new(1, -20, 0.5, -3),
		anchor = Vector2.new(1, 0.5),
		color = UI.Theme.green,
		parent = card,
		onClick = onClick,
	})
	return { info = info, bar = bar, button = button }
end

local function refreshUpgrade(row: UpgradeRow, costs: { number }, level: number, coins: number)
	local cost = Economy.nextUpgradeCost(costs, level)
	UI.setBar(row.bar, level / #costs, `Level {level} / {#costs}`)
	if cost then
		UI.setButton(row.button, { text = "💰 " .. Format.number(cost), enabled = coins >= cost })
	else
		UI.setButton(row.button, { text = "MAX ✓", enabled = false })
	end
end

local function refresh()
	local snapshot = ClientState.get()
	local restock = Cycle.restock(Clock.cycleNow())
	restockChip.label.Text = "🔄 New eggs in " .. Format.time(restock.secondsLeft)
	if not snapshot then
		return
	end
	local now = Clock.now()
	luckLabel.Text = if snapshot.boosts.luckUntil > now
		then "🍀 Luck is on: rare dinos are 2x as likely!"
		else ""
	local bought = if snapshot.shopBought.restock == restock.index
		then snapshot.shopBought.bought
		else {}
	for _, card in cards do
		local left = (restock.stock[card.egg.id] or 0) - (bought[card.egg.id] or 0)
		card.stock.Text = if left > 0 then `x{left} left` else "Sold out"
		local affordable = snapshot.coins >= card.egg.price
		UI.setButton(card.buy, {
			text = if left <= 0 then "Sold out" elseif affordable then "Buy" else "Need coins",
			enabled = left > 0 and affordable,
		})
	end
	slotRow.info.Text = `Room for {snapshot.maxSlots} dinos ({#snapshot.dinos} living here)`
	refreshUpgrade(slotRow, Config.SLOT_UPGRADE_COSTS, snapshot.upgrades.slots, snapshot.coins)
	incubatorRow.info.Text = `You have {snapshot.maxIncubators} incubators`
	refreshUpgrade(
		incubatorRow,
		Config.INCUBATOR_UPGRADE_COSTS,
		snapshot.upgrades.incubators,
		snapshot.coins
	)
end

local function updateShopBillboard()
	local map = Workspace:FindFirstChild("Map")
	local hub = map and map:FindFirstChild("Hub")
	local promptPart = hub and hub:FindFirstChild("ShopPrompt")
	local gui = promptPart and promptPart:FindFirstChild("ShopBillboard")
	local label = gui and gui:FindFirstChild("Restock")
	if label and label:IsA("TextLabel") then
		label.Text = "New eggs in " .. Format.time(Cycle.restock(Clock.cycleNow()).secondsLeft)
	end
end

function ShopUI.open()
	Panels.open("Shop")
end

function ShopUI.init()
	local _, content = Panels.window("Shop", "🥚 Egg Shop", Vector2.new(880, 500), UI.Theme.green)

	local selectTab = Panels.tabs(content, {
		{ name = "Eggs", text = "🥚 Eggs", color = UI.Theme.orange },
		{ name = "Upgrades", text = "🏗 Upgrades", color = UI.Theme.blue },
	}, function(name: string)
		eggsPage.Visible = name == "Eggs"
		upgradesPage.Visible = name == "Upgrades"
	end)
	restockChip = UI.chip({
		name = "Restock",
		text = "",
		size = UDim2.fromOffset(250, 38),
		position = UDim2.new(1, 0, 0, 2),
		anchor = Vector2.new(1, 0),
		color = UI.Theme.purple,
		maxTextSize = 20,
		parent = content,
	})

	eggsPage = UI.new("ScrollingFrame", {
		Name = "Eggs",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 1, -86),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 6,
		BorderSizePixel = 0,
		Parent = content,
	}, {
		UI.list(
			Enum.FillDirection.Horizontal,
			14,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Center
		),
	}) :: ScrollingFrame
	for _, egg in EggData.LIST do
		table.insert(cards, buildCard(eggsPage, egg))
	end
	luckLabel = UI.body({
		text = "",
		size = UDim2.new(1, 0, 0, 24),
		position = UDim2.new(0, 0, 1, -24),
		color = UI.Theme.good,
		font = UI.Font,
		maxTextSize = 20,
		parent = content,
	})

	upgradesPage = UI.new("Frame", {
		Name = "Upgrades",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 1, -64),
		Visible = false,
		Parent = content,
	}, { UI.list(Enum.FillDirection.Vertical, 16) }) :: Frame
	slotRow = upgradeCard(upgradesPage, 1, "🦖", "+1 Dino Slot", function()
		Net.send("BuyUpgrade", "slots")
	end)
	incubatorRow = upgradeCard(upgradesPage, 2, "🥚", "+1 Incubator", function()
		Net.send("BuyUpgrade", "incubators")
	end)
	selectTab("Eggs")

	-- Odds window
	local _, oddsContent =
		Panels.window("Odds", "📊 Egg Odds", Vector2.new(680, 500), UI.Theme.blue)
	UI.button({
		name = "Back",
		text = "← Back",
		size = UDim2.fromOffset(120, 42),
		color = UI.Theme.orange,
		depth = 4,
		maxTextSize = 22,
		parent = oddsContent,
		onClick = function()
			Panels.open("Shop")
		end,
	})
	oddsTitle = UI.body({
		text = "",
		size = UDim2.new(1, -140, 0, 36),
		position = UDim2.fromOffset(136, 3),
		font = UI.Font,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 22,
		parent = oddsContent,
	})
	oddsList = UI.new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 1, -56),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		BorderSizePixel = 0,
		Parent = oddsContent,
	}, { UI.list(Enum.FillDirection.Vertical, 8), UI.padding(2, 4) }) :: ScrollingFrame

	Panels.onOpen("Shop", refresh)
	ClientState.changed:connect(function(_: Types.Snapshot)
		if Panels.isOpen("Shop") then
			refresh()
		elseif Panels.isOpen("Odds") then
			renderOdds()
		end
	end)
end

function ShopUI.start()
	while true do
		task.wait(0.5)
		updateShopBillboard()
		if Panels.isOpen("Shop") then
			refresh()
		end
	end
end

return ShopUI
