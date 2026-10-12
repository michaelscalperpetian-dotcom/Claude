--!strict
-- Dino-Dex: every species, silhouetted until discovered, with the mutations
-- you've found for each. Completion is a big reason to keep hatching.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DinoData = require(ReplicatedStorage.Shared.Data.DinoData)
local DinoModel = require(ReplicatedStorage.Shared.Visual.DinoModel)
local MutationData = require(ReplicatedStorage.Shared.Data.MutationData)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientState = require(script.Parent.ClientState)
local Panels = require(script.Parent.Parent.Lib.Panels)
local UI = require(script.Parent.Parent.Lib.UI)

local DexUI = {}

type Card = {
	species: DinoData.Species,
	frame: Frame,
	viewport: ViewportFrame,
	name: TextLabel,
	badges: { [string]: TextLabel },
	discovered: boolean?,
}

local cards: { Card } = {}
local header: TextLabel

local function setSilhouette(viewport: ViewportFrame, silhouette: boolean)
	viewport.ImageColor3 = if silhouette then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
	viewport.ImageTransparency = if silhouette then 0.35 else 0
end

local function refresh(snapshot: Types.Snapshot)
	local found = 0
	for _, card in cards do
		local entry = snapshot.dex[card.species.id]
		local discovered = entry ~= nil
		if discovered then
			found += 1
		end
		if card.discovered ~= discovered then
			card.discovered = discovered
			setSilhouette(card.viewport, not discovered)
			card.name.Text = if discovered then card.species.name else "???"
		end
		for mutation, badge in card.badges do
			local has = entry ~= nil and entry[mutation] == true
			badge.TextTransparency = if has then 0 else 0.75
		end
	end
	header.Text = `Discovered {found} / {#cards} dinos. Find every mutation too!`
end

function DexUI.init()
	local _, content = Panels.window("Dex", "📖 Dino-Dex", Vector2.new(840, 540), UI.Theme.purple)
	header = UI.text({
		text = "",
		size = UDim2.new(1, 0, 0, 34),
		color = UI.Theme.ink,
		stroke = false,
		maxTextSize = 24,
		parent = content,
	})
	local grid = UI.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = content,
	}, {
		UI.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(150, 190),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: ScrollingFrame

	for index, species in DinoData.LIST do
		local frame = UI.new("Frame", {
			Name = species.id,
			BackgroundColor3 = UI.Theme.panelDark,
			LayoutOrder = index,
			Parent = grid,
		}, {
			UI.corner(14),
			UI.stroke(UI.rgb(DinoData.rarityInfo(species.rarity).color), 4),
		}) :: Frame
		local viewport = UI.viewport(
			DinoModel.build(species.id, 3, nil, "Static"),
			UDim2.new(1, -10, 0, 110),
			frame
		)
		viewport.Position = UDim2.fromOffset(5, 4)
		local name = UI.text({
			text = "???",
			size = UDim2.new(1, -8, 0, 26),
			position = UDim2.fromOffset(4, 114),
			color = UI.Theme.ink,
			stroke = false,
			maxTextSize = 20,
			parent = frame,
		})
		UI.text({
			text = species.rarity,
			size = UDim2.new(1, -8, 0, 18),
			position = UDim2.fromOffset(4, 138),
			color = UI.rgb(DinoData.rarityInfo(species.rarity).color),
			maxTextSize = 16,
			parent = frame,
		})
		local badgeRow = UI.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -8, 0, 26),
			Position = UDim2.fromOffset(4, 158),
			Parent = frame,
		}, { UI.list(Enum.FillDirection.Horizontal, 2) }) :: Frame
		local badges: { [string]: TextLabel } = {}
		for order, mutationId in MutationData.ORDER do
			local info = MutationData.get(mutationId)
			if info then
				badges[mutationId] = UI.text({
					text = info.emoji,
					size = UDim2.fromOffset(24, 24),
					maxTextSize = 20,
					order = order,
					stroke = false,
					parent = badgeRow,
				})
			end
		end
		local card: Card = {
			species = species,
			frame = frame,
			viewport = viewport,
			name = name,
			badges = badges,
			discovered = nil,
		}
		setSilhouette(viewport, true)
		table.insert(cards, card)
	end

	ClientState.changed:connect(refresh)
	Panels.onOpen("Dex", function()
		local snapshot = ClientState.get()
		if snapshot then
			refresh(snapshot)
		end
	end)
end

return DexUI
