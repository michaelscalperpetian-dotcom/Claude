--!strict
-- Dino-Dex: every species, silhouetted until discovered, with the mutations
-- you've found for each. Completion is a big reason to keep hatching.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DexRewards = require(ReplicatedStorage.Shared.Data.DexRewards)
local DinoData = require(ReplicatedStorage.Shared.Data.DinoData)
local DinoModel = require(ReplicatedStorage.Shared.Visual.DinoModel)
local MutationData = require(ReplicatedStorage.Shared.Data.MutationData)
local Types = require(ReplicatedStorage.Shared.Types)
local Net = require(ReplicatedStorage.Shared.Net)
local ClientState = require(script.Parent.ClientState)
local Hud = require(script.Parent.Hud)
local Panels = require(script.Parent.Parent.Lib.Panels)
local UI = require(script.Parent.Parent.Lib.UI)

local DexUI = {}

type Card = {
	species: DinoData.Species,
	frame: Frame,
	viewport: ViewportFrame,
	name: TextLabel,
	badges: { [string]: Frame },
	discovered: boolean?,
}

local cards: { Card } = {}
local progress: UI.Bar
local prizes: { { count: number, emoji: string, button: UI.Button } } = {}

local function setSilhouette(viewport: ViewportFrame, silhouette: boolean)
	viewport.ImageColor3 = if silhouette then Color3.fromRGB(40, 32, 60) else Color3.new(1, 1, 1)
	viewport.ImageTransparency = if silhouette then 0.25 else 0
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
			badge.BackgroundTransparency = if has then 0 else 0.7
			local icon = badge:FindFirstChildOfClass("TextLabel")
			if icon then
				icon.TextTransparency = if has then 0 else 0.65
			end
		end
	end
	UI.setBar(progress, found / #cards, `{found} / {#cards} dinos found`)
	for _, prize in prizes do
		if snapshot.dexClaimed[tostring(prize.count)] == true then
			UI.setButton(prize.button, { text = "✓", enabled = false })
		elseif found >= prize.count then
			UI.setButton(
				prize.button,
				{ text = `Claim {prize.emoji}`, enabled = true, color = UI.Theme.green }
			)
		else
			UI.setButton(
				prize.button,
				{ text = `{prize.count} {prize.emoji}`, enabled = true, color = UI.Theme.inkSoft }
			)
		end
	end
end

-- Any Dex prize ready to claim? (drives the menu badge)
function DexUI.claimable(snapshot: Types.Snapshot): boolean
	local found = DexRewards.discovered(snapshot.dex)
	for _, milestone in DexRewards.MILESTONES do
		if found >= milestone.count and not snapshot.dexClaimed[tostring(milestone.count)] then
			return true
		end
	end
	return false
end

local function buildCard(grid: Instance, index: number, species: DinoData.Species): Card
	local rarityColor = UI.rgb(DinoData.rarityInfo(species.rarity).color)
	local frame = UI.card({
		name = species.id,
		size = UDim2.fromScale(1, 1),
		order = index,
		radius = 16,
		edge = rarityColor,
		parent = grid,
	})
	local stage = UI.new("Frame", {
		Name = "Stage",
		Size = UDim2.new(1, -12, 0, 104),
		Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = UI.lighten(rarityColor, 0.72),
		Parent = frame,
	}, { UI.corner(12), UI.shade(0.9) }) :: Frame
	local viewport =
		UI.viewport(DinoModel.build(species.id, 3, nil, "Static"), UDim2.fromScale(1, 1), stage, 30)
	local name = UI.body({
		text = "???",
		size = UDim2.new(1, -10, 0, 24),
		position = UDim2.fromOffset(5, 114),
		font = UI.Font,
		maxTextSize = 20,
		parent = frame,
	})
	UI.body({
		text = species.rarity,
		size = UDim2.new(1, -10, 0, 18),
		position = UDim2.fromOffset(5, 138),
		color = UI.darken(rarityColor, 0.15),
		font = UI.HeavyFont,
		maxTextSize = 15,
		parent = frame,
	})
	local badgeRow = UI.new("Frame", {
		Name = "Mutations",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -10, 0, 24),
		Position = UDim2.fromOffset(5, 160),
		Parent = frame,
	}, {
		UI.list(
			Enum.FillDirection.Horizontal,
			3,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Center
		),
	}) :: Frame
	local badges: { [string]: Frame } = {}
	for order, mutationId in MutationData.ORDER do
		local info = MutationData.get(mutationId)
		if info then
			local badge = UI.new("Frame", {
				Name = mutationId,
				Size = UDim2.fromOffset(24, 24),
				BackgroundColor3 = UI.lighten(UI.rgb(info.color), 0.4),
				LayoutOrder = order,
				Parent = badgeRow,
			}, { UI.round() }) :: Frame
			UI.text({
				text = info.emoji,
				size = UDim2.fromScale(0.8, 0.8),
				position = UDim2.fromScale(0.5, 0.5),
				anchor = Vector2.new(0.5, 0.5),
				maxTextSize = 16,
				noOutline = true,
				parent = badge,
			})
			badges[mutationId] = badge
		end
	end
	setSilhouette(viewport, true)
	return {
		species = species,
		frame = frame,
		viewport = viewport,
		name = name,
		badges = badges,
		discovered = nil,
	}
end

function DexUI.init()
	local _, content = Panels.window("Dex", "📖 Dino-Dex", Vector2.new(880, 500), UI.Theme.pink)
	local header = UI.new("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		Parent = content,
	}) :: Frame
	progress = UI.bar({
		size = UDim2.new(0.42, 0, 0, 30),
		position = UDim2.fromOffset(0, 4),
		color = UI.Theme.pink,
		parent = header,
	})
	local prizeRow = UI.new("Frame", {
		Name = "Prizes",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.56, 0, 0, 40),
		Parent = header,
	}, {
		UI.list(
			Enum.FillDirection.Horizontal,
			8,
			Enum.HorizontalAlignment.Right,
			Enum.VerticalAlignment.Center
		),
	}) :: Frame
	for i, milestone in DexRewards.MILESTONES do
		local count = milestone.count
		local button = UI.button({
			name = "Prize" .. count,
			text = `{count} {milestone.reward.emoji}`,
			size = UDim2.fromOffset(104, 36),
			color = UI.Theme.inkSoft,
			order = i,
			depth = 4,
			radius = 12,
			maxTextSize = 20,
			parent = prizeRow,
			onClick = function()
				Net.send("ClaimDex", count)
			end,
		})
		table.insert(prizes, { count = count, emoji = milestone.reward.emoji, button = button })
	end
	local grid = UI.new("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 1, -50),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		BorderSizePixel = 0,
		Parent = content,
	}, {
		UI.grid(Vector2.new(152, 192), 12),
		UI.padding(4, 6),
	}) :: ScrollingFrame

	for index, species in DinoData.LIST do
		table.insert(cards, buildCard(grid, index, species))
	end

	ClientState.changed:connect(refresh)
	table.insert(Hud.badgeRefreshers, function(snapshot: Types.Snapshot)
		local item = Hud.menu.Dex
		if item then
			item.badge.Visible = DexUI.claimable(snapshot)
		end
	end)
	Panels.onOpen("Dex", function()
		local snapshot = ClientState.get()
		if snapshot then
			refresh(snapshot)
		end
	end)
end

return DexUI
