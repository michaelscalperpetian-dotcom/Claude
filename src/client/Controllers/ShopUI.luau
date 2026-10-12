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
	price: TextLabel,
	stock: TextLabel,
	buy: TextButton,
}

local cards: { Card } = {}
local restockLabel: TextLabel
local luckLabel: TextLabel
local eggsPage: GuiObject
local upgradesPage: GuiObject
local slotRow: { info: TextLabel, button: TextButton }
local incubatorRow: { info: TextLabel, button: TextButton }

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

local function oddsRow(order: number, left: string, right: string, color: Color3)
	local row = UI.new("Frame", {
		Size = UDim2.new(1, -12, 0, 40),
		BackgroundColor3 = UI.Theme.panelDark,
		LayoutOrder = order,
		Parent = oddsList,
	}, { UI.corner(10) }) :: Frame
	UI.new("Frame", {
		Size = UDim2.fromOffset(12, 28),
		Position = UDim2.fromOffset(8, 6),
		BackgroundColor3 = color,
		Parent = row,
	}, { UI.corner(6) })
	UI.text({
		text = left,
		size = UDim2.new(0.7, -30, 1, -8),
		position = UDim2.fromOffset(28, 4),
		color = UI.Theme.ink,
		stroke = false,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 22,
		parent = row,
	})
	UI.text({
		text = right,
		size = UDim2.new(0.3, -12, 1, -8),
		position = UDim2.new(1, -10, 0, 4),
		anchor = Vector2.new(1, 0),
		color = UI.Theme.ink,
		stroke = false,
		align = Enum.TextXAlignment.Right,
		maxTextSize = 22,
		parent = row,
	})
end

local function renderOdds()
	local eggId = oddsEgg
	local egg = eggId and EggData.get(eggId)
	if not egg then
		return
	end
	for _, child in oddsList:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local snapshot = ClientState.get()
	local luck = snapshot ~= nil and snapshot.boosts.luckUntil > Clock.now()
	oddsTitle.Text = if luck
		then `{egg.name}: chance of each dino (🍀 your Luck boost is included)`
		else `{egg.name}: chance of each dino`

	local order = 0
	for _, chance in EggOdds.species(egg.id, luck) do
		order += 1
		local species = DinoData.get(chance.species)
		local name = if species then `{species.name} ({species.rarity})` else chance.species
		oddsRow(order, name, Odds.format(chance.bp), rarityColor(chance.species))
	end

	order += 1
	UI.text({
		text = "Mutation chance for each hatch right now:",
		size = UDim2.new(1, -12, 0, 34),
		color = UI.Theme.ink,
		stroke = false,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 22,
		order = order,
		parent = oddsList,
	})
	local mutationTotal = 0
	for _, m in EggOdds.mutations(Clock.cycleNow()) do
		order += 1
		mutationTotal += m.bp
		local info = MutationData.get(m.key)
		local label = if info then `{info.emoji} {info.name} (x{info.multiplier} coins)` else m.key
		oddsRow(order, label, Odds.format(m.bp), if info then UI.rgb(info.color) else UI.Theme.grey)
	end
	order += 1
	oddsRow(order, "No mutation", Odds.format(Odds.TOTAL_BP - mutationTotal), UI.Theme.grey)
	order += 1
	UI.text({
		text = "Odds are exact and add up to 100%. Storms change mutation chances.",
		size = UDim2.new(1, -12, 0, 30),
		color = UI.Theme.ink,
		stroke = false,
		font = UI.BodyFont,
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
	local card = UI.new("Frame", {
		Name = egg.id,
		Size = UDim2.fromOffset(182, 344),
		BackgroundColor3 = UI.Theme.panelDark,
		LayoutOrder = egg.order,
		Parent = parent,
	}, { UI.corner(16), UI.stroke(UI.Theme.ink, 3) }) :: Frame
	local preview = EggModel.build(EggModel.lookForShopEgg(egg.id), 3, true)
	local viewport = UI.viewport(preview, UDim2.fromOffset(120, 120), card)
	viewport.Position = UDim2.new(0.5, 0, 0, 6)
	viewport.AnchorPoint = Vector2.new(0.5, 0)
	UI.text({
		text = egg.name,
		size = UDim2.new(1, -12, 0, 30),
		position = UDim2.fromOffset(6, 128),
		color = UI.Theme.ink,
		stroke = false,
		maxTextSize = 24,
		parent = card,
	})
	local price = UI.text({
		text = "💰 " .. Format.number(egg.price),
		size = UDim2.new(1, -12, 0, 26),
		position = UDim2.fromOffset(6, 158),
		color = Color3.fromRGB(190, 130, 0),
		stroke = false,
		maxTextSize = 22,
		parent = card,
	})
	UI.text({
		text = "⏱ " .. Format.duration(egg.hatchSeconds),
		size = UDim2.new(1, -12, 0, 22),
		position = UDim2.fromOffset(6, 184),
		color = UI.Theme.ink,
		stroke = false,
		font = UI.BodyFont,
		maxTextSize = 18,
		parent = card,
	})
	local stock = UI.text({
		text = "",
		size = UDim2.new(1, -12, 0, 22),
		position = UDim2.fromOffset(6, 206),
		color = UI.Theme.ink,
		stroke = false,
		font = UI.BodyFont,
		maxTextSize = 18,
		parent = card,
	})
	local buy = UI.button({
		text = "Buy",
		size = UDim2.new(1, -20, 0, 48),
		position = UDim2.fromOffset(10, 234),
		color = UI.Theme.green,
		parent = card,
		onClick = function()
			Net.send("BuyEgg", egg.id)
		end,
	})
	UI.button({
		text = "📊 Odds",
		size = UDim2.new(1, -20, 0, 40),
		position = UDim2.fromOffset(10, 290),
		color = UI.Theme.blue,
		maxTextSize = 22,
		parent = card,
		onClick = function()
			ShopUI.showOdds(egg.id)
		end,
	})
	return { egg = egg, price = price, stock = stock, buy = buy }
end

local function upgradeRow(
	parent: Instance,
	order: number,
	title: string,
	onClick: () -> ()
): { info: TextLabel, button: TextButton }
	local row = UI.new("Frame", {
		Size = UDim2.new(1, -10, 0, 90),
		BackgroundColor3 = UI.Theme.panelDark,
		LayoutOrder = order,
		Parent = parent,
	}, { UI.corner(14), UI.stroke(UI.Theme.ink, 2) }) :: Frame
	UI.text({
		text = title,
		size = UDim2.new(0.62, 0, 0, 40),
		position = UDim2.fromOffset(14, 6),
		color = UI.Theme.ink,
		stroke = false,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 28,
		parent = row,
	})
	local info = UI.text({
		text = "",
		size = UDim2.new(0.62, 0, 0, 30),
		position = UDim2.fromOffset(14, 48),
		color = UI.Theme.ink,
		stroke = false,
		font = UI.BodyFont,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 20,
		parent = row,
	})
	local button = UI.button({
		text = "",
		size = UDim2.new(0.34, 0, 0, 60),
		position = UDim2.new(1, -12, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = UI.Theme.green,
		parent = row,
		onClick = onClick,
	})
	return { info = info, button = button }
end

local function refresh()
	local snapshot = ClientState.get()
	local restock = Cycle.restock(Clock.cycleNow())
	restockLabel.Text = "🔄 New stock in " .. Format.time(restock.secondsLeft)
	if not snapshot then
		return
	end
	local now = Clock.now()
	luckLabel.Text = if snapshot.boosts.luckUntil > now
		then "🍀 Luck active: rare dinos are 2x as likely!"
		else ""
	local bought = if snapshot.shopBought.restock == restock.index
		then snapshot.shopBought.bought
		else {}
	for _, card in cards do
		local left = (restock.stock[card.egg.id] or 0) - (bought[card.egg.id] or 0)
		card.stock.Text = if left > 0 then `In stock: {left}` else "Sold out!"
		card.stock.TextColor3 = if left > 0 then UI.Theme.ink else UI.Theme.red
		local affordable = snapshot.coins >= card.egg.price
		UI.setEnabled(card.buy, left > 0 and affordable, UI.Theme.green)
		card.buy.Text = if left <= 0 then "Sold out" elseif affordable then "Buy" else "Need coins"
	end

	local slotCost = Economy.nextUpgradeCost(Config.SLOT_UPGRADE_COSTS, snapshot.upgrades.slots)
	slotRow.info.Text = `Your nest holds {snapshot.maxSlots} dinos ({#snapshot.dinos} now)`
	if slotCost then
		slotRow.button.Text = "💰 " .. Format.number(slotCost)
		UI.setEnabled(slotRow.button, snapshot.coins >= slotCost, UI.Theme.green)
	else
		slotRow.button.Text = "MAX"
		UI.setEnabled(slotRow.button, false, UI.Theme.green)
	end
	local incubatorCost =
		Economy.nextUpgradeCost(Config.INCUBATOR_UPGRADE_COSTS, snapshot.upgrades.incubators)
	incubatorRow.info.Text = `You have {snapshot.maxIncubators} incubators`
	if incubatorCost then
		incubatorRow.button.Text = "💰 " .. Format.number(incubatorCost)
		UI.setEnabled(incubatorRow.button, snapshot.coins >= incubatorCost, UI.Theme.green)
	else
		incubatorRow.button.Text = "MAX"
		UI.setEnabled(incubatorRow.button, false, UI.Theme.green)
	end
end

local function showPage(page: string)
	eggsPage.Visible = page == "Eggs"
	upgradesPage.Visible = page == "Upgrades"
end

local function updateShopBillboard()
	local map = Workspace:FindFirstChild("Map")
	local hub = map and map:FindFirstChild("Hub")
	local promptPart = hub and hub:FindFirstChild("ShopPrompt")
	local gui = promptPart and promptPart:FindFirstChild("ShopBillboard")
	local label = gui and gui:FindFirstChild("Restock")
	if label and label:IsA("TextLabel") then
		label.Text = "New stock in " .. Format.time(Cycle.restock(Clock.cycleNow()).secondsLeft)
	end
end

function ShopUI.open()
	Panels.open("Shop")
end

function ShopUI.init()
	local _, content = Panels.window("Shop", "🥚 Egg Shop", Vector2.new(820, 520), UI.Theme.green)

	local tabs = UI.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 46),
		Parent = content,
	}, { UI.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left) }) :: Frame
	UI.button({
		text = "🥚 Eggs",
		size = UDim2.fromOffset(150, 42),
		color = UI.Theme.orange,
		order = 1,
		parent = tabs,
		onClick = function()
			showPage("Eggs")
		end,
	})
	UI.button({
		text = "🏗 Upgrades",
		size = UDim2.fromOffset(170, 42),
		color = UI.Theme.blue,
		order = 2,
		parent = tabs,
		onClick = function()
			showPage("Upgrades")
		end,
	})
	restockLabel = UI.text({
		text = "",
		size = UDim2.new(0, 260, 0, 34),
		position = UDim2.new(1, 0, 0, 4),
		anchor = Vector2.new(1, 0),
		color = UI.Theme.ink,
		stroke = false,
		align = Enum.TextXAlignment.Right,
		maxTextSize = 22,
		parent = content,
	})

	eggsPage = UI.new("ScrollingFrame", {
		Name = "Eggs",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 1, -84),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 6,
		Parent = content,
	}, {
		UI.list(
			Enum.FillDirection.Horizontal,
			12,
			Enum.HorizontalAlignment.Left,
			Enum.VerticalAlignment.Center
		),
	}) :: ScrollingFrame
	for _, egg in EggData.LIST do
		table.insert(cards, buildCard(eggsPage, egg))
	end
	luckLabel = UI.text({
		text = "",
		size = UDim2.new(1, 0, 0, 26),
		position = UDim2.new(0, 0, 1, -26),
		color = Color3.fromRGB(40, 140, 60),
		stroke = false,
		maxTextSize = 20,
		parent = content,
	})

	upgradesPage = UI.new("Frame", {
		Name = "Upgrades",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 1, -60),
		Visible = false,
		Parent = content,
	}, { UI.list(Enum.FillDirection.Vertical, 12) }) :: Frame
	slotRow = upgradeRow(upgradesPage, 1, "🦖 +1 Dino Slot", function()
		Net.send("BuyUpgrade", "slots")
	end)
	incubatorRow = upgradeRow(upgradesPage, 2, "🥚 +1 Incubator", function()
		Net.send("BuyUpgrade", "incubators")
	end)

	-- Odds window
	local _, oddsContent =
		Panels.window("Odds", "📊 Egg Odds", Vector2.new(620, 520), UI.Theme.blue)
	oddsTitle = UI.text({
		text = "",
		size = UDim2.new(1, -110, 0, 40),
		position = UDim2.fromOffset(110, 0),
		color = UI.Theme.ink,
		stroke = false,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 22,
		parent = oddsContent,
	})
	UI.button({
		text = "← Back",
		size = UDim2.fromOffset(100, 40),
		color = UI.Theme.orange,
		parent = oddsContent,
		onClick = function()
			Panels.open("Shop")
		end,
	})
	oddsList = UI.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 1, -48),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = oddsContent,
	}, { UI.list(Enum.FillDirection.Vertical, 6) }) :: ScrollingFrame

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
