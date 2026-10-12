--!strict
-- Robux store: game passes, boosts, coin packs, the one-time Starter Pack and
-- the Dino Club subscription. Prices come live from Roblox. Items that feed
-- random egg results are hidden for players PolicyService restricts.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local StoreData = require(ReplicatedStorage.Shared.Data.StoreData)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientState = require(script.Parent.ClientState)
local Toasts = require(script.Parent.Toasts)
local Panels = require(script.Parent.Parent.Lib.Panels)
local UI = require(script.Parent.Parent.Lib.UI)

local StoreUI = {}

type Card = {
	item: StoreData.Item,
	frame: Frame,
	button: UI.Button,
}

type Section = { frame: Frame, cards: { Card } }

local list: ScrollingFrame
local cards: { Card } = {}
local sections: { Section } = {}
local starterCard: Card
local hero: Frame
local clubCard: Frame
local clubButton: UI.Button
local prices: { [string]: number } = {}

local CARD_HEIGHT = 104
local GRID_GAP = 12

local function idFor(item: StoreData.Item): number
	if item.kind == "pass" then
		return (Config.GAME_PASS_IDS :: { [string]: number })[item.key] or 0
	end
	return (Config.PRODUCT_IDS :: { [string]: number })[item.key] or 0
end

local function fetchPrice(item: StoreData.Item)
	local id = idFor(item)
	if id == 0 or prices[item.key] then
		return
	end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(
				id,
				if item.kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
			)
		end)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			prices[item.key] = info.PriceInRobux
			StoreUI.refresh()
		end
	end)
end

local function buy(item: StoreData.Item)
	if idFor(item) == 0 then
		Toasts.show(`🛠 Paste the {item.key} ID into Config to sell this.`, "info")
		return
	end
	Net.send("PromptPurchase", item.kind, item.key)
end

local function iconBubble(parent: Instance, emoji: string, color: Color3, size: number): Frame
	local bubble = UI.new("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.new(0, 12, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = UI.lighten(color, 0.55),
		Parent = parent,
	}, { UI.round(), UI.stroke(color, 3) }) :: Frame
	UI.text({
		text = emoji,
		size = UDim2.fromScale(0.68, 0.68),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		maxTextSize = 48,
		noOutline = true,
		parent = bubble,
	})
	return bubble
end

local function buildCard(item: StoreData.Item, parent: Instance, order: number, color: Color3): Card
	local frame = UI.card({
		name = item.key,
		size = UDim2.fromScale(1, 1),
		order = order,
		radius = 18,
		parent = parent,
	})
	iconBubble(frame, item.emoji, color, 76)
	UI.body({
		text = item.name,
		size = UDim2.new(1, -250, 0, 30),
		position = UDim2.fromOffset(100, 12),
		font = UI.Font,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 24,
		parent = frame,
	})
	UI.body({
		text = item.description,
		size = UDim2.new(1, -250, 0, 46),
		position = UDim2.fromOffset(100, 44),
		color = UI.Theme.inkSoft,
		align = Enum.TextXAlignment.Left,
		valign = Enum.TextYAlignment.Top,
		maxTextSize = 17,
		parent = frame,
	})
	local button = UI.button({
		name = "Buy",
		text = "",
		size = UDim2.fromOffset(124, 54),
		position = UDim2.new(1, -14, 0.5, -2),
		anchor = Vector2.new(1, 0.5),
		color = UI.Theme.green,
		maxTextSize = 24,
		parent = frame,
		onClick = function()
			buy(item)
		end,
	})
	return { item = item, frame = frame, button = button }
end

local function sectionTitle(text: string, order: number)
	UI.body({
		name = "Section",
		text = text,
		size = UDim2.new(1, -16, 0, 34),
		font = UI.Font,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 26,
		order = order,
		parent = list,
	})
end

local function gridSection(items: { StoreData.Item }, order: number, color: Color3): Section
	local frame = UI.new("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 0, 0),
		LayoutOrder = order,
		Parent = list,
	}, {
		UI.new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -GRID_GAP / 2, 0, CARD_HEIGHT),
			CellPadding = UDim2.fromOffset(GRID_GAP, GRID_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame
	local section: Section = { frame = frame, cards = {} }
	for i, item in items do
		local card = buildCard(item, frame, i, color)
		table.insert(section.cards, card)
		table.insert(cards, card)
	end
	table.insert(sections, section)
	return section
end

-- Grids don't size themselves; fit each one to its visible cards.
local function resizeSections()
	for _, section in sections do
		local visible = 0
		for _, card in section.cards do
			if card.frame.Visible then
				visible += 1
			end
		end
		local rows = math.ceil(visible / 2)
		section.frame.Size =
			UDim2.new(1, -16, 0, rows * CARD_HEIGHT + math.max(rows - 1, 0) * GRID_GAP)
		section.frame.Visible = visible > 0
	end
end

local function priceText(item: StoreData.Item): string
	local price = prices[item.key] or (Config.SUGGESTED_PRICES :: { [string]: number })[item.key]
	return if price then `R$ {price}` else "Buy"
end

function StoreUI.refresh()
	local snapshot = ClientState.get()
	if not snapshot then
		return
	end
	for _, card in cards do
		local item = card.item
		local id = idFor(item)
		local hiddenByPolicy = item.feedsRandom == true and snapshot.restricted
		local hiddenStarter = item.key == "StarterPack" and snapshot.starterPackBought
		local notSetUp = id == 0 and not snapshot.isDev
		card.frame.Visible = not hiddenByPolicy and not hiddenStarter and not notSetUp
		if item.kind == "pass" and snapshot.passes[item.key] then
			UI.setButton(card.button, { text = "Owned ✓", enabled = false })
		else
			UI.setButton(card.button, { text = priceText(item), enabled = true })
		end
	end
	resizeSections()
	hero.Visible = starterCard.frame.Visible
	local clubConfigured = Config.SUBSCRIPTION_ID ~= ""
	clubCard.Visible = clubConfigured or snapshot.isDev
	if snapshot.subscribed then
		UI.setButton(clubButton, { text = "Member ✓", enabled = false })
	else
		UI.setButton(clubButton, { text = "Join", enabled = true })
	end
end

function StoreUI.init()
	local _, content = Panels.window("Store", "💎 Store", Vector2.new(880, 500), UI.Theme.blue)
	list = UI.new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		BorderSizePixel = 0,
		Parent = content,
	}, { UI.list(Enum.FillDirection.Vertical, 10), UI.padding(2, 4) }) :: ScrollingFrame

	-- Starter Pack hero banner
	hero = UI.new("Frame", {
		Name = "StarterHolder",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 0, 112),
		LayoutOrder = 1,
		Parent = list,
	}) :: Frame
	starterCard = buildCard(StoreData.STARTER_PACK, hero, 1, UI.Theme.orange)
	starterCard.frame.BackgroundColor3 = Color3.fromRGB(255, 240, 196)
	local heroStroke = starterCard.frame:FindFirstChildOfClass("UIStroke")
	if heroStroke then
		heroStroke.Color = UI.Theme.orange
		heroStroke.Thickness = 4
	end
	UI.setButton(starterCard.button, { color = UI.Theme.orange })
	local ribbon = UI.chip({
		name = "Ribbon",
		text = "⭐ BEST VALUE",
		size = UDim2.fromOffset(150, 30),
		position = UDim2.new(1, -150, 0, -12),
		color = UI.Theme.red,
		maxTextSize = 17,
		parent = starterCard.frame,
	})
	ribbon.root.ZIndex = 3
	table.insert(cards, starterCard)

	sectionTitle("⭐ Game Passes (forever)", 2)
	gridSection(StoreData.PASSES, 3, UI.Theme.blue)

	sectionTitle("👑 Dino Club (monthly)", 4)
	clubCard = UI.card({
		name = "Club",
		size = UDim2.new(1, -16, 0, 96),
		order = 5,
		radius = 18,
		color = Color3.fromRGB(240, 230, 255),
		edge = UI.Theme.purple,
		parent = list,
	})
	iconBubble(clubCard, "👑", UI.Theme.purple, 72)
	UI.body({
		text = "Dino Club",
		size = UDim2.new(1, -260, 0, 30),
		position = UDim2.fromOffset(98, 12),
		font = UI.Font,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 24,
		parent = clubCard,
	})
	UI.body({
		text = "+10% coins on everything and a free coin gift every day.",
		size = UDim2.new(1, -260, 0, 40),
		position = UDim2.fromOffset(98, 44),
		color = UI.Theme.inkSoft,
		align = Enum.TextXAlignment.Left,
		valign = Enum.TextYAlignment.Top,
		maxTextSize = 17,
		parent = clubCard,
	})
	clubButton = UI.button({
		name = "Join",
		text = "Join",
		size = UDim2.fromOffset(124, 54),
		position = UDim2.new(1, -14, 0.5, -2),
		anchor = Vector2.new(1, 0.5),
		color = UI.Theme.purple,
		maxTextSize = 24,
		parent = clubCard,
		onClick = function()
			if Config.SUBSCRIPTION_ID == "" then
				Toasts.show("🛠 Set SUBSCRIPTION_ID in Config to sell the Dino Club.", "info")
				return
			end
			Net.send("PromptPurchase", "subscription", "DinoClub")
		end,
	})

	sectionTitle("⚡ Boosts & Coins", 6)
	gridSection(StoreData.PRODUCTS, 7, UI.Theme.orange)

	UI.body({
		text = "Purchases help us make the game. Always ask a grown-up before buying!",
		size = UDim2.new(1, -16, 0, 26),
		color = UI.Theme.inkSoft,
		maxTextSize = 16,
		order = 8,
		parent = list,
	})

	Panels.onOpen("Store", function()
		for _, card in cards do
			fetchPrice(card.item)
		end
		StoreUI.refresh()
	end)
	ClientState.changed:connect(function(_: Types.Snapshot)
		if Panels.isOpen("Store") then
			StoreUI.refresh()
		end
	end)
end

function StoreUI.open()
	Panels.open("Store")
end

return StoreUI
