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
local Panels = require(script.Parent.Parent.Lib.Panels)
local UI = require(script.Parent.Parent.Lib.UI)

local StoreUI = {}

type Card = {
	item: StoreData.Item,
	frame: Frame,
	button: TextButton,
}

local list: ScrollingFrame
local cards: { Card } = {}
local clubCard: Frame
local clubButton: TextButton
local prices: { [string]: number } = {}

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

local function sectionTitle(text: string, order: number)
	UI.text({
		text = text,
		size = UDim2.new(1, -12, 0, 36),
		color = UI.Theme.ink,
		stroke = false,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 26,
		order = order,
		parent = list,
	})
end

local function buildCard(item: StoreData.Item, order: number, highlight: boolean?): Card
	local frame = UI.new("Frame", {
		Name = item.key,
		Size = UDim2.new(1, -12, 0, 86),
		BackgroundColor3 = if highlight then Color3.fromRGB(255, 236, 170) else UI.Theme.panelDark,
		LayoutOrder = order,
		Parent = list,
	}, {
		UI.corner(14),
		UI.stroke(if highlight then UI.Theme.orange else UI.Theme.ink, if highlight then 4 else 2),
	}) :: Frame
	UI.text({
		text = item.emoji,
		size = UDim2.fromOffset(64, 64),
		position = UDim2.fromOffset(10, 11),
		maxTextSize = 48,
		parent = frame,
	})
	UI.text({
		text = item.name,
		size = UDim2.new(0.6, -80, 0, 34),
		position = UDim2.fromOffset(84, 8),
		color = UI.Theme.ink,
		stroke = false,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 26,
		parent = frame,
	})
	UI.text({
		text = item.description,
		size = UDim2.new(0.62, -80, 0, 34),
		position = UDim2.fromOffset(84, 44),
		color = UI.Theme.ink,
		stroke = false,
		font = UI.BodyFont,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 18,
		parent = frame,
	})
	local button = UI.button({
		text = "",
		size = UDim2.new(0.3, 0, 0, 56),
		position = UDim2.new(1, -12, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = UI.Theme.green,
		parent = frame,
		onClick = function()
			Net.send("PromptPurchase", item.kind, item.key)
		end,
	})
	return { item = item, frame = frame, button = button }
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
			card.button.Text = "Owned ✓"
			UI.setEnabled(card.button, false, UI.Theme.green)
		elseif id == 0 then
			card.button.Text = "Set ID in Config"
			UI.setEnabled(card.button, false, UI.Theme.green)
		else
			local price = prices[item.key]
			card.button.Text = if price then `R$ {price}` else "Buy"
			UI.setEnabled(card.button, true, UI.Theme.green)
		end
	end
	local clubConfigured = Config.SUBSCRIPTION_ID ~= ""
	clubCard.Visible = clubConfigured or snapshot.isDev
	if snapshot.subscribed then
		clubButton.Text = "Member ✓"
		UI.setEnabled(clubButton, false, UI.Theme.purple)
	elseif not clubConfigured then
		clubButton.Text = "Set ID in Config"
		UI.setEnabled(clubButton, false, UI.Theme.purple)
	else
		clubButton.Text = "Join"
		UI.setEnabled(clubButton, true, UI.Theme.purple)
	end
end

function StoreUI.init()
	local _, content = Panels.window("Store", "💎 Store", Vector2.new(760, 540), UI.Theme.blue)
	list = UI.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = content,
	}, { UI.list(Enum.FillDirection.Vertical, 8) }) :: ScrollingFrame

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	table.insert(cards, buildCard(StoreData.STARTER_PACK, nextOrder(), true))

	sectionTitle("Game Passes (forever)", nextOrder())
	for _, item in StoreData.PASSES do
		table.insert(cards, buildCard(item, nextOrder()))
	end

	sectionTitle("Dino Club (monthly)", nextOrder())
	clubCard = UI.new("Frame", {
		Size = UDim2.new(1, -12, 0, 86),
		BackgroundColor3 = Color3.fromRGB(235, 220, 255),
		LayoutOrder = nextOrder(),
		Parent = list,
	}, { UI.corner(14), UI.stroke(UI.Theme.purple, 3) }) :: Frame
	UI.text({
		text = "🦖",
		size = UDim2.fromOffset(64, 64),
		position = UDim2.fromOffset(10, 11),
		maxTextSize = 48,
		parent = clubCard,
	})
	UI.text({
		text = "Dino Club: +10% coins + a daily coin gift",
		size = UDim2.new(0.62, -80, 0, 60),
		position = UDim2.fromOffset(84, 12),
		color = UI.Theme.ink,
		stroke = false,
		align = Enum.TextXAlignment.Left,
		maxTextSize = 22,
		parent = clubCard,
	})
	clubButton = UI.button({
		text = "Join",
		size = UDim2.new(0.3, 0, 0, 56),
		position = UDim2.new(1, -12, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		color = UI.Theme.purple,
		parent = clubCard,
		onClick = function()
			Net.send("PromptPurchase", "subscription", "DinoClub")
		end,
	})

	sectionTitle("Boosts & Coins", nextOrder())
	for _, item in StoreData.PRODUCTS do
		table.insert(cards, buildCard(item, nextOrder()))
	end

	UI.text({
		text = "Purchases support the game. Ask a grown-up before buying!",
		size = UDim2.new(1, -12, 0, 28),
		color = UI.Theme.ink,
		stroke = false,
		font = UI.BodyFont,
		maxTextSize = 16,
		order = nextOrder(),
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
