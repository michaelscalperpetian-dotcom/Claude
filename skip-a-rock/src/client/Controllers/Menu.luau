--!strict
-- The menu (press M, tap a button on the left, or walk up to a shop):
--   Rocks     buy rocks and pick which one to throw
--   Upgrades  arm strength: +1, +10 or as many as you can afford
--   Rebirth   start over stronger (what you keep, what resets)
--   Islands   how far each island is and the bonus it gives
--   Goals     little things to aim for

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Economy = require(ReplicatedStorage.Shared.Economy)
local GoalData = require(ReplicatedStorage.Shared.Data.GoalData)
local IslandData = require(ReplicatedStorage.Shared.Data.IslandData)
local Net = require(ReplicatedStorage.Shared.Net)
local RockData = require(ReplicatedStorage.Shared.Data.RockData)
local Types = require(ReplicatedStorage.Shared.Types)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Audio = require(script.Parent.Audio)
local ClientState = require(script.Parent.ClientState)
local UI = require(script.Parent.Parent.Lib.UI)

local Menu = {}

export type Tab = "Rocks" | "Upgrades" | "Rebirth" | "Islands" | "Goals"
local TABS: { Tab } = { "Rocks", "Upgrades", "Rebirth", "Islands", "Goals" }

local T = UI.Theme
local PANEL = Vector2.new(800, 510)
local COIN = Color3.fromRGB(206, 150, 20)

local panel: Frame? = nil
local body: Frame? = nil
local tabButtons: { [Tab]: UI.Button } = {}
local current: Tab = "Rocks"
local isOpen = false
local rebirthArmedAt = -math.huge

local function clear(frame: Frame)
	for _, child in frame:GetChildren() do
		child:Destroy()
	end
end

local function statsOf(snapshot: Types.Snapshot): Economy.Stats
	return {
		strength = snapshot.strength,
		rebirths = snapshot.rebirths,
		equipped = snapshot.equipped,
		islands = snapshot.islands,
	}
end

-- A progress bar (0..1) in `parent`.
local function bar(
	parent: Instance,
	progress: number,
	color: Color3,
	size: UDim2,
	position: UDim2
): Frame
	local track = UI.new("Frame", {
		Name = "Bar",
		BackgroundColor3 = T.paperDark,
		BorderSizePixel = 0,
		Size = size,
		Position = position,
		Parent = parent,
	}, { UI.round() }) :: Frame
	UI.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1),
		Parent = track,
	}, { UI.round() })
	return track
end

-- ===== Rocks =====

local function rockCard(rock: RockData.Rock, snapshot: Types.Snapshot, order: number): Frame
	local owned = snapshot.rocks[rock.id] == true
	local inHand = snapshot.equipped == rock.id
	local unlocked = Economy.rockUnlocked(rock, snapshot.islands)
	local affordable = snapshot.coins >= rock.price
	local rarityColor = UI.rgb(RockData.rarityInfo(rock.rarity).color)
	local card = UI.new("Frame", {
		Name = rock.id,
		BackgroundColor3 = if inHand then UI.lighten(T.gold, 0.7) else T.card,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, {
		UI.corner(14),
		UI.stroke(if inHand then T.gold else T.line, if inHand then 3 else 2),
	}) :: Frame
	local swatch = UI.new("Frame", {
		Name = "Swatch",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(52, 30),
		BackgroundColor3 = if unlocked then UI.rgb(rock.color) else T.paperDark,
		BorderSizePixel = 0,
		Parent = card,
	}, { UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) }) :: Frame
	if not unlocked then
		UI.body({ text = "🔒", size = UDim2.fromScale(1, 1), maxTextSize = 20, parent = swatch })
	end
	UI.body({
		name = "Title",
		text = rock.name,
		size = UDim2.new(1, -10, 0, 18),
		position = UDim2.fromOffset(5, 40),
		font = UI.Font,
		maxTextSize = 16,
		parent = card,
	})
	UI.body({
		name = "Power",
		text = `{rock.rarity} · {Format.times(rock.power)} distance`,
		size = UDim2.new(1, -10, 0, 15),
		position = UDim2.fromOffset(5, 58),
		color = rarityColor,
		maxTextSize = 12,
		parent = card,
	})
	local label: string
	local color: Color3
	local enabled = true
	if inHand then
		label, color, enabled = "In hand", T.good, false
	elseif owned then
		label, color = "Equip", T.water
	elseif not unlocked then
		local island = if rock.island then IslandData.get(rock.island) else nil
		label, color, enabled = `Reach {if island then island.name else "?"}`, T.inkSoft, false
	else
		label = "🪙 " .. Format.short(rock.price)
		color = if affordable then T.good else T.inkSoft
		enabled = affordable
	end
	local button = UI.button({
		name = "Action",
		text = label,
		size = UDim2.new(1, -16, 0, 26),
		position = UDim2.new(0, 8, 1, -32),
		color = color,
		parent = card,
		onClick = function()
			if owned then
				Net.send("Equip", rock.id)
			else
				Net.send("BuyRock", rock.id)
			end
		end,
	})
	UI.setButton(button, { enabled = enabled })
	return card
end

local function showRocks(frame: Frame, snapshot: Types.Snapshot)
	local grid = UI.new("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -40),
		Parent = frame,
	}, { UI.grid(Vector2.new(178, 108), 10) }) :: Frame
	for i, rock in RockData.LIST do
		rockCard(rock, snapshot, i).Parent = grid
	end
	local held = Economy.rockOf(statsOf(snapshot))
	UI.body({
		name = "About",
		text = `{held.name}: {held.blurb}`,
		size = UDim2.new(1, -20, 0, 32),
		position = UDim2.new(0, 10, 1, -34),
		font = UI.LightFont,
		maxTextSize = 15,
		parent = frame,
	})
end

-- ===== Upgrades =====

local function costOf(level: number, count: number): number
	local total = 0
	for i = 0, count - 1 do
		total += Economy.strengthCost(level + i)
	end
	return total
end

local function showUpgrades(frame: Frame, snapshot: Types.Snapshot)
	local level = snapshot.strength
	UI.body({
		text = "💪 Arm Strength",
		size = UDim2.new(1, 0, 0, 40),
		position = UDim2.fromOffset(0, 10),
		font = UI.Font,
		maxTextSize = 34,
		parent = frame,
	})
	UI.body({
		name = "Level",
		text = `Level {level} · throws {Format.times(Economy.strengthPower(level))} as far`,
		size = UDim2.new(1, 0, 0, 26),
		position = UDim2.fromOffset(0, 56),
		color = T.inkSoft,
		maxTextSize = 20,
		parent = frame,
	})
	UI.body({
		text = `Each level throws {math.floor((Economy.STRENGTH_STEP - 1) * 100 + 0.5)}% further. Strength resets when you rebirth.`,
		size = UDim2.new(1, -60, 0, 22),
		position = UDim2.fromOffset(30, 88),
		font = UI.LightFont,
		maxTextSize = 16,
		parent = frame,
	})
	local row = UI.new("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 140),
		Size = UDim2.fromOffset(660, 150),
		Parent = frame,
	}, { UI.list(Enum.FillDirection.Horizontal, 20) }) :: Frame
	local options: { { label: string, count: number } } = {
		{ label = "+1 level", count = 1 },
		{ label = "+10 levels", count = 10 },
		{ label = "Max", count = 100 },
	}
	for i, option in options do
		local count = option.count
		local cost = costOf(level, count)
		local affordable = snapshot.coins >= Economy.strengthCost(level)
		local card = UI.new("Frame", {
			Name = "Option" .. i,
			BackgroundColor3 = T.card,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(200, 150),
			LayoutOrder = i,
			Parent = row,
		}, { UI.corner(16), UI.stroke(T.line, 2) }) :: Frame
		UI.body({
			text = option.label,
			size = UDim2.new(1, -16, 0, 34),
			position = UDim2.fromOffset(8, 12),
			font = UI.Font,
			maxTextSize = 26,
			parent = card,
		})
		UI.body({
			name = "Cost",
			text = if count >= 100
				then "as many as you can afford"
				else "🪙 " .. Format.short(cost),
			size = UDim2.new(1, -16, 0, 24),
			position = UDim2.fromOffset(8, 52),
			color = if count >= 100 then T.inkSoft else COIN,
			maxTextSize = if count >= 100 then 15 else 22,
			parent = card,
		})
		local button = UI.button({
			name = "Buy",
			text = "Buy",
			size = UDim2.new(1, -24, 0, 40),
			position = UDim2.new(0, 12, 1, -52),
			color = if affordable then T.good else T.inkSoft,
			parent = card,
			onClick = function()
				Net.send("Upgrade", count)
			end,
		})
		UI.setButton(button, { enabled = affordable })
	end
	UI.body({
		text = `You have 🪙 {Format.short(snapshot.coins)} · next level 🪙 {Format.short(
			snapshot.strengthCost
		)}`,
		size = UDim2.new(1, 0, 0, 26),
		position = UDim2.new(0, 0, 1, -40),
		color = COIN,
		maxTextSize = 20,
		parent = frame,
	})
end

-- ===== Rebirth =====

local function showRebirth(frame: Frame, snapshot: Types.Snapshot)
	local cost = snapshot.rebirthCost
	local ready = snapshot.coins >= cost
	UI.body({
		text = `🔁 Rebirth {snapshot.rebirths + 1}`,
		size = UDim2.new(1, 0, 0, 44),
		position = UDim2.fromOffset(0, 8),
		font = UI.Font,
		maxTextSize = 36,
		parent = frame,
	})
	local now = statsOf(snapshot)
	local after = table.clone(now)
	after.rebirths += 1
	local lines = {
		`✅ Every throw pays {Format.times(Economy.coinMultiplier(after))} coins (now {Format.times(
			Economy.coinMultiplier(now)
		)})`,
		`✅ Rocks fly {Format.times(Economy.rebirthPower(after.rebirths))} as far`,
		"✅ You keep every rock and island",
		"↩️ Your coins and arm strength go back to zero",
	}
	for i, line in lines do
		UI.body({
			text = line,
			size = UDim2.new(1, -80, 0, 30),
			position = UDim2.fromOffset(40, 60 + (i - 1) * 34),
			align = Enum.TextXAlignment.Left,
			maxTextSize = 20,
			color = if i == 4 then T.inkSoft else T.ink,
			parent = frame,
		})
	end
	bar(
		frame,
		snapshot.coins / cost,
		if ready then T.good else T.gold,
		UDim2.new(1, -80, 0, 18),
		UDim2.fromOffset(40, 210)
	)
	UI.body({
		name = "Progress",
		text = `🪙 {Format.short(snapshot.coins)} / {Format.short(cost)}`,
		size = UDim2.new(1, 0, 0, 24),
		position = UDim2.fromOffset(0, 234),
		color = COIN,
		maxTextSize = 20,
		parent = frame,
	})
	local armed = os.clock() - rebirthArmedAt < 3
	local button = UI.button({
		name = "RebirthButton",
		text = if not ready
			then "Not enough coins yet"
			elseif armed then "Tap again to rebirth"
			else "Rebirth",
		size = UDim2.fromOffset(300, 54),
		position = UDim2.new(0.5, 0, 0, 280),
		anchor = Vector2.new(0.5, 0),
		color = if armed then T.coral else T.dusk,
		parent = frame,
		onClick = function()
			-- two taps, so nobody rebirths by accident
			if os.clock() - rebirthArmedAt < 3 and os.clock() - rebirthArmedAt > 0.4 then
				rebirthArmedAt = -math.huge
				Net.send("Rebirth")
			else
				rebirthArmedAt = os.clock()
			end
			Menu.render()
		end,
	})
	UI.setButton(button, { enabled = ready })
end

-- ===== Islands =====

local function showIslands(frame: Frame, snapshot: Types.Snapshot)
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
	for i, island in IslandData.LIST do
		local reached = snapshot.islands[island.id] == true
		local row = UI.new("Frame", {
			Name = island.id,
			BackgroundColor3 = if reached then UI.lighten(T.sage, 0.75) else T.card,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -16, 0, 50),
			LayoutOrder = i,
			Parent = scroll,
		}, { UI.corner(12), UI.stroke(T.line, 1.5) }) :: Frame
		UI.body({
			text = (if reached then "🏝️ " else "🌊 ") .. island.name,
			size = UDim2.new(0.42, 0, 0, 24),
			position = UDim2.fromOffset(14, 13),
			align = Enum.TextXAlignment.Left,
			maxTextSize = 19,
			parent = row,
		})
		UI.body({
			text = `{Format.distance(island.distance)} · +{math.floor(island.bonus * 100 + 0.5)}% coins`,
			size = UDim2.new(0.3, 0, 0, 20),
			position = UDim2.new(0.42, 0, 0, 15),
			color = T.inkSoft,
			maxTextSize = 16,
			parent = row,
		})
		if reached then
			UI.body({
				text = "✓",
				size = UDim2.fromOffset(40, 30),
				position = UDim2.new(1, -50, 0, 10),
				color = T.good,
				font = UI.Font,
				maxTextSize = 26,
				parent = row,
			})
		else
			-- progress on a log scale, so far-off islands still show movement
			local progress = math.log10(1 + snapshot.bestDistance) / math.log10(1 + island.distance)
			bar(row, progress, T.water, UDim2.new(0.22, 0, 0, 12), UDim2.new(0.75, 0, 0, 19))
		end
	end
end

-- ===== Goals =====

local function showGoals(frame: Frame, snapshot: Types.Snapshot)
	local rocks = 0
	for _, owned in snapshot.rocks do
		if owned then
			rocks += 1
		end
	end
	local stats: GoalData.Stats = {
		bestSkips = snapshot.bestSkips,
		bestDistance = snapshot.bestDistance,
		perfects = snapshot.perfects,
		rocks = rocks,
		rebirths = snapshot.rebirths,
		throws = snapshot.throws,
		totalCoins = snapshot.totalCoins,
	}
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
	local done = 0
	for i, goal in GoalData.GOALS do
		local finished = snapshot.goals[goal.id] == true
		if finished then
			done += 1
		end
		local value = GoalData.progress(goal, stats)
		local progress = if goal.kind == "distance" or goal.kind == "coins"
			then math.log10(1 + value) / math.log10(1 + goal.value)
			else value / goal.value
		local row = UI.new("Frame", {
			Name = goal.id,
			BackgroundColor3 = if finished then UI.lighten(T.sage, 0.75) else T.card,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -16, 0, 44),
			LayoutOrder = if finished then 100 + i else i,
			Parent = scroll,
		}, { UI.corner(12), UI.stroke(T.line, 1.5) }) :: Frame
		UI.body({
			text = goal.emoji,
			size = UDim2.fromOffset(32, 32),
			position = UDim2.fromOffset(8, 6),
			font = UI.Font,
			maxTextSize = 22,
			parent = row,
		})
		UI.body({
			text = goal.text,
			size = UDim2.new(1, -230, 0, 24),
			position = UDim2.fromOffset(48, 10),
			align = Enum.TextXAlignment.Left,
			maxTextSize = 18,
			parent = row,
		})
		bar(
			row,
			if finished then 1 else progress,
			if finished then T.good else T.water,
			UDim2.fromOffset(110, 12),
			UDim2.new(1, -170, 0.5, -6)
		)
		UI.body({
			text = if finished then "✓" else `{math.floor(math.clamp(progress, 0, 1) * 100)}%`,
			size = UDim2.fromOffset(48, 24),
			position = UDim2.new(1, -54, 0.5, -12),
			color = if finished then T.good else T.inkSoft,
			font = UI.Font,
			maxTextSize = 18,
			parent = row,
		})
	end
	local header = UI.body({
		text = `{done} of {#GoalData.GOALS} goals done · {Format.commas(snapshot.throws)} rocks skipped`,
		size = UDim2.new(1, -16, 0, 24),
		color = T.inkSoft,
		maxTextSize = 16,
		parent = scroll,
	})
	header.LayoutOrder = -1
end

-- ===== Panel =====

function Menu.render()
	local frame = body
	local snapshot = ClientState.get()
	if not frame or not snapshot or not isOpen then
		return
	end
	clear(frame)
	if current == "Rocks" then
		showRocks(frame, snapshot)
	elseif current == "Upgrades" then
		showUpgrades(frame, snapshot)
	elseif current == "Rebirth" then
		showRebirth(frame, snapshot)
	elseif current == "Islands" then
		showIslands(frame, snapshot)
	else
		showGoals(frame, snapshot)
	end
	for tab, button in tabButtons do
		UI.setButton(button, { color = if tab == current then T.waterDeep else T.inkSoft })
	end
end

function Menu.isOpen(): boolean
	return isOpen
end

function Menu.current(): Tab
	return current
end

function Menu.open(tab: Tab?)
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
	Menu.render()
end

function Menu.close()
	local frame = panel
	if not frame or not isOpen then
		return
	end
	isOpen = false
	frame.Visible = false
end

function Menu.toggle()
	if isOpen then
		Menu.close()
	else
		Menu.open()
	end
end

local function build()
	local _, canvas = UI.screen("Menu", 10)
	local frame = UI.paper({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(PANEL.X, PANEL.Y),
		Visible = false,
		Parent = canvas,
	})
	local tabs = UI.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 14),
		Size = UDim2.new(1, -90, 0, 38),
		Parent = frame,
	}, { UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left) }) :: Frame
	for i, name in TABS do
		local tab: Tab = name :: Tab
		tabButtons[tab] = UI.button({
			name = tab,
			text = tab,
			size = UDim2.fromOffset(126, 38),
			color = T.inkSoft,
			order = i,
			parent = tabs,
			onClick = function()
				current = tab
				Menu.render()
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
		onClick = Menu.close,
	})
	body = UI.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 64),
		Size = UDim2.new(1, -36, 1, -80),
		Parent = frame,
	}) :: Frame
	panel = frame
end

function Menu.init()
	build()
	ClientState.changed:connect(function()
		Menu.render()
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.M or input.KeyCode == Enum.KeyCode.ButtonY then
			Menu.toggle()
		elseif input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			Menu.close()
		end
	end)
	-- the shops on the boardwalk open their tab
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local tab = prompt:GetAttribute("Menu")
		if type(tab) == "string" and table.find(TABS, tab :: any) then
			Menu.open(tab :: Tab)
		end
	end)
end

return Menu
