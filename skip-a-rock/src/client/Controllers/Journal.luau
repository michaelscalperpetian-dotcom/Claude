--!strict
-- The skipper's journal (press J, or tap your stone): every kind of stone
-- (found ones can be picked to throw), the goals to aim for, and your records.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GoalData = require(ReplicatedStorage.Shared.Data.GoalData)
local Net = require(ReplicatedStorage.Shared.Net)
local StoneData = require(ReplicatedStorage.Shared.Data.StoneData)
local Types = require(ReplicatedStorage.Shared.Types)
local Audio = require(script.Parent.Audio)
local ClientState = require(script.Parent.ClientState)
local UI = require(script.Parent.Parent.Lib.UI)

local Journal = {}

export type Tab = "Stones" | "Goals" | "Records"
local TABS: { Tab } = { "Stones", "Goals", "Records" }

local T = UI.Theme
local PANEL = Vector2.new(720, 500)

local panel: Frame? = nil
local body: Frame? = nil
local tabButtons: { [Tab]: UI.Button } = {}
local current: Tab = "Stones"
local isOpen = false

-- 0..1 -> five dots, e.g. "●●●○○"
function Journal.dots(value: number): string
	local filled = math.clamp(math.floor(value * 5 + 0.5), 1, 5)
	return string.rep("●", filled) .. string.rep("○", 5 - filled)
end

local function clear(frame: Frame)
	for _, child in frame:GetChildren() do
		child:Destroy()
	end
end

-- ===== Stones =====

local function stoneCard(stone: StoneData.Stone, snapshot: Types.Snapshot, order: number): Frame
	local count = snapshot.stones[stone.id] or 0
	local owned = count > 0
	local inHand = snapshot.equipped == stone.id
	local rarityColor = UI.rgb(StoneData.rarityInfo(stone.rarity).color)
	local card = UI.new("TextButton", {
		Name = stone.id,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = if inHand then UI.lighten(T.gold, 0.7) else T.card,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, {
		UI.corner(14),
		UI.stroke(if inHand then T.gold else T.line, if inHand then 3 else 2),
	}) :: TextButton
	-- the stone itself: a soft oval in its colour, or a question mark
	local swatch = UI.new("Frame", {
		Name = "Swatch",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(54, 34),
		BackgroundColor3 = if owned then UI.rgb(stone.color) else T.paperDark,
		BorderSizePixel = 0,
		Parent = card,
	}, { UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) }) :: Frame
	if not owned then
		UI.body({
			text = "?",
			size = UDim2.fromScale(1, 1),
			color = T.inkSoft,
			font = UI.Font,
			maxTextSize = 24,
			parent = swatch,
		})
	end
	UI.body({
		name = "Title", -- (not "Name": card.Name is the card's own name)
		text = if owned then stone.name else "Not found yet",
		size = UDim2.new(1, -12, 0, 20),
		position = UDim2.fromOffset(6, 48),
		font = UI.Font,
		maxTextSize = 17,
		color = if owned then T.ink else T.inkSoft,
		parent = card,
	})
	UI.body({
		name = "Rarity",
		text = stone.rarity .. (if count > 1 then ` · ×{count}` else ""),
		size = UDim2.new(1, -12, 0, 16),
		position = UDim2.fromOffset(6, 69),
		color = rarityColor,
		maxTextSize = 13,
		parent = card,
	})
	local status = if inHand
		then "In hand"
		elseif owned then `Skips {Journal.dots(stone.flat)}`
		elseif stone.findWeight > 0 then "Look for glints"
		else ""
	UI.body({
		name = "Status",
		text = status,
		size = UDim2.new(1, -12, 0, 16),
		position = UDim2.fromOffset(6, 88),
		color = if inHand then T.good else T.inkSoft,
		font = UI.LightFont,
		maxTextSize = 13,
		parent = card,
	})
	if owned and not inHand then
		card.Activated:Connect(function()
			Audio.play("click")
			Net.send("Equip", stone.id)
		end)
	end
	return card :: any
end

local function showStones(frame: Frame, snapshot: Types.Snapshot)
	local grid = UI.new("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -64),
		Parent = frame,
	}, { UI.grid(Vector2.new(152, 110), 10) }) :: Frame
	for i, stone in StoneData.LIST do
		stoneCard(stone, snapshot, i).Parent = grid
	end
	local held = StoneData.get(snapshot.equipped) or StoneData.get(StoneData.STARTER)
	if held then
		local night = if held.nightBonus then " Even better at night." else ""
		UI.body({
			name = "About",
			text = `{held.name}: {held.blurb}{night}  Skips {Journal.dots(held.flat)}   Hops {Journal.dots(
				held.weight
			)}`,
			size = UDim2.new(1, -20, 0, 50),
			position = UDim2.new(0, 10, 1, -54),
			font = UI.LightFont,
			maxTextSize = 16,
			parent = frame,
		})
	end
end

-- ===== Goals =====

local function showGoals(frame: Frame, snapshot: Types.Snapshot)
	local stats: GoalData.Stats = {
		bestSkips = snapshot.bestSkips,
		bestDistance = snapshot.bestDistance,
		perfects = snapshot.perfects,
		stones = 0,
		shore = snapshot.shore,
		nightSkips = snapshot.nightSkips,
		throws = snapshot.throws,
	}
	for _, count in snapshot.stones do
		if count > 0 then
			stats.stones += 1
		end
	end
	local scroll = UI.new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = T.inkSoft,
		Parent = frame,
	}, { UI.list(Enum.FillDirection.Vertical, 8), UI.padding(6, 4) }) :: ScrollingFrame
	local doneCount = 0
	for i, goal in GoalData.GOALS do
		local done = snapshot.goals[goal.id] == true
		if done then
			doneCount += 1
		end
		local progress = math.clamp(GoalData.progress(goal, stats) / goal.value, 0, 1)
		local row = UI.new("Frame", {
			Name = goal.id,
			BackgroundColor3 = if done then UI.lighten(T.sage, 0.75) else T.card,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -16, 0, 46),
			LayoutOrder = if done then 100 + i else i,
			Parent = scroll,
		}, { UI.corner(12), UI.stroke(T.line, 1.5) }) :: Frame
		UI.body({
			text = goal.emoji,
			size = UDim2.fromOffset(34, 34),
			position = UDim2.fromOffset(8, 6),
			font = UI.Font,
			maxTextSize = 24,
			parent = row,
		})
		UI.body({
			text = goal.text,
			size = UDim2.new(1, -230, 0, 24),
			position = UDim2.fromOffset(50, 11),
			align = Enum.TextXAlignment.Left,
			maxTextSize = 18,
			parent = row,
		})
		local bar = UI.new("Frame", {
			Name = "Bar",
			BackgroundColor3 = T.paperDark,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -60, 0.5, 0),
			Size = UDim2.fromOffset(110, 12),
			Parent = row,
		}, { UI.round() }) :: Frame
		UI.new("Frame", {
			Name = "Fill",
			BackgroundColor3 = if done then T.good else T.water,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(progress, 1),
			Parent = bar,
		}, { UI.round() })
		UI.body({
			text = if done then "✓" else `{math.floor(progress * 100)}%`,
			size = UDim2.fromOffset(48, 24),
			position = UDim2.new(1, -54, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			color = if done then T.good else T.inkSoft,
			font = UI.Font,
			maxTextSize = 18,
			parent = row,
		})
	end
	local header = UI.body({
		text = `{doneCount} of {#GoalData.GOALS} goals done`,
		size = UDim2.new(1, -16, 0, 24),
		color = T.inkSoft,
		maxTextSize = 16,
		order = 0,
		parent = scroll,
	})
	header.LayoutOrder = -1
end

-- ===== Records =====

local function nextTitle(bestSkips: number): string?
	local best: GoalData.Title? = nil
	for _, title in GoalData.TITLES do
		if title.skips > bestSkips and (best == nil or title.skips < best.skips) then
			best = title
		end
	end
	return if best then `{best.name} at {best.skips} skips` else nil
end

local function showRecords(frame: Frame, snapshot: Types.Snapshot)
	local found = 0
	for _, count in snapshot.stones do
		if count > 0 then
			found += 1
		end
	end
	local rows: { { string } } = {
		{ "🌊", "Most skips in one throw", tostring(snapshot.bestSkips) },
		{ "📏", "Longest throw", string.format("%.1f studs", snapshot.bestDistance) },
		{ "🌙", "Most skips at night", tostring(snapshot.nightSkips) },
		{ "🎯", "Perfect releases", tostring(snapshot.perfects) },
		{ "🧺", "Stones skipped", tostring(snapshot.throws) },
		{ "💧", "Skips altogether", tostring(snapshot.totalSkips) },
		{ "🪨", "Kinds of stone found", `{found} / {#StoneData.LIST}` },
		{ "🏝️", "Across the whole lake", if snapshot.shore then "Yes!" else "Not yet" },
	}
	local list = UI.new("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -70),
		Parent = frame,
	}, { UI.list(Enum.FillDirection.Vertical, 6) }) :: Frame
	for i, row in rows do
		local line = UI.new("Frame", {
			Name = "Row" .. i,
			BackgroundColor3 = if i % 2 == 0 then T.paperDark else T.card,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -20, 0, 38),
			LayoutOrder = i,
			Parent = list,
		}, { UI.corner(10) }) :: Frame
		UI.body({
			text = row[1],
			size = UDim2.fromOffset(30, 28),
			position = UDim2.fromOffset(10, 5),
			font = UI.Font,
			maxTextSize = 22,
			parent = line,
		})
		UI.body({
			text = row[2],
			size = UDim2.new(0.6, -50, 0, 24),
			position = UDim2.fromOffset(48, 7),
			align = Enum.TextXAlignment.Left,
			maxTextSize = 18,
			parent = line,
		})
		UI.body({
			name = "Value",
			text = row[3],
			size = UDim2.new(0.4, -20, 0, 26),
			position = UDim2.new(1, -12, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			align = Enum.TextXAlignment.Right,
			font = UI.Font,
			maxTextSize = 20,
			parent = line,
		})
	end
	local titleText = if snapshot.title then `Your title: {snapshot.title}` else "No title yet"
	local upcoming = nextTitle(snapshot.bestSkips)
	UI.body({
		name = "Title",
		text = if upcoming
			then `{titleText}  ·  Next: {upcoming}`
			else `{titleText}  ·  The highest there is!`,
		size = UDim2.new(1, -20, 0, 50),
		position = UDim2.new(0, 10, 1, -56),
		color = T.inkSoft,
		maxTextSize = 17,
		parent = frame,
	})
end

-- ===== Panel =====

local function render()
	local frame = body
	local snapshot = ClientState.get()
	if not frame or not snapshot or not isOpen then
		return
	end
	clear(frame)
	if current == "Stones" then
		showStones(frame, snapshot)
	elseif current == "Goals" then
		showGoals(frame, snapshot)
	else
		showRecords(frame, snapshot)
	end
	for tab, button in tabButtons do
		UI.setButton(button, {
			color = if tab == current then T.waterDeep else T.inkSoft,
		})
	end
end

function Journal.isOpen(): boolean
	return isOpen
end

function Journal.open(tab: Tab?)
	local frame = panel
	if not frame then
		return
	end
	current = tab or current
	if not isOpen then
		isOpen = true
		frame.Visible = true
		UI.pop(frame, 0.9)
		Audio.play("open")
	end
	render()
end

function Journal.close()
	local frame = panel
	if not frame or not isOpen then
		return
	end
	isOpen = false
	frame.Visible = false
end

function Journal.toggle()
	if isOpen then
		Journal.close()
	else
		Journal.open()
	end
end

local function build()
	local _, canvas = UI.screen("Journal", 10)
	local frame = UI.paper({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL.X, PANEL.Y),
		Visible = false,
		Parent = canvas,
	})
	UI.body({
		text = "Skipper's Journal",
		size = UDim2.fromOffset(300, 36),
		position = UDim2.fromOffset(24, 14),
		align = Enum.TextXAlignment.Left,
		font = UI.Font,
		maxTextSize = 30,
		parent = frame,
	})
	local tabs = UI.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -70, 0, 14),
		Size = UDim2.fromOffset(330, 38),
		Parent = frame,
	}, { UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right) }) :: Frame
	for i, name in TABS do
		local tab: Tab = name :: Tab
		tabButtons[tab] = UI.button({
			name = tab,
			text = tab,
			size = UDim2.fromOffset(100, 38),
			color = T.inkSoft,
			order = i,
			parent = tabs,
			onClick = function()
				current = tab
				render()
			end,
		})
	end
	UI.button({
		name = "Close",
		text = "✕",
		size = UDim2.fromOffset(40, 38),
		position = UDim2.new(1, -16, 0, 14),
		anchor = Vector2.new(1, 0),
		color = T.coral,
		parent = frame,
		onClick = Journal.close,
	})
	body = UI.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 66),
		Size = UDim2.new(1, -36, 1, -82),
		Parent = frame,
	}) :: Frame
	panel = frame
end

function Journal.init()
	build()
	ClientState.changed:connect(function()
		render()
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.J or input.KeyCode == Enum.KeyCode.ButtonY then
			Journal.toggle()
		elseif input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			Journal.close()
		end
	end)
end

return Journal
